defmodule MetaCredo.Check.Readability.NestedFunctionCalls do
  use MetaCredo.Check,
    category: :readability,
    base_priority: :normal,
    param_defaults: [max_nesting: 2],
    explanations: [
      check: """
      Detects deeply nested function calls like `foo(bar(baz(x)))`.
      Extract intermediate results into variables or use pipes for clarity.
      """,
      params: [
        max_nesting: "Maximum allowed nesting depth of function calls (default: 2)"
      ]
    ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    max_nesting = params_get(params, :max_nesting)

    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc ->
        traverse(node, acc, source_file, max_nesting)
      end)

    issues
  end

  defp traverse({:function_call, meta, args} = node, issues, source_file, max_nesting)
       when is_list(meta) and is_list(args) do
    depth = call_nesting_depth(args)

    if depth > max_nesting do
      name = Keyword.get(meta, :name, "?")
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message:
            "Nested function call depth #{depth} in '#{name}' (max: #{max_nesting}) -- extract into variables or use pipes",
          trigger: to_string(name),
          line_no: line
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _sf, _max), do: {node, issues}

  defp call_nesting_depth(args) when is_list(args) do
    args
    |> Enum.map(&arg_call_depth/1)
    |> Enum.max(fn -> 0 end)
  end

  defp arg_call_depth({:function_call, _meta, nested_args}) when is_list(nested_args) do
    1 + call_nesting_depth(nested_args)
  end

  defp arg_call_depth(_), do: 0
end
