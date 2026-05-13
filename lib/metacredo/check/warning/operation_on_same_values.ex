defmodule MetaCredo.Check.Warning.OperationOnSameValues do
  use MetaCredo.Check,
    category: :warning,
    base_priority: :normal,
    explanations: [
      check: """
      Detects arithmetic operations on identical operands that produce a
      constant result: `x - x` is always 0, `x / x` is always 1.
      These are likely copy-paste errors or logic mistakes.
      """
    ]

  @constant_result_ops [:-, :/]

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
    operator = Keyword.get(meta, :operator)

    if operator in @constant_result_ops and left == right do
      line = Keyword.get(meta, :line)
      result = if operator == :-, do: "0", else: "1"

      issue =
        format_issue(source_file,
          message: "Operation '#{operator}' on identical operands -- result is always #{result}",
          trigger: to_string(operator),
          line_no: line
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _source_file), do: {node, issues}
end
