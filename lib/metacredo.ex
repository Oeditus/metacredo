defmodule MetaCredo do
  @moduledoc """
  Cross-language static code analysis tool built on MetaAST.

  MetaCredo is a static analysis tool that operates on the unified MetaAST
  representation provided by Metastatic. Write a check once and run it
  across all languages supported by Metastatic: Elixir, Python, Ruby,
  Haskell, Erlang, and more.

  ## Usage

      # Run all checks
      $ mix metacredo

      # Run with strict mode
      $ mix metacredo --strict

      # Generate default configuration
      $ mix metacredo.gen.config

  ## Programmatic API

      alias MetaCredo.{Execution, SourceFile}

      source_files = MetaCredo.Sources.find("lib/")
      {:ok, report} = Execution.run(source_files)

      Enum.each(report.issues, fn issue ->
        IO.puts("\#{issue.filename}:\#{issue.line_no} \#{issue.message}")
      end)
  """

  @version Mix.Project.config()[:version]

  @doc "Returns the version of MetaCredo."
  def version, do: @version
end
