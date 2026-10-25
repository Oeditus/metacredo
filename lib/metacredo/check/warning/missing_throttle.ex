defmodule MetaCredo.Check.Warning.MissingThrottle do
  use MetaCredo.Check,
    category: :warning,
    base_priority: :normal,
    confidence: :low,
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
    hammer exrated plug_attack plugattack bucket
  )

  @api_context_indicators ~W(
    post put patch delete create update
    action controller endpoint handler
    api webhook mutation
    search query upload export report
  )

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    ast = SourceFile.ast(source_file)

    # A rate limiter is usually declared at module level (`plug PlugAttack`),
    # not inside the endpoint function, so the whole file is inspected once.
    file_has_limiter? = contains_rate_limiting?(ast)

    {_, {issues, _, _}} =
      AST.prewalk(ast, {[], nil, file_has_limiter?}, fn node, acc ->
        traverse(node, acc, source_file)
      end)

    issues
  end

  # Track function context for API endpoint detection.
  #
  # An "API endpoint" must be a *whole word* match on the function name
  # (`create`, `update`, `action`, ...). Substring matching flagged helpers
  # like `generate_summary_from_result` because they contain "create" inside
  # "generate".
  #
  # The API context is scoped to the function body: it is computed here and
  # reset to `nil` immediately after, so a following sibling function cannot
  # inherit it. A bare `prewalk` accumulator would otherwise leak the context
  # from `update_summary/1` into every subsequent function in the file.
  defp traverse(
         {:function_def, meta, children} = node,
         {issues, _ctx, file_has_limiter?},
         source_file
       )
       when is_list(meta) do
    func_name = CheckUtils.safe_name(meta)

    api_context = if api_endpoint_name?(func_name), do: func_name, else: nil
    has_limiter? = file_has_limiter? or contains_rate_limiting?(children)

    {_, {issues, _, _}} =
      AST.prewalk({:block, [], children}, {issues, api_context, has_limiter?}, fn child, acc ->
        traverse_call(child, acc, source_file)
      end)

    # Do not descend again from the parent walk, and reset the context.
    {node, {issues, nil, false}}
  end

  defp traverse(node, acc, source_file), do: traverse_call(node, acc, source_file)

  # Detect expensive operations without throttling
  defp traverse_call(
         {:function_call, meta, _args} = node,
         {issues, api_context, has_limiter},
         source_file
       )
       when is_list(meta) and is_binary(api_context) and not has_limiter do
    fn_name = CheckUtils.safe_name(meta)
    fn_lower = String.downcase(fn_name)

    if Enum.any?(@expensive_operations, &String.contains?(fn_lower, &1)) do
      line = CheckUtils.line_of(meta)

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

  defp traverse_call(node, acc, _source_file), do: {node, acc}

  # A function is an API endpoint when one of its name *segments* (split on
  # `_`/`?`/`!`) is an API context indicator -- so `create_user` and
  # `update/2` match, while `generate_summary_from_result` does not.
  #
  # Predicates (`has_upload_param?`, `searchable?`) are excluded: they ask a
  # question about data, they are not endpoints.
  defp api_endpoint_name?(func_name) when is_binary(func_name) do
    segments =
      func_name
      |> String.downcase()
      |> String.split(~r/[^a-z0-9]+/, trim: true)

    not predicate_name?(func_name) and
      Enum.any?(segments, &(&1 in @api_context_indicators))
  end

  defp api_endpoint_name?(_), do: false

  defp predicate_name?(func_name) do
    String.ends_with?(func_name, "?") or
      Enum.any?(~W(has is get_ find_ check_), &String.starts_with?(func_name, &1))
  end

  defp contains_rate_limiting?({:function_call, meta, args}) when is_list(meta) do
    fn_name = CheckUtils.safe_name(meta)
    fn_lower = String.downcase(fn_name)

    # `plug PlugAttack` declares the limiter as an *argument*, so the
    # arguments are inspected as well as the call name.
    Enum.any?(@rate_limit_indicators, &String.contains?(fn_lower, &1)) or
      contains_rate_limiting?(args)
  end

  # A bare module reference such as `PlugAttack` in `plug PlugAttack`.
  defp contains_rate_limiting?({:variable, _meta, name}) when is_binary(name) do
    lower = String.downcase(name)
    Enum.any?(@rate_limit_indicators, &String.contains?(lower, &1))
  end

  defp contains_rate_limiting?(tuple) when is_tuple(tuple) do
    tuple |> Tuple.to_list() |> Enum.any?(&contains_rate_limiting?/1)
  end

  defp contains_rate_limiting?(list) when is_list(list) do
    Enum.any?(list, &contains_rate_limiting?/1)
  end

  defp contains_rate_limiting?(_), do: false
end
