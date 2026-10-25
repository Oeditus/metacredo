defmodule MetaCredo.Check.Observability.MissingTelemetryInObanWorker do
  use MetaCredo.Check,
    category: :observability,
    base_priority: :normal,
    confidence: :low,
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
      enricher to identify actual behaviour callbacks. When that metadata is
      absent -- as it is for Elixir, whose adapter does not emit it -- the
      check falls back to detecting a `use <JobBehaviour>` directive
      (`use Oban.Worker`, `use Broadway`, ...) in the enclosing module, which
      is how job workers are declared in practice.

      When `fallback_heuristic` is `true`, functions are additionally matched
      by name against `job_indicators`.
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
          defmodule MyApp.DigestWorker do
            use Oban.Worker, queue: :mailers

            @impl Oban.Worker
            def perform(%Oban.Job{args: %{"user_id" => id}}) do
              send_digest_email(id)
            end
          end
          """,
          correct: """
          # Wrap with :telemetry.span/3 to track success, failure, and latency
          defmodule MyApp.DigestWorker do
            use Oban.Worker, queue: :mailers

            @impl Oban.Worker
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
          end
          """
        ]
      ]
    ]

  # Threaded check configuration. Bundling the four params into a struct
  # keeps `traverse/3` readable and below the arity limit.
  defmodule Config do
    @moduledoc false
    defstruct job_behaviours: [], telemetry_indicators: [], fallback?: false, job_indicators: []
  end

  @impl true
  def run(%SourceFile{} = source_file, params) do
    config = %Config{
      job_behaviours: params_get(params, :job_behaviours),
      telemetry_indicators: params_get(params, :telemetry_indicators),
      fallback?: params_get(params, :fallback_heuristic),
      job_indicators: params_get(params, :job_indicators)
    }

    ast = SourceFile.ast(source_file)

    {_, issues} =
      AST.prewalk(ast, [], fn node, acc ->
        traverse(node, acc, source_file, config, worker_module?(ast, config))
      end)

    issues
  end

  # Elixir's adapter does not emit `callback_for`, so a worker is recognised
  # by a `use <JobBehaviour>` directive anywhere in the file.
  defp worker_module?(ast, config) do
    {_, found} =
      AST.prewalk(ast, false, fn
        {:import, meta, _} = node, acc when is_list(meta) ->
          source = Keyword.get(meta, :source, "")
          {node, acc or source in config.job_behaviours}

        node, acc ->
          {node, acc}
      end)

    found
  end

  # Match function definitions with callback_for metadata
  defp traverse(
         {:function_def, meta, children} = node,
         issues,
         source_file,
         %Config{} = config,
         worker_module?
       )
       when is_list(meta) do
    name = Keyword.get(meta, :name, "")
    callback_for = Keyword.get(meta, :callback_for)

    is_job_callback =
      cond do
        callback_for -> callback_for in config.job_behaviours
        worker_module? -> name in ~W(perform execute run call)
        true -> config.fallback? and job_function?(name, config.job_indicators)
      end

    if is_job_callback and not body_has_telemetry?(children, config.telemetry_indicators) do
      line = CheckUtils.line_of(meta)

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

  defp traverse(node, issues, _sf, _config, _worker), do: {node, issues}

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
