defmodule MetaCredo.Check.Readability.MagicNumber do
  use MetaCredo.Check,
    category: :readability,
    base_priority: :low,
    confidence: :high,
    param_defaults: [ignored_numbers: [0, 1, -1]],
    explanations: [
      check: """
      Detects numeric literals used directly in expressions without
      being assigned to a named constant. Magic numbers make code
      harder to understand and maintain.
      """,
      params: [
        ignored_numbers: "Numbers to skip (default: [0, 1, -1])"
      ],
      examples: [
        elixir: [
          wrong: """
          # Reader must guess what 3600, 5, and 0.15 mean
          if age >= 18 do
            discount = total * 0.15
            expires_at = now + 3600
            if attempts > 5, do: lock_account()
          end
          """,
          correct: """
          # Named constants document the intent
          @minimum_age 18
          @loyalty_discount 0.15
          @session_ttl_seconds 3600
          @max_login_attempts 5

          if age >= @minimum_age do
            discount = total * @loyalty_discount
            expires_at = now + @session_ttl_seconds
            if attempts > @max_login_attempts, do: lock_account()
          end
          """
        ]
      ]
    ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    ignored = params_get(params, :ignored_numbers)

    source_file
    |> SourceFile.ast()
    |> find_magic_numbers([], nil, ignored)
    |> Enum.map(fn {value, line} ->
      format_issue(source_file,
        message: "Magic number #{value} should be a named constant",
        trigger: to_string(value),
        line_no: line
      )
    end)
  end

  # Node types whose numeric literals count as "in an expression".
  @expression_contexts [:binary_op, :unary_op]

  defp find_magic_numbers(ast, context, current_line, ignored) do
    case ast do
      # A module-attribute value *is* a named constant -- never report it.
      {kind, _meta, [{:variable, _, "@" <> _}, _value]}
      when kind in [:assignment, :inline_match] ->
        []

      {:binary_op, meta, [left, right]} when is_list(meta) ->
        line = Keyword.get(meta, :line, current_line)
        descend([left, right], [:binary_op | context], line, ignored)

      {:literal, meta, value} when is_list(meta) and is_number(value) ->
        if magic_number?(meta, value, context, ignored),
          do: [{value, current_line}],
          else: []

      {:unary_op, meta, [operand]} when is_list(meta) ->
        descend([operand], [:unary_op | context], Keyword.get(meta, :line, current_line), ignored)

      {:function_call, meta, args} when is_list(meta) and is_list(args) ->
        descend(args, context, Keyword.get(meta, :line, current_line), ignored)

      # Any other compound node: keep descending, preserving the expression
      # context. Without this, literals nested under `:conditional`,
      # `:inline_match`, `:container`, etc. were never reached.
      {_type, _meta, children} when is_list(children) ->
        descend(children, context, current_line, ignored)

      list when is_list(list) ->
        descend(list, context, current_line, ignored)

      _ ->
        []
    end
  end

  # Recurse into `nodes`, carrying the expression context and line.
  defp descend(nodes, context, line, ignored) do
    Enum.flat_map(nodes, &find_magic_numbers(&1, context, line, ignored))
  end

  # A numeric literal is "magic" when it appears inside an arithmetic
  # expression, is an integer or float, and is not in the ignored set.
  defp magic_number?(meta, value, context, ignored) do
    Keyword.get(meta, :subtype) in [:integer, :float] and
      Enum.any?(context, &(&1 in @expression_contexts)) and
      value not in ignored
  end
end
