defmodule MetaCredo.Analysis.Purity do
  @moduledoc """
  Programmatic purity / side-effect analysis API.

  Determines whether code is pure (no side effects) or impure
  (I/O, mutations, random operations, etc.) by operating on
  the unified MetaAST representation.

  Delegates to `Metastatic.Analysis.Purity` for the actual analysis,
  giving MetaCredo a stable API surface for downstream consumers.

  ## Usage

      alias Metastatic.Document
      alias MetaCredo.Analysis.Purity

      doc = Document.new(ast, :elixir)
      {:ok, result} = Purity.analyze(doc)

      result.pure?        # => true
      result.effects      # => []
      result.confidence   # => :high
  """

  @doc "Analyzes a document for purity / side effects."
  defdelegate analyze(doc), to: Metastatic.Analysis.Purity

  @doc "Analyzes a document for purity with options."
  defdelegate analyze(doc_or_language, opts_or_source), to: Metastatic.Analysis.Purity

  @doc false
  defdelegate analyze(language, source_or_ast, opts), to: Metastatic.Analysis.Purity

  @doc "Analyzes a document for purity, raising on error."
  defdelegate analyze!(doc), to: Metastatic.Analysis.Purity

  @doc false
  defdelegate analyze!(doc_or_language, opts_or_source), to: Metastatic.Analysis.Purity

  @doc false
  defdelegate analyze!(language, source_or_ast, opts), to: Metastatic.Analysis.Purity
end
