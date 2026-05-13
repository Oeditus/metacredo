defmodule MetaCredo.Check.Warning.DirectStructUpdate do
  use MetaCredo.Check,
    category: :warning,
    base_priority: :normal,
    explanations: [
      check: """
      Detects direct struct field updates (e.g. `%User{user | name: "new"}`)
      that bypass validation. In Ecto-backed applications, data changes should
      go through changesets to ensure validation, casting, and constraint
      checking.

      Use `Ecto.Changeset.change/2` or a dedicated changeset function instead.
      """,
      examples: [
        wrong: """
        # Bypasses changeset validation -- constraints and callbacks are skipped
        def update_email(user, new_email) do
          Repo.update!(%User{user | email: new_email})
        end
        """,
        correct: """
        # Go through a changeset so validations and constraints are enforced
        def update_email(user, new_email) do
          user
          |> User.email_changeset(%{email: new_email})
          |> Repo.update()
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

  # record_update: {:record_update, [name: "User", ...], [base | field_pairs]}
  # This matches %User{user | field: value} syntax in MetaAST
  defp traverse(
         {:record_update, meta, _children} = node,
         issues,
         source_file
       )
       when is_list(meta) do
    name = Keyword.get(meta, :name, "")
    line = Keyword.get(meta, :line)

    issue =
      format_issue(source_file,
        message:
          "Direct struct update on #{name} bypasses validation -- use a changeset function instead",
        trigger: "%#{name}{",
        line_no: line
      )

    {node, [issue | issues]}
  end

  # Also catch map updates that look like struct updates:
  # {:map_update, meta, [base, ...pairs]}
  defp traverse(
         {:map_update, meta, [base | _pairs]} = node,
         issues,
         source_file
       )
       when is_list(meta) do
    if looks_like_struct_update?(base) do
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message:
            "Direct map/struct update bypasses validation -- consider using a changeset function",
          trigger: "%{",
          line_no: line
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _source_file), do: {node, issues}

  # Heuristic: if the base variable name looks like a schema struct
  defp looks_like_struct_update?({:variable, _meta, name}) when is_binary(name) do
    lower = String.downcase(name)

    Enum.any?(
      ["user", "account", "record", "item", "order", "post", "comment", "product"],
      &String.contains?(lower, &1)
    )
  end

  defp looks_like_struct_update?(_), do: false
end
