defmodule MetaCredo.Check.Warning.NPlusOneQuery do
  use MetaCredo.Check,
    category: :warning,
    base_priority: :high,
    explanations: [
      check: """
      Detects database operations (e.g. `Repo.get`, `Repo.one`) called inside
      collection operations like `Enum.map/2` or `Enum.each/2`. This creates
      an N+1 query problem where N extra queries are issued for N items.

      Use `Repo.preload/2`, `from(..., preload: [...])`, or batch the query
      outside the loop.
      """,
      examples: [
        elixir: [
          wrong: """
          # 1 query to get users + 1 query per user = N+1 total
          users = Repo.all(User)
          Enum.map(users, fn user ->
            org = Repo.get!(Organization, user.org_id)
            %{name: user.name, org: org.name}
          end)
          """,
          correct: """
          # Preload associations or use a single JOIN query
          users = User |> Repo.all() |> Repo.preload(:organization)
          Enum.map(users, fn user ->
            %{name: user.name, org: user.organization.name}
          end)
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

  # collection_op with keyword meta: {:collection_op, [op_type: :map], [lambda, collection]}
  defp traverse(
         {:collection_op, meta, [lambda | _rest]} = node,
         issues,
         source_file
       )
       when is_list(meta) do
    operation = Keyword.get(meta, :op_type)

    if operation in [:map, :each, :flat_map, :reduce] and contains_database_call?(lambda) do
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message:
            "Potential N+1 query: database operation inside #{operation} -- use preload or batch query",
          trigger: "#{operation}",
          line_no: line
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _source_file), do: {node, issues}

  # Check if a lambda/block contains database-like function calls
  defp contains_database_call?({:lambda, meta, children})
       when is_list(meta) and is_list(children) do
    Enum.any?(children, &contains_database_call?/1)
  end

  defp contains_database_call?({:block, _meta, statements}) when is_list(statements) do
    Enum.any?(statements, &contains_database_call?/1)
  end

  defp contains_database_call?({:function_call, call_meta, _args}) when is_list(call_meta) do
    case Keyword.get(call_meta, :op_kind) do
      op_kind when is_list(op_kind) ->
        Keyword.get(op_kind, :domain) == :db

      nil ->
        func_name = Keyword.get(call_meta, :name, "")
        database_function?(func_name)
    end
  end

  defp contains_database_call?(tuple) when is_tuple(tuple) do
    tuple |> Tuple.to_list() |> Enum.any?(&contains_database_call?/1)
  end

  defp contains_database_call?(list) when is_list(list) do
    Enum.any?(list, &contains_database_call?/1)
  end

  defp contains_database_call?(_), do: false

  defp database_function?(name) when is_binary(name) do
    lower = String.downcase(name)

    Enum.any?(
      ["repo.", "get", "find", "query", "fetch", "load", "select"],
      &String.contains?(lower, &1)
    )
  end

  defp database_function?(name) when is_atom(name) do
    name in [:get, :get!, :get_by, :find, :query, :fetch, :load, :select, :one, :all] or
      database_function?(Atom.to_string(name))
  end

  defp database_function?(_), do: false
end
