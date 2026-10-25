defmodule Mix.Tasks.Metacredo do
  @shortdoc "Run MetaCredo static analysis checks"
  @moduledoc """
  Runs MetaCredo checks on your project.

  ## Usage

      $ mix metacredo
      $ mix metacredo --path lib/my_module
      $ mix metacredo --strict
      $ mix metacredo --only security,warning
      $ mix metacredo --min-confidence high
      $ mix metacredo --format json
      $ mix metacredo --format github
      $ mix metacredo --diff
      $ mix metacredo --diff --diff-lines
      $ mix metacredo --diff --base origin/develop --head HEAD
      $ mix metacredo --config path/to/.metacredo.exs
      $ mix metacredo --write-baseline .metacredo.baseline.json
      $ mix metacredo --baseline .metacredo.baseline.json
      $ mix metacredo explain MetaCredo.Check.Security.HardcodedValue
      $ mix metacredo explain lib/my_app/accounts.ex:42

  ## Path

  The `--path` option restricts analysis to a specific file or directory.
  When omitted, the `included` paths from `.metacredo.exs` are used (or
  their `["lib/", "src/", "web/"]` default), with excluded patterns from
  the configuration still applied. Test trees (`test/`, including nested
  `lib/test/` and umbrella `apps/*/test/`) are excluded by default; passing
  `--path test/` (or listing it in `files.included`) opts them back in.

      $ mix metacredo --path lib/
      $ mix metacredo --path lib/my_app/accounts.ex
      $ mix metacredo --path test/

  ## Diff Mode

  When `--diff` is given, only files changed between `--base` (default:
  `origin/main`) and `--head` (default: `HEAD`) are analyzed. This is
  ideal for CI pipelines where you only want to check new or modified
  code in a pull request.

  Add `--diff-lines` to report only findings on the lines the diff actually
  touched. Files are still analysed whole (a check needs surrounding
  context), but pre-existing findings elsewhere in a changed file are
  suppressed.

  ## Confidence

  Every issue carries a confidence level. `--min-confidence high` keeps only
  AST-structural findings, dropping the name-substring heuristics that
  account for most false positives. Accepts `high`, `medium` (default), or
  `low`.

  ## Baseline

  `--write-baseline PATH` records the current findings; `--baseline PATH`
  then reports only issues *not* present in that file. This is how to adopt
  MetaCredo on a codebase that is not clean today.

  ## GitHub Actions Format

  Use `--format github` to emit GitHub Actions workflow commands that
  produce inline PR annotations:

      ::error file=lib/foo.ex,line=42::Security issue found
  """

  use Mix.Task

  alias MetaCredo.{CLI.Explain, CLI.Output, Execution, Git, Issue, Sources}

  # Switches understood by the analysis path. `explain` is a *subcommand*, not
  # a switch, and must be dispatched before `OptionParser` ever sees it:
  # `OptionParser.parse/2` in `:strict` mode raises `ParseError` on the bare
  # word `explain`, which previously aborted the whole task and fell through
  # to a full analysis run.
  @switches [
    path: :string,
    strict: :boolean,
    only: :string,
    ignore: :string,
    format: :string,
    config: :string,
    config_file: :string,
    files_included: :string,
    files_excluded: :string,
    diff: :boolean,
    diff_lines: :boolean,
    base: :string,
    head: :string,
    no_db: :boolean,
    no_user: :boolean,
    min_confidence: :string,
    baseline: :string,
    write_baseline: :string
  ]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("compile", ["--no-warnings"])

    case argv do
      ["explain" | rest] ->
        Explain.run(rest)

      _ ->
        run_analysis(parse_opts(argv))
    end
  end

  # Parses analysis switches, raising a readable `Mix.raise/1` on unknown or
  # malformed options instead of letting an `OptionParser.ParseError` escape
  # as an opaque stacktrace.
  defp parse_opts(argv) do
    case OptionParser.parse(argv, strict: @switches) do
      {opts, _args, []} ->
        opts

      {_opts, _args, invalid} ->
        Mix.raise(
          "Invalid option(s): " <>
            Enum.map_join(invalid, ", ", fn {name, _value} -> name end) <>
            "\nRun `mix help metacredo` for the list of supported options."
        )
    end
  end

  defp run_analysis(opts) do
    exec_opts = build_execution_opts(opts)
    strip_prefix = exec_opts[:path_prefix_to_strip]
    report = Execution.run(Keyword.delete(exec_opts, :path_prefix_to_strip))
    report = %{report | issues: relativize_issues(report.issues, strip_prefix)}

    case opts[:format] do
      "json" ->
        IO.puts(Output.to_json(report))

      "github" ->
        Output.print_github(report)

      _ ->
        Output.print_report(report)
    end

    # Set exit code based on issues
    exit_status =
      report.issues
      |> Enum.map(& &1.exit_status)
      |> Enum.reduce(0, &Bitwise.bor/2)

    if exit_status > 0 do
      System.at_exit(fn _ -> exit({:shutdown, exit_status}) end)
    end
  end

  # Rewrites absolute issue filenames back to repo-relative form. Diff mode
  # discovers files via absolute paths (required to read them), but every
  # consumer -- GitHub annotations, JSON output, editor jump-to-line -- needs
  # paths relative to the repository root.
  defp relativize_issues(issues, nil), do: issues

  defp relativize_issues(issues, prefix) do
    Enum.map(issues, fn issue ->
      %{issue | filename: Path.relative_to(issue.filename, prefix)}
    end)
  end

  @doc false
  # Builds `MetaCredo.Execution.run/1`'s options from parsed CLI `opts`.
  # Exposed (undocumented) for regression testing of the --path / config
  # `included` precedence rules, since `mix metacredo`'s own `run/1` drives
  # real compilation, filesystem discovery, and process exit codes that are
  # awkward to assert on directly.
  @spec build_execution_opts(keyword()) :: keyword()
  def build_execution_opts(opts) do
    []
    |> maybe_add(:strict, opts[:strict])
    |> maybe_add(:config_file, opts[:config] || opts[:config_file])
    |> maybe_add(:only, parse_list(opts[:only]))
    |> maybe_add(:ignore, parse_list(opts[:ignore]))
    |> maybe_add(:files_included, parse_list(opts[:files_included]))
    |> maybe_add(:files_excluded, parse_list(opts[:files_excluded]))
    |> maybe_add(:no_db, opts[:no_db])
    |> maybe_add(:no_user, opts[:no_user])
    |> maybe_add(:min_confidence, Issue.parse_confidence(opts[:min_confidence]))
    |> maybe_add(:baseline, opts[:baseline])
    |> maybe_add(:write_baseline, opts[:write_baseline])
    |> maybe_add_path(opts)
    |> maybe_add_diff_files(opts)
  end

  # Applies --path as the analysis root when --files-included is not set.
  # When neither --path nor --files-included is given, :files_included is
  # left unset entirely so `Execution.resolve_file_patterns/2` falls back to
  # the `included` list from `.metacredo.exs` (or its "lib/"/"src/"/"web/"
  # default) instead of silently defaulting to the current directory -- which
  # would sweep `deps/`, `_build/`, and other non-source directories into
  # analysis, ignoring the configured/default exclusions in the process (see
  # CHANGELOG for details).
  defp maybe_add_path(opts_acc, opts) do
    cond do
      Keyword.has_key?(opts_acc, :files_included) ->
        opts_acc

      opts[:path] ->
        Keyword.put(opts_acc, :files_included, [opts[:path]])

      true ->
        opts_acc
    end
  end

  # Resolves changed files from git diff and injects them as :files_included.
  # When --path is given, the repo root is resolved from that path so that
  # diffs in an external directory are handled correctly. Files are then
  # further filtered to those under the given path.
  defp maybe_add_diff_files(opts_acc, opts) do
    if opts[:diff] do
      git_search_dir =
        case opts[:path] do
          nil -> File.cwd!()
          path -> path |> Path.expand() |> Path.absname()
        end

      repo_root = Git.repo_root(git_search_dir)

      unless repo_root do
        Mix.raise("--diff requires a git repository, but none was found in #{git_search_dir}")
      end

      diff_opts =
        []
        |> maybe_add(:base, opts[:base])
        |> maybe_add(:head, opts[:head])
        |> maybe_add(:extensions, Sources.supported_extensions())

      files = Git.changed_files!(repo_root, diff_opts)

      # `Sources.find/1` needs absolute paths to read the files, but issue
      # `filename`s must stay repo-relative or GitHub Actions cannot attach
      # inline PR annotations (`::warning file=/abs/path` is silently dropped).
      # We therefore hand absolute paths to discovery and rewrite the
      # resulting issue filenames back to repo-relative before reporting.
      scoped_files =
        files
        |> Enum.map(&Path.join(repo_root, &1))
        |> restrict_to_path(opts[:path])

      if scoped_files == [] do
        Mix.shell().info("No changed files found in diff, nothing to analyze.")
      end

      # `--diff-lines` narrows reporting to the lines the diff actually
      # touched. Files are still analysed whole (a check needs surrounding
      # context), but only findings on changed lines are reported.
      changed_lines =
        if opts[:diff_lines] do
          repo_root
          |> Git.changed_lines!(diff_opts)
          |> restrict_lines_to_path(opts[:path], repo_root)
        end

      opts_acc
      |> Keyword.put(:files_included, scoped_files)
      |> Keyword.put(:path_prefix_to_strip, repo_root)
      |> Keyword.put(:changed_lines, changed_lines)
      # Diff mode derives its file list from git, not from a deliberate user
      # opt-in, so the default `test/` exclusion must stay in force -- exactly
      # as it does for a normal run.
      |> Keyword.put(:lift_test_exclusion, false)
    else
      opts_acc
    end
  end

  # When `--path` is given, restrict diff results to files under that path.
  defp restrict_to_path(files, nil), do: files

  defp restrict_to_path(files, path) do
    scope = path |> Path.expand() |> Path.absname()
    Enum.filter(files, &String.starts_with?(&1, scope))
  end

  defp restrict_lines_to_path(lines, nil, _repo_root), do: lines

  defp restrict_lines_to_path(lines, path, repo_root) do
    scope = path |> Path.expand() |> Path.absname() |> Path.relative_to(repo_root)
    Map.filter(lines, fn {file, _} -> String.starts_with?(file, scope) end)
  end

  defp parse_list(nil), do: nil
  defp parse_list(""), do: nil

  defp parse_list(str) do
    str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.to_atom/1)
  end

  defp maybe_add(opts, _key, nil), do: opts
  defp maybe_add(opts, key, value), do: Keyword.put(opts, key, value)
end
