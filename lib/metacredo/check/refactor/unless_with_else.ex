defmodule MetaCredo.Check.Refactor.UnlessWithElse do
  use MetaCredo.Check,
    category: :refactor,
    base_priority: :normal,
    explanations: [
      check: """
      Detects `unless ... else` constructs. `unless` with an `else` branch
      is confusing -- use `if` with swapped branches instead.
      """
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
