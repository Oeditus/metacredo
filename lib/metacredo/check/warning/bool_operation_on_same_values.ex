defmodule MetaCredo.Check.Warning.BoolOperationOnSameValues do
  use MetaCredo.Check,
    category: :warning,
    base_priority: :normal,
    explanations: [
      check: """
      Detects boolean operations where both operands are structurally identical,
      such as `x && x`, `x || x`, `x and x`, `x or x`. These are always
      redundant and likely indicate a copy-paste error.
      """
    ]

  @boolean_operators [:and, :or, :&&, :||]

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc -> traverse(node, acc, source_file) end)

    issues
  end

  defp traverse(
         {:binary_op, meta, [left, right]} = node,
         issues,
         source_file
       )
       when is_list(meta) do
    category = Keyword.get(meta, :category)
    operator = Keyword.get(meta, :operator)

    if category == :boolean and operator in @boolean_operators and
         structurally_equal?(left, right) do
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message:
            "Boolean '#{operator}' with identical operands -- expression is always redundant",
          trigger: to_string(operator),
          line_no: line
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _source_file), do: {node, issues}

  defp structurally_equal?(a, b), do: a == b
end
