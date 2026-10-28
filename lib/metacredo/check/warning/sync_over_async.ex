defmodule MetaCredo.Check.Warning.SyncOverAsync do
  use MetaCredo.Check,
    category: :warning,
    base_priority: :high,
    explanations: [
      check: """
      Detects blocking synchronous operations (HTTP calls, long DB queries,
      file I/O) inside GenServer callbacks (`handle_call`, `handle_cast`,
      `handle_info`) or LiveView callbacks (`mount`, `handle_event`,
      `handle_params`). Blocking in these contexts stalls the process
      mailbox and degrades responsiveness.

      Offload blocking work to `Task.Supervisor.async_nolink/2` or use
      `start_async/3` in LiveView.
      """,
      examples: [
        elixir: [
          wrong: """
          # Blocks the GenServer mailbox for the duration of the HTTP call
          def handle_call(:refresh, _from, state) do
            data = HTTPoison.get!("https://api.example.com/data").body
            {:reply, data, %{state | data: data}}
          end
          """,
          correct: """
          # Offload the blocking work to a supervised task
          def handle_call(:refresh, _from, state) do
            Task.Supervisor.async_nolink(MyApp.TaskSup, fn ->
              HTTPoison.get!("https://api.example.com/data").body
            end)
            {:reply, :refreshing, state}
          end

          def handle_info({ref, data}, state) when is_reference(ref) do
            Process.demonitor(ref, [:flush])
            {:noreply, %{state | data: data}}
          end
          """
        ]
      ]
    ]

  @async_callback_names ~W(
    handle_call handle_cast handle_info handle_continue
    mount handle_event handle_params handle_async
  )

  # Calls that already move work off the calling process. Anything inside
  # their lambda argument is, by definition, no longer blocking the callback.
  @offload_calls ~W(
    Task.async Task.start Task.start_link Task.async_stream Task.async_stream_nolink
    Task.Supervisor.async Task.Supervisor.async_nolink Task.Supervisor.start_child
    Task.Supervisor.async_stream Task.Supervisor.async_stream_nolink
    Phoenix.LiveView.start_async start_async
  )

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    {_, {issues, _}} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk({[], nil}, fn node, acc -> traverse(node, acc, source_file) end)

    issues
  end

  # Track when we enter a function_def that is an async callback.
  #
  # The callback body is walked here, with offloaded subtrees skipped, and the
  # node is returned unchanged so the outer `prewalk` does not descend into it
  # a second time.
  defp traverse(
         {:function_def, meta, children} = node,
         {issues, _ctx},
         source_file
       )
       when is_list(meta) and is_list(children) do
    func_name = CheckUtils.safe_name(meta)

    if func_name in @async_callback_names do
      {issues, _} = walk_body(children, {issues, func_name}, source_file)
      {node, {issues, nil}}
    else
      {node, {issues, nil}}
    end
  end

  defp traverse(node, acc, _source_file), do: {node, acc}

  # `AST.prewalk/3` cannot prune subtrees, and offloaded work (a
  # `Task.Supervisor` lambda) must not be descended into at all -- so the
  # callback body is walked manually here.
  defp walk_body(children, acc, source_file) when is_list(children) do
    Enum.reduce(children, acc, &walk_body(&1, &2, source_file))
  end

  defp walk_body({:function_call, meta, args} = node, acc, source_file) when is_list(meta) do
    if offload_call?(CheckUtils.safe_name(meta)) do
      # Lambda bodies run elsewhere; other arguments are still evaluated
      # synchronously before the task can be started.
      Enum.reduce(args, acc, fn
        {:lambda, _, _}, inner -> inner
        argument, inner -> walk_body(argument, inner, source_file)
      end)
    else
      {_node, acc} = traverse_call(node, acc, source_file)
      walk_body(args, acc, source_file)
    end
  end

  defp walk_body({_type, _meta, children}, acc, source_file) when is_list(children) do
    walk_body(children, acc, source_file)
  end

  defp walk_body(_node, acc, _source_file), do: acc

  # An offloading call: do not descend into it, its work is already async.
  # Otherwise, report it if it blocks while we are inside a callback.
  defp traverse_call({:function_call, meta, _args} = node, {issues, callback_name}, source_file)
       when is_list(meta) do
    fn_name = CheckUtils.safe_name(meta)

    if blocking_in_callback?(fn_name, callback_name, meta) do
      issue =
        format_issue(source_file,
          message:
            "Blocking '#{fn_name}' call in #{callback_name} -- offload to Task.Supervisor or start_async",
          trigger: fn_name,
          line_no: CheckUtils.line_of(meta)
        )

      {node, {[issue | issues], callback_name}}
    else
      {node, {issues, callback_name}}
    end
  end

  defp traverse_call(node, acc, _source_file), do: {node, acc}

  # Blocking only matters inside a callback, and only for calls that are not
  # already offloaded to a supervised task.
  defp blocking_in_callback?(fn_name, callback_name, meta) do
    is_binary(callback_name) and not offload_call?(fn_name) and blocking_call?(meta, fn_name)
  end

  defp offload_call?(name) when is_binary(name) do
    String.replace_prefix(name, "Elixir.", "") in @offload_calls
  end

  defp blocking_call?(meta, fn_name) do
    not field_access_sentinel?(String.downcase(fn_name)) and CheckUtils.blocking_call?(meta)
  end

  # Metastatic's encoding of *field access* (`state.data`), matched against the
  # downcased function name.
  @field_access_sentinels ~W(map.fetch! map.get map.fetch elem get_in)

  defp field_access_sentinel?(fn_lower), do: fn_lower in @field_access_sentinels
end
