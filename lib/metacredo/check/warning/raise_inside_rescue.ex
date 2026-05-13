defmodule MetaCredo.Check.Warning.RaiseInsideRescue do
  use MetaCredo.Check,
    category: :warning,
    base_priority: :high,
    explanations: [
      check: """
      Detects bare `raise` or `throw` inside rescue/exception handling blocks
      without re-raise semantics. Using `raise` inside a rescue block instead
      of `reraise` loses the original stack trace, making debugging harder.

      Use `reraise(exception, __STACKTRACE__)` to preserve the original trace.
      """
    ]

  @bare_raise_names ~w(raise throw)
  @reraise_names ~w(reraise)

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc -> traverse(node, acc, source_file) end)

    issues
  end

  defp traverse(
         {:exception_handling, meta, children} = node,
         issues,
         source_file
       )
       when is_list(meta) and is_list(children) do
    catch_clauses =
      Enum.filter(children, fn
        {:match_arm, _, _} -> true
        _ -> false
      end)

    new_issues =
      Enum.reduce(catch_clauses, issues, fn {:match_arm, _arm_meta, body}, acc ->
        body_list = if is_list(body), do: body, else: [body]
        find_bare_raises(body_list, acc, source_file)
      end)

    {node, new_issues}
  end

  defp traverse(node, issues, _source_file), do: {node, issues}

  defp find_bare_raises(nodes, issues, source_file) when is_list(nodes) do
    Enum.reduce(nodes, issues, fn node, acc ->
      find_bare_raises(node, acc, source_file)
    end)
  end

  defp find_bare_raises(
         {:function_call, call_meta, _args} = _node,
         issues,
         source_file
       )
       when is_list(call_meta) do
    fn_name = to_string(Keyword.get(call_meta, :name, ""))
    fn_base = fn_name |> String.split(".") |> List.last()

    cond do
      fn_base in @reraise_names ->
        issues

      fn_base in @bare_raise_names ->
        line = Keyword.get(call_meta, :line)

        [
          format_issue(source_file,
            message:
              "Bare '#{fn_name}' inside rescue -- use reraise to preserve the original stack trace",
            trigger: fn_name,
            line_no: line
          )
          | issues
        ]

      true ->
        issues
    end
  end

  defp find_bare_raises({:block, _meta, stmts}, issues, source_file) when is_list(stmts) do
    find_bare_raises(stmts, issues, source_file)
  end

  defp find_bare_raises({_type, _meta, children}, issues, source_file)
       when is_list(children) do
    find_bare_raises(children, issues, source_file)
  end

  defp find_bare_raises(_, issues, _source_file), do: issues
end
