defmodule MetaCredo.Check.Refactor.FilterCount do
  use MetaCredo.Check,
    category: :refactor,
    base_priority: :low,
    explanations: [
      check: """
      Detects `Enum.filter(...) |> Enum.count()` patterns. Use
      `Enum.count(enumerable, fun)` instead for a single-pass operation.
      """,
      examples: [
        wrong: """
        # Two passes: filter allocates an intermediate list, then count traverses it
        active_count = Enum.filter(users, &(&1.active)) |> Enum.count()
        """,
        correct: """
        # Single pass with a predicate -- no intermediate list
        active_count = Enum.count(users, &(&1.active))
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

  # Pipe form: Enum.filter(...) |> Enum.count()
  defp traverse(
         {:pipe, meta,
          [
            {:function_call, filter_meta, _filter_args},
            {:function_call, count_meta, _count_args}
          ]} = node,
         issues,
         source_file
       )
       when is_list(meta) and is_list(filter_meta) and is_list(count_meta) do
    filter_name = to_string(Keyword.get(filter_meta, :name, ""))
    count_name = to_string(Keyword.get(count_meta, :name, ""))

    if filter_call?(filter_name) and count_call?(count_name) do
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message:
            "Use `Enum.count/2` with a predicate instead of `Enum.filter/2 |> Enum.count/1`",
          trigger: "Enum.count",
          line_no: line,
          severity: :refactoring_opportunity
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _sf), do: {node, issues}

  defp filter_call?(name), do: name in ["Enum.filter", "filter"]
  defp count_call?(name), do: name in ["Enum.count", "count"]
end
