defmodule MetaCredo.Check.Readability.VariableNames do
  use MetaCredo.Check,
    category: :readability,
    base_priority: :normal,
    explanations: [
      check: """
      Detects variable names that do not follow snake_case convention.
      Variables in Elixir should use snake_case (e.g. `my_var`, `_unused`).
      """,
      examples: [
        wrong: """
        # camelCase variables are not idiomatic Elixir
        firstName = "Alice"
        maxRetries = 3
        isValid = check(input)
        """,
        correct: """
        # snake_case throughout
        first_name = "Alice"
        max_retries = 3
        is_valid = check(input)
        _unused_result = side_effect()  # prefix _ for intentionally unused vars
        """
      ]
    ]

  @snake_case ~r/^_?[a-z][a-z0-9_]*[!?]?$/

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

  defp traverse({:variable, meta, name} = node, issues, source_file)
       when is_list(meta) do
    name_str = to_string(name)

    if name_str != "" and not CheckUtils.special_variable?(name_str) and
         not Regex.match?(@snake_case, name_str) do
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message: "Variable name '#{name_str}' is not in snake_case",
          trigger: name_str,
          line_no: line
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _sf), do: {node, issues}
end
