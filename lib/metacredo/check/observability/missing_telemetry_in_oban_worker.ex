defmodule MetaCredo.Check.Observability.MissingTelemetryInObanWorker do
  use MetaCredo.Check,
    category: :observability,
    base_priority: :normal,
    param_defaults: [
      job_indicators: ~w[perform execute process run worker job task handler],
      telemetry_indicators: ~w[telemetry emit log trace metric record measure monitor]
    ],
    explanations: [
      check: """
      Detects background job processing functions (e.g. Oban worker `perform/1`)
      without telemetry instrumentation. Background jobs should emit metrics
      for monitoring, debugging, and alerting on job execution.
      """,
      params: [
        job_indicators: "Function/module name fragments that indicate a job context",
        telemetry_indicators: "Function name fragments that indicate telemetry calls"
      ]
    ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    job_indicators = params_get(params, :job_indicators)
    telemetry_indicators = params_get(params, :telemetry_indicators)

    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc ->
        traverse(node, acc, source_file, job_indicators, telemetry_indicators)
      end)

    issues
  end

  # Match function definitions that look like job workers
  defp traverse(
         {:function_def, meta, children} = node,
         issues,
         source_file,
         job_indicators,
         telemetry_indicators
       )
       when is_list(meta) do
    name = Keyword.get(meta, :name, "")

    if job_function?(name, job_indicators) and
         not body_has_telemetry?(children, telemetry_indicators) do
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message: "Background job '#{name}' without telemetry -- add metrics for job execution",
          trigger: to_string(name),
          line_no: line
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _source_file, _job_indicators, _telemetry_indicators),
    do: {node, issues}

  defp job_function?(name, indicators) when is_binary(name) do
    lower = String.downcase(name)
    Enum.any?(indicators, &String.contains?(lower, &1))
  end

  defp job_function?(name, indicators) when is_atom(name),
    do: job_function?(Atom.to_string(name), indicators)

  defp job_function?(_, _), do: false

  defp body_has_telemetry?(children, indicators) when is_list(children) do
    Enum.any?(children, &node_has_telemetry?(&1, indicators))
  end

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

  defp node_has_telemetry?({:conditional, _meta, branches}, indicators) when is_list(branches),
    do: Enum.any?(branches, &node_has_telemetry?(&1, indicators))

  defp node_has_telemetry?({_type, _meta, children}, indicators) when is_list(children),
    do: Enum.any?(children, &node_has_telemetry?(&1, indicators))

  defp node_has_telemetry?(_, _), do: false

  defp telemetry_call?(name, indicators) when is_binary(name) do
    lower = String.downcase(name)
    Enum.any?(indicators, &String.contains?(lower, &1))
  end

  defp telemetry_call?(_, _), do: false
end
