defmodule MetaCredo.Check.Refactor.VariableRebinding do
  use MetaCredo.Check,
    category: :refactor,
    base_priority: :low,
    explanations: [
      check: """
      Detects the same variable name being assigned multiple times in the
      same block. Rebinding variables makes code harder to follow --
      use distinct names or restructure the code.
      """,
      examples: [
        wrong: """
        # What does `result` mean at each point? The reader must trace all assignments.
        result = fetch_data(id)
        result = transform(result)
        result = validate(result)
        persist(result)
        """,
        correct: """
        # Use pipes to express the transformation pipeline, or distinct names
        id
        |> fetch_data()
        |> transform()
        |> validate()
        |> persist()
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

  defp traverse({:block, _meta, stmts} = node, issues, source_file)
       when is_list(stmts) do
    new_issues = check_block(stmts, source_file)
    {node, new_issues ++ issues}
  end

  defp traverse(node, issues, _sf), do: {node, issues}

  defp check_block(stmts, source_file) do
    {issues, _seen} =
      Enum.reduce(stmts, {[], MapSet.new()}, fn stmt, {acc, seen} ->
        case extract_assignment_target(stmt) do
          {name, line} when is_binary(name) ->
            if MapSet.member?(seen, name) do
              issue =
                format_issue(source_file,
                  message: "Variable '#{name}' is rebound in the same block",
                  trigger: name,
                  line_no: line,
                  severity: :refactoring_opportunity
                )

              {[issue | acc], seen}
            else
              {acc, MapSet.put(seen, name)}
            end

          nil ->
            {acc, seen}
        end
      end)

    issues
  end

  defp extract_assignment_target({:assignment, meta, [{:variable, _vm, name} | _rest]})
       when is_list(meta) do
    name_str = to_string(name)
    line = Keyword.get(meta, :line)

    if String.starts_with?(name_str, "_") do
      nil
    else
      {name_str, line}
    end
  end

  defp extract_assignment_target(_), do: nil
end
