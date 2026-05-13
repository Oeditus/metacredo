defmodule MetaCredo.Check.Warning.UnusedOperation do
  use MetaCredo.Check,
    category: :warning,
    base_priority: :normal,
    explanations: [
      check: """
      Detects function call results that are unused. A function call appearing
      as a statement in a block whose result is neither assigned nor returned
      (i.e., not the last statement and not wrapped in an assignment) likely
      indicates a missing assignment or accidental side-effect-only call.
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

  # Match blocks and check non-last, non-assigned function_call statements
  defp traverse({:block, _meta, statements} = node, issues, source_file)
       when is_list(statements) and length(statements) > 1 do
    non_last = Enum.slice(statements, 0..(length(statements) - 2)//1)

    new_issues =
      Enum.reduce(non_last, issues, fn
        {:function_call, call_meta, _args}, acc when is_list(call_meta) ->
          fn_name = to_string(Keyword.get(call_meta, :name, ""))

          if side_effect_only?(fn_name) do
            acc
          else
            line = Keyword.get(call_meta, :line)

            issue =
              format_issue(source_file,
                message:
                  "Result of '#{fn_name}' is unused -- assign the result or use it as the return value",
                trigger: fn_name,
                line_no: line
              )

            [issue | acc]
          end

        _other, acc ->
          acc
      end)

    {node, new_issues}
  end

  defp traverse(node, issues, _source_file), do: {node, issues}

  @side_effect_fns ~w(
    send put_in update_in Process.send Agent.update
    Logger.info Logger.warn Logger.error Logger.debug Logger.warning
    IO.puts IO.write IO.inspect
  )

  defp side_effect_only?(fn_name) do
    fn_name in @side_effect_fns or String.starts_with?(fn_name, "IO.") or
      String.starts_with?(fn_name, "Logger.")
  end
end
