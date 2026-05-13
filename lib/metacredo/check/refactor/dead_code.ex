defmodule MetaCredo.Check.Refactor.DeadCode do
  use MetaCredo.Check,
    category: :refactor,
    base_priority: :high,
    explanations: [
      check: """
      Detects unreachable code after early returns. Statements following
      a `return`, `raise`, or `throw` can never execute and should be removed.
      """
    ]

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    source_file
    |> SourceFile.ast()
    |> find_dead_code(source_file)
  end

  defp find_dead_code(ast, source_file) do
    {_, issues} =
      AST.prewalk(ast, [], fn node, acc ->
        traverse(node, acc, source_file)
      end)

    issues
  end

  # Check blocks for statements after early_return
  defp traverse({:block, meta, stmts} = node, issues, source_file)
       when is_list(meta) and is_list(stmts) do
    new_issues = check_block_for_dead(stmts, source_file)
    {node, new_issues ++ issues}
  end

  defp traverse(node, issues, _sf), do: {node, issues}

  defp check_block_for_dead(stmts, source_file) do
    {issues, _} =
      Enum.reduce(stmts, {[], false}, fn stmt, {acc, found_return?} ->
        cond do
          found_return? ->
            line = extract_line(stmt)

            issue =
              format_issue(source_file,
                message: "Unreachable code after early return -- remove dead code",
                trigger: "unreachable",
                line_no: line
              )

            {[issue | acc], true}

          early_return?(stmt) ->
            {acc, true}

          true ->
            {acc, false}
        end
      end)

    issues
  end

  defp early_return?({:early_return, _meta, _children}), do: true
  defp early_return?(_), do: false

  defp extract_line({_type, meta, _children}) when is_list(meta),
    do: Keyword.get(meta, :line)

  defp extract_line(_), do: nil
end
