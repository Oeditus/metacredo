defmodule MetaCredo.Check.Warning.CallbackHell do
  use MetaCredo.Check,
    category: :warning,
    base_priority: :normal,
    param_defaults: [max_nesting: 3],
    explanations: [
      check: """
      Detects deeply nested conditional statements (`case`, `with`, `if/else`)
      exceeding the configured nesting threshold. Deep nesting creates
      "callback hell" that is hard to read, test, and maintain.

      Refactor using `with`, early returns, guard clauses, or extract
      nested logic into separate functions.
      """,
      params: [
        max_nesting: "Maximum allowed nesting depth (default: 3)"
      ]
    ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    max_nesting = params_get(params, :max_nesting)

    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc -> traverse(node, acc, source_file, max_nesting) end)

    issues
  end

  defp traverse(
         {:conditional, meta, _children} = node,
         issues,
         source_file,
         max_nesting
       )
       when is_list(meta) do
    depth = count_conditional_nesting(node)

    if depth > max_nesting do
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message:
            "#{depth} levels of nested conditionals (max #{max_nesting}) -- refactor with `with`, early returns, or extract functions",
          trigger: "case",
          line_no: line
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _source_file, _max_nesting), do: {node, issues}

  # Count nesting depth of conditionals
  defp count_conditional_nesting({:conditional, _meta, [_cond, then_branch, else_branch]}) do
    then_depth = count_nested_conditionals(then_branch)
    else_depth = count_nested_conditionals(else_branch)
    1 + max(then_depth, else_depth)
  end

  defp count_conditional_nesting({:conditional, _meta, [_cond | branches]}) do
    branch_depth =
      branches
      |> List.flatten()
      |> Enum.map(&count_nested_conditionals/1)
      |> Enum.max(fn -> 0 end)

    1 + branch_depth
  end

  defp count_conditional_nesting(_), do: 0

  defp count_nested_conditionals({:block, _meta, statements}) when is_list(statements) do
    statements
    |> Enum.map(&count_conditional_nesting/1)
    |> Enum.max(fn -> 0 end)
  end

  defp count_nested_conditionals({:conditional, _meta, _children} = node) do
    count_conditional_nesting(node)
  end

  defp count_nested_conditionals({:match_arm, _meta, body}) when is_list(body) do
    body
    |> Enum.map(&count_conditional_nesting/1)
    |> Enum.max(fn -> 0 end)
  end

  defp count_nested_conditionals(_), do: 0
end
