defmodule MetaCredo.Check.Readability.MagicNumber do
  use MetaCredo.Check,
    category: :readability,
    base_priority: :low,
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

  defp find_magic_numbers(ast, context, current_line, ignored) do
    case ast do
      {:binary_op, meta, [left, right]} when is_list(meta) ->
        line = Keyword.get(meta, :line, current_line)

        find_magic_numbers(left, [:binary_op | context], line, ignored) ++
          find_magic_numbers(right, [:binary_op | context], line, ignored)

      {:literal, meta, value} when is_list(meta) and is_number(value) ->
        subtype = Keyword.get(meta, :subtype)
        in_expr? = :binary_op in context or :unary_op in context

        if in_expr? and subtype in [:integer, :float] and value not in ignored do
          [{value, current_line}]
        else
          []
        end

      {:unary_op, meta, [operand]} when is_list(meta) ->
        line = Keyword.get(meta, :line, current_line)
        find_magic_numbers(operand, [:unary_op | context], line, ignored)

      {:block, _meta, statements} when is_list(statements) ->
        Enum.flat_map(statements, &find_magic_numbers(&1, context, current_line, ignored))

      {:function_call, meta, args} when is_list(meta) and is_list(args) ->
        line = Keyword.get(meta, :line, current_line)
        Enum.flat_map(args, &find_magic_numbers(&1, context, line, ignored))

      _ ->
        []
    end
  end
end
