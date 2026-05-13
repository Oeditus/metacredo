defmodule MetaCredo.Check.Observability.MissingTelemetryForExternalHttp do
  use MetaCredo.Check,
    category: :observability,
    base_priority: :normal,
    param_defaults: [
      http_indicators: ~W[http fetch request get post put patch delete],
      telemetry_indicators: ~W[telemetry emit log trace metric record measure span]
    ],
    explanations: [
      check: """
      Detects external HTTP client calls (e.g. HTTPoison.get, Req.post,
      fetch, axios) without telemetry instrumentation. External requests
      should be wrapped with telemetry to track API latency, failure rates,
      and service health.
      """,
      params: [
        http_indicators: "Function name fragments indicating HTTP calls",
        telemetry_indicators: "Function name fragments indicating telemetry wrapping"
      ]
    ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    http_indicators = params_get(params, :http_indicators)
    telemetry_indicators = params_get(params, :telemetry_indicators)

    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc ->
        traverse(node, acc, source_file, http_indicators, telemetry_indicators)
      end)

    issues
  end

  # Detect bare HTTP calls not inside a telemetry wrapper
  defp traverse(
         {:function_call, meta, _args} = node,
         issues,
         source_file,
         http_indicators,
         telemetry_indicators
       )
       when is_list(meta) do
    name = Keyword.get(meta, :name, "")

    if http_call?(name, http_indicators) and not telemetry_call?(name, telemetry_indicators) and
         not CheckUtils.safe_stdlib_call?(name) do
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message: "HTTP call '#{name}' without telemetry -- wrap with instrumentation",
          trigger: to_string(name),
          line_no: line
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _sf, _hi, _ti), do: {node, issues}

  defp http_call?(name, indicators) when is_binary(name) do
    lower = String.downcase(name)
    Enum.any?(indicators, &String.contains?(lower, &1))
  end

  defp http_call?(name, indicators) when is_atom(name),
    do: http_call?(Atom.to_string(name), indicators)

  defp http_call?(_, _), do: false

  defp telemetry_call?(name, indicators) when is_binary(name) do
    lower = String.downcase(name)
    Enum.any?(indicators, &String.contains?(lower, &1))
  end

  defp telemetry_call?(_, _), do: false
end
