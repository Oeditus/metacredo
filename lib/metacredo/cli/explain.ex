defmodule MetaCredo.CLI.Explain do
  @moduledoc """
  Resolves and renders `mix metacredo explain` targets.

  Extracted from `Mix.Tasks.Metacredo` so the explain path can be tested
  without driving real compilation, filesystem discovery, and process exit
  codes, and so the Mix task keeps a single responsibility (option parsing
  plus analysis dispatch).

  ## Supported references

    * `file:line` -- runs a quick analysis on the file and explains the check
      that produced the first issue at that line, rendering the offending
      source snippet. Falls back to treating the path as a check definition
      file when nothing is found at that line.
    * `file` -- explains the check whose source file is given.
    * `FQN` -- e.g. `MetaCredo.Check.Security.HardcodedValue`.
    * `short name` -- e.g. `HardcodedValue`.
  """

  alias MetaCredo.{CLI.Output, Config, Execution, Sources}

  # Project descriptor files, in priority order. The first entry whose files
  # exist wins. Expressed as data rather than a ten-deep `cond` so the
  # detection order is readable and extending it is a one-line change.
  @language_markers [
    {["mix.exs"], :elixir},
    {["rebar.config", "rebar.lock"], :erlang},
    {["pyproject.toml", "requirements.txt", "setup.py"], :python},
    {["Gemfile"], :ruby},
    {["stack.yaml", "cabal.project", "package.yaml"], :haskell},
    {["tsconfig.json"], :typescript},
    {["package.json"], :javascript},
    {["cure.json"], :cure},
    {["march.json"], :march}
  ]

  @doc """
  Explains the check referenced by `argv` (the arguments following
  `explain`), printing the explanation to stdout.

  Raises `Mix.Error` when no reference is given or it cannot be resolved.
  """
  @spec run([String.t()]) :: :ok
  def run([]) do
    Mix.raise("Usage: mix metacredo explain <check|file[:line]>")
  end

  def run([check_ref | _rest]) do
    {module, issue, language} = resolve(check_ref)

    if module && Code.ensure_loaded?(module) && function_exported?(module, :category, 0) do
      Output.print_explanation(module, issue, language)
    else
      Mix.raise("Check '#{check_ref}' not found.")
    end
  end

  @doc """
  Resolves a check reference to `{module, issue | nil, language}`.

  `issue` is only non-nil for the `file:line` form, where it carries the
  offending snippet shown by `Output.print_explanation/3`.
  """
  @spec resolve(String.t()) :: {module() | nil, MetaCredo.Issue.t() | nil, atom()}
  def resolve(ref) do
    cond do
      file_ref?(ref) -> resolve_file_ref(ref)
      String.contains?(ref, ".") -> {module_from_fqn(ref), nil, detect_project_language()}
      true -> {find_check_by_short_name(ref), nil, detect_project_language()}
    end
  end

  @doc """
  Detects the primary programming language used in the current project.

  Checks well-known project descriptor files first, then falls back to
  scanning source directories and returning the most prevalent language.
  """
  @spec detect_project_language() :: atom()
  def detect_project_language do
    Enum.find_value(@language_markers, &marker_language/1) || detect_language_from_sources()
  end

  # -- Private --

  defp resolve_file_ref(ref) do
    {path, line_no} = split_file_ref(ref)
    language = Sources.language_for(path) || detect_project_language()

    issue =
      if line_no && File.exists?(path), do: check_at_location(path, line_no)

    module = (issue && issue.check) || path_to_check_module(path)
    {module, issue, language}
  end

  defp module_from_fqn(ref), do: ref |> String.split(".") |> Module.concat()

  defp marker_language({files, language}) do
    if Enum.any?(files, &File.exists?/1), do: language
  end

  defp detect_language_from_sources do
    config = Config.default()

    counts =
      config.files.included
      |> Enum.flat_map(&source_paths/1)
      |> Enum.map(&Sources.language_for/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.frequencies()

    case Enum.max_by(counts, fn {_lang, count} -> count end, fn -> nil end) do
      {lang, _} -> lang
      nil -> :elixir
    end
  end

  defp source_paths(path) do
    if File.dir?(path) do
      Sources.supported_extensions()
      |> Enum.flat_map(&Path.wildcard("#{path}/**/*#{&1}"))
    else
      [path]
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
  #
  # `Application.ensure_all_started(:metastatic)` is required here: `explain`
  # is dispatched before `Execution.run/1`, so nothing else has started the
  # adapter registry yet and every parse would fail with `:noproc`.
  defp check_at_location(file_path, line_no) do
    _ = Application.ensure_all_started(:metastatic)
    checks = Config.enabled_checks(Config.default())
    source_files = Sources.find(%{included: [file_path], excluded: []})

    source_files
    |> Execution.run_on_source_files(checks)
    |> Enum.find(&(&1.line_no == line_no))
  end

  # Converts a check source file path to its module by case-insensitive
  # comparison against all compiled check modules in the build directory.
  #
  # The path may be relative (`lib/metacredo/check/...`) or absolute and
  # living outside the project (`/tmp/demo.ex`). Rather than stripping a
  # leading `lib/` (which only worked for in-project paths), we keep only the
  # trailing `MetaCredo/Check/...` segment when present, and otherwise fall
  # back to matching on the bare basename -- so `explain /tmp/foo.ex` resolves
  # by filename instead of failing outright.
  defp path_to_check_module(path) do
    normalized =
      path
      |> String.replace("\\", "/")
      |> String.replace(~r/\.exs?$/, "")

    case Regex.run(~r{(?:^|/)(MetaCredo/Check/.+)$}, normalized) do
      [_, tail] -> find_module_by_tail(tail)
      nil -> find_module_by_basename(Path.basename(normalized))
    end
  end

  defp find_module_by_tail(tail) do
    expected = tail |> String.split("/") |> Enum.map_join(".", &camelize/1) |> String.downcase()

    metacredo_check_modules()
    |> Enum.find(fn mod ->
      mod |> to_string() |> String.replace("Elixir.", "") |> String.downcase() == expected
    end)
  end

  defp find_module_by_basename(basename) do
    expected = camelize(basename) |> String.downcase()

    metacredo_check_modules()
    |> Enum.find(fn mod ->
      mod |> to_string() |> String.split(".") |> List.last() |> String.downcase() == expected
    end)
  end

  defp camelize(part) do
    part |> String.split("_") |> Enum.map_join("", &String.capitalize/1)
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
end
