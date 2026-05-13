defmodule MetaCredo.Check.Warning.UnmanagedTask do
  use MetaCredo.Check,
    category: :warning,
    base_priority: :high,
    explanations: [
      check: """
      Detects `Task.async/1` and `Task.start/1` calls that are not routed
      through a `Task.Supervisor`. Unsupervised tasks can leak memory,
      silently fail, and leave orphaned processes.

      Use `Task.Supervisor.async_nolink/2` or `Task.Supervisor.start_child/2`.
      """
    ]

  @unsupervised_patterns ~w(Task.async Task.start Task.async_stream)

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc -> traverse(node, acc, source_file) end)

    issues
  end

  # Direct async_operation spawn
  defp traverse(
         {:async_operation, meta, _children} = node,
         issues,
         source_file
       )
       when is_list(meta) do
    line = Keyword.get(meta, :line)

    issue =
      format_issue(source_file,
        message: "Unsupervised async operation -- use Task.Supervisor to prevent leaks",
        trigger: "async",
        line_no: line
      )

    {node, [issue | issues]}
  end

  # Function call matching Task.async/Task.start pattern
  defp traverse(
         {:function_call, meta, _args} = node,
         issues,
         source_file
       )
       when is_list(meta) do
    func_name = to_string(Keyword.get(meta, :name, ""))

    if unsupervised_task?(func_name) do
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message:
            "Unsupervised '#{func_name}' -- use Task.Supervisor.async_nolink/2 to prevent leaks and silent failures",
          trigger: func_name,
          line_no: line
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _source_file), do: {node, issues}

  defp unsupervised_task?(func_name) when is_binary(func_name) do
    # Match Task.async but not Task.Supervisor.async
    Enum.any?(@unsupervised_patterns, &(func_name == &1)) or
      (String.contains?(func_name, "Task.async") and
         not String.contains?(func_name, "Supervisor"))
  end
end
