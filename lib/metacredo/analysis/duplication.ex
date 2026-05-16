defmodule MetaCredo.Analysis.Duplication do
  @moduledoc """
  Programmatic code duplication detection API.

  Detects code clones across the same or different programming languages
  by operating on the unified MetaAST representation. Supports four types:

  - **Type I**: Exact clones (identical AST)
  - **Type II**: Renamed clones (identical structure, different identifiers)
  - **Type III**: Near-miss clones (similar structure with modifications)
  - **Type IV**: Semantic clones (different syntax, same behavior)

  Delegates to `Metastatic.Analysis.Duplication` for the actual analysis,
  giving MetaCredo a stable API surface for downstream consumers.

  ## Usage

      alias Metastatic.Document
      alias MetaCredo.Analysis.Duplication

      doc1 = Document.new(ast1, :elixir)
      doc2 = Document.new(ast2, :python)

      {:ok, result} = Duplication.detect(doc1, doc2)
      result.duplicate?        # => true
      result.clone_type        # => :type_i
      result.similarity_score  # => 1.0
  """

  @doc "Detects duplication between two documents."
  defdelegate detect(doc1, doc2), to: Metastatic.Analysis.Duplication

  @doc "Detects duplication between two documents with options."
  defdelegate detect(doc1, doc2, opts), to: Metastatic.Analysis.Duplication

  @doc "Detects duplication between two documents, raising on error."
  defdelegate detect!(doc1, doc2), to: Metastatic.Analysis.Duplication

  @doc false
  defdelegate detect!(doc1, doc2, opts), to: Metastatic.Analysis.Duplication

  @doc "Calculates similarity score between two ASTs (0.0 to 1.0)."
  defdelegate similarity(ast1, ast2), to: Metastatic.Analysis.Duplication

  @doc "Detects duplicates across multiple documents."
  defdelegate detect_in_list(documents), to: Metastatic.Analysis.Duplication

  @doc "Detects duplicates across multiple documents with options."
  defdelegate detect_in_list(documents, opts), to: Metastatic.Analysis.Duplication

  @doc "Detects duplicates across multiple documents, raising on error."
  defdelegate detect_in_list!(documents), to: Metastatic.Analysis.Duplication

  @doc false
  defdelegate detect_in_list!(documents, opts), to: Metastatic.Analysis.Duplication

  @doc "Generates a structural fingerprint for an AST."
  defdelegate fingerprint(ast), to: Metastatic.Analysis.Duplication
end
