defmodule MetaCredo.Check.Readability.NestedFunctionCalls do
  use MetaCredo.Check,
    category: :readability,
    base_priority: :normal,
    confidence: :high,
    param_defaults: [max_nesting: 3],
    explanations: [
      check: """
      Detects deeply nested function calls like `foo(bar(baz(qux(x))))`.
      Extract intermediate results into variables or use pipes for clarity.

      Pipe chains are not reported: `input |> f() |> g()` desugars to
      `g(f(input))`, but the pipeline reads linearly, so its steps are not
      counted as nesting levels.
      """,
      params: [
        max_nesting: "Maximum allowed nesting depth of function calls (default: 3)"
      ],
      examples: [
        elixir: [
          wrong: """
          # Five levels deep -- must read inside-out to understand data flow
          def normalize(input) do
            Enum.join(
              Enum.map(String.split(String.trim(String.downcase(input)), ","), fn x ->
                String.trim(x)
              end),
              " | "
            )
          end
          """,
          correct: """
          # Use pipes or intermediate variables to make the flow linear
          def normalize(input) do
            input
            |> String.trim()
            |> String.split(",")
            |> Enum.map(fn x -> String.trim(x) end)
            |> Enum.join(" | ")
          end
          """
        ]
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
    name = to_string(Keyword.get(meta, :name, "?"))

    if name in ~W(assert refute test describe setup setup_all) do
      {node, issues}
    else
      depth = call_nesting_depth(args)

      if depth > max_nesting do
        line = CheckUtils.line_of(meta)

        issue =
          format_issue(source_file,
            message:
              "Nested function call depth #{depth} in '#{name}' (max: #{max_nesting}) -- extract into variables or use pipes",
            trigger: name,
            line_no: line
          )

        {node, [issue | issues]}
      else
        {node, issues}
      end
    end
  end

  defp traverse(node, issues, _sf, _max), do: {node, issues}

  defp call_nesting_depth(args) when is_list(args) do
    args
    |> Enum.map(&arg_call_depth/1)
    |> Enum.max(fn -> 0 end)
  end

  # A pipe step (`x |> f(y)` desugars to `f(x, y)` with `pipe: true`) is not a
  # nesting level: the piped-in value is threaded as the first argument, so the
  # chain reads linearly rather than inside-out. We still recurse into the pipe
  # step's arguments so that genuinely nested calls *within* a pipe are counted.
  defp arg_call_depth({:function_call, meta, nested_args})
       when is_list(meta) and is_list(nested_args) do
    if Keyword.get(meta, :pipe, false) do
      call_nesting_depth(nested_args)
    else
      1 + call_nesting_depth(nested_args)
    end
  end

  # `Enum.map/2`, `Enum.filter/2`, ... are emitted as `:collection_op` rather
  # than `:function_call`, so they are a nesting level in their own right.
  defp arg_call_depth({:collection_op, meta, nested_args})
       when is_list(meta) and is_list(nested_args) do
    if Keyword.get(meta, :pipe, false) do
      call_nesting_depth(nested_args)
    else
      1 + call_nesting_depth(nested_args)
    end
  end

  defp arg_call_depth(_), do: 0
end
