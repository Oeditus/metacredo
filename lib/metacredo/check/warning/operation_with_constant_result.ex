defmodule MetaCredo.Check.Warning.OperationWithConstantResult do
  use MetaCredo.Check,
    category: :warning,
    base_priority: :normal,
    explanations: [
      check: """
      Detects arithmetic operations with a constant result or identity
      operand: `x * 0` is always 0, and `x + 0` is a no-op identity.
      These suggest dead code or incomplete expressions.
      """,
      examples: [
        elixir: [
          wrong: """
          # Multiplying by 0 always gives 0 -- the variable is never used
          total = quantity * 0
          # Adding 0 is a no-op -- likely a placeholder never replaced
          adjusted = price + 0
          """,
          correct: """
          # Replace the constant with the actual intended operand
          total = quantity * unit_price
          adjusted = price + discount
          """
        ]
      ]
    ]

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
    new_issues = check_constant(operator, left, right, meta, issues, source_file)
    {node, new_issues}
  end

  defp traverse(node, issues, _source_file), do: {node, issues}

  defp check_constant(:*, left, right, meta, issues, source_file) do
    if literal_zero?(left) or literal_zero?(right) do
      line = Keyword.get(meta, :line)

      [
        format_issue(source_file,
          message: "Multiplication by 0 -- result is always 0",
          trigger: "*",
          line_no: line
        )
        | issues
      ]
    else
      issues
    end
  end

  defp check_constant(:+, left, right, meta, issues, source_file) do
    if literal_zero?(left) or literal_zero?(right) do
      line = Keyword.get(meta, :line)

      [
        format_issue(source_file,
          message: "Addition of 0 -- expression is a no-op identity",
          trigger: "+",
          line_no: line
        )
        | issues
      ]
    else
      issues
    end
  end

  defp check_constant(_op, _left, _right, _meta, issues, _source_file), do: issues

  defp literal_zero?({:literal, meta, 0}) when is_list(meta), do: true
  defp literal_zero?({:literal, meta, "0"}) when is_list(meta), do: true
  defp literal_zero?(_), do: false
end
