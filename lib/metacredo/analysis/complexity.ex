defmodule MetaCredo.Analysis.Complexity do
  @moduledoc """
  Programmatic complexity analysis API.

  Provides access to comprehensive code complexity metrics that work
  uniformly across all supported languages by operating on the unified
  MetaAST representation.

  Delegates to `Metastatic.Analysis.Complexity` for the actual analysis,
  giving MetaCredo a stable API surface for downstream consumers
  (e.g., Ragex) that do not need to depend on Metastatic directly.

  ## Metrics

  - **Cyclomatic Complexity** -- McCabe metric, decision points + 1
  - **Cognitive Complexity** -- Structural complexity with nesting penalties
  - **Nesting Depth** -- Maximum nesting level
  - **Halstead Metrics** -- Volume, difficulty, effort
  - **Lines of Code** -- Physical, logical, comments
  - **Function Metrics** -- Statements, returns, variables

  ## Usage

      alias Metastatic.Document
      alias MetaCredo.Analysis.Complexity

      doc = Document.new(ast, :elixir)
      {:ok, result} = Complexity.analyze(doc)

      result.cyclomatic       # => 2
      result.cognitive        # => 1
      result.max_nesting      # => 1
  """

  @doc "Analyzes a document for complexity metrics."
  defdelegate analyze(doc), to: Metastatic.Analysis.Complexity

  @doc "Analyzes a document for complexity metrics with options."
  defdelegate analyze(doc_or_language, opts_or_source), to: Metastatic.Analysis.Complexity

  @doc false
  defdelegate analyze(language, source_or_ast, opts), to: Metastatic.Analysis.Complexity

  @doc "Analyzes a document for complexity metrics, raising on error."
  defdelegate analyze!(doc), to: Metastatic.Analysis.Complexity

  @doc false
  defdelegate analyze!(doc_or_language, opts_or_source), to: Metastatic.Analysis.Complexity

  @doc false
  defdelegate analyze!(language, source_or_ast, opts), to: Metastatic.Analysis.Complexity
end
