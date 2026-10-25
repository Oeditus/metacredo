defmodule MetaCredo.Check.Refactor.NegatedConditionWithElse do
  use MetaCredo.Check,
    category: :refactor,
    base_priority: :low,
    confidence: :high,
    explanations: [
      check: """
      Detects `if !condition do ... else ... end` or `if not condition do ... else ... end`.
      Swap the branches and remove the negation for clearer code.
      """,
      examples: [
        elixir: [
          wrong: """
          # Negation with else forces the reader to mentally invert the condition
          if !valid?(input) do
            {:error, :invalid}
          else
            process(input)
          end
          """,
          correct: """
          # Swap branches to eliminate the negation
          if valid?(input) do
            process(input)
          else
            {:error, :invalid}
          end
          """
        ]
      ]
    ]

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    # `cond` desugars to a chain of `if/else` conditionals whose `else` branch
    # is the *next clause*. Swapping branches is meaningless there, and
    # `cond do not empty?(x) -> ...; true -> ... end` is idiomatic. The
    # `original_form: :cond` marker is attached to the *parent* clause rather
    # than to the node carrying the unary op, so it cannot be read off the
    # candidate node -- but every desugared clause lives inside a `cond`
    # block, so a file-level check is both reliable and cheap.
    cond_free? = not cond_block?(source_file)

    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc ->
        traverse(node, acc, source_file, cond_free?)
      end)

    issues
  end

  defp cond_block?(%SourceFile{} = source_file) do
    source_file
    |> SourceFile.ast()
    |> AST.prewalk(false, fn
      {:conditional, meta, _} = node, acc when is_list(meta) ->
        {node, acc or Keyword.get(meta, :original_form) == :cond}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
  end

  defp traverse(
         {:conditional, meta, [{:unary_op, op_meta, [_operand]}, _then_branch, else_branch]} =
           node,
         issues,
         source_file,
         cond_free?
       )
       when is_list(meta) and is_list(op_meta) do
    operator = Keyword.get(op_meta, :operator)

    if operator in [:!, :not] and else_branch != nil and cond_free? do
      line = CheckUtils.line_of(meta, op_meta)

      issue =
        format_issue(source_file,
          message: "Negated condition with else branch -- swap branches and remove negation",
          trigger: to_string(operator),
          line_no: line,
          severity: :refactoring_opportunity
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _sf, _cond_free?), do: {node, issues}
end
