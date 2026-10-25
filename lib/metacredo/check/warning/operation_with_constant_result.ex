defmodule MetaCredo.Check.Warning.OperationWithConstantResult do
  use MetaCredo.Check,
    category: :warning,
    base_priority: :normal,
    confidence: :high,
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
    new_issues = check_constant(operator, {left, right}, meta, issues, source_file)
    {node, new_issues}
  end

  defp traverse(node, issues, _source_file), do: {node, issues}

  # Operator => message for constant-result patterns where the operand is 0.
  @zero_operand_messages %{
    :* => "Multiplication by 0 -- result is always 0",
    :+ => "Addition of 0 -- expression is a no-op identity"
  }

  defp check_constant(operator, {left, right}, meta, issues, source_file) do
    with {:ok, message} <- Map.fetch(@zero_operand_messages, operator),
         true <- literal_zero?(left) or literal_zero?(right) do
      [
        format_issue(source_file,
          message: message,
          trigger: to_string(operator),
          line_no: CheckUtils.line_of(meta)
        )
        | issues
      ]
    else
      _ -> issues
    end
  end

  defp literal_zero?({:literal, meta, 0}) when is_list(meta), do: true
  defp literal_zero?({:literal, meta, "0"}) when is_list(meta), do: true
  defp literal_zero?(_), do: false
end
