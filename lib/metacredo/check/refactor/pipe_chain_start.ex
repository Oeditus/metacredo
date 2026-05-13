defmodule MetaCredo.Check.Refactor.PipeChainStart do
  use MetaCredo.Check,
    category: :refactor,
    base_priority: :low,
    explanations: [
      check: """
      Detects pipe chains that start with a literal value. Pipes should
      start with a variable or function call, not a raw literal like
      `"hello" |> String.upcase()`.
      """,
      examples: [
        elixir: [
          wrong: """
          # Literal string fed directly into a pipe -- misleading visual flow
          result = "hello world" |> String.upcase() |> String.split()
          """,
          correct: """
          # Assign to a variable first, making the data flow explicit
          input = "hello world"
          result = input |> String.upcase() |> String.split()

          # Or just use direct function composition without a pipe
          result = String.split(String.upcase("hello world"))
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

  defp traverse({:pipe, meta, [_left, _right]} = node, issues, source_file)
       when is_list(meta) do
    leftmost = find_leftmost(node)

    case leftmost do
      {:literal, _lm, _value} ->
        line = Keyword.get(meta, :line)

        issue =
          format_issue(source_file,
            message: "Pipe chain starts with a literal value -- use a variable or function call",
            trigger: "|>",
            line_no: line,
            severity: :refactoring_opportunity
          )

        {node, [issue | issues]}

      _ ->
        {node, issues}
    end
  end

  defp traverse(node, issues, _sf), do: {node, issues}

  defp find_leftmost({:pipe, _meta, [left, _right]}), do: find_leftmost(left)
  defp find_leftmost(node), do: node
end
