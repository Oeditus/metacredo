defmodule MetaCredo.Check.Warning.InefficientFilter do
  use MetaCredo.Check,
    category: :warning,
    base_priority: :high,
    explanations: [
      check: """
      Detects the pattern of fetching all records from the database (e.g.
      `Repo.all(User)`) and then filtering them in memory with `Enum.filter/2`
      or `Enum.reject/2`. This wastes bandwidth, memory, and CPU.

      Push the filter down to the database using `Ecto.Query.where/3` or
      equivalent query-level filtering.
      """,
      examples: [
        elixir: [
          wrong: """
          # Loads ALL users into memory, then discards most of them
          users = Repo.all(User)
          active_users = Enum.filter(users, &(&1.active))
          """,
          correct: """
          # Let the database do the filtering before transferring data
          active_users = from(u in User, where: u.active == true) |> Repo.all()
          """
        ]
      ]
    ]

  @fetch_all_indicators ~W(all findall getall fetchall tolist)

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc -> traverse(node, acc, source_file) end)

    issues
  end

  # Look for blocks containing assignment-then-filter patterns
  defp traverse(
         {:block, meta, statements} = node,
         issues,
         source_file
       )
       when is_list(meta) and is_list(statements) do
    new_issues = find_fetch_filter_pattern(statements, source_file)
    {node, new_issues ++ issues}
  end

  # Also check function_def bodies
  defp traverse(
         {:function_def, _meta, body} = node,
         issues,
         source_file
       )
       when is_list(body) do
    new_issues = find_fetch_filter_pattern(body, source_file)
    {node, new_issues ++ issues}
  end

  defp traverse(node, issues, _source_file), do: {node, issues}

  defp find_fetch_filter_pattern(statements, source_file) do
    statements
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(&check_fetch_filter_pair(&1, source_file))
  end

  # assignment + collection_op filter on same variable
  defp check_fetch_filter_pair(
         [
           {:assignment, _assign_meta, [var, fetch_expr]},
           {:collection_op, coll_meta, [_lambda, filter_var]}
         ],
         source_file
       )
       when is_list(coll_meta) do
    op_type = Keyword.get(coll_meta, :op_type)

    if op_type in [:filter, :reject] and variables_match?(var, filter_var) and
         fetch_all?(fetch_expr) do
      line = Keyword.get(coll_meta, :line)

      [
        format_issue(source_file,
          message:
            "Fetching all records then filtering in memory -- push filter to database query (WHERE clause)",
          trigger: "Enum.filter",
          line_no: line
        )
      ]
    else
      []
    end
  end

  defp check_fetch_filter_pair(_, _source_file), do: []

  defp variables_match?({:variable, _m1, name}, {:variable, _m2, name}), do: true
  defp variables_match?(_, _), do: false

  defp fetch_all?({:function_call, meta, _args}) when is_list(meta) do
    case Keyword.get(meta, :op_kind) do
      op_kind when is_list(op_kind) ->
        Keyword.get(op_kind, :domain) == :db and
          Keyword.get(op_kind, :operation) in [:retrieve_all, :query]

      nil ->
        func_name = CheckUtils.safe_name(meta)
        fetch_all_function?(func_name)
    end
  end

  defp fetch_all?(_), do: false

  defp fetch_all_function?(func_name) when is_binary(func_name) do
    lower = String.downcase(func_name)

    Enum.any?(@fetch_all_indicators, &String.contains?(lower, &1)) or
      String.contains?(lower, "repo.")
  end
end
