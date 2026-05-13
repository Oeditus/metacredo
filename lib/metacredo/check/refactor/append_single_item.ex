defmodule MetaCredo.Check.Refactor.AppendSingleItem do
  use MetaCredo.Check,
    category: :refactor,
    base_priority: :low,
    explanations: [
      check: """
      Detects `list ++ [item]` pattern. Appending to a list with `++` creates
      a full copy of the left list. Consider prepending with `[item | list]`
      and reversing, or using a different data structure.
      """,
      examples: [
        wrong: """
        # O(n) copy of acc on every iteration
        Enum.reduce(items, [], fn item, acc ->
          acc ++ [transform(item)]
        end)
        """,
        correct: """
        # Prepend in O(1) and reverse once at the end
        items
        |> Enum.reduce([], fn item, acc -> [transform(item) | acc] end)
        |> Enum.reverse()

        # Or just use Enum.map/2 directly
        Enum.map(items, &transform/1)
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
         {:binary_op, meta, [_left, {:list, _list_meta, [_single_element]}]} = node,
         issues,
         source_file
       )
       when is_list(meta) do
    operator = Keyword.get(meta, :operator)

    if operator == :++ do
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message:
            "Appending single item with `++` is inefficient -- consider prepending with `[item | list]`",
          trigger: "++",
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
