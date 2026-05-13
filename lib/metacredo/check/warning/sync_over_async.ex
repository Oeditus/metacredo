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

  @blocking_indicators ~W(
    get post put delete patch request
    fetch download upload
    read write open
    query execute transaction
    sleep wait
  )

  @async_callback_names ~W(
    handle_call handle_cast handle_info handle_continue
    mount handle_event handle_params handle_async
  )

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    {_, {issues, _}} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk({[], nil}, fn node, acc -> traverse(node, acc, source_file) end)

    issues
  end

  # Track when we enter a function_def that is an async callback
  defp traverse(
         {:function_def, meta, _children} = node,
         {issues, _ctx},
         _source_file
       )
       when is_list(meta) do
    func_name = to_string(Keyword.get(meta, :name, ""))

    if func_name in @async_callback_names do
      {node, {issues, func_name}}
    else
      {node, {issues, nil}}
    end
  end

  # Detect blocking calls inside an async callback context
  defp traverse(
         {:function_call, meta, _args} = node,
         {issues, callback_name},
         source_file
       )
       when is_list(meta) and is_binary(callback_name) do
    fn_name = to_string(Keyword.get(meta, :name, ""))
    fn_lower = String.downcase(fn_name)

    blocking? =
      case Keyword.get(meta, :op_kind) do
        op_kind when is_list(op_kind) ->
          domain = Keyword.get(op_kind, :domain)
          domain in [:db, :http, :file, :external_api]

        nil ->
          Enum.any?(@blocking_indicators, &String.contains?(fn_lower, &1))
      end

    if blocking? do
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message:
            "Blocking '#{fn_name}' call in #{callback_name} -- offload to Task.Supervisor or start_async",
          trigger: fn_name,
          line_no: line
        )

      {node, {[issue | issues], callback_name}}
    else
      {node, {issues, callback_name}}
    end
  end

  defp traverse(node, acc, _source_file), do: {node, acc}
end
