defmodule MetaCredo.SourceFile do
  @moduledoc """
  Wraps a `Metastatic.Document` with source text and filename for analysis.

  Analogous to `Credo.SourceFile`, providing access to the AST, source lines,
  and metadata needed by checks.
  """

  alias Metastatic.Document

  @type t :: %__MODULE__{
          document: Document.t(),
          filename: String.t(),
          source: String.t(),
          lines: [{pos_integer(), String.t()}],
          language: atom(),
          status: :valid | :invalid | :timed_out
        }

  @enforce_keys [:document, :filename, :language]
  defstruct [
    :document,
    :filename,
    :source,
    :language,
    lines: [],
    status: :valid
  ]

  @doc """
  Parses source code into a `SourceFile`.

  Uses the appropriate `Metastatic.Adapter` for the given language to
  produce a `Metastatic.Document`, then wraps it with source metadata.
  """
  @spec parse(String.t(), String.t(), atom()) :: {:ok, t()} | {:error, term()}
  def parse(source, filename, language) do
    with {:ok, adapter} <- Metastatic.adapter_for_language(language),
         {:ok, native_ast} <- adapter.parse(source),
         {:ok, meta_ast, metadata} <- adapter.to_meta(native_ast) do
      doc = Document.new(meta_ast, language, metadata, source)
      lines = to_lines(source)

      {:ok,
       %__MODULE__{
         document: doc,
         filename: filename,
         source: source,
         language: language,
         lines: lines,
         status: :valid
       }}
    else
      {:error, reason} ->
        {:error, {:parse_failed, filename, reason}}
    end
  end

  @doc "Returns the MetaAST for this source file."
  @spec ast(t()) :: Metastatic.AST.meta_ast()
  def ast(%__MODULE__{document: %Document{ast: ast}}), do: ast

  @doc "Returns the source code as a string."
  @spec source(t()) :: String.t()
  def source(%__MODULE__{source: source}), do: source

  @doc "Returns lines as `[{line_no, line_content}]`."
  @spec lines(t()) :: [{pos_integer(), String.t()}]
  def lines(%__MODULE__{lines: lines}), do: lines

  @doc "Returns the line at the given 1-based line number."
  @spec line_at(t(), pos_integer()) :: String.t() | nil
  def line_at(%__MODULE__{lines: lines}, line_no) do
    case Enum.find(lines, fn {n, _} -> n == line_no end) do
      {_, line} -> line
      nil -> nil
    end
  end

  @doc "Returns the language of this source file."
  @spec language(t()) :: atom()
  def language(%__MODULE__{language: lang}), do: lang

  defp to_lines(source) when is_binary(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map(fn {line, idx} -> {idx, line} end)
  end

  defp to_lines(_), do: []
end
