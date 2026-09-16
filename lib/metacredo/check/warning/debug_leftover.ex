defmodule MetaCredo.Check.Warning.DebugLeftover do
  use MetaCredo.Check,
    category: :warning,
    base_priority: :high,
    explanations: [
      check: """
      Detects debug function calls left in code, such as `IO.inspect`,
      `dbg()`, `binding()`, `IEx.pry`, and `console.log`. These should be
      removed before merging to production.

      Legitimate output primitives (`IO.puts`, `IO.write`, `print`, etc.)
      are intentionally not flagged, since they are the intended output
      mechanism in CLI tools, scripts, and libraries.
      """,
      examples: [
        elixir: [
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
    ]

  # Functions whose *only* purpose is debugging/inspection. These are safe to
  # flag: they carry no production value and should be removed before merge.
  #
  # NOTE: legitimate output primitives (`IO.puts`, `IO.write`, `print`,
  # `println`, `puts`, `pp`, `puts`) are deliberately NOT listed here. In a
  # CLI tool, library, or script those are the intended output mechanism, not
  # leftover debugging -- flagging them produces a flood of false positives.
  @debug_functions ~W(
    IO.inspect IO.inspect! IO.binwrite
    dbg IEx.pry binding
    console.log console.debug console.warn console.error console.trace
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
    fn_name = CheckUtils.safe_name(meta)

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
