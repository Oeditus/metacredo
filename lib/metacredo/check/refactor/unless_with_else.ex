defmodule MetaCredo.Check.Refactor.UnlessWithElse do
  use MetaCredo.Check,
    category: :refactor,
    base_priority: :normal,
    explanations: [
      check: """
      Detects `unless ... else` constructs. `unless` with an `else` branch
      is confusing -- use `if` with swapped branches instead.
      """,
      examples: [
        elixir: [
          wrong: """
          # unless + else is a double-negative that is hard to parse
          unless error?(result) do
            persist(result)
          else
            report_error(result)
          end
          """,
          correct: """
          # Flip to if with the positive condition in the then-branch
          if error?(result) do
            report_error(result)
          else
            persist(result)
          end
          """
        ]
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
         {:conditional, meta, [_condition, _then_branch, else_branch]} = node,
         issues,
         source_file
       )
       when is_list(meta) do
    kind = Keyword.get(meta, :conditional_kind)

    if kind == :unless and else_branch != nil do
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message: "Unless with else clause -- use `if` with swapped branches instead",
          trigger: "unless",
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
