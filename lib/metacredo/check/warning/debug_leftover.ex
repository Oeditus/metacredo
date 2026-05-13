defmodule MetaCredo.Check.Warning.DebugLeftover do
  use MetaCredo.Check,
    category: :warning,
    base_priority: :high,
    explanations: [
      check: """
      Detects debug function calls left in code, such as `IO.inspect`,
      `IO.puts`, `dbg()`, `print()`, `console.log`, `pry`, and similar.
      These should be removed before merging to production.
      """,
      examples: [
        wrong: """
        def process(order) do
          IO.inspect(order, label: "order")  # left over from debugging
          total = calculate_total(order)
          dbg(total)
          persist(total)
        end
        """,
        correct: """
        def process(order) do
          total = calculate_total(order)
          persist(total)
        end
        """
      ]
    ]

  @debug_functions ~W(
    IO.inspect IO.puts IO.write
    dbg IEx.pry binding
    console.log console.debug console.warn console.error
    print println pp p puts
    var_dump print_r dd dump
    Debug.print debugger pry
  )

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc -> traverse(node, acc, source_file) end)

    issues
  end

  defp traverse(
         {:function_call, meta, _args} = node,
         issues,
         source_file
       )
       when is_list(meta) do
    fn_name = to_string(Keyword.get(meta, :name, ""))

    if debug_function?(fn_name) do
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message: "Debug call '#{fn_name}' left in code -- remove before production",
          trigger: fn_name,
          line_no: line
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _source_file), do: {node, issues}

  defp debug_function?(fn_name), do: fn_name in @debug_functions
end
