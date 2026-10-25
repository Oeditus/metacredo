defmodule MetaCredo.Check.Refactor.DeadCode do
  use MetaCredo.Check,
    category: :refactor,
    base_priority: :high,
    explanations: [
      check: """
      Detects unreachable code after early returns. Statements following
      a `return`, `raise`, or `throw` can never execute and should be removed.
      """,
      examples: [
        elixir: [
          wrong: """
          # Everything after `raise` is unreachable
          def fetch!(id) do
            raise "not found"
            Repo.get!(User, id)  # unreachable
            Logger.info("fetched")  # unreachable
          end
          """,
          correct: """
          # Remove the dead statements
          def fetch!(id) do
            raise "not found"
          end
          """
        ]
      ]
    ]

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    source_file
    |> SourceFile.ast()
    |> find_dead_code(source_file)
  end

  defp find_dead_code(ast, source_file) do
    {_, issues} =
      AST.prewalk(ast, [], fn node, acc ->
        traverse(node, acc, source_file)
      end)

    issues
  end

  # Check blocks for statements after early_return.
  #
  # A function body arrives as a bare statement list, and `raise`/`throw`/
  # `return` are emitted as plain `:function_call` nodes rather than
  # `:early_return` -- both shapes must be handled.
  defp traverse({:block, meta, stmts} = node, issues, source_file)
       when is_list(meta) and is_list(stmts) do
    {node, check_block_for_dead(stmts, source_file) ++ issues}
  end

  defp traverse({:function_def, meta, stmts} = node, issues, source_file)
       when is_list(meta) and is_list(stmts) do
    {node, check_block_for_dead(stmts, source_file) ++ issues}
  end

  defp traverse(node, issues, _sf), do: {node, issues}

  defp check_block_for_dead(stmts, source_file) do
    {issues, _} =
      Enum.reduce(stmts, {[], false}, fn stmt, {acc, found_return?} ->
        cond do
          found_return? ->
            line = extract_line(stmt)

            issue =
              format_issue(source_file,
                message: "Unreachable code after early return -- remove dead code",
                trigger: "unreachable",
                line_no: line
              )

            {[issue | acc], true}

          early_return?(stmt) ->
            {acc, true}

          true ->
            {acc, false}
        end
      end)

    issues
  end

  # Statements that terminate control flow for the remainder of the block.
  @terminators ~W(raise reraise throw exit return)

  defp early_return?({:early_return, _meta, _children}), do: true

  defp early_return?({:function_call, meta, _args}) when is_list(meta) do
    CheckUtils.safe_name(meta) in @terminators
  end

  defp early_return?(_), do: false

  defp extract_line({_type, meta, _children}) when is_list(meta),
    do: CheckUtils.line_of(meta)

  defp extract_line(_), do: nil
end
