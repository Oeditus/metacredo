defmodule MetaCredo.Check.Warning.MissingThrottle do
  use MetaCredo.Check,
    category: :warning,
    base_priority: :normal,
    explanations: [
      check: """
      Detects expensive operations triggered by user input (form submissions,
      search endpoints, API mutations) without rate limiting or throttling.
      In LiveView, form inputs sending `phx-change` events should use
      `phx-debounce` or `phx-throttle` to avoid flooding the server.

      For API endpoints, add rate-limiting middleware (e.g. `Hammer`,
      `PlugAttack`, `ExRated`).
      """,
      examples: [
        elixir: [
          wrong: """
          # POST /search -- no rate limiting, any client can hammer this
          def search(conn, %{"q" => q}) do
            results = FullTextSearch.query(q)
            json(conn, results)
          end
          """,
          correct: """
          # Add a rate-limiting plug before the action
          plug PlugAttack

          def search(conn, %{"q" => q}) do
            results = FullTextSearch.query(q)
            json(conn, results)
          end

          # Or for LiveView inputs, add phx-debounce:
          # <input phx-change="search" phx-debounce="300" />
          """
        ]
      ]
    ]

  @expensive_operations ~W(
    search query aggregate calculate compute
    export generate process batch
    upload download convert transform
    analyze scan report render
  )

  @rate_limit_indicators ~W(
    ratelimit rate_limit throttle limiter debounce
    hammer exrated plug_attack bucket
  )

  @api_context_indicators ~W(
    post put patch delete create update
    action controller endpoint handler
    api webhook mutation
  )

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    {_, {issues, _, _}} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk({[], nil, false}, fn node, acc -> traverse(node, acc, source_file) end)

    issues
  end

  # Track function context for API endpoint detection
  defp traverse(
         {:function_def, meta, children} = node,
         {issues, _ctx, _has_limiter},
         _source_file
       )
       when is_list(meta) do
    func_name = to_string(Keyword.get(meta, :name, ""))
    fn_lower = String.downcase(func_name)

    in_api? = Enum.any?(@api_context_indicators, &String.contains?(fn_lower, &1))
    has_limiter? = contains_rate_limiting?(children)

    {node, {issues, if(in_api?, do: func_name, else: nil), has_limiter?}}
  end

  # Detect expensive operations without throttling
  defp traverse(
         {:function_call, meta, _args} = node,
         {issues, api_context, has_limiter},
         source_file
       )
       when is_list(meta) and is_binary(api_context) and not has_limiter do
    fn_name = to_string(Keyword.get(meta, :name, ""))
    fn_lower = String.downcase(fn_name)

    if Enum.any?(@expensive_operations, &String.contains?(fn_lower, &1)) do
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message:
            "Expensive '#{fn_name}' in endpoint without rate limiting -- add throttle/debounce to prevent abuse",
          trigger: fn_name,
          line_no: line
        )

      {node, {[issue | issues], api_context, has_limiter}}
    else
      {node, {issues, api_context, has_limiter}}
    end
  end

  defp traverse(node, acc, _source_file), do: {node, acc}

  defp contains_rate_limiting?({:function_call, meta, _args}) when is_list(meta) do
    fn_name = to_string(Keyword.get(meta, :name, ""))
    fn_lower = String.downcase(fn_name)
    Enum.any?(@rate_limit_indicators, &String.contains?(fn_lower, &1))
  end

  defp contains_rate_limiting?(tuple) when is_tuple(tuple) do
    tuple |> Tuple.to_list() |> Enum.any?(&contains_rate_limiting?/1)
  end

  defp contains_rate_limiting?(list) when is_list(list) do
    Enum.any?(list, &contains_rate_limiting?/1)
  end

  defp contains_rate_limiting?(_), do: false
end
