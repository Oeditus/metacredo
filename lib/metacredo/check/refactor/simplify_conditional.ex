defmodule MetaCredo.Check.Refactor.SimplifyConditional do
  use MetaCredo.Check,
    category: :refactor,
    base_priority: :low,
    explanations: [
      check: """
      Detects conditionals that return boolean literals and can be simplified
      to direct boolean expressions.

      Patterns detected:
      - `if condition do true else false end` -> `condition`
      - `if condition do false else true end` -> `not condition`
      - `if condition do condition else false end` -> `condition`
      """
    ]

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc -> traverse(node, acc, source_file) end)

    issues
  end

  # if cond do true else false end => cond
  defp traverse(
         {:conditional, meta,
          [
            _condition,
            {:literal, then_meta, true},
            {:literal, else_meta, false}
          ]} = node,
         issues,
         source_file
       )
       when is_list(meta) do
    if boolean_literal?(then_meta) and boolean_literal?(else_meta) do
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message: "Conditional can be simplified to just the condition expression",
          trigger: "if ... do true else false end",
          line_no: line,
          severity: :refactoring_opportunity
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  # if cond do false else true end => not cond
  defp traverse(
         {:conditional, meta,
          [
            _condition,
            {:literal, then_meta, false},
            {:literal, else_meta, true}
          ]} = node,
         issues,
         source_file
       )
       when is_list(meta) do
    if boolean_literal?(then_meta) and boolean_literal?(else_meta) do
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message: "Conditional can be simplified to `not condition`",
          trigger: "if ... do false else true end",
          line_no: line,
          severity: :refactoring_opportunity
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  # if cond do cond else false end => cond
  defp traverse(
         {:conditional, meta,
          [
            condition,
            condition,
            {:literal, else_meta, false}
          ]} = node,
         issues,
         source_file
       )
       when is_list(meta) do
    if boolean_literal?(else_meta) do
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message:
            "Conditional returns its condition in then-branch and false in else -- simplify to condition",
          trigger: "if cond do cond else false end",
          line_no: line,
          severity: :refactoring_opportunity
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _sf), do: {node, issues}

  defp boolean_literal?(meta) when is_list(meta),
    do: Keyword.get(meta, :subtype) == :boolean

  defp boolean_literal?(_), do: false
end
