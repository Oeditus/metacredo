defmodule MetaCredo.Check.Observability.MissingTelemetryInObanWorker do
  use MetaCredo.Check,
    category: :observability,
    base_priority: :normal,
    param_defaults: [
      job_behaviours: ~W[
        Oban.Worker
        Sidekiq::Worker
        Sidekiq::Job
        ActiveJob::Base
        celery.Task
        dramatiq.Actor
        Broadway
      ],
      telemetry_indicators: ~W[telemetry emit log trace metric record measure monitor],
      fallback_heuristic: false,
      job_indicators: ~W[perform execute process run worker job task handler]
    ],
    explanations: [
      check: """
      Detects background job processing functions (e.g. Oban worker `perform/1`)
      without telemetry instrumentation. Background jobs should emit metrics
      for monitoring, debugging, and alerting on job execution.

      The check uses `callback_for` metadata produced by Metastatic's semantic
      enricher to identify actual behaviour callbacks. Only functions whose
      `callback_for` matches one of the configured `job_behaviours` are flagged.

      When `fallback_heuristic` is `true`, functions without `callback_for`
      metadata are also checked using name-based `job_indicators` matching
      (the legacy behaviour). This is off by default.
      """,
      params: [
        job_behaviours:
          "Behaviour/base-class module names that identify job workers (matched against callback_for metadata on function_def nodes)",
        telemetry_indicators: "Function name fragments that indicate telemetry calls",
        fallback_heuristic:
          "When true, also flag functions matching job_indicators even without callback_for metadata (legacy name-based heuristic)",
        job_indicators:
          "Function name fragments for the fallback heuristic (only used when fallback_heuristic is true)"
      ],
      examples: [
        elixir: [
          wrong: """
          # Job execution is invisible -- no way to track duration or failures
          def perform(%Oban.Job{args: %{"user_id" => id}}) do
            send_digest_email(id)
          end
          """,
          correct: """
          # Wrap with :telemetry.span/3 to track success, failure, and latency
          def perform(%Oban.Job{args: %{"user_id" => id}}) do
            :telemetry.span(
              [:my_app, :workers, :digest_email],
              %{user_id: id},
              fn ->
                result = send_digest_email(id)
                {result, %{}}
              end
            )
          end
          """
        ]
      ]
    ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    job_behaviours = params_get(params, :job_behaviours)
    telemetry_indicators = params_get(params, :telemetry_indicators)
    fallback? = params_get(params, :fallback_heuristic)
    job_indicators = params_get(params, :job_indicators)

    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc ->
        traverse(
          node,
          acc,
          source_file,
          job_behaviours,
          telemetry_indicators,
          fallback?,
          job_indicators
        )
      end)

    issues
  end

  # Match function definitions with callback_for metadata
  defp traverse(
         {:function_def, meta, children} = node,
         issues,
         source_file,
         job_behaviours,
         telemetry_indicators,
         fallback?,
         job_indicators
       )
       when is_list(meta) do
    name = Keyword.get(meta, :name, "")
    callback_for = Keyword.get(meta, :callback_for)

    is_job_callback =
      if callback_for do
        callback_for in job_behaviours
      else
        fallback? and job_function?(name, job_indicators)
      end

    if is_job_callback and not body_has_telemetry?(children, telemetry_indicators) do
      line = Keyword.get(meta, :line)

      label = callback_for || "job"

      issue =
        format_issue(source_file,
          message:
            "#{label} callback '#{name}' without telemetry -- add metrics for job execution",
          trigger: to_string(name),
          line_no: line
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _sf, _jb, _ti, _fb, _ji), do: {node, issues}

  # -- Fallback heuristic helpers (only used when fallback_heuristic: true) --

  defp job_function?(name, indicators) when is_binary(name) do
    lower = String.downcase(name)
    Enum.any?(indicators, &String.contains?(lower, &1))
  end

  defp job_function?(name, indicators) when is_atom(name),
    do: job_function?(Atom.to_string(name), indicators)

  defp job_function?(_, _), do: false

  # -- Telemetry detection (unchanged) --

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
