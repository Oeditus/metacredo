defmodule MetaCredo.Check.Warning.BlockingInPlug do
  use MetaCredo.Check,
    category: :warning,
    base_priority: :high,
    explanations: [
      check: """
      Detects blocking operations (HTTP calls, long DB queries, file I/O)
      inside Plug middleware functions (`call/2`, `init/1`) or Phoenix
      controller plugs. Blocking in the request pipeline degrades throughput
      for all concurrent requests.

      Move blocking work to a cached value, background task, or async
      middleware pattern.
      """
    ]

  @blocking_operations ~W(
    get post query find read write
    sleep wait fetch load download
  )

  @middleware_functions ~W(call init plug)

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk({[], nil}, fn node, acc -> traverse(node, acc, source_file) end)

    issues
  end

  # Track when we enter a middleware function
  defp traverse(
         {:function_def, meta, _children} = node,
         {issues, _ctx},
         _source_file
       )
       when is_list(meta) do
    func_name = to_string(Keyword.get(meta, :name, ""))

    if func_name in @middleware_functions do
      {node, {issues, func_name}}
    else
      {node, {issues, nil}}
    end
  end

  # Detect blocking calls inside middleware
  defp traverse(
         {:function_call, meta, _args} = node,
         {issues, middleware_fn},
         source_file
       )
       when is_list(meta) and is_binary(middleware_fn) do
    fn_name = to_string(Keyword.get(meta, :name, ""))
    fn_lower = String.downcase(fn_name)

    blocking? =
      case Keyword.get(meta, :op_kind) do
        op_kind when is_list(op_kind) ->
          domain = Keyword.get(op_kind, :domain)
          domain in [:db, :http, :file, :cache, :external_api]

        nil ->
          has_blocking_indicator?(fn_lower)
      end

    if blocking? do
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message:
            "Blocking '#{fn_name}' in Plug #{middleware_fn}/2 -- use caching, async, or move to background task",
          trigger: fn_name,
          line_no: line
        )

      {node, {[issue | issues], middleware_fn}}
    else
      {node, {issues, middleware_fn}}
    end
  end

  defp traverse(node, acc, _source_file), do: {node, acc}

  defp has_blocking_indicator?(fn_lower) do
    Enum.any?(@blocking_operations, &String.contains?(fn_lower, &1))
  end
end
