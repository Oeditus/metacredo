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
      """,
      examples: [
        elixir: [
          wrong: """
          # Every request blocks waiting for a remote feature flag check
          def call(conn, _opts) do
            flags = HTTPoison.get!("https://flags.example.com/api").body
            assign(conn, :flags, flags)
          end
          """,
          correct: """
          # Cache flags at startup or refresh periodically in a GenServer
          def call(conn, _opts) do
            flags = FeatureFlags.get_all()  # reads from ETS or local cache
            assign(conn, :flags, flags)
          end
          """
        ]
      ]
    ]

  @blocking_operations ~W(
    get post query find read write
    sleep wait fetch load download
  )

  @middleware_functions ~W(call init plug)

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    {_, {issues, _}} =
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
    func_name = CheckUtils.safe_name(meta)

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
    fn_name = CheckUtils.safe_name(meta)
    fn_lower = String.downcase(fn_name)

    blocking? =
      case Keyword.get(meta, :op_kind) do
        op_kind when is_list(op_kind) ->
          domain = Keyword.get(op_kind, :domain)
          domain in [:db, :http, :file, :cache, :external_api]

        nil ->
          has_blocking_indicator?(fn_lower)
      end

    # `Map.fetch!/2` / `Map.get/2` are Metastatic's encoding of *field access*
    # (`conn.assigns`), not blocking I/O. The adapter may attach an `op_kind`
    # to them, so the sentinel check has to run regardless of which branch
    # above decided `blocking?`.
    blocking? = blocking? and not field_access_sentinel?(fn_lower)

    if blocking? do
      line = CheckUtils.line_of(meta)

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
    # `Map.fetch!/2` and `Map.get/2` are how Metastatic encodes *field access*
    # (`conn.assigns`), not blocking I/O -- matching them flagged every plug
    # that reads a struct field.
    not field_access_sentinel?(fn_lower) and
      Enum.any?(@blocking_operations, &String.contains?(fn_lower, &1))
  end

  # Metastatic's encoding of *field access* (`conn.assigns`), matched against
  # the downcased function name.
  @field_access_sentinels ~W(map.fetch! map.get map.fetch elem get_in)

  defp field_access_sentinel?(fn_lower), do: fn_lower in @field_access_sentinels
end
