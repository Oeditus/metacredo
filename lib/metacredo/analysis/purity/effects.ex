defmodule MetaCredo.Analysis.Purity.Effects do
  @moduledoc """
  Detects side effects in MetaAST nodes.
  """

  alias MetaCredo.Analysis.Purity.Result

  @type effect :: Result.effect()

  @spec detect(Metastatic.AST.meta_ast()) :: [effect()]
  def detect(ast)

  def detect({:function_call, meta, _args}) when is_list(meta) do
    name = Keyword.get(meta, :name)
    if is_binary(name), do: classify_function_call(name), else: []
  end

  def detect({:literal, _meta, _value}), do: []
  def detect({:variable, _meta, _name}), do: []
  def detect({:binary_op, _meta, _children}), do: []
  def detect({:unary_op, _meta, _children}), do: []
  def detect({:conditional, _meta, _children}), do: []
  def detect({:block, _meta, _children}), do: []
  def detect({:loop, _meta, _children}), do: []
  def detect({:assignment, _meta, _children}), do: [:mutation]
  def detect({:inline_match, _meta, _children}), do: []
  def detect({:lambda, _meta, _children}), do: []
  def detect({:collection_op, _meta, _children}), do: []
  def detect({:exception_handling, _meta, _children}), do: [:exception]
  def detect({:early_return, _meta, _children}), do: []
  def detect({:language_specific, _meta, _native_ast}), do: []
  def detect({:pair, _meta, _children}), do: []
  def detect({:list, _meta, _children}), do: []
  def detect({:map, _meta, _children}), do: []
  def detect(_), do: []

  # Effect categories in priority order: the first matching predicate wins.
  defp effect_classifiers do
    [
      {:io, &io_function?/1},
      {:random, &random_function?/1},
      {:time, &time_function?/1},
      {:network, &network_function?/1},
      {:database, &database_function?/1}
    ]
  end

  defp classify_function_call(name) do
    case Enum.find(effect_classifiers(), fn {_effect, pred} -> pred.(name) end) do
      {effect, _pred} -> [effect]
      nil -> []
    end
  end

  defp io_function?("print"), do: true
  defp io_function?("puts"), do: true
  defp io_function?("write"), do: true
  defp io_function?("read"), do: true
  defp io_function?("open"), do: true
  defp io_function?("input"), do: true
  defp io_function?("IO." <> _), do: true
  defp io_function?("File." <> _), do: true
  defp io_function?("io:" <> _), do: true
  defp io_function?("file:" <> _), do: true
  defp io_function?(_), do: false

  defp random_function?("random" <> _), do: true
  defp random_function?("rand" <> _), do: true
  defp random_function?(":rand." <> _), do: true
  defp random_function?("Random." <> _), do: true
  defp random_function?(_), do: false

  defp time_function?("time" <> _), do: true
  defp time_function?("now" <> _), do: true
  defp time_function?("Date" <> _), do: true
  defp time_function?("DateTime" <> _), do: true
  defp time_function?("Time" <> _), do: true
  defp time_function?("erlang:now"), do: true
  defp time_function?(_), do: false

  defp network_function?("http" <> _), do: true
  defp network_function?("fetch" <> _), do: true
  defp network_function?("request" <> _), do: true
  defp network_function?("socket" <> _), do: true
  defp network_function?("HTTPoison." <> _), do: true
  defp network_function?(_), do: false

  defp database_function?("query" <> _), do: true
  defp database_function?("insert" <> _), do: true
  defp database_function?("update" <> _), do: true
  defp database_function?("delete" <> _), do: true
  defp database_function?("Repo." <> _), do: true
  defp database_function?("Ecto." <> _), do: true
  defp database_function?(_), do: false
end
