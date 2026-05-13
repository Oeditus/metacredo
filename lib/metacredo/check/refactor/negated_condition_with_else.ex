defmodule MetaCredo.Check.Refactor.NegatedConditionWithElse do
  use MetaCredo.Check,
    category: :refactor,
    base_priority: :low,
    explanations: [
      check: """
      Detects `if !condition do ... else ... end` or `if not condition do ... else ... end`.
      Swap the branches and remove the negation for clearer code.
      """,
      examples: [
        wrong: """
        # Negation with else forces the reader to mentally invert the condition
        if !valid?(input) do
          {:error, :invalid}
        else
          process(input)
        end
        """,
        correct: """
        # Swap branches to eliminate the negation
        if valid?(input) do
          process(input)
        else
          {:error, :invalid}
        end
        """
      ]
    ]

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc ->
        traverse(node, acc, source_file)
      end)

    issues
  end

  defp traverse(
         {:conditional, meta, [{:unary_op, op_meta, [_operand]}, _then_branch, else_branch]} =
           node,
         issues,
         source_file
       )
       when is_list(meta) and is_list(op_meta) do
    operator = Keyword.get(op_meta, :operator)

    if operator in [:!, :not] and else_branch != nil do
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message: "Negated condition with else branch -- swap branches and remove negation",
          trigger: to_string(operator),
          line_no: line,
          severity: :refactoring_opportunity
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _sf), do: {node, issues}
end
