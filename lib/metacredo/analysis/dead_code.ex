defmodule MetaCredo.Analysis.DeadCode do
  @moduledoc """
  Programmatic intraprocedural dead code detection API.

  Identifies unreachable code, unused functions, and other patterns
  that result in dead code. Works across all supported languages
  by operating on the unified MetaAST representation.

  Delegates to `Metastatic.Analysis.DeadCode` for the actual analysis,
  giving MetaCredo a stable API surface for downstream consumers.

  ## Dead Code Types

  - **Unreachable after return** -- Code following early_return nodes
  - **Constant conditionals** -- Branches that can never execute
  - **Unused functions** -- Function definitions never called (module context)

  ## Usage

      alias Metastatic.Document
      alias MetaCredo.Analysis.DeadCode

      doc = Document.new(ast, :python)
      {:ok, result} = DeadCode.analyze(doc)

      result.has_dead_code?         # => true
      result.total_dead_statements  # => 1
      result.dead_locations         # => [%{type: :unreachable_after_return, ...}]
  """

  @doc "Analyzes a document for dead code patterns."
  defdelegate analyze(doc), to: Metastatic.Analysis.DeadCode

  @doc "Analyzes a document for dead code patterns with options."
  defdelegate analyze(doc_or_language, opts_or_source), to: Metastatic.Analysis.DeadCode

  @doc false
  defdelegate analyze(language, source_or_ast, opts), to: Metastatic.Analysis.DeadCode

  @doc "Analyzes a document for dead code patterns, raising on error."
  defdelegate analyze!(doc), to: Metastatic.Analysis.DeadCode

  @doc false
  defdelegate analyze!(doc_or_language, opts_or_source), to: Metastatic.Analysis.DeadCode

  @doc false
  defdelegate analyze!(language, source_or_ast, opts), to: Metastatic.Analysis.DeadCode
end
