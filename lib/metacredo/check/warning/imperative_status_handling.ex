defmodule MetaCredo.Check.Warning.ImperativeStatusHandling do
  use MetaCredo.Check,
    category: :warning,
    base_priority: :normal,
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

      Also flags direct assignments to status fields and functions whose
      names encode state-transition verbs (e.g. `activate`, `suspend`).
      """,
      params: [
        status_field_names: "Field/variable names to watch (default: [\"status\", \"state\"])",
        min_states: "Minimum distinct status values before flagging (default: 3)"
      ],
      examples: [
        wrong: """
        # Ad-hoc status machine -- missing transitions are easy to miss
        def process(order) do
          case order.status do
            :pending -> {:ok, %{order | status: :processing}}
            :processing -> {:ok, %{order | status: :shipped}}
            :shipped -> {:ok, %{order | status: :delivered}}
            :cancelled -> {:error, :already_cancelled}
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

  @default_transition_verbs ~W(
    activate deactivate publish unpublish archive unarchive
    suspend resume complete cancel approve reject
    enable disable start stop pause draft
    submit finalize close reopen expire revoke
    block unblock lock unlock freeze thaw
  )

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
    if accesses_status_field?(condition, status_fields) do
      states = extract_branch_literals(node)

      if MapSet.size(states) >= min_states do
        line = Keyword.get(meta, :line)

        issue =
          format_issue(source_file,
            message:
              "Branching on #{MapSet.size(states)} status values (#{format_states(states)}) -- consider replacing with an FSM",
            trigger: "case",
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

  # Tier 2: Assignment to status field
  defp traverse(
         {:assignment, meta, [target, value]} = node,
         issues,
         source_file,
         status_fields,
         _min_states
       )
       when is_list(meta) do
    if assigns_to_status_field?(target, status_fields) do
      state_value = extract_literal_value(value)

      if state_value do
        line = Keyword.get(meta, :line)

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

  # Tier 3: Transition-verb function names
  defp traverse(
         {:function_def, meta, _children} = node,
         issues,
         source_file,
         _status_fields,
         _min_states
       )
       when is_list(meta) do
    func_name = extract_function_name(meta)

    if func_name && matches_transition_verb?(func_name) do
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message:
            "Function `#{func_name}` looks like a state transition -- consider modeling as an FSM event",
          trigger: func_name,
          line_no: line
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _source_file, _status_fields, _min_states), do: {node, issues}

  # -- Helpers --

  defp accesses_status_field?({:field_access, meta, _children}, status_fields) do
    field_name = Keyword.get(meta, :field) || Keyword.get(meta, :name)
    field_name && to_string(field_name) in status_fields
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
    field_name && to_string(field_name) in status_fields
  end

  defp assigns_to_status_field?({:variable, _meta, name}, status_fields) do
    to_string(name) in status_fields
  end

  defp assigns_to_status_field?(_target, _status_fields), do: false

  defp extract_branch_literals({:conditional, _meta, [_condition | branches]}) do
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

  defp extract_branch_literals(_), do: MapSet.new()

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

  defp extract_function_name(meta) when is_list(meta) do
    name = Keyword.get(meta, :name) || Keyword.get(meta, :function)
    if name, do: to_string(name), else: nil
  end

  defp extract_function_name(_), do: nil

  defp matches_transition_verb?(func_name) do
    normalized = func_name |> to_string() |> String.downcase()

    Enum.any?(@default_transition_verbs, fn verb ->
      String.contains?(normalized, verb) or
        String.starts_with?(normalized, verb <> "_") or
        String.ends_with?(normalized, "_" <> verb)
    end)
  end

  defp format_states(states) do
    states
    |> MapSet.to_list()
    |> Enum.sort()
    |> Enum.map_join(", ", &inspect/1)
  end
end
