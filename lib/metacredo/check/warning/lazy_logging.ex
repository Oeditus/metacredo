defmodule MetaCredo.Check.Warning.LazyLogging do
  use MetaCredo.Check,
    category: :warning,
    base_priority: :normal,
    explanations: [
      check: """
      Detects Logger calls that use string interpolation directly instead of
      wrapping the message in an anonymous function. Eager interpolation
      performs the string building even when the log level is disabled.

      Use `Logger.info(fn -> "msg: \#{val}" end)` instead.
      """,
      examples: [
        elixir: [
          wrong: """
          # String is always built, even if :debug level is disabled in production
          Logger.debug("Processing order \#{order.id} for user \#{user.email}")
          """,
          correct: """
          # Lazy evaluation: string is only built when the level is active
          Logger.debug(fn -> "Processing order \#{order.id} for user \#{user.email}" end)
          """
        ]
      ]
    ]

  @logger_names ~W(Logger.info Logger.warn Logger.error Logger.debug Logger.warning Logger.notice Logger.critical Logger.alert Logger.emergency)

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc -> traverse(node, acc, source_file) end)

    issues
  end

  defp traverse(
         {:function_call, meta, args} = node,
         issues,
         source_file
       )
       when is_list(meta) and is_list(args) do
    fn_name = CheckUtils.safe_name(meta)

    if logger_call?(fn_name) and has_interpolation_arg?(args) do
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message:
            "Use lazy logging with an anonymous function to avoid eager interpolation in '#{fn_name}'",
          trigger: fn_name,
          line_no: line
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _source_file), do: {node, issues}

  defp logger_call?(fn_name), do: fn_name in @logger_names

  defp has_interpolation_arg?(args) do
    Enum.any?(args, &contains_interpolation?/1)
  end

  defp contains_interpolation?({:string_interpolation, _meta, _children}), do: true

  defp contains_interpolation?({_type, _meta, children}) when is_list(children) do
    Enum.any?(children, &contains_interpolation?/1)
  end

  defp contains_interpolation?(_), do: false
end
