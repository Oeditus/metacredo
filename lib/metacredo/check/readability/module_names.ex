defmodule MetaCredo.Check.Readability.ModuleNames do
  use MetaCredo.Check,
    category: :readability,
    base_priority: :normal,
    confidence: :high,
    explanations: [
      check: """
      Detects module names that do not follow the naming convention of the
      source language. Elixir modules use PascalCase (e.g. `MyApp.UserAccount`);
      Go packages are conventionally lower-case (`package main`) and are not
      subject to a case rule at all.
      """,
      examples: [
        elixir: [
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
        ],
        javascript: [
          wrong: """
          // A class is the JavaScript module-level container; lower-case is not idiomatic
          class userAccount {
            constructor(id) {
              this.id = id;
            }
          }
          """,
          correct: """
          // PascalCase for classes and module namespaces
          class UserAccount {
            constructor(id) {
              this.id = id;
            }
          }
          """
        ],
        typescript: [
          wrong: """
          // A class is the TypeScript module-level container; lower-case is not idiomatic
          class userAccount {
            id: number;
          }
          """,
          correct: """
          // PascalCase for classes and module namespaces
          class UserAccount {
            id: number;
          }
          """
        ]
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

    cond do
      # Rust names modules in snake_case, so PascalCase is the wrong rule for
      # a `mod` item. See `CheckUtils.rust_mod?/1`.
      #
      # Go opens every file with a lower-case `package` clause, which the
      # adapter reports as a `:module` container; Go has no case rule for
      # package names. See `CheckUtils.go_package?/1`.
      CheckUtils.nameless_container?(meta) ->
        {node, issues}

      name_str == "" or Regex.match?(@pascal_case, name_str) ->
        {node, issues}

      true ->
        line = CheckUtils.line_of(meta)

        issue =
          format_issue(source_file,
            message: "Module name '#{name_str}' is not in PascalCase",
            trigger: name_str,
            line_no: line
          )

        {node, [issue | issues]}
    end
  end

  defp traverse(node, issues, _sf), do: {node, issues}
end
