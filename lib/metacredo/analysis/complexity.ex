defmodule MetaCredo.Analysis.Complexity do
  @moduledoc """
  Programmatic complexity analysis API.

  Provides access to comprehensive code complexity metrics that work
  uniformly across all supported languages by operating on the unified
  MetaAST representation.

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

  alias MetaCredo.Analysis.Complexity.{
    Cognitive,
    Cyclomatic,
    FunctionMetrics,
    Halstead,
    LoC,
    Nesting,
    Result
  }

  alias Metastatic.Document

  use MetaCredo.Analysis.Analyzer,
    doc: """
    Analyzes a document for complexity.

    Returns `{:ok, result}` where result is a `MetaCredo.Analysis.Complexity.Result` struct.

    ## Options

    - `:thresholds` - Threshold map for warnings
    - `:metrics` - List of metrics to calculate (default: `:all`)
    """

  @dialyzer :no_opaque

  @impl MetaCredo.Analysis.Analyzer
  def handle_analyze(%Document{ast: ast, metadata: metadata} = doc, opts \\ []) do
    thresholds = Keyword.get(opts, :thresholds, %{})
    metrics = Keyword.get(opts, :metrics, :all)

    analysis_ast = extract_analyzable_ast(ast, metadata)
    per_function = extract_per_function_metrics(ast, metadata)

    result =
      %{}
      |> calculate_cyclomatic(analysis_ast, metrics)
      |> calculate_cognitive(analysis_ast, metrics)
      |> calculate_nesting(analysis_ast, metrics)
      |> calculate_halstead(analysis_ast, metrics)
      |> calculate_loc(analysis_ast, doc, metrics)
      |> calculate_function_metrics(analysis_ast, metrics)
      |> Map.put(:per_function, per_function)
      |> Result.new()
      |> Result.apply_thresholds(thresholds)

    {:ok, result}
  end

  defp calculate_cyclomatic(metrics, ast, metric_list) do
    if metric_list == :all or :cyclomatic in metric_list do
      Map.put(metrics, :cyclomatic, Cyclomatic.calculate(ast))
    else
      Map.put(metrics, :cyclomatic, 0)
    end
  end

  defp calculate_cognitive(metrics, ast, metric_list) do
    if metric_list == :all or :cognitive in metric_list do
      Map.put(metrics, :cognitive, Cognitive.calculate(ast))
    else
      Map.put(metrics, :cognitive, 0)
    end
  end

  defp calculate_nesting(metrics, ast, metric_list) do
    if metric_list == :all or :nesting in metric_list do
      Map.put(metrics, :max_nesting, Nesting.calculate(ast))
    else
      Map.put(metrics, :max_nesting, 0)
    end
  end

  defp calculate_halstead(metrics, ast, metric_list) do
    if metric_list == :all or :halstead in metric_list do
      Map.put(metrics, :halstead, Halstead.calculate(ast))
    else
      Map.put(metrics, :halstead, %{})
    end
  end

  defp calculate_loc(metrics, ast, doc, metric_list) do
    if metric_list == :all or :loc in metric_list do
      metadata = Map.get(doc, :metadata, %{})
      Map.put(metrics, :loc, LoC.calculate(ast, metadata))
    else
      Map.put(metrics, :loc, %{})
    end
  end

  defp calculate_function_metrics(metrics, ast, metric_list) do
    if metric_list == :all or :function_metrics in metric_list do
      Map.put(metrics, :function_metrics, FunctionMetrics.calculate(ast))
    else
      Map.put(metrics, :function_metrics, %{})
    end
  end

  defp extract_analyzable_ast({:language_specific, meta, _native}, metadata)
       when is_list(meta) do
    Map.get(metadata, :body, {:block, [], []})
  end

  defp extract_analyzable_ast({:container, meta, [body]}, _doc_metadata)
       when is_list(meta) do
    if is_list(body), do: {:block, [], body}, else: body
  end

  defp extract_analyzable_ast({:function_def, meta, [body]}, _doc_metadata)
       when is_list(meta) do
    body
  end

  defp extract_analyzable_ast(ast, _metadata), do: ast

  defp extract_per_function_metrics({:language_specific, meta, _native}, doc_metadata)
       when is_list(meta) do
    hint = Keyword.get(meta, :hint)

    if hint == :module_definition do
      body = Map.get(doc_metadata, :body)
      extract_functions_from_body(body)
    else
      []
    end
  end

  defp extract_per_function_metrics({:container, meta, children}, _doc_metadata)
       when is_list(meta) and is_list(children) do
    members =
      case children do
        [{:block, _, statements}] when is_list(statements) -> statements
        _ -> children
      end

    collect_function_defs_recursive(members)
  end

  defp extract_per_function_metrics(_ast, _metadata), do: []

  defp collect_function_defs_recursive(members) when is_list(members) do
    Enum.flat_map(members, fn
      {:function_def, _, _} = node ->
        case analyze_function_def(node) do
          nil -> []
          result -> [result]
        end

      {:container, meta, children} when is_list(meta) and is_list(children) ->
        inner =
          case children do
            [{:block, _, statements}] when is_list(statements) -> statements
            _ -> children
          end

        collect_function_defs_recursive(inner)

      {:block, _, statements} when is_list(statements) ->
        collect_function_defs_recursive(statements)

      {:language_specific, _, _} = node ->
        case analyze_function(node) do
          nil -> []
          result -> [result]
        end

      _ ->
        []
    end)
  end

  defp collect_function_defs_recursive(_), do: []

  defp extract_functions_from_body({:block, _meta, statements}) when is_list(statements) do
    statements
    |> Enum.filter(
      &match?(
        ast when is_tuple(ast) and elem(ast, 0) in [:function_def, :language_specific],
        &1
      )
    )
    |> Enum.map(fn
      {:function_def, _, _} = node -> analyze_function_def(node)
      {:language_specific, _, _} = node -> analyze_function(node)
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_functions_from_body(_), do: []

  defp analyze_function({:language_specific, meta, native_ast}) when is_list(meta) do
    hint = Keyword.get(meta, :hint)

    if hint == :function_definition do
      function_name =
        case native_ast do
          %{"function_name" => name} -> name
          _ -> "unknown"
        end

      line =
        case native_ast do
          %{"line" => l} -> l
          _ -> Keyword.get(meta, :line)
        end

      body =
        case native_ast do
          %{"body" => b} -> b
          _ -> nil
        end

      if body do
        variables = Metastatic.AST.variables(body)

        %{
          name: function_name,
          line: line,
          cyclomatic: Cyclomatic.calculate(body),
          cognitive: Cognitive.calculate(body),
          max_nesting: Nesting.calculate(body),
          statements: FunctionMetrics.calculate(body).statement_count,
          variables: MapSet.size(variables)
        }
      else
        nil
      end
    else
      nil
    end
  end

  defp analyze_function(_), do: nil

  defp analyze_function_def({:function_def, meta, children}) when is_list(meta) do
    name = Keyword.get(meta, :name, "unknown")
    line = Keyword.get(meta, :line)

    body =
      case children do
        [single] -> single
        statements when is_list(statements) -> {:block, [], statements}
        other -> other
      end

    variables = Metastatic.AST.variables(body)

    %{
      name: name,
      line: line,
      cyclomatic: Cyclomatic.calculate(body),
      cognitive: Cognitive.calculate(body),
      max_nesting: Nesting.calculate(body),
      statements: FunctionMetrics.calculate(body).statement_count,
      variables: MapSet.size(variables)
    }
  end

  defp analyze_function_def(_), do: nil
end
