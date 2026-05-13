defmodule MetaCredo.Check.Readability.ComplexConditional do
  use MetaCredo.Check,
    category: :readability,
    base_priority: :normal,
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

  # Check conditional nodes for complex boolean conditions
  defp traverse(
         {:conditional, meta, [condition | _rest]} = node,
         issues,
         source_file,
         max_depth
       )
       when is_list(meta) do
    depth = boolean_depth(condition)

    if depth > max_depth do
      line = Keyword.get(meta, :line)

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
