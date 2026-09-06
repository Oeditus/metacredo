defmodule MetaCredo do
  @moduledoc """
  Cross-language static code analysis tool built on MetaAST.

  MetaCredo is a static analysis tool that operates on the unified MetaAST
  representation provided by Metastatic. Write a check once and run it
  across all languages supported by Metastatic: Elixir, Python, Ruby,
  Haskell, Erlang, Cure, March, JavaScript, TypeScript, and more.

  ## Usage

      # Run all checks
      $ mix metacredo

      # Run with strict mode (normal+ priority)
      $ mix metacredo --strict

      # Run diff-based analysis on changed files
      $ mix metacredo --diff --strict

      # Emit GitHub Actions workflow commands (inline PR annotations)
      $ mix metacredo --diff --format github

      # Generate default configuration file (.metacredo.exs)
      $ mix metacredo.gen.config

  ## Programmatic API

      alias MetaCredo.{Execution, SourceFile}

      source_files = MetaCredo.Sources.find("lib/")
      report = Execution.run(files_included: ["lib/"])

      Enum.each(report.issues, fn issue ->
        IO.puts("\#{issue.filename}:\#{issue.line_no} \#{issue.message}")
      end)
  """

  @version Mix.Project.config()[:version]

  @doc "Returns the version of MetaCredo."
  def version, do: @version
end
