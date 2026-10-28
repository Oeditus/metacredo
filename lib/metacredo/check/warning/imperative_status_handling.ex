defmodule MetaCredo.Check.Warning.ImperativeStatusHandling do
  use MetaCredo.Check,
    category: :warning,
    base_priority: :normal,
    confidence: :low,
    param_defaults: [
      status_field_names: ["status", "state"],
      min_states: 3
    ],
    explanations: [
      check: """
      Detects imperative if/else or case chains that branch on a `status` or
      `state` field with 3+ distinct values. Ad-hoc status management is
      error-prone (missing transitions, invalid state paths) and should be
      replaced with a finite state machine (`Finitomata`, `gen_statem`, or
      equivalent).

      Also flags direct assignments and record updates to status fields.
      Lifecycle function names alone are not evidence of an ad-hoc FSM.
      """,
      params: [
        status_field_names: "Field/variable names to watch (default: [\"status\", \"state\"])",
        min_states: "Minimum distinct status values before flagging (default: 3)"
      ],
      examples: [
        elixir: [
          wrong: """
          # Ad-hoc status machine -- missing transitions are easy to miss
          defmodule Orders do
            def process(order) do
              case order.status do
                :pending -> {:ok, %{order | status: :processing}}
                :processing -> {:ok, %{order | status: :shipped}}
                :shipped -> {:ok, %{order | status: :delivered}}
                :cancelled -> {:error, :already_cancelled}
              end
            end
          end
          """,
          correct: """
          # Model transitions explicitly with Finitomata or gen_statem
          # The FSM string declares every valid transition:
          #   idle --> |submit| processing
          #   processing --> |ship| shipped
          #   shipped --> |deliver| delivered
          #   processing --> |cancel| cancelled
          defmodule OrderFSM do
            use Finitomata, fsm: @fsm_definition
          end
          """
        ]
      ]
    ]

  # Threaded check configuration, so the branching helper stays below the
  # parameter-count limit.
  defmodule Ctx do
    @moduledoc false
    defstruct [:source_file, :status_fields, :min_states]
  end

  @impl true
  def run(%SourceFile{} = source_file, params) do
    status_fields = params_get(params, :status_field_names)
    min_states = params_get(params, :min_states)

    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc ->
        traverse(node, acc, source_file, status_fields, min_states)
      end)

    issues
  end

  # Tier 1: Conditional branching on status field
  defp traverse(
         {:conditional, meta, [condition | _branches]} = node,
         issues,
         source_file,
         status_fields,
         min_states
       )
       when is_list(meta) do
    ctx = %Ctx{source_file: source_file, status_fields: status_fields, min_states: min_states}
    check_status_branching(node, condition, meta, issues, ctx)
  end

  # `case order.status do ... end` is emitted as `:pattern_match`.
  defp traverse(
         {:pattern_match, meta, [condition | _arms]} = node,
         issues,
         source_file,
         status_fields,
         min_states
       )
       when is_list(meta) do
    ctx = %Ctx{source_file: source_file, status_fields: status_fields, min_states: min_states}
    check_status_branching(node, condition, meta, issues, ctx)
  end

  # Tier 2: Assignment to status field
  defp traverse(
         {kind, meta, [target, value]} = node,
         issues,
         source_file,
         status_fields,
         _min_states
       )
       when kind in [:assignment, :inline_match] and is_list(meta) do
    if assigns_to_status_field?(target, status_fields) do
      state_value = extract_literal_value(value)

      if state_value do
        line = CheckUtils.line_of(meta)

        issue =
          format_issue(source_file,
            message:
              "Imperative status assignment to #{inspect(state_value)} -- FSM transitions should manage state changes",
            trigger: "status =",
            line_no: line
          )

        {node, [issue | issues]}
      else
        {node, issues}
      end
    else
      {node, issues}
    end
  end

  # Parsed Elixir map updates encode record writes as Map.put/Map.merge.
  defp traverse(
         {:function_call, meta, _children} = node,
         issues,
         source_file,
         status_fields,
         _min_states
       )
       when is_list(meta) do
    found =
      for {field, value} <- status_writes(node),
          to_string(field) in status_fields,
          is_atom(value) or is_binary(value) do
        format_issue(source_file,
          message:
            "Imperative status assignment to #{inspect(value)} -- FSM transitions should manage state changes",
          trigger: "#{field} =",
          line_no: CheckUtils.line_of(meta)
        )
      end

    {node, found ++ issues}
  end

  defp traverse(node, issues, _source_file, _status_fields, _min_states), do: {node, issues}

  # -- Helpers --

  # `order.status` is emitted as `Map.fetch!(order, :status)`.
  defp accesses_status_field?(
         {:function_call, meta, [_receiver, {:literal, lit_meta, field}]},
         status_fields
       )
       when is_list(meta) and is_list(lit_meta) do
    Keyword.get(meta, :name) in ~W(Map.fetch! Map.fetch) and
      to_string(field) in status_fields
  end

  defp accesses_status_field?({:field_access, meta, _children}, status_fields) do
    field_name = Keyword.get(meta, :field) || Keyword.get(meta, :name)
    is_simple = is_binary(field_name) or is_atom(field_name)
    is_simple && to_string(field_name) in status_fields
  end

  defp accesses_status_field?({:variable, _meta, name}, status_fields) when is_binary(name) do
    name in status_fields
  end

  defp accesses_status_field?({:binary_op, _meta, [left, right]}, status_fields) do
    accesses_status_field?(left, status_fields) or
      accesses_status_field?(right, status_fields)
  end

  defp accesses_status_field?(_node, _status_fields), do: false

  defp assigns_to_status_field?({:field_access, meta, _children}, status_fields) do
    field_name = Keyword.get(meta, :field) || Keyword.get(meta, :name)
    is_simple = is_binary(field_name) or is_atom(field_name)
    is_simple && to_string(field_name) in status_fields
  end

  defp assigns_to_status_field?({:variable, _meta, name}, status_fields) when is_binary(name) do
    name in status_fields
  end

  defp assigns_to_status_field?(_target, _status_fields), do: false

  defp extract_branch_literals({kind, _meta, [_condition | branches]})
       when kind in [:conditional, :pattern_match] do
    branches
    |> List.flatten()
    |> Enum.reduce(MapSet.new(), fn branch, acc ->
      case branch do
        {:block, _m, statements} when is_list(statements) ->
          Enum.reduce(statements, acc, &collect_literal_patterns/2)

        {:match_arm, arm_meta, _body} ->
          case Keyword.get(arm_meta, :pattern) do
            {:literal, _, value} when is_atom(value) or is_binary(value) ->
              MapSet.put(acc, value)

            _ ->
              acc
          end

        nil ->
          acc

        other ->
          collect_literal_patterns(other, acc)
      end
    end)
  end

  defp collect_literal_patterns({:literal, meta, value}, acc)
       when is_atom(value) or is_binary(value) do
    subtype = Keyword.get(meta, :subtype)
    if subtype in [:atom, :string, :symbol, nil], do: MapSet.put(acc, value), else: acc
  end

  defp collect_literal_patterns(_node, acc), do: acc

  defp extract_literal_value({:literal, _meta, value})
       when is_atom(value) or is_binary(value),
       do: value

  defp extract_literal_value(_), do: nil

  defp status_writes(
         {:function_call, meta, [_record, {:literal, _, field}, {:literal, _, value}]}
       ) do
    if CheckUtils.safe_name(meta) in ~W(Map.put Map.replace),
      do: [{field, value}],
      else: []
  end

  defp status_writes({:function_call, meta, [_record, changes]}) do
    if CheckUtils.safe_name(meta) == "Map.merge", do: map_pairs(changes), else: []
  end

  defp status_writes(_node), do: []

  defp map_pairs({:function_call, meta, [{:list, _, pairs}]}) do
    if CheckUtils.safe_name(meta) == "Map.new" do
      Enum.flat_map(pairs, fn
        {:tuple, _, [{:literal, _, field}, {:literal, _, value}]} -> [{field, value}]
        _ -> []
      end)
    else
      []
    end
  end

  defp map_pairs(_node), do: []

  defp format_states(states) do
    states
    |> MapSet.to_list()
    |> Enum.sort()
    |> Enum.map_join(", ", &inspect/1)
  end

  defp check_status_branching(node, condition, meta, issues, %Ctx{} = ctx) do
    if accesses_status_field?(condition, ctx.status_fields) do
      states = extract_branch_literals(node)

      if MapSet.size(states) >= ctx.min_states do
        issue =
          format_issue(ctx.source_file,
            message:
              "Branching on #{MapSet.size(states)} status values (#{format_states(states)}) -- consider replacing with an FSM",
            trigger: "case",
            line_no: CheckUtils.line_of(meta)
          )

        {node, [issue | issues]}
      else
        {node, issues}
      end
    else
      {node, issues}
    end
  end
end
