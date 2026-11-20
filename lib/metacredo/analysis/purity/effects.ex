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

  # Bare, unqualified names that unambiguously denote an effect. A local call
  # such as `timeout(5000)` or `update_counters/2` must NOT be classified by
  # prefix: those are ordinary project functions, and treating them as
  # effects made `Purity.analyze/1` report pure code as impure.
  defp io_function?("print"), do: true
  defp io_function?("puts"), do: true
  defp io_function?("open"), do: true
  defp io_function?("input"), do: true
  defp io_function?(name), do: qualified?(name) and qualified_io?(name)

  defp qualified_io?(name) do
    prefix?(name, "IO.") or prefix?(name, "File.") or prefix?(name, "io:") or
      prefix?(name, "file:")
  end

  defp random_function?(name), do: qualified?(name) and qualified_random?(name)

  defp qualified_random?(name) do
    prefix?(name, "random") or prefix?(name, "rand") or prefix?(name, ":rand.") or
      prefix?(name, "Random.")
  end

  defp time_function?(name), do: qualified?(name) and qualified_time?(name)

  defp qualified_time?(name) do
    prefix?(name, "time") or prefix?(name, "now") or prefix?(name, "Date") or
      prefix?(name, "DateTime") or prefix?(name, "Time") or name == "erlang:now"
  end

  defp network_function?(name), do: qualified?(name) and qualified_network?(name)

  defp qualified_network?(name) do
    prefix?(name, "http") or prefix?(name, "fetch") or prefix?(name, "request") or
      prefix?(name, "socket") or prefix?(name, "HTTPoison.")
  end

  defp database_function?(name), do: qualified?(name) and qualified_database?(name)

  defp qualified_database?(name) do
    prefix?(name, "query") or prefix?(name, "insert") or prefix?(name, "update") or
      prefix?(name, "delete") or prefix?(name, "Repo.") or prefix?(name, "Ecto.")
  end

  # A name is qualified when it carries a module/receiver separator. Only
  # qualified names are matched by prefix; bare local calls are matched
  # exactly (see the `io_function?/1` clauses above).
  defp qualified?(name), do: String.contains?(name, ".") or String.contains?(name, ":")

  defp prefix?(name, prefix), do: String.starts_with?(name, prefix)
end
