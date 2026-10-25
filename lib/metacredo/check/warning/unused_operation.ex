defmodule MetaCredo.Check.Warning.UnusedOperation do
  use MetaCredo.Check,
    category: :warning,
    base_priority: :normal,
    confidence: :high,
    tags: [:returns],
    explanations: [
      check: """
      Detects function call results that are unused. A function call appearing
      as a statement in a block whose result is neither assigned nor returned
      (i.e., not the last statement and not wrapped in an assignment) likely
      indicates a missing assignment or accidental side-effect-only call.
      """,
      examples: [
        elixir: [
          wrong: """
          # The uppercased string is computed and immediately discarded
          defmodule Names do
            def normalize(name) do
              String.upcase(name)
              String.trim(name)
            end
          end
          """,
          correct: """
          # Assign or pipe the result so it is actually used
          def normalize(name) do
            name
            |> String.upcase()
            |> String.trim()
          end
          """
        ]
      ]
    ]

  # Offset from the end of a statement list: the last statement's index.
  @last 2

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc -> traverse(node, acc, source_file) end)

    issues
  end

  # Match blocks and check non-last, non-assigned function_call statements.
  #
  # A function body arrives as a bare statement list rather than a `:block`
  # node, so both shapes are handled.
  defp traverse({:block, _meta, statements} = node, issues, source_file)
       when is_list(statements) and length(statements) > 1 do
    {node, check_statements(statements, issues, source_file)}
  end

  defp traverse({:function_def, meta, statements} = node, issues, source_file)
       when is_list(meta) and is_list(statements) and length(statements) > 1 do
    {node, check_statements(statements, issues, source_file)}
  end

  defp traverse(node, issues, _source_file), do: {node, issues}

  defp check_statements(statements, issues, source_file) do
    non_last = Enum.slice(statements, 0..(length(statements) - @last)//1)

    Enum.reduce(non_last, issues, fn
      {:function_call, call_meta, _args}, acc when is_list(call_meta) ->
        fn_name = to_string(Keyword.get(call_meta, :name, ""))

        if side_effect_only?(fn_name) do
          acc
        else
          issue =
            format_issue(source_file,
              message:
                "Result of '#{fn_name}' is unused -- assign the result or use it as the return value",
              trigger: fn_name,
              line_no: CheckUtils.line_of(call_meta)
            )

          [issue | acc]
        end

      _other, acc ->
        acc
    end)
  end

  @side_effect_fns ~W(
    send put_in update_in Process.send Agent.update
    Logger.info Logger.warn Logger.error Logger.debug Logger.warning
    IO.puts IO.write IO.inspect
    assert refute test describe setup setup_all on_exit
  )

  defp side_effect_only?(fn_name) do
    fn_name in @side_effect_fns or
      String.starts_with?(fn_name, "IO.") or
      String.starts_with?(fn_name, "Logger.") or
      String.starts_with?(fn_name, "File.") or
      String.starts_with?(fn_name, "Mix.") or
      String.ends_with?(fn_name, "!")
  end
end
