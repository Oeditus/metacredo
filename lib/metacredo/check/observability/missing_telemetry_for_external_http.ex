defmodule MetaCredo.Check.Observability.MissingTelemetryForExternalHttp do
  use MetaCredo.Check,
    category: :observability,
    base_priority: :normal,
    confidence: :low,
    param_defaults: [
      # Fragments that must appear in the MODULE part of the call to qualify as an
      # HTTP client library (e.g. "HTTPoison.get" matches because the module
      # "HTTPoison" contains "httpoison"). Local helpers and stdlib calls are
      # excluded because their module names do not match any of these hints.
      http_client_modules: ~W[
        httpoison req tesla finch mint gun faraday hackney ibrowse
        httpclient webclient restclient http https api client
      ],
      # The method name (the part after the last dot) must equal one of these verbs
      # or start with one followed by an underscore (e.g. "get", "get_async").
      http_methods: ~W[get post put patch delete head options request fetch send],
      telemetry_indicators: ~W[telemetry emit log trace metric record measure span]
    ],
    explanations: [
      check: """
      Detects external HTTP client calls (e.g. HTTPoison.get, Req.post,
      Tesla.request, Finch.request) without telemetry instrumentation.
      External requests should be wrapped with telemetry to track API
      latency, failure rates, and service health.

      Only module-qualified calls whose module name contains an HTTP library
      hint are flagged, so local helpers and stdlib functions (e.g.
      Access.get, Map.fetch!) are never reported.
      """,
      params: [
        http_client_modules: "Fragments matched against the MODULE part of qualified calls",
        http_methods: "HTTP verbs matched against the method (last dot-segment) of calls",
        telemetry_indicators: "Function name fragments indicating telemetry wrapping"
      ],
      examples: [
        elixir: [
          wrong: """
          # Bare HTTP call -- latency and failures are invisible
          def fetch_user(id) do
            HTTPoison.get!("https://api.example.com/users/\#{id}")
          end
          """,
          correct: """
          # Wrap with :telemetry.span/3 to capture latency and errors
          def fetch_user(id) do
            :telemetry.span(
              [:my_app, :external, :fetch_user],
              %{id: id},
              fn ->
                result = HTTPoison.get!("https://api.example.com/users/\#{id}")
                {result, %{}}
              end
            )
          end
          """
        ]
      ]
    ]

  # Threaded check configuration. Bundling the three params into a struct
  # keeps `traverse/3` readable and below the arity limit.
  defmodule Config do
    @moduledoc false
    defstruct client_modules: [], methods: [], telemetry_indicators: []
  end

  @impl true
  def run(%SourceFile{} = source_file, params) do
    config = %Config{
      client_modules: params_get(params, :http_client_modules),
      methods: params_get(params, :http_methods),
      telemetry_indicators: params_get(params, :telemetry_indicators)
    }

    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> then(fn ast -> walk(ast, [], source_file, config) end)

    issues
  end

  # A manual walk, because `AST.prewalk/3` cannot prune subtrees and an HTTP
  # call already wrapped in `:telemetry.span/3` must not be reported.
  defp walk({:function_call, meta, args}, issues, source_file, %Config{} = config)
       when is_list(meta) do
    name = Keyword.get(meta, :name, "")

    cond do
      telemetry_call?(name, config.telemetry_indicators) ->
        {issues, nil}

      http_call?(name, config.client_modules, config.methods) ->
        issue =
          format_issue(source_file,
            message: "HTTP call '#{name}' without telemetry -- wrap with instrumentation",
            trigger: to_string(name),
            line_no: CheckUtils.line_of(meta)
          )

        {[issue | issues], walk_all(args, source_file, config)}

      true ->
        {issues, walk_all(args, source_file, config)}
    end
  end

  defp walk({_type, _meta, children}, issues, source_file, config) when is_list(children),
    do: {issues, walk_all(children, source_file, config)}

  defp walk(list, issues, source_file, config) when is_list(list),
    do: {issues, walk_all(list, source_file, config)}

  defp walk(_node, issues, _source_file, _config), do: {issues, nil}

  defp walk_all(nodes, source_file, config) do
    Enum.reduce(nodes, [], fn node, acc ->
      {issues, _} = walk(node, [], source_file, config)
      issues ++ acc
    end)
  end

  # A call qualifies as an HTTP call only when:
  #   1. It is module-qualified (contains a dot) — local helpers are never HTTP clients
  #   2. The MODULE part contains one of the http_client_modules hints
  #   3. The METHOD part (after the last dot) equals or starts with an http_methods verb
  defp http_call?(name, client_modules, methods) when is_binary(name) do
    case String.split(name, ".") do
      [_bare] ->
        false

      parts ->
        module = parts |> Enum.drop(-1) |> Enum.join(".") |> String.downcase()
        # `get!`/`get?` are the same verb as `get`.
        method =
          parts
          |> List.last()
          |> String.downcase()
          |> String.trim_trailing("!")
          |> String.trim_trailing("?")

        Enum.any?(client_modules, &String.contains?(module, &1)) and
          Enum.any?(methods, fn m ->
            method == m or String.starts_with?(method, m <> "_")
          end)
    end
  end

  defp http_call?(name, client_modules, methods) when is_atom(name),
    do: http_call?(Atom.to_string(name), client_modules, methods)

  defp http_call?(_, _, _), do: false

  defp telemetry_call?(name, indicators) when is_binary(name) do
    lower = String.downcase(name)
    Enum.any?(indicators, &String.contains?(lower, &1))
  end

  defp telemetry_call?(_, _), do: false
end
