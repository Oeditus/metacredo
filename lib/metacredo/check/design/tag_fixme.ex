defmodule MetaCredo.Check.Design.TagFixme do
  use MetaCredo.Check,
    category: :design,
    base_priority: :high,
    param_defaults: [include_source_scan: true, tags: ["FIXME"]],
    explanations: [
      check: """
      Detects FIXME comments left in the codebase. FIXME tags indicate known
      bugs or broken code that must be fixed before shipping.

      Only matches that occur *inside a comment* are reported -- a `FIXME`
      appearing in a string literal, variable name, or `@moduledoc` prose
      is ignored. For languages whose adapter does not surface comment
      nodes (e.g. Elixir), the raw source is scanned with the comment
      portion of each line extracted first, so code and strings are never
      matched.
      """,
      params: [
        include_source_scan:
          "Also scan raw source lines for FIXME comments (default: true). Needed for languages whose adapter strips comments from the AST.",
        tags:
          "List of tag patterns (strings or regexes) to report as FIXME comments (default: [\"FIXME\"]). Strings match literally; regexes are used as-is. Example: [\"FIXME\", ~r/HACK/]"
      ],
      examples: [
        elixir: [
          wrong: """
          def calculate(a, b) do
            # FIXME: division by zero not handled
            a / b
          end
          """,
          correct: """
          # Either fix the issue inline or remove the comment and
          # open a ticket in your issue tracker with reproduction steps.
          def calculate(_a, 0), do: {:error, :division_by_zero}
          def calculate(a, b), do: {:ok, a / b}
          """
        ]
      ]
    ]

  alias MetaCredo.Check.Design.TagScan

  @impl true
  def run(%SourceFile{} = source_file, params) do
    include_source = params_get(params, :include_source_scan)
    regex = params_get(params, :tags) |> TagScan.compile_tags()

    {_, ast_issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc -> traverse(node, acc, source_file, regex) end)

    source_issues =
      if include_source do
        scan_source_lines(source_file, regex)
      else
        []
      end

    deduplicate(ast_issues ++ source_issues)
  end

  defp traverse(
         {:comment, meta, text} = node,
         issues,
         source_file,
         regex
       )
       when is_list(meta) and is_binary(text) do
    if TagScan.matches?(regex, text) do
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message: "Found FIXME comment -- fix the issue before shipping",
          trigger: trigger_for(regex, text),
          line_no: line
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _source_file, _regex), do: {node, issues}

  defp scan_source_lines(%SourceFile{lines: lines, language: language} = source_file, regex) do
    Enum.reduce(lines, [], fn {line_no, line_text}, acc ->
      # Only search the comment portion of the line -- never the code or
      # string literals that precede it.
      case TagScan.comment_text(line_text, language) do
        nil ->
          acc

        comment ->
          if TagScan.matches?(regex, comment) do
            [
              format_issue(source_file,
                message: "Found FIXME comment -- fix the issue before shipping",
                trigger: trigger_for(regex, comment),
                line_no: line_no
              )
              | acc
            ]
          else
            acc
          end
      end
    end)
  end

  # Prefer the actual matched text as the trigger (so custom tags surface
  # their own text); fall back to "FIXME" when the match cannot be
  # extracted.
  defp trigger_for(regex, text) do
    case Regex.run(regex, text) do
      [match | _] -> match
      _ -> "FIXME"
    end
  end

  defp deduplicate(issues) do
    issues
    |> Enum.uniq_by(fn issue -> issue.line_no end)
    |> Enum.sort_by(fn issue -> issue.line_no end)
  end
end
