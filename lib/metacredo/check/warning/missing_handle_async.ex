defmodule MetaCredo.Check.Warning.MissingHandleAsync do
  use MetaCredo.Check,
    category: :warning,
    base_priority: :high,
    explanations: [
      check: """
      Detects LiveView `handle_event` callbacks that perform blocking work
      (HTTP calls, heavy computation, long DB queries) without delegating
      to `start_async/3` or `Task.Supervisor`. Blocking in `handle_event`
      freezes the LiveView process and the user sees no feedback.

      Use `assign_async/3`, `start_async/3`, or `Task.Supervisor` to run
      expensive work asynchronously and handle results in `handle_async/3`.
      """,
      examples: [
        wrong: """
        # Blocks the LiveView process -- user sees a frozen UI during the request
        def handle_event("search", %{"q" => q}, socket) do
          results = HTTPoison.get!("https://api.example.com/search?q=\#{q}")
          {:noreply, assign(socket, :results, results)}
        end
        """,
        correct: """
        # Delegate to start_async/3 and update socket in handle_async/3
        def handle_event("search", %{"q" => q}, socket) do
          {:noreply, start_async(socket, :search, fn -> do_search(q) end)}
        end

        def handle_async(:search, {:ok, results}, socket) do
          {:noreply, assign(socket, :results, results)}
        end

        def handle_async(:search, {:exit, reason}, socket) do
          {:noreply, assign(socket, :error, reason)}
        end
        """
      ]
    ]

  @async_spawn_indicators ~W(
    create_task run_async start spawn
    task async future start_async assign_async
  )

  @blocking_indicators ~W(
    get post put delete request fetch download
    query execute transaction sleep wait
  )

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    {_, {issues, _}} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk({[], false}, fn node, acc -> traverse(node, acc, source_file) end)

    issues
  end

  # Track entering a handle_event function
  defp traverse(
         {:function_def, meta, children} = node,
         {issues, _in_handle_event},
         source_file
       )
       when is_list(meta) do
    func_name = to_string(Keyword.get(meta, :name, ""))

    if func_name == "handle_event" do
      # Check if body contains blocking calls without async delegation
      has_blocking = contains_blocking?(children)
      has_async = contains_async_delegation?(children)

      if has_blocking and not has_async do
        line = Keyword.get(meta, :line)

        issue =
          format_issue(source_file,
            message:
              "Blocking operation in handle_event without async pattern -- use start_async/3 or assign_async/3",
            trigger: "handle_event",
            line_no: line
          )

        {node, {[issue | issues], true}}
      else
        {node, {issues, true}}
      end
    else
      {node, {issues, false}}
    end
  end

  defp traverse(node, acc, _source_file), do: {node, acc}

  defp contains_blocking?({:function_call, meta, _args}) when is_list(meta) do
    fn_name = to_string(Keyword.get(meta, :name, ""))
    fn_lower = String.downcase(fn_name)
    Enum.any?(@blocking_indicators, &String.contains?(fn_lower, &1))
  end

  defp contains_blocking?(tuple) when is_tuple(tuple) do
    tuple |> Tuple.to_list() |> Enum.any?(&contains_blocking?/1)
  end

  defp contains_blocking?(list) when is_list(list) do
    Enum.any?(list, &contains_blocking?/1)
  end

  defp contains_blocking?(_), do: false

  defp contains_async_delegation?({:function_call, meta, _args}) when is_list(meta) do
    fn_name = to_string(Keyword.get(meta, :name, ""))
    fn_lower = String.downcase(fn_name)
    Enum.any?(@async_spawn_indicators, &String.contains?(fn_lower, &1))
  end

  defp contains_async_delegation?(tuple) when is_tuple(tuple) do
    tuple |> Tuple.to_list() |> Enum.any?(&contains_async_delegation?/1)
  end

  defp contains_async_delegation?(list) when is_list(list) do
    Enum.any?(list, &contains_async_delegation?/1)
  end

  defp contains_async_delegation?(_), do: false
end
