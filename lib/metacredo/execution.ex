defmodule MetaCredo.Execution do
  @moduledoc """
  Orchestrates the full analysis pipeline: source discovery, check execution,
  issue collection, and inline-disable filtering.
  """

  alias MetaCredo.{Baseline, Config, Issue, SourceFile, Sources}
  alias Metastatic.AST

  require Logger

  @type report :: %{
          source_files: [SourceFile.t()],
          issues: [Issue.t()],
          checks_run: [module()],
          summary: map(),
          timing_ms: non_neg_integer() | nil
        }

  @type run_opts :: [
          config: Config.config() | nil,
          config_file: String.t() | nil,
          strict: boolean(),
          only: [atom()],
          ignore: [atom()],
          files_included: [String.t()] | nil,
          files_excluded: [term()] | nil,
          lift_test_exclusion: boolean(),
          no_db: boolean(),
          no_user: boolean()
        ]

  @doc """
  Runs the full analysis pipeline.

  ## Options

  - `:config` - Pre-loaded config map (takes precedence over `:config_file`)
  - `:config_file` - Path to `.metacredo.exs`
  - `:strict` - Only report issues with priority >= :normal (default: false)
  - `:only` - Only run checks in these categories
  - `:ignore` - Skip checks in these categories
  - `:files_included` - Override file include patterns
  - `:files_excluded` - Override file exclude patterns
  - `:lift_test_exclusion` - Whether an explicit `:files_included` should
    lift the default `test/` exclusion (default: `true`). Diff mode sets
    this to `false`: it supplies a *machine-derived* file list, not a
    deliberate user opt-in, so test files must stay excluded exactly as
    they are for a normal run.

  When `:files_included` is given, the *default* `test/` exclusion is lifted
  so an explicitly targeted path (e.g. `--path test/`) is analysed; all other
  exclusions and any configured `excluded` patterns still apply. When
  `:files_excluded` is given it replaces the configured exclusions verbatim.
  Set `lift_test_exclusion: false` to keep the `test/` exclusion in force.
  """
  @spec run(run_opts()) :: report()
  def run(opts \\ []) do
    start = System.monotonic_time(:millisecond)

    _ = Application.ensure_all_started(:metastatic)

    config = opts[:config] || Config.read(opts[:config_file])

    # Resolve file patterns
    file_patterns = resolve_file_patterns(config, opts)

    # Discover and parse source files
    source_files = Sources.find(file_patterns)

    # Resolve which checks to run
    checks = resolve_checks(config, opts)

    # Run checks on all source files
    issues =
      source_files
      |> Enum.flat_map(fn source_file ->
        run_checks_on_file(source_file, checks)
      end)
      |> filter_disabled_by_comments(source_files)
      |> maybe_filter_strict(opts[:strict])
      |> maybe_filter_confidence(opts[:min_confidence])
      |> maybe_filter_changed_lines(opts[:changed_lines])
      |> sort_issues()

    # A baseline records the issues that already existed; only *new* ones are
    # reported. Writing a baseline captures the current state instead.
    issues = apply_baseline(issues, opts)

    elapsed = System.monotonic_time(:millisecond) - start

    # Strip heavy document AST and text data from source_files to release memory post-execution
    stripped_source_files =
      Enum.map(source_files, fn %SourceFile{} = sf ->
        %{sf | document: nil, lines: [], source: nil}
      end)

    %{
      source_files: stripped_source_files,
      issues: issues,
      checks_run: Enum.map(checks, &elem(&1, 0)),
      summary: summarize(issues),
      timing_ms: elapsed
    }
  end

  @doc "Runs checks on pre-parsed source files."
  @spec run_on_source_files([SourceFile.t()], [{module(), Keyword.t()}]) :: [Issue.t()]
  def run_on_source_files(source_files, checks) do
    source_files
    |> Enum.flat_map(&run_checks_on_file(&1, checks))
    |> sort_issues()
  end

  # -- Private --

  defp resolve_file_patterns(config, opts) do
    base = Config.file_patterns(config)

    %{
      included: opts[:files_included] || base.included,
      excluded: resolve_excluded(base.excluded, opts)
    }
  end

  # The default `test/` exclusion is a *default*, not a hard rule: when the
  # user explicitly targets paths via `:files_included` (e.g. `--path test/`
  # or `--files-included test/`), that is a deliberate opt-in and must not be
  # silently swallowed by the default pattern. Every other exclusion
  # (`deps/`, `_build/`, ...) and any user-configured `excluded` patterns
  # still apply. An explicit `:files_excluded` always wins verbatim.
  defp resolve_excluded(base_excluded, opts) do
    case Keyword.fetch(opts, :files_excluded) do
      {:ok, excluded} when is_list(excluded) -> excluded
      _ -> lift_default_test_exclusion(base_excluded, opts)
    end
  end

  defp lift_default_test_exclusion(base_excluded, opts) do
    lift? = Keyword.get(opts, :lift_test_exclusion, true)

    case Keyword.fetch(opts, :files_included) do
      {:ok, included} when is_list(included) and lift? ->
        test_pattern = Config.test_exclusion_pattern()
        Enum.reject(base_excluded, &same_pattern?(&1, test_pattern))

      _ ->
        base_excluded
    end
  end

  # Regexes do not implement structural equality (two separately-built
  # `~r"foo"` values are not `==`), so compare their `source` instead.
  defp same_pattern?(%Regex{source: a}, %Regex{source: b}), do: a == b
  defp same_pattern?(a, b), do: a == b

  defp resolve_checks(config, opts) do
    config
    |> Config.enabled_checks()
    |> reject_umbrella_switches(config, opts)
    |> filter_categories(opts)
  end

  # Applies the `--no-db` / `--no-user` umbrella switches, which can come
  # either from the CLI opts or from the config file.
  defp reject_umbrella_switches(checks, config, opts) do
    no_db? = opts[:no_db] || Map.get(config, :no_db, false)
    no_user? = opts[:no_user] || Map.get(config, :no_user, false)

    checks
    |> reject_if(no_db?, &db_check?/1)
    |> reject_if(no_user?, &user_check?/1)
  end

  defp reject_if(checks, true, predicate),
    do: Enum.reject(checks, fn {mod, _} -> predicate.(mod) end)

  defp reject_if(checks, _false, _predicate), do: checks

  # Applies `--only` then `--ignore`, both of which select by category.
  defp filter_categories(checks, opts) do
    checks
    |> keep_categories(opts[:only])
    |> drop_categories(opts[:ignore])
  end

  defp keep_categories(checks, categories) when categories in [nil, []], do: checks

  defp keep_categories(checks, categories),
    do: Enum.filter(checks, fn {mod, _} -> mod.category() in categories end)

  defp drop_categories(checks, categories) when categories in [nil, []], do: checks

  defp drop_categories(checks, categories),
    do: Enum.reject(checks, fn {mod, _} -> mod.category() in categories end)

  # Umbrella switches are driven *purely* by declared tags. Matching on
  # module-name substrings (the previous implementation) is precisely the
  # unsound heuristic that `Config.default_disabled_checks/0` documents as
  # the reason for disabling seven checks -- a linter must not ship the
  # anti-pattern it warns about. Every DB check declares `tags: [:db]` and
  # every user-input check declares `tags: [:user_input]`.
  defp db_check?(mod), do: tag?(mod, :db)

  defp user_check?(mod), do: tag?(mod, :user_input) or tag?(mod, :user)

  defp tag?(mod, tag) do
    function_exported?(mod, :tags, 0) and tag in mod.tags()
  end

  defp run_checks_on_file(%SourceFile{} = source_file, checks) do
    Enum.flat_map(checks, fn {check_module, params} ->
      try do
        check_module.run(source_file, params)
      rescue
        e ->
          Logger.warning(fn ->
            "Check #{inspect(check_module)} failed on #{source_file.filename}: #{inspect(e)}"
          end)

          []
      end
    end)
  end

  @dialyzer {:nowarn_function, filter_disabled_by_comments: 2}
  defp filter_disabled_by_comments(issues, source_files) do
    # Build a set of {filename, line_no, check_module} to suppress
    disabled = collect_disabled_lines(source_files)

    Enum.reject(issues, fn issue ->
      key = {issue.filename, issue.line_no, issue.check}
      wildcard_key = {issue.filename, issue.line_no, :all}
      MapSet.member?(disabled, key) or MapSet.member?(disabled, wildcard_key)
    end)
  end

  @spec collect_disabled_lines([SourceFile.t()]) :: MapSet.t()
  defp collect_disabled_lines(source_files) do
    source_files
    |> Enum.flat_map(fn sf ->
      ast_disabled = collect_disabled_from_ast(sf)
      line_disabled = collect_disabled_from_lines(sf)
      ast_disabled ++ line_disabled
    end)
    |> Enum.flat_map(fn
      {filename, :all_lines, check_ref} ->
        # File-level disable: match all lines
        [{filename, nil, check_ref}]

      entry ->
        [entry]
    end)
    |> MapSet.new()
  end

  defp collect_disabled_from_ast(sf) do
    {_, disabled} =
      AST.traverse(
        SourceFile.ast(sf),
        [],
        fn
          {:comment, _meta, text} = node, acc when is_binary(text) ->
            case parse_disable_comment(text) do
              {:ok, check_ref, :next_line} ->
                line = AST.get_meta(node, :line)

                if line do
                  {node, [{sf.filename, line + 1, check_ref} | acc]}
                else
                  {node, acc}
                end

              {:ok, check_ref, :this_file} ->
                {node, [{sf.filename, :all_lines, check_ref} | acc]}

              # `parse_disable_comment/1` only ever returns these three shapes,
              # but an explicit catch-all keeps the match total if it grows.
              _ ->
                {node, acc}
            end

          node, acc ->
            {node, acc}
        end,
        fn node, acc -> {node, acc} end
      )

    disabled
  end

  defp collect_disabled_from_lines(%SourceFile{lines: lines, filename: filename}) do
    Enum.flat_map(lines, fn {line_no, line_content} ->
      case parse_disable_comment(line_content) do
        {:ok, check_ref, :next_line} ->
          [{filename, line_no + 1, check_ref}]

        {:ok, check_ref, :this_file} ->
          [{filename, :all_lines, check_ref}]

        _ ->
          []
      end
    end)
  end

  @disable_pattern ~r/metacredo:disable-for-(next-line|this-file)\s*(.*)/

  defp parse_disable_comment(text) do
    case Regex.run(@disable_pattern, String.trim(text)) do
      [_, "next-line", check_name] ->
        {:ok, resolve_check_ref(check_name), :next_line}

      [_, "this-file", check_name] ->
        {:ok, resolve_check_ref(check_name), :this_file}

      _ ->
        :ignore
    end
  end

  defp resolve_check_ref(""), do: :all
  defp resolve_check_ref(name), do: Module.concat([String.trim(name)])

  defp maybe_filter_strict(issues, true) do
    Enum.filter(issues, fn issue ->
      Issue.priority_value(issue.priority) >= Issue.priority_value(:normal)
    end)
  end

  defp maybe_filter_strict(issues, _), do: issues

  # `--min-confidence high` keeps only AST-structural findings, dropping the
  # name-substring heuristics that produce most of the noise.
  defp maybe_filter_confidence(issues, nil), do: issues

  defp maybe_filter_confidence(issues, min_confidence) do
    floor = Issue.confidence_value(min_confidence)

    Enum.filter(issues, fn issue ->
      Issue.confidence_value(issue.confidence) >= floor
    end)
  end

  # `--diff-lines`: keep only findings on lines the diff actually touched.
  # Issues without a line number cannot be attributed to a hunk, so they are
  # dropped rather than reported against the whole file.
  defp maybe_filter_changed_lines(issues, nil), do: issues

  defp maybe_filter_changed_lines(issues, changed_lines) do
    Enum.filter(issues, fn issue ->
      case Map.get(changed_lines, issue.filename) do
        nil -> false
        lines -> issue.line_no != nil and MapSet.member?(lines, issue.line_no)
      end
    end)
  end

  # -- Baseline --

  defp apply_baseline(issues, opts) do
    cond do
      path = opts[:write_baseline] ->
        Baseline.write(path, issues)
        issues

      path = opts[:baseline] ->
        Baseline.filter(issues, path)

      true ->
        issues
    end
  end

  defp sort_issues(issues) do
    Enum.sort_by(issues, fn issue ->
      {issue.filename || "", issue.line_no || 0, -Issue.priority_value(issue.priority)}
    end)
  end

  defp summarize(issues) do
    %{
      total: length(issues),
      by_category: Enum.frequencies_by(issues, & &1.category),
      by_severity: Enum.frequencies_by(issues, & &1.severity),
      by_check: Enum.frequencies_by(issues, & &1.check)
    }
  end
end
