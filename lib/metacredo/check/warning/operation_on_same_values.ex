defmodule MetaCredo.Check.Warning.OperationOnSameValues do
  use MetaCredo.Check,
    category: :warning,
    base_priority: :normal,
    confidence: :high,
    explanations: [
      check: """
      Detects arithmetic operations on identical operands that produce a
      constant result: `x - x` is always 0, `x / x` is always 1.
      These are likely copy-paste errors or logic mistakes.
      """,
      examples: [
        elixir: [
          wrong: """
          # x - x is always 0; x / x is always 1 -- likely a copy-paste bug
          diff = end_date - end_date  # should be start_date
          ratio = count / count        # should be total or something else
          """,
          correct: """
          # Use the distinct values that were intended
          diff = end_date - start_date
          ratio = count / total
          """
        ],
        javascript: [
          wrong: """
          // ratio is always 1 -- the divisor should be the total, not the count
          function progress(completed) {
            const ratio = completed / completed;
            return ratio;
          }
          """,
          correct: """
          // Use the distinct values that were intended
          function progress(completed, total) {
            const ratio = completed / total;
            return ratio;
          }
          """
        ],
        typescript: [
          wrong: """
          // ratio is always 1 -- the divisor should be the total, not the count
          export function progress(completed: number): number {
            const ratio = completed / completed;
            return ratio;
          }
          """,
          correct: """
          // Use the distinct values that were intended
          export function progress(completed: number, total: number): number {
            const ratio = completed / total;
            return ratio;
          }
          """
        ],
        go: [
          wrong: """
          // ratio is always 1 -- the divisor should be the total, not the count
          func progress(completed float64) float64 {
          \tratio := completed / completed
          \treturn ratio
          }
          """,
          correct: """
          // Use the distinct values that were intended
          func progress(completed, total float64) float64 {
          \tratio := completed / total
          \treturn ratio
          }
          """
        ]
      ]
    ]

  @constant_result_ops [:-, :/]

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc -> traverse(node, acc, source_file) end)

    issues
  end

  defp traverse(
         {:binary_op, meta, [left, right]} = node,
         issues,
         source_file
       )
       when is_list(meta) do
    operator = Keyword.get(meta, :operator)

    if operator in @constant_result_ops and structurally_equal?(left, right) do
      line = CheckUtils.line_of(meta)
      result = if operator == :-, do: "0", else: "1"

      issue =
        format_issue(source_file,
          message: "Operation '#{operator}' on identical operands -- result is always #{result}",
          trigger: to_string(operator),
          line_no: line
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _source_file), do: {node, issues}

  # Compares two operand subtrees for structural identity, ignoring source
  # position.
  #
  # A plain `left == right` is wrong across languages: the Rust adapter stamps
  # `line:`/`col:` on *every* node, so `x - x` yields two `:variable` nodes that
  # differ only in position and the equality test is always false -- the check
  # never fired on Rust source. Elixir nodes carry no position metadata, which
  # is why the defect stayed hidden. Position is presentation, not structure,
  # so it is dropped before comparing.
  defp structurally_equal?(a, b), do: strip_position(a) == strip_position(b)

  defp strip_position({type, meta, children}) when is_list(meta),
    do: {type, Keyword.drop(meta, [:line, :col]), strip_position(children)}

  defp strip_position(list) when is_list(list), do: Enum.map(list, &strip_position/1)

  defp strip_position(other), do: other
end
