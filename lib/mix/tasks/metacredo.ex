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

  alias MetaCredo.{CLI.Output, Execution}

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

    {:ok, report} = Execution.run(execution_opts)

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

  defp run_explain(check_name) do
    module =
      check_name
      |> String.split(".")
      |> Module.concat()

    if Code.ensure_loaded?(module) and function_exported?(module, :category, 0) do
      Output.print_explanation(module)
    else
      Mix.shell().error("Check #{check_name} not found.")
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
