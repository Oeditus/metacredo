defmodule MetaCredo.Check.Readability.FunctionNames do
  use MetaCredo.Check,
    category: :readability,
    base_priority: :normal,
    confidence: :high,
    explanations: [
      check: """
      Detects function names that do not follow the naming convention of the
      source language. Elixir, Erlang, Python, Ruby and Rust use `snake_case`
      (optionally ending with `!` or `?` in Elixir); JavaScript, TypeScript and
      Go use `camelCase`.
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
        ],
        javascript: [
          wrong: """
          // snake_case is not idiomatic JavaScript
          function process_user_data(user) {
            return user.name;
          }
          """,
          correct: """
          // camelCase is the JavaScript convention
          function processUserData(user) {
            return user.name;
          }
          """
        ],
        typescript: [
          wrong: """
          // snake_case is not idiomatic TypeScript
          export function get_user_by_id(id: number): string {
            return String(id);
          }
          """,
          correct: """
          // camelCase is the TypeScript convention
          export function getUserById(id: number): string {
            return String(id);
          }
          """
        ],
        go: [
          wrong: """
          package main

          // snake_case is not idiomatic Go
          func process_user_data(name string) string {
          \treturn name
          }
          """,
          correct: """
          package main

          // camelCase is the Go convention
          func processUserData(name string) string {
          \treturn name
          }
          """
        ]
      ]
    ]

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    language = SourceFile.language(source_file)

    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc ->
        traverse(node, acc, source_file, language)
      end)

    issues
  end

  defp traverse({:function_def, meta, _children} = node, issues, source_file, language)
       when is_list(meta) do
    name = Keyword.get(meta, :name, "")
    name_str = to_string(name)

    if name_str != "" and not CheckUtils.conventional_name?(name_str, language) do
      line = CheckUtils.line_of(meta)

      issue =
        format_issue(source_file,
          message:
            "Function name '#{name_str}' is not in #{CheckUtils.convention_label(language)}",
          trigger: name_str,
          line_no: line
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _sf, _language), do: {node, issues}
end
