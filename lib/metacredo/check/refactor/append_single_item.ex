defmodule MetaCredo.Check.Refactor.AppendSingleItem do
  use MetaCredo.Check,
    category: :refactor,
    base_priority: :low,
    confidence: :high,
    explanations: [
      check: """
      Detects `list ++ [item]` pattern. Appending to a list with `++` creates
      a full copy of the left list. Consider prepending with `[item | list]`
      and reversing, or using a different data structure.
      """,
      examples: [
        elixir: [
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

  # The Elixir adapter emits `a ++ b` as a `:function_call` named `"++"`,
  # not as a `:binary_op`, so both shapes are matched.
  defp traverse(
         {:function_call, meta, [_left, {:list, _list_meta, [_single_element]}]} = node,
         issues,
         source_file
       )
       when is_list(meta) do
    if Keyword.get(meta, :name) == "++" do
      {node, [append_issue(meta, source_file) | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(
         {:binary_op, meta, [_left, {:list, _list_meta, [_single_element]}]} = node,
         issues,
         source_file
       )
       when is_list(meta) do
    if Keyword.get(meta, :operator) == :++ do
      {node, [append_issue(meta, source_file) | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _sf), do: {node, issues}

  defp append_issue(meta, source_file) do
    format_issue(source_file,
      message:
        "Appending single item with `++` is inefficient -- consider prepending with `[item | list]`",
      trigger: "++",
      line_no: CheckUtils.line_of(meta),
      severity: :refactoring_opportunity
    )
  end
end
