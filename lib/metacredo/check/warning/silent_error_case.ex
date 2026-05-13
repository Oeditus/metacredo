defmodule MetaCredo.Check.Warning.SilentErrorCase do
  use MetaCredo.Check,
    category: :warning,
    base_priority: :high,
    explanations: [
      check: """
      Detects `case` statements that match on `{:ok, _}` without a corresponding
      `{:error, _}` branch. Missing error branches cause silent failures when
      the called function returns an error tuple.

      Use explicit error handling or add a catch-all clause.
      """
    ]

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc -> traverse(node, acc, source_file) end)

    issues
  end

  # case expression: {:conditional, meta, [condition, ...branches]}
  # In MetaAST, a case/match with branches is represented as a conditional
  # with match_arm children. We look for cases where there's an :ok branch
  # but no :error branch and no catch-all.
  defp traverse(
         {:conditional, meta, [_condition | branches]} = node,
         issues,
         source_file
       )
       when is_list(meta) do
    arms = collect_match_arms(branches)

    if has_ok_arm?(arms) and not has_error_or_catchall?(arms) do
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message:
            "Case matches {:ok, _} without {:error, _} or catch-all branch -- errors may be silently ignored",
          trigger: "case",
          line_no: line
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _source_file), do: {node, issues}

  # Collect match_arm nodes from branch children
  defp collect_match_arms(branches) when is_list(branches) do
    Enum.filter(List.flatten(branches), fn
      {:match_arm, _, _} -> true
      _ -> false
    end)
  end

  defp collect_match_arms(_), do: []

  # Check if any arm matches {:ok, ...}
  defp has_ok_arm?(arms) do
    Enum.any?(arms, fn
      {:match_arm, arm_meta, _body} ->
        pattern = Keyword.get(arm_meta, :pattern)
        matches_ok_tuple?(pattern)

      _ ->
        false
    end)
  end

  # Check if any arm matches {:error, ...} or is a catch-all (_)
  defp has_error_or_catchall?(arms) do
    Enum.any?(arms, fn
      {:match_arm, arm_meta, _body} ->
        pattern = Keyword.get(arm_meta, :pattern)
        matches_error_tuple?(pattern) or catchall?(pattern)

      _ ->
        false
    end)
  end

  defp matches_ok_tuple?({:tuple, _, [{:literal, _, :ok} | _]}), do: true
  defp matches_ok_tuple?(_), do: false

  defp matches_error_tuple?({:tuple, _, [{:literal, _, :error} | _]}), do: true
  defp matches_error_tuple?(_), do: false

  defp catchall?({:variable, _, "_"}), do: true
  defp catchall?(:_), do: true
  defp catchall?(_), do: false
end
