defmodule MetaCredo.Check.Observability.TelemetryInRecursiveFunction do
  use MetaCredo.Check,
    category: :observability,
    base_priority: :high,
    param_defaults: [
      telemetry_indicators:
        ~W[telemetry metric statsd emit record increment gauge timing histogram counter execute span observe]
    ],
    explanations: [
      check: """
      Detects telemetry/metrics emissions inside recursive functions.
      This causes metric spam (N emissions for N iterations), performance
      degradation, and misleading metrics. Instead, wrap the entire
      recursive operation with telemetry at the top level.
      """,
      params: [
        telemetry_indicators: "Function name fragments that indicate telemetry/metrics calls"
      ],
      examples: [
        wrong: """
        # Emits a metric on EVERY recursive step -- N emissions per call
        def process_nodes([head | tail]) do
          :telemetry.execute([:my_app, :node_processed], %{count: 1}, %{})
          do_process(head)
          process_nodes(tail)
        end

        def process_nodes([]), do: :ok
        """,
        correct: """
        # Wrap the entry-point once; pass counters through accumulators
        def process_nodes(nodes) do
          :telemetry.span(
            [:my_app, :nodes_processed],
            %{count: length(nodes)},
            fn ->
              result = do_process_nodes(nodes)
              {result, %{}}
            end
          )
        end

        defp do_process_nodes([head | tail]) do
          do_process(head)
          do_process_nodes(tail)
        end

        defp do_process_nodes([]), do: :ok
        """
      ]
    ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    telemetry_indicators = params_get(params, :telemetry_indicators)

    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc ->
        traverse(node, acc, source_file, telemetry_indicators)
      end)

    issues
  end

  defp traverse(
         {:function_def, meta, children} = node,
         issues,
         source_file,
         telemetry_indicators
       )
       when is_list(meta) do
    name = Keyword.get(meta, :name, "")

    if name != "" and recursive?(name, children) and
         contains_telemetry?(children, telemetry_indicators) do
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message:
            "Telemetry emitted in recursive function '#{name}' -- wrap entire operation instead",
          trigger: to_string(name),
          line_no: line,
          severity: :warning
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _sf, _ti), do: {node, issues}

  # Check if function calls itself (direct recursion)
  defp recursive?(func_name, body), do: contains_call_to?(body, func_name)

  defp contains_call_to?({:function_call, meta, _args}, target) when is_list(meta) do
    name = Keyword.get(meta, :name, "")
    normalize(name) == normalize(target)
  end

  defp contains_call_to?({:block, _meta, stmts}, target) when is_list(stmts),
    do: Enum.any?(stmts, &contains_call_to?(&1, target))

  defp contains_call_to?({:conditional, _meta, branches}, target) when is_list(branches),
    do: Enum.any?(branches, &contains_call_to?(&1, target))

  defp contains_call_to?({_type, _meta, children}, target) when is_list(children),
    do: Enum.any?(children, &contains_call_to?(&1, target))

  defp contains_call_to?(list, target) when is_list(list),
    do: Enum.any?(list, &contains_call_to?(&1, target))

  defp contains_call_to?(_, _), do: false

  # Check if body contains telemetry calls
  defp contains_telemetry?({:function_call, meta, _args}, indicators) when is_list(meta) do
    name = Keyword.get(meta, :name, "")
    telemetry_function?(name, indicators)
  end

  defp contains_telemetry?({:block, _meta, stmts}, indicators) when is_list(stmts),
    do: Enum.any?(stmts, &contains_telemetry?(&1, indicators))

  defp contains_telemetry?({_type, _meta, children}, indicators) when is_list(children),
    do: Enum.any?(children, &contains_telemetry?(&1, indicators))

  defp contains_telemetry?(list, indicators) when is_list(list),
    do: Enum.any?(list, &contains_telemetry?(&1, indicators))

  defp contains_telemetry?(_, _), do: false

  defp telemetry_function?(name, indicators) when is_binary(name) do
    lower = String.downcase(name)
    Enum.any?(indicators, &String.contains?(lower, &1))
  end

  defp telemetry_function?(name, indicators) when is_atom(name),
    do: telemetry_function?(Atom.to_string(name), indicators)

  defp telemetry_function?(_, _), do: false

  defp normalize(name) when is_atom(name), do: Atom.to_string(name)
  defp normalize(name) when is_binary(name), do: name
  defp normalize(_), do: ""
end
