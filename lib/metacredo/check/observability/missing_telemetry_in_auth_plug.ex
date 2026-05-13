defmodule MetaCredo.Check.Observability.MissingTelemetryInAuthPlug do
  use MetaCredo.Check,
    category: :observability,
    base_priority: :high,
    param_defaults: [
      auth_indicators:
        ~W[auth authenticate authorize permission verify check validate token session login logout sign_in sign_out],
      telemetry_indicators: ~W[telemetry emit log audit trace metric record]
    ],
    explanations: [
      check: """
      Detects authentication/authorization code without telemetry or audit
      logging. Auth operations should be instrumented for security auditing,
      compliance, and incident response.
      """,
      params: [
        auth_indicators: "Function/module name fragments indicating auth context",
        telemetry_indicators: "Function name fragments indicating telemetry/audit calls"
      ]
    ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    auth_indicators = params_get(params, :auth_indicators)
    telemetry_indicators = params_get(params, :telemetry_indicators)

    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc ->
        traverse(node, acc, source_file, auth_indicators, telemetry_indicators)
      end)

    issues
  end

  defp traverse(
         {:function_def, meta, children} = node,
         issues,
         source_file,
         auth_indicators,
         telemetry_indicators
       )
       when is_list(meta) do
    name = Keyword.get(meta, :name, "")

    if auth_function?(name, auth_indicators) and
         not body_has_telemetry?(children, telemetry_indicators) do
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message: "Auth function '#{name}' without telemetry -- add audit logging for security",
          trigger: to_string(name),
          line_no: line,
          severity: :warning
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _sf, _ai, _ti), do: {node, issues}

  defp auth_function?(name, indicators) when is_binary(name) do
    lower = String.downcase(name)
    Enum.any?(indicators, &String.contains?(lower, &1))
  end

  defp auth_function?(name, indicators) when is_atom(name),
    do: auth_function?(Atom.to_string(name), indicators)

  defp auth_function?(_, _), do: false

  defp body_has_telemetry?(children, indicators) when is_list(children),
    do: Enum.any?(children, &node_has_telemetry?(&1, indicators))

  defp body_has_telemetry?(_, _), do: false

  defp node_has_telemetry?({:function_call, meta, args}, indicators) when is_list(meta) do
    name = Keyword.get(meta, :name, "")

    if telemetry_call?(name, indicators) do
      true
    else
      is_list(args) and Enum.any?(args, &node_has_telemetry?(&1, indicators))
    end
  end

  defp node_has_telemetry?({:block, _meta, stmts}, indicators) when is_list(stmts),
    do: Enum.any?(stmts, &node_has_telemetry?(&1, indicators))

  defp node_has_telemetry?({_type, _meta, children}, indicators) when is_list(children),
    do: Enum.any?(children, &node_has_telemetry?(&1, indicators))

  defp node_has_telemetry?(_, _), do: false

  defp telemetry_call?(name, indicators) when is_binary(name) do
    lower = String.downcase(name)
    Enum.any?(indicators, &String.contains?(lower, &1))
  end

  defp telemetry_call?(_, _), do: false
end
