defmodule MetaCredo.Check.Readability.VariableNames do
  use MetaCredo.Check,
    category: :readability,
    base_priority: :normal,
    confidence: :high,
    explanations: [
      check: """
      Detects variable names that do not follow the naming convention of the
      source language. Elixir, Erlang, Python, Ruby and Rust use `snake_case`
      (e.g. `my_var`, `_unused`); JavaScript, TypeScript and Go use
      `camelCase` (e.g. `myVar`, `_unused`).
      """,
      examples: [
        elixir: [
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
        ],
        javascript: [
          wrong: """
          // snake_case variables are not idiomatic JavaScript
          const first_name = "Alice";
          let max_retries = 3;
          """,
          correct: """
          // camelCase throughout
          const firstName = "Alice";
          let maxRetries = 3;
          """
        ],
        typescript: [
          wrong: """
          // snake_case variables are not idiomatic TypeScript
          const user_id: number = 42;
          let is_valid: boolean = true;
          """,
          correct: """
          // camelCase throughout
          const userId: number = 42;
          let isValid: boolean = true;
          """
        ],
        go: [
          wrong: """
          package main

          // snake_case variables are not idiomatic Go
          func main() {
          \tmax_retries := 3
          \t_ = max_retries
          }
          """,
          correct: """
          package main

          // camelCase throughout
          func main() {
          \tmaxRetries := 3
          \t_ = maxRetries
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

  defp traverse({:variable, meta, name} = node, issues, source_file, language)
       when is_list(meta) do
    name_str = to_string(name)

    if invalid_variable_name?(name_str, language) do
      line = CheckUtils.line_of(meta)

      issue =
        format_issue(source_file,
          message:
            "Variable name '#{name_str}' is not in #{CheckUtils.convention_label(language)}",
          trigger: name_str,
          line_no: line
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _sf, _language), do: {node, issues}

  # A variable name is reported when it is non-empty, not a language special
  # form / module attribute, and not in the convention of its language.
  defp invalid_variable_name?("", _language), do: false

  defp invalid_variable_name?(name_str, language) do
    not CheckUtils.special_variable?(name_str) and
      not CheckUtils.conventional_name?(name_str, language)
  end
end
