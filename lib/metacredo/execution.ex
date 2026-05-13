defmodule MetaCredo.Execution do
  @moduledoc """
  Orchestrates the full analysis pipeline: source discovery, check execution,
  issue collection, and inline-disable filtering.
  """

  alias MetaCredo.{Config, Issue, Sources, SourceFile}
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
          files_excluded: [term()] | nil
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
  """
  @spec run(run_opts()) :: report()
  def run(opts \\ []) do
    start = System.monotonic_time(:millisecond)

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
      |> sort_issues()

    elapsed = System.monotonic_time(:millisecond) - start

    %{
      source_files: source_files,
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
      excluded: opts[:files_excluded] || base.excluded
    }
  end

  defp resolve_checks(config, opts) do
    checks = Config.enabled_checks(config)

    checks =
      case opts[:only] do
        nil -> checks
        [] -> checks
        categories -> Enum.filter(checks, fn {mod, _} -> mod.category() in categories end)
      end

    case opts[:ignore] do
      nil -> checks
      [] -> checks
      categories -> Enum.reject(checks, fn {mod, _} -> mod.category() in categories end)
    end
  end

  defp run_checks_on_file(%SourceFile{} = source_file, checks) do
    Enum.flat_map(checks, fn {check_module, params} ->
      try do
        check_module.run(source_file, params)
      rescue
        e ->
          Logger.warning(
            "Check #{inspect(check_module)} failed on #{source_file.filename}: #{inspect(e)}"
          )

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
      {_, disabled} =
        AST.traverse(
          SourceFile.ast(sf),
          [],
          fn
            {:comment, _meta, text} = node, acc when is_binary(text) ->
              case parse_disable_comment(text) do
                {:ok, check_ref, :next_line} ->
                  # The line after the comment
                  line = AST.get_meta(node, :line)

                  if line do
                    {node, [{sf.filename, line + 1, check_ref} | acc]}
                  else
                    {node, acc}
                  end

                {:ok, check_ref, :this_file} ->
                  {node, [{sf.filename, :all_lines, check_ref} | acc]}

                :ignore ->
                  {node, acc}
              end

            node, acc ->
              {node, acc}
          end,
          fn node, acc -> {node, acc} end
        )

      disabled
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
