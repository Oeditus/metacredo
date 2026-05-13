defmodule Mix.Tasks.Metacredo do
  @shortdoc "Run MetaCredo static analysis checks"
  @moduledoc """
  Runs MetaCredo checks on your project.

  ## Usage

      $ mix metacredo
      $ mix metacredo --strict
      $ mix metacredo --only security,warning
      $ mix metacredo --format json
      $ mix metacredo explain MetaCredo.Check.Security.HardcodedValue
  """

  use Mix.Task

  alias MetaCredo.{CLI.Output, Config, Execution, Sources}

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("compile", ["--no-warnings"])

    {opts, args, _} =
      OptionParser.parse(argv,
        strict: [
          strict: :boolean,
          only: :string,
          ignore: :string,
          format: :string,
          config_file: :string,
          files_included: :string,
          files_excluded: :string
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

    report = Execution.run(execution_opts)

    case opts[:format] do
      "json" ->
        IO.puts(Output.to_json(report))

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

  defp run_explain(check_ref) do
    module = resolve_check_module(check_ref)

    if module && Code.ensure_loaded?(module) && function_exported?(module, :category, 0) do
      Output.print_explanation(module)
    else
      Mix.shell().error("Check '#{check_ref}' not found.")
    end
  end

  # Resolves a check reference in any of these forms:
  #   file:line  e.g. lib/metacredo/cli/output.ex:42
  #              Runs a quick analysis on the file; explains the check that
  #              produced an issue at that line. Falls back to treating the
  #              file as a check definition if no issue is found.
  #   file       e.g. lib/metacredo/check/security/hardcoded_value.ex
  #   FQN        e.g. MetaCredo.Check.Security.HardcodedValue
  #   short name e.g. HardcodedValue
  defp resolve_check_module(ref) do
    cond do
      file_ref?(ref) ->
        {path, line_no} = split_file_ref(ref)

        check_from_location =
          if line_no && File.exists?(path), do: check_at_location(path, line_no)

        check_from_location || path_to_check_module(path)

      String.contains?(ref, ".") ->
        try do
          ref |> String.split(".") |> Module.concat()
        rescue
          _ -> nil
        end

      true ->
        find_check_by_short_name(ref)
    end
  end

  defp file_ref?(str), do: Regex.match?(~r/\.exs?(:\d+)?$/, str)

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

  # Run all enabled checks on a single file and return the check module that
  # produced the first issue at the given line number.
  defp check_at_location(file_path, line_no) do
    checks = Config.enabled_checks(Config.default())
    source_files = Sources.find(%{included: [file_path], excluded: []})

    source_files
    |> Execution.run_on_source_files(checks)
    |> Enum.find(&(&1.line_no == line_no))
    |> case do
      nil -> nil
      issue -> issue.check
    end
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
      |> Enum.map(fn part ->
        part |> String.split("_") |> Enum.map(&String.capitalize/1) |> Enum.join()
      end)
      |> Enum.join(".")
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
