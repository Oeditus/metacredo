defmodule MetaCredo.Check.Readability.ModuleDoc do
  use MetaCredo.Check,
    category: :readability,
    base_priority: :normal,
    explanations: [
      check: """
      Detects modules without documentation. Every module should have
      a `@moduledoc` describing its purpose.
      """,
      examples: [
        elixir: [
          wrong: """
          # No documentation -- purpose is unknown to new readers
          defmodule MyApp.Accounts.UserToken do
            use Ecto.Schema
            import Ecto.Changeset

            schema "user_tokens" do
              ...
            end
          end
          """,
          correct: """
          defmodule MyApp.Accounts.UserToken do
            @moduledoc \"\"\"
            Manages authentication tokens for users.

            Tokens are single-use, time-limited, and scoped to a specific
            context (e.g. password reset or email confirmation).
            \"\"\"

            use Ecto.Schema
            import Ecto.Changeset

            schema "user_tokens" do
              ...
            end
          end
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

  defp traverse({:container, meta, children} = node, issues, source_file)
       when is_list(meta) and is_list(children) do
    name = Keyword.get(meta, :name, "unknown")

    if has_doc_comment?(children) do
      {node, issues}
    else
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message: "Module '#{name}' has no documentation",
          trigger: to_string(name),
          line_no: line
        )

      {node, [issue | issues]}
    end
  end

  defp traverse(node, issues, _sf), do: {node, issues}

  defp has_doc_comment?(children) when is_list(children) do
    Enum.any?(children, fn
      {:comment, meta, _text} when is_list(meta) ->
        Keyword.get(meta, :comment_kind) == :doc

      _ ->
        false
    end)
  end

  defp has_doc_comment?(_), do: false
end
