defmodule MetaCredo.Check.Warning.MissingErrorHandling do
  use MetaCredo.Check,
    category: :warning,
    base_priority: :high,
    explanations: [
      check: """
      Detects pattern matches on success tuples (`{:ok, value} = expr`)
      without corresponding error handling. This can crash the process
      on unexpected errors.

      Use `case`, `with`, or multi-clause function heads instead.
      """,
      examples: [
        wrong: """
        # Crashes the process if Repo returns {:error, ...}
        {:ok, user} = Repo.insert(changeset)
        send_welcome_email(user)
        """,
        correct: """
        # Handle both outcomes explicitly
        case Repo.insert(changeset) do
          {:ok, user} -> send_welcome_email(user)
          {:error, changeset} -> {:error, changeset}
        end
        """
      ]
    ]

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc -> traverse(node, acc, source_file) end)

    issues
  end

  # Match: {:ok, _} = some_call(...)
  # In MetaAST: {:assignment, meta, [pattern, value]}
  # where pattern is {:tuple, _, [{:literal, [subtype: :symbol], :ok}, _]}
  defp traverse(
         {:assignment, meta,
          [
            {:tuple, _, [{:literal, ok_meta, :ok} | _]},
            {:function_call, _, _}
          ]} = node,
         issues,
         source_file
       )
       when is_list(meta) and is_list(ok_meta) do
    line = Keyword.get(meta, :line)

    issue =
      format_issue(source_file,
        message: "Match on {:ok, ...} without error handling -- use case/with instead",
        trigger: "{:ok, _} =",
        line_no: line
      )

    {node, [issue | issues]}
  end

  # Match: {:inline_match, meta, [pattern, value]} for languages using = as match
  defp traverse(
         {:inline_match, meta,
          [
            {:tuple, _, [{:literal, ok_meta, :ok} | _]},
            {:function_call, _, _}
          ]} = node,
         issues,
         source_file
       )
       when is_list(meta) and is_list(ok_meta) do
    line = Keyword.get(meta, :line)

    issue =
      format_issue(source_file,
        message: "Match on {:ok, ...} without error handling -- use case/with instead",
        trigger: "{:ok, _} =",
        line_no: line
      )

    {node, [issue | issues]}
  end

  defp traverse(node, issues, _source_file), do: {node, issues}
end
