defmodule MetaCredo.Check.Readability.FunctionNames do
  use MetaCredo.Check,
    category: :readability,
    base_priority: :normal,
    explanations: [
      check: """
      Detects function names that do not follow snake_case convention.
      Elixir functions should be named in snake_case, optionally ending
      with `!` or `?`.
      """,
      examples: [
        elixir: [
          wrong: """
          # camelCase and PascalCase are not idiomatic in Elixir
          def processUserData(user), do: ...
          def GetUserById(id), do: ...
          """,
          correct: """
          # snake_case is the Elixir convention
          def process_user_data(user), do: ...
          def get_user_by_id(id), do: ...
          def valid?, do: ...
          def save!, do: ...
          """
        ]
      ]
    ]

  @snake_case ~r/^[a-z_][a-z0-9_]*[!?]?$/

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

  defp traverse({:function_def, meta, _children} = node, issues, source_file)
       when is_list(meta) do
    name = Keyword.get(meta, :name, "")
    name_str = to_string(name)

    if name_str != "" and not Regex.match?(@snake_case, name_str) do
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message: "Function name '#{name_str}' is not in snake_case",
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
