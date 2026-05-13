defmodule MetaCredo.Check.Design.HighComplexity do
  use MetaCredo.Check,
    category: :design,
    base_priority: :high,
    param_defaults: [max_complexity: 10],
    explanations: [
      check: """
      Detects functions with cyclomatic complexity exceeding a threshold.
      Cyclomatic complexity measures the number of linearly independent paths
      through a function. High complexity makes code harder to test, understand,
      and maintain.

      Thresholds:
      - 1-10: Simple, low risk
      - 11-20: More complex, moderate risk
      - 21-50: Complex, high risk
      - 51+: Untestable, very high risk
      """,
      params: [
        max_complexity: "Maximum allowed cyclomatic complexity (default: 10)"
      ]
    ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    max_complexity = params_get(params, :max_complexity)

    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc ->
        traverse(node, acc, source_file, max_complexity)
      end)

    issues
  end

  defp traverse({:function_def, meta, children} = node, issues, source_file, max_complexity)
       when is_list(meta) do
    name = Keyword.get(meta, :name, "anonymous")
    complexity = 1 + count_decision_points(children)

    if complexity > max_complexity do
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message:
            "Function '#{name}' has cyclomatic complexity #{complexity} (max allowed: #{max_complexity})",
          trigger: to_string(name),
          line_no: line,
          metadata: %{complexity: complexity}
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _sf, _max), do: {node, issues}

  # Count decision points (each adds a path through the code)
  defp count_decision_points({:conditional, _meta, children}) when is_list(children) do
    1 + Enum.reduce(children, 0, fn c, acc -> acc + count_decision_points(c) end)
  end

  defp count_decision_points({:loop, _meta, children}) when is_list(children) do
    1 + Enum.reduce(children, 0, fn c, acc -> acc + count_decision_points(c) end)
  end

  defp count_decision_points({:pattern_match, _meta, [_scrutinee | arms]})
       when is_list(arms) do
    # Each arm adds a decision point
    length(arms) +
      Enum.reduce(arms, 0, fn arm, acc -> acc + count_decision_points(arm) end)
  end

  defp count_decision_points({:exception_handling, _meta, [try_block, catches, else_block]}) do
    catches_list = if is_list(catches), do: catches, else: []

    length(catches_list) +
      count_decision_points(try_block) +
      Enum.reduce(catches_list, 0, fn c, acc -> acc + count_decision_points(c) end) +
      count_decision_points(else_block)
  end

  defp count_decision_points({:binary_op, meta, [left, right]}) when is_list(meta) do
    category = Keyword.get(meta, :category)
    op = Keyword.get(meta, :operator)

    bonus = if category == :boolean and op in [:and, :or], do: 1, else: 0
    bonus + count_decision_points(left) + count_decision_points(right)
  end

  defp count_decision_points({:block, _meta, stmts}) when is_list(stmts) do
    Enum.reduce(stmts, 0, fn s, acc -> acc + count_decision_points(s) end)
  end

  defp count_decision_points({_type, _meta, children}) when is_list(children) do
    Enum.reduce(children, 0, fn c, acc -> acc + count_decision_points(c) end)
  end

  defp count_decision_points(list) when is_list(list) do
    Enum.reduce(list, 0, fn c, acc -> acc + count_decision_points(c) end)
  end

  defp count_decision_points(nil), do: 0
  defp count_decision_points(_), do: 0
end
