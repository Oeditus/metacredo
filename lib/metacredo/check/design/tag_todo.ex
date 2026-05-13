defmodule MetaCredo.Check.Design.TagTodo do
  use MetaCredo.Check,
    category: :design,
    base_priority: :low,
    param_defaults: [include_source_scan: true],
    explanations: [
      check: """
      Detects TODO comments left in the codebase. While useful during
      development, TODOs should be tracked in an issue tracker and resolved
      before shipping to production.
      """,
      params: [
        include_source_scan: "Also scan raw source lines for TODO (default: true)"
      ],
      examples: [
        elixir: [
          wrong: """
          def create_user(attrs) do
            # TODO: add email uniqueness validation
            Repo.insert(%User{} |> User.changeset(attrs))
          end
          """,
          correct: """
          # Either implement the missing feature now, or remove the comment
          # and open a properly tracked issue in your project tracker.
          def create_user(attrs) do
            %User{}
            |> User.changeset(attrs)
            |> Repo.insert()
          end
          """
        ]
      ]
    ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    include_source = params_get(params, :include_source_scan)

    {_, ast_issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc -> traverse(node, acc, source_file) end)

    source_issues =
      if include_source do
        scan_source_lines(source_file)
      else
        []
      end

    deduplicate(ast_issues ++ source_issues)
  end

  defp traverse(
         {:comment, meta, text} = node,
         issues,
         source_file
       )
       when is_list(meta) and is_binary(text) do
    if String.contains?(String.upcase(text), "TODO") do
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message: "Found TODO comment -- track in issue tracker and resolve",
          trigger: "TODO",
          line_no: line
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _source_file), do: {node, issues}

  defp scan_source_lines(%SourceFile{lines: lines} = source_file) do
    Enum.reduce(lines, [], fn {line_no, line_text}, acc ->
      if String.contains?(String.upcase(line_text), "TODO") do
        [
          format_issue(source_file,
            message: "Found TODO comment -- track in issue tracker and resolve",
            trigger: "TODO",
            line_no: line_no
          )
          | acc
        ]
      else
        acc
      end
    end)
  end

  defp deduplicate(issues) do
    issues
    |> Enum.uniq_by(fn issue -> issue.line_no end)
    |> Enum.sort_by(fn issue -> issue.line_no end)
  end
end
