defmodule MetaCredo.Check.Warning.SilentErrorCase do
  use MetaCredo.Check,
    category: :warning,
    base_priority: :high,
    confidence: :low,
    explanations: [
      check: """
      Detects `case` statements that match on `{:ok, _}` without a corresponding
      `{:error, _}` branch. Missing error branches cause silent failures when
      the called function returns an error tuple.

      Use explicit error handling or add a catch-all clause.
      """,
      examples: [
        elixir: [
          wrong: """
          # If Repo.insert returns {:error, ...}, the case crashes silently
          case Repo.insert(changeset) do
            {:ok, record} -> notify_user(record)
          end
          """,
          correct: """
          # Handle both success and failure explicitly
          case Repo.insert(changeset) do
            {:ok, record} -> notify_user(record)
            {:error, changeset} -> log_and_return_error(changeset)
          end
          """
        ]
      ]
    ]

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc -> traverse(node, acc, source_file) end)

    issues
  end

  # `case` is emitted as `:pattern_match` (scrutinee followed by match arms).
  # Some adapters use `:conditional` with match_arm children instead, so both
  # shapes are accepted.
  defp traverse(
         {:pattern_match, meta, [_scrutinee | branches]} = node,
         issues,
         source_file
       )
       when is_list(meta) do
    check_case_arms(node, collect_match_arms(branches), meta, issues, source_file)
  end

  defp traverse(
         {:conditional, meta, [_condition | branches]} = node,
         issues,
         source_file
       )
       when is_list(meta) do
    check_case_arms(node, collect_match_arms(branches), meta, issues, source_file)
  end

  defp traverse(node, issues, _source_file), do: {node, issues}

  defp check_case_arms(node, arms, meta, issues, source_file) do
    if has_ok_arm?(arms) and not has_error_or_catchall?(arms) do
      line = CheckUtils.line_of(meta)

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
  # The Elixir adapter emits a bare `_` pattern as the symbol literal `:_`.
  defp catchall?({:literal, _, :_}), do: true
  defp catchall?(:_), do: true
  defp catchall?(_), do: false
end
