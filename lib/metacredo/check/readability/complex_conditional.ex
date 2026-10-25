defmodule MetaCredo.Check.Readability.ComplexConditional do
  use MetaCredo.Check,
    category: :readability,
    base_priority: :normal,
    confidence: :high,
    param_defaults: [max_boolean_depth: 2],
    explanations: [
      check: """
      Detects deeply nested boolean operations (e.g. `a and (b or (c and d))`).
      Complex boolean expressions are hard to reason about. Extract sub-conditions
      into well-named variables or helper functions.
      """,
      params: [
        max_boolean_depth: "Maximum allowed nesting depth of boolean operations (default: 2)"
      ],
      examples: [
        elixir: [
          wrong: """
          # Deeply nested boolean -- reader must mentally evaluate all paths
          if user.active and (user.role == :admin or (user.beta and user.verified)) do
            perform_action()
          end
          """,
          correct: """
          # Extract sub-conditions into named variables
          is_privileged = user.role == :admin or (user.beta and user.verified)

          if user.active and is_privileged do
            perform_action()
          end
          """
        ]
      ]
    ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    max_depth = params_get(params, :max_boolean_depth)

    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc ->
        traverse(node, acc, source_file, max_depth)
      end)

    issues
  end

  # Check conditional nodes for complex boolean conditions.
  #
  # `cond` desugars to a chain of nested `:conditional` nodes, so the
  # *desugared* tree looks deeply nested even when the source has a flat list
  # of clauses. Only the outermost clause of a `cond` carries
  # `original_form: :cond`; the inner ones must be skipped or every
  # multi-clause `cond` is reported as a complex conditional.
  defp traverse(
         {:conditional, meta, [condition | _rest]} = node,
         issues,
         source_file,
         max_depth
       )
       when is_list(meta) do
    depth = boolean_depth(condition)

    if depth > max_depth and not cond_fallthrough?(node) do
      line = CheckUtils.line_of(meta)

      issue =
        format_issue(source_file,
          message:
            "Complex conditional with boolean nesting depth #{depth} (max: #{max_depth}) -- extract into named conditions",
          trigger: "conditional",
          line_no: line
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _sf, _max), do: {node, issues}

  # A conditional that is the `else` continuation of a `cond` clause has no
  # source-level counterpart of its own.
  defp cond_fallthrough?({:conditional, _meta, [_c, _t, else_branch]}) do
    match?({:conditional, _, _}, else_branch)
  end

  defp cond_fallthrough?(_), do: false

  # Calculate nesting depth of boolean operations
  defp boolean_depth({:binary_op, meta, [left, right]}) when is_list(meta) do
    category = Keyword.get(meta, :category)

    if category == :boolean do
      1 + max(boolean_depth(left), boolean_depth(right))
    else
      0
    end
  end

  defp boolean_depth({:unary_op, meta, [operand]}) when is_list(meta) do
    if Keyword.get(meta, :category) == :boolean do
      1 + boolean_depth(operand)
    else
      0
    end
  end

  defp boolean_depth(_), do: 0
end
