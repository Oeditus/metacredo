defmodule MetaCredo.Check.Readability.ModuleNames do
  use MetaCredo.Check,
    category: :readability,
    base_priority: :normal,
    explanations: [
      check: """
      Detects module names that do not follow PascalCase convention.
      Module names in Elixir should use PascalCase (e.g. `MyApp.UserAccount`).
      """,
      examples: [
        wrong: """
        # snake_case and all-caps names are not idiomatic
        defmodule my_app.user_account, do: ...
        defmodule MYAPP.USERREPO, do: ...
        """,
        correct: """
        # PascalCase for every segment separated by dots
        defmodule MyApp.UserAccount, do: ...
        defmodule MyApp.Repo, do: ...
        """
      ]
    ]

  @pascal_case ~r/^[A-Z][a-zA-Z0-9]*(\.[A-Z][a-zA-Z0-9]*)*$/

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

  defp traverse({:container, meta, _children} = node, issues, source_file)
       when is_list(meta) do
    name = Keyword.get(meta, :name, "")
    name_str = to_string(name)

    if name_str != "" and not Regex.match?(@pascal_case, name_str) do
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message: "Module name '#{name_str}' is not in PascalCase",
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
