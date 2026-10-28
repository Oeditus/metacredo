defmodule MetaCredo.Check.Warning.MissingThrottle do
  use MetaCredo.Check,
    category: :warning,
    base_priority: :normal,
    confidence: :low,
    explanations: [
      check: """
      Detects expensive work at request boundaries without rate limiting.
      Controller actions need a request parameter, LiveView events need
      callback/socket evidence, and HTTP route macros establish their own
      boundary. CRUD names in storage modules are not endpoints.

      Add rate-limiting middleware (e.g. Hammer, PlugAttack, ExRated) at the
      request boundary, or debounce/throttle user-driven LiveView inputs.
      """,
      examples: [
        elixir: [
          wrong: """
          def search(conn, %{"q" => q}) do
            results = FullTextSearch.query(q)
            json(conn, results)
          end
          """,
          correct: """
          plug PlugAttack

          def search(conn, %{"q" => q}) do
            results = FullTextSearch.query(q)
            json(conn, results)
          end
          """
        ]
      ]
    ]

  @expensive_operations ~W(
    search query aggregate calculate compute export generate process batch
    upload download convert transform analyze scan report render
  )
  @limiter_pattern ~r/(^|[._\/])(rate_?limit|throttle|limiter|debounce|hammer|ex_?rated|plug_?attack)($|[._\/!?])/

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    scan(SourceFile.ast(source_file), {nil, false, false}, source_file, [])
  end

  defp request_module?(meta, children) do
    String.ends_with?(CheckUtils.safe_name(meta), "Controller") or
      Enum.any?(children, fn
        {:import, meta, _} ->
          Keyword.get(meta, :source) in ~W(Phoenix.Controller Phoenix.LiveView Plug.Router Plug.Builder)

        {:function_call, meta, _} ->
          CheckUtils.safe_name(meta) == "plug"

        _ ->
          false
      end)
  end

  defp response_body?(children) do
    {_node, found?} =
      AST.prewalk({:block, [], children}, false, fn
        {:function_call, meta, _} = node, found? ->
          {_module, function} = CheckUtils.call_parts(CheckUtils.safe_name(meta))
          {node, found? or function in ~W(json send_resp render)}

        node, found? ->
          {node, found?}
      end)

    found?
  end

  # Each container owns its plug declarations; neither limiter evidence nor
  # request context may leak into a sibling function/module.
  defp scan({:container, meta, children}, _context, source_file, issues) do
    limiter? = Enum.any?(children, &limiter_declaration?/1)
    scan(children, {nil, limiter?, request_module?(meta, children)}, source_file, issues)
  end

  defp scan({:block, _meta, children}, {nil, limited?, request_module?}, source_file, issues) do
    limiter? = limited? or Enum.any?(children, &limiter_declaration?/1)
    scan(children, {nil, limiter?, request_module?}, source_file, issues)
  end

  defp scan(
         {:function_def, meta, children},
         {_ctx, module_limiter?, request_module?},
         source_file,
         issues
       ) do
    endpoint =
      if request_boundary?(meta, children, request_module?),
        do: CheckUtils.safe_name(meta),
        else: nil

    limited? = module_limiter? or contains_rate_limiting?(children)
    scan(children, {endpoint, limited?, request_module?}, source_file, issues)
  end

  defp scan({:function_call, meta, args} = node, context, source_file, issues) do
    context =
      if route_call?(meta, args),
        do: {CheckUtils.safe_name(meta), elem(context, 1) or contains_rate_limiting?(args), true},
        else: context

    issues = check_call(node, context, source_file, issues)
    scan(args, context, source_file, issues)
  end

  defp scan({_kind, _meta, children}, context, source_file, issues) when is_list(children) do
    scan(children, context, source_file, issues)
  end

  defp scan(children, context, source_file, issues) when is_list(children) do
    Enum.reduce(children, issues, &scan(&1, context, source_file, &2))
  end

  defp scan(_node, _context, _source_file, issues), do: issues

  defp check_call(
         {:function_call, meta, _args},
         {endpoint, false, _request_module?},
         source_file,
         issues
       )
       when is_binary(endpoint) do
    if expensive_call?(meta) do
      name = CheckUtils.safe_name(meta)

      [
        format_issue(source_file,
          message:
            "Expensive '#{name}' in endpoint without rate limiting -- add throttle/debounce to prevent abuse",
          trigger: name,
          line_no: CheckUtils.line_of(meta)
        )
        | issues
      ]
    else
      issues
    end
  end

  defp check_call(_node, _context, _source_file, issues), do: issues

  defp expensive_call?(meta) do
    name = CheckUtils.safe_name(meta)
    {_module, function} = CheckUtils.call_parts(name)

    io? =
      case Keyword.get(meta, :op_kind) do
        kind when is_list(kind) ->
          Keyword.get(kind, :domain) in [:db, :http, :file, :external_api]

        _ ->
          CheckUtils.blocking_call?(meta)
      end

    not CheckUtils.pure_operation?(name) and
      (io? or
         Enum.any?(segments(function), &(&1 in @expensive_operations)))
  end

  defp request_boundary?(meta, children, request_module?) do
    name = CheckUtils.safe_name(meta)

    params =
      Enum.map(Keyword.get(meta, :params, []), fn
        {:param, _, name} when is_binary(name) -> name
        _ -> ""
      end)

    callback = to_string(Keyword.get(meta, :callback_for, ""))
    request_param? = Enum.any?(params, &(&1 in ~W(conn request req)))

    live_event? =
      name == "handle_event" and ("socket" in params or callback == "Phoenix.LiveView")

    http? = request_module? or callback in ~W(Phoenix.Controller Plug) or response_body?(children)

    Keyword.get(meta, :visibility, :public) != :private and
      not String.ends_with?(name, "?") and
      (live_event? or (request_param? and http?))
  end

  defp segments(name), do: name |> String.downcase() |> String.split(~r/[^a-z0-9]+/, trim: true)

  defp route_call?(meta, [{:literal, _, path} | _args]) when is_binary(path) do
    CheckUtils.safe_name(meta) in ~W(get post put patch delete options head) and
      String.starts_with?(path, "/")
  end

  defp route_call?(_meta, _args), do: false

  defp limiter_declaration?({:function_call, meta, args}) do
    CheckUtils.safe_name(meta) == "plug" and Enum.any?(args, &limiter_argument?/1)
  end

  defp limiter_declaration?(_node), do: false

  defp contains_rate_limiting?({:function_def, _meta, _children}), do: false

  defp contains_rate_limiting?({:function_call, meta, args}) do
    limiter_name?(CheckUtils.safe_name(meta)) or contains_rate_limiting?(args)
  end

  defp contains_rate_limiting?(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.any?(&contains_rate_limiting?/1)

  defp contains_rate_limiting?(list) when is_list(list),
    do: Enum.any?(list, &contains_rate_limiting?/1)

  defp contains_rate_limiting?(_node), do: false

  defp limiter_argument?({kind, _meta, name})
       when kind in [:variable, :literal] and (is_binary(name) or is_atom(name)),
       do: limiter_name?(to_string(name))

  defp limiter_argument?(_node), do: false

  defp limiter_name?(name) do
    Regex.match?(@limiter_pattern, Macro.underscore(name))
  end
end
