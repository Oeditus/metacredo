defmodule MetaCredo.Check.Observability.MissingTelemetryInLiveviewMount do
  use MetaCredo.Check,
    category: :observability,
    base_priority: :normal,
    param_defaults: [
      lifecycle_indicators: ~W[mount componentdidmount oninit oninitialize mounted created setup],
      telemetry_indicators: ~W[telemetry emit log trace metric record measure]
    ],
    explanations: [
      check: """
      Detects component lifecycle methods (e.g. LiveView `mount/3`, React
      `componentDidMount`) without telemetry. Lifecycle events should be
      tracked for performance monitoring.
      """,
      params: [
        lifecycle_indicators: "Function name fragments indicating lifecycle hooks",
        telemetry_indicators: "Function name fragments indicating telemetry calls"
      ],
      examples: [
        wrong: """
        # Mount latency is invisible to dashboards and alerting
        def mount(_params, _session, socket) do
          {:ok, assign(socket, :users, Repo.all(User))}
        end
        """,
        correct: """
        # Emit telemetry so LiveView render time shows up in metrics
        def mount(_params, _session, socket) do
          :telemetry.execute(
            [:my_app, :live_view, :mount],
            %{system_time: System.system_time()},
            %{view: __MODULE__}
          )
          {:ok, assign(socket, :users, Repo.all(User))}
        end
        """
      ]
    ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    lifecycle_indicators = params_get(params, :lifecycle_indicators)
    telemetry_indicators = params_get(params, :telemetry_indicators)

    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc ->
        traverse(node, acc, source_file, lifecycle_indicators, telemetry_indicators)
      end)

    issues
  end

  defp traverse(
         {:function_def, meta, children} = node,
         issues,
         source_file,
         lifecycle_indicators,
         telemetry_indicators
       )
       when is_list(meta) do
    name = Keyword.get(meta, :name, "")

    if lifecycle_function?(name, lifecycle_indicators) and
         not body_has_telemetry?(children, telemetry_indicators) do
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message: "Lifecycle method '#{name}' without telemetry -- add performance tracking",
          trigger: to_string(name),
          line_no: line
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _sf, _li, _ti), do: {node, issues}

  defp lifecycle_function?(name, indicators) when is_binary(name) do
    lower = String.downcase(name)
    Enum.any?(indicators, &String.contains?(lower, &1))
  end

  defp lifecycle_function?(name, indicators) when is_atom(name),
    do: lifecycle_function?(Atom.to_string(name), indicators)

  defp lifecycle_function?(_, _), do: false

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
