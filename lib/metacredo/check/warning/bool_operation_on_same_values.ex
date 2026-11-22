defmodule MetaCredo.Check.Warning.BoolOperationOnSameValues do
  use MetaCredo.Check,
    category: :warning,
    base_priority: :normal,
    confidence: :high,
    explanations: [
      check: """
      Detects boolean operations where both operands are structurally identical,
      such as `x && x`, `x || x`, `x and x`, `x or x`. These are always
      redundant and likely indicate a copy-paste error.
      """,
      examples: [
        elixir: [
          wrong: """
          # Both sides are identical -- likely a copy-paste mistake
          if user.active? and user.active? do
            grant_access()
          end

          valid = input != nil || input != nil
          """,
          correct: """
          # Use each condition only once; add the missing distinct condition
          if user.active? and user.verified? do
            grant_access()
          end

          valid = input != nil
          """
        ],
        javascript: [
          wrong: """
          // Both operands are identical -- likely a copy-paste mistake
          function grant(profile) {
            if (profile.active && profile.active) {
              return "granted";
            }
            return "denied";
          }
          """,
          correct: """
          // Use each condition once, or add the missing distinct condition
          function grant(profile) {
            if (profile.active && profile.verified) {
              return "granted";
            }
            return "denied";
          }
          """
        ],
        typescript: [
          wrong: """
          // Both operands are identical -- likely a copy-paste mistake
          export function grant(profile: { active: boolean }): string {
            if (profile.active && profile.active) {
              return "granted";
            }
            return "denied";
          }
          """,
          correct: """
          // Use each condition once, or add the missing distinct condition
          export function grant(profile: { active: boolean; verified: boolean }): string {
            if (profile.active && profile.verified) {
              return "granted";
            }
            return "denied";
          }
          """
        ],
        go: [
          wrong: """
          // Both operands are identical -- likely a copy-paste mistake
          func isEligible(age int) bool {
          \treturn age >= 18 && age >= 18
          }
          """,
          correct: """
          // Use each condition once, or add the missing distinct condition
          func isEligible(age int, verified bool) bool {
          \treturn age >= 18 && verified
          }
          """
        ]
      ]
    ]

  @boolean_operators [:and, :or, :&&, :||]

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
    category = Keyword.get(meta, :category)
    operator = Keyword.get(meta, :operator)

    if category == :boolean and operator in @boolean_operators and
         structurally_equal?(left, right) do
      line = CheckUtils.line_of(meta)

      issue =
        format_issue(source_file,
          message:
            "Boolean '#{operator}' with identical operands -- expression is always redundant",
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
  # A plain `a == b` is wrong across languages: the Rust adapter stamps
  # `line:`/`col:` on *every* node, so `x && x` yields two `:variable` nodes
  # that differ only in position and the equality test is always false -- the
  # check never fired on Rust source. Elixir nodes carry no position metadata,
  # which is why the defect stayed hidden. Position is presentation, not
  # structure, so it is dropped before comparing.
  defp structurally_equal?(a, b), do: strip_position(a) == strip_position(b)

  defp strip_position({type, meta, children}) when is_list(meta),
    do: {type, Keyword.drop(meta, [:line, :col]), strip_position(children)}

  defp strip_position(list) when is_list(list), do: Enum.map(list, &strip_position/1)

  defp strip_position(other), do: other
end
