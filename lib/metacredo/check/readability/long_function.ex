defmodule MetaCredo.Check.Readability.LongFunction do
  use MetaCredo.Check,
    category: :readability,
    base_priority: :normal,
    param_defaults: [max_statements: 50],
    explanations: [
      check: """
      Detects functions with too many statements. Long functions are harder
      to read, test, and maintain. Break them into smaller, focused functions.
      """,
      params: [
        max_statements: "Maximum allowed statements per function (default: 50)"
      ],
      examples: [
        elixir: [
          wrong: """
          # 60+ statements all crammed into one function
          def process_order(order, user, opts) do
            validate_user(user)
            check_inventory(order)
            apply_discounts(order)
            calculate_tax(order)
            # ... 55 more statements ...
          end
          """,
          correct: """
          # Compose focused private helpers that each do one thing
          def process_order(order, user, opts) do
            with :ok <- validate(order, user),
                 order <- apply_pricing(order, opts),
                 {:ok, order} <- persist(order) do
              {:ok, order}
            end
          end

          defp validate(order, user), do: ...
          defp apply_pricing(order, opts), do: ...
          defp persist(order), do: ...
          """
        ]
      ]
    ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    max_statements = params_get(params, :max_statements)

    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc ->
        traverse(node, acc, source_file, max_statements)
      end)

    issues
  end

  defp traverse({:function_def, meta, children} = node, issues, source_file, max_statements)
       when is_list(meta) do
    name = Keyword.get(meta, :name, "anonymous")
    count = count_statements(children)

    if count > max_statements do
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message: "Function '#{name}' has #{count} statements (max allowed: #{max_statements})",
          trigger: to_string(name),
          line_no: line
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _sf, _max), do: {node, issues}

  # Count top-level statements in a function body
  defp count_statements({:block, _meta, stmts}) when is_list(stmts) do
    Enum.reduce(stmts, 0, fn stmt, acc -> acc + count_statements(stmt) end)
  end

  defp count_statements(children) when is_list(children) do
    Enum.reduce(children, 0, fn child, acc -> acc + count_statements(child) end)
  end

  # Each significant node counts as one statement
  defp count_statements({type, _meta, _children})
       when type in [
              :assignment,
              :function_call,
              :conditional,
              :loop,
              :pattern_match,
              :exception_handling,
              :early_return,
              :augmented_assignment,
              :inline_match
            ] do
    1
  end

  defp count_statements(_), do: 0
end
