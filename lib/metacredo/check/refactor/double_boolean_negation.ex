defmodule MetaCredo.Check.Refactor.DoubleBooleanNegation do
  use MetaCredo.Check,
    category: :refactor,
    base_priority: :low,
    explanations: [
      check: """
      Detects `!!value` (double boolean negation). While commonly used to
      coerce a value to boolean, it harms readability. Use explicit
      conversion or pattern matching instead.
      """,
      examples: [
        wrong: """
        # `!!` coerces to bool but the intent is opaque
        active? = !!user.confirmed_at
        has_posts? = !!Enum.count(posts)
        """,
        correct: """
        # Express the boolean intent explicitly
        active? = not is_nil(user.confirmed_at)
        has_posts? = Enum.any?(posts)
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
         {:unary_op, outer_meta, [{:unary_op, inner_meta, [_operand]}]} = node,
         issues,
         source_file
       )
       when is_list(outer_meta) and is_list(inner_meta) do
    outer_op = Keyword.get(outer_meta, :operator)
    inner_op = Keyword.get(inner_meta, :operator)

    if outer_op == :! and inner_op == :! do
      line = Keyword.get(outer_meta, :line)

      issue =
        format_issue(source_file,
          message: "Double boolean negation (`!!`) -- use explicit boolean conversion instead",
          trigger: "!!",
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
