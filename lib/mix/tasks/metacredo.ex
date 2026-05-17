defmodule Mix.Tasks.Metacredo do
  @shortdoc "Run MetaCredo static analysis checks"
  @moduledoc """
  Runs MetaCredo checks on your project.

  ## Usage

      $ mix metacredo
      $ mix metacredo --path lib/my_module
      $ mix metacredo --strict
      $ mix metacredo --only security,warning
      $ mix metacredo --format json
      $ mix metacredo --format github
      $ mix metacredo --diff
      $ mix metacredo --diff --base origin/develop --head HEAD
      $ mix metacredo explain MetaCredo.Check.Security.HardcodedValue

  ## Path

  The `--path` option restricts analysis to a specific file or directory.
  When omitted, the current directory (`.`) is used, with excluded patterns
  from the configuration still applied.

      $ mix metacredo --path lib/
      $ mix metacredo --path lib/my_app/accounts.ex

  ## Diff Mode

  When `--diff` is given, only files changed between `--base` (default:
  `origin/main`) and `--head` (default: `HEAD`) are analyzed. This is
  ideal for CI pipelines where you only want to check new or modified
  code in a pull request.

  ## GitHub Actions Format

  Use `--format github` to emit GitHub Actions workflow commands that
  produce inline PR annotations:

      ::error file=lib/foo.ex,line=42::Security issue found
  """

  use Mix.Task

  alias MetaCredo.{CLI.Output, Config, Execution, Git, Sources}

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("compile", ["--no-warnings"])

    {opts, args, _} =
      OptionParser.parse(argv,
        strict: [
          path: :string,
          strict: :boolean,
          only: :string,
          ignore: :string,
          format: :string,
          config_file: :string,
          files_included: :string,
          files_excluded: :string,
          diff: :boolean,
          base: :string,
          head: :string
        ]
      )

    case args do
      ["explain", check_name | _] ->
        run_explain(check_name)

      _ ->
        run_analysis(opts)
    end
  end

  defp run_analysis(opts) do
    execution_opts =
      []
      |> maybe_add(:strict, opts[:strict])
      |> maybe_add(:config_file, opts[:config_file])
      |> maybe_add(:only, parse_list(opts[:only]))
      |> maybe_add(:ignore, parse_list(opts[:ignore]))
      |> maybe_add(:files_included, parse_list(opts[:files_included]))
      |> maybe_add(:files_excluded, parse_list(opts[:files_excluded]))
      |> maybe_add_path(opts)
      |> maybe_add_diff_files(opts)

    report = Execution.run(execution_opts)

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

  # Applies --path as the analysis root when --files-included is not set.
  # Defaults to "." (current directory) when neither option is provided.
  defp maybe_add_path(opts_acc, opts) do
    if Keyword.has_key?(opts_acc, :files_included) do
      opts_acc
    else
      path = opts[:path] || "."
      Keyword.put(opts_acc, :files_included, [path])
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

      # Convert relative paths to absolute for Sources.find/1
      absolute_files = Enum.map(files, &Path.join(repo_root, &1))

      # When --path is given, restrict diff results to files under that path.
      absolute_files =
        case opts[:path] do
          nil ->
            absolute_files

          path ->
            scope = path |> Path.expand() |> Path.absname()
            Enum.filter(absolute_files, &String.starts_with?(&1, scope))
        end

      if absolute_files == [] do
        Mix.shell().info("No changed files found in diff, nothing to analyze.")
      end

      Keyword.put(opts_acc, :files_included, absolute_files)
    else
      opts_acc
    end
  end

  defp run_explain(check_ref) do
    {module, issue, language} = resolve_check_with_context(check_ref)

    if module && Code.ensure_loaded?(module) && function_exported?(module, :category, 0) do
      Output.print_explanation(module, issue, language)
    else
      Mix.shell().error("Check '#{check_ref}' not found.")
    end
  end

  # Resolves a check reference and returns {module, issue | nil, language}.
  #
  # Supported forms:
  #   file:line  e.g. lib/metacredo/cli/output.ex:42
  #              Runs a quick analysis on the file; returns the check module
  #              and issue that produced the first hit at that line.
  #              Falls back to treating the path as a check definition file.
  #   file       e.g. lib/metacredo/check/security/hardcoded_value.ex
  #   FQN        e.g. MetaCredo.Check.Security.HardcodedValue
  #   short name e.g. HardcodedValue
  defp resolve_check_with_context(ref) do
    cond do
      file_ref?(ref) ->
        {path, line_no} = split_file_ref(ref)
        language = Sources.language_for(path) || detect_project_language()

        issue =
          if line_no && File.exists?(path), do: check_at_location(path, line_no)

        module = (issue && issue.check) || path_to_check_module(path)
        {module, issue, language}

      String.contains?(ref, ".") ->
        module = ref |> String.split(".") |> Module.concat()
        {module, nil, detect_project_language()}

      true ->
        {find_check_by_short_name(ref), nil, detect_project_language()}
    end
  end

  defp file_ref?(str) do
    exts = Sources.supported_extensions() |> Enum.map_join("|", &Regex.escape/1)
    Regex.match?(~r/(?:#{exts})(:\d+)?$/, str)
  end

  defp split_file_ref(str) do
    case String.split(str, ":") do
      [path, line] ->
        case Integer.parse(line) do
          {n, ""} -> {path, n}
          _ -> {str, nil}
        end

      [path] ->
        {path, nil}

      _ ->
        {str, nil}
    end
  end

  # Run all enabled checks on a single file and return the first issue at the
  # given line number (or nil if none is found).
  defp check_at_location(file_path, line_no) do
    checks = Config.enabled_checks(Config.default())
    source_files = Sources.find(%{included: [file_path], excluded: []})

    source_files
    |> Execution.run_on_source_files(checks)
    |> Enum.find(&(&1.line_no == line_no))
  end

  # Converts a check source file path to its module by case-insensitive
  # comparison against all compiled check modules in the build directory.
  defp path_to_check_module(path) do
    relative =
      path
      |> String.replace(~r/^(lib|test|src)\//, "")
      |> String.replace(~r/\.exs?$/, "")

    expected =
      relative
      |> String.split("/")
      |> Enum.map_join(".", fn part ->
        part |> String.split("_") |> Enum.map_join("", &String.capitalize/1)
      end)
      |> String.downcase()

    metacredo_check_modules()
    |> Enum.find(fn mod ->
      mod |> to_string() |> String.replace("Elixir.", "") |> String.downcase() == expected
    end)
  end

  defp find_check_by_short_name(short_name) do
    metacredo_check_modules()
    |> Enum.find(fn mod ->
      mod |> to_string() |> String.split(".") |> List.last() == short_name
    end)
  end

  # Enumerate all MetaCredo check modules by scanning the compiled BEAM files.
  # This is reliable in a Mix task context where :application.get_key/2 may
  # not yet be available.
  defp metacredo_check_modules do
    ebin = Path.join([Mix.Project.build_path(), "lib", "metacredo", "ebin"])

    if File.dir?(ebin) do
      ebin
      |> File.ls!()
      |> Enum.filter(&String.match?(&1, ~r/^Elixir\.MetaCredo\.Check\./i))
      |> Enum.flat_map(fn beam_file ->
        mod = beam_file |> String.trim_trailing(".beam") |> String.to_atom()

        if Code.ensure_loaded?(mod) and function_exported?(mod, :category, 0),
          do: [mod],
          else: []
      end)
    else
      []
    end
  end

  # Detects the primary programming language used in the current project.
  # Checks for well-known project descriptor files first, then falls back to
  # scanning source directories and returning the most prevalent language.
  defp detect_project_language do
    cond do
      File.exists?("mix.exs") ->
        :elixir

      File.exists?("rebar.config") or File.exists?("rebar.lock") ->
        :erlang

      true ->
        detect_language_from_sources()
    end
  end

  defp detect_language_from_sources do
    config = Config.default()

    counts =
      config.files.included
      |> Enum.flat_map(fn path ->
        if File.dir?(path) do
          Sources.supported_extensions()
          |> Enum.flat_map(&Path.wildcard("#{path}/**/*#{&1}"))
        else
          [path]
        end
      end)
      |> Enum.map(&Sources.language_for/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.frequencies()

    case Enum.max_by(counts, fn {_lang, count} -> count end, fn -> nil end) do
      {lang, _} -> lang
      nil -> :elixir
    end
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
