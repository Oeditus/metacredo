defmodule MetaCredo.Check.Warning.MissingPreload do
  use MetaCredo.Check,
    category: :warning,
    base_priority: :high,
    confidence: :low,
    tags: [:db],
    explanations: [
      check: """
      Detects collection operations (e.g. `Enum.map`) over database query
      results that were fetched without eager loading. This pattern is a
      strong indicator of potential N+1 queries when associations are accessed
      inside the loop.

      Use `Repo.preload/2` or `from(..., preload: [...])` before iterating.
      """,
      examples: [
        elixir: [
          wrong: """
          # Accessing posts.author inside map triggers one query per post
          posts = Repo.all(Post)
          Enum.map(posts, fn post -> %{title: post.title, author: post.author.name} end)
          """,
          correct: """
          # Preload associations before iterating to issue a single JOIN
          posts = Post |> Repo.all() |> Repo.preload(:author)
          Enum.map(posts, fn post -> %{title: post.title, author: post.author.name} end)
          """
        ]
      ]
    ]

  @query_functions ~W(all find query select fetch load findall getall)

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc -> traverse(node, acc, source_file) end)

    issues
  end

  # collection_op mapping over a database query result
  defp traverse(
         {:collection_op, meta, [_fn | rest]} = node,
         issues,
         source_file
       )
       when is_list(meta) do
    op_type = Keyword.get(meta, :op_type)
    collection = List.last(rest)

    if op_type == :map and db_collection?(collection, source_file) do
      line = CheckUtils.line_of(meta)

      issue =
        format_issue(source_file,
          message:
            "Mapping over database results without eager loading -- potential N+1 queries. Use preload/include",
          trigger: "map",
          line_no: line
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  # loop iterating over database query result
  defp traverse(
         {:loop, meta, [_iterator, collection | _body]} = node,
         issues,
         source_file
       )
       when is_list(meta) do
    loop_type = Keyword.get(meta, :loop_type)

    if loop_type == :for and db_collection?(collection, source_file) do
      line = CheckUtils.line_of(meta)

      issue =
        format_issue(source_file,
          message:
            "Looping over database results -- ensure associations are preloaded to avoid N+1 queries",
          trigger: "for",
          line_no: line
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _source_file), do: {node, issues}

  # The collection may be a direct query call (`Enum.map(Repo.all(Post), ...)`)
  # or a variable bound to one (`posts = Repo.all(Post); Enum.map(posts, ...)`).
  # The latter is by far the more common shape, so the binding is resolved.
  defp db_collection?({:variable, _, name}, source_file) when is_binary(name) do
    source_file
    |> SourceFile.ast()
    |> bound_to_db_query?(name)
  end

  defp db_collection?(collection, _source_file), do: from_database_query?(collection)

  defp bound_to_db_query?(ast, name) do
    {_, found} =
      AST.prewalk(ast, false, fn
        {kind, _meta, [{:variable, _, ^name}, value]} = node, acc
        when kind in [:inline_match, :assignment] ->
          {node, acc or from_database_query?(value)}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp from_database_query?({:function_call, meta, _args}) when is_list(meta) do
    case Keyword.get(meta, :op_kind) do
      op_kind when is_list(op_kind) ->
        Keyword.get(op_kind, :domain) == :db and
          Keyword.get(op_kind, :operation) in [:retrieve_all, :query]

      nil ->
        query_call?(Keyword.get(meta, :name, ""))
    end
  end

  defp from_database_query?(_), do: false

  # The call must be *module-qualified* and the module must look like a
  # database layer. Checking only the method name matched `Sources.find/1`
  # (contains `find`) and `Enum.map(source_files, ...)`.
  @db_module_hints ~W(Repo Ecto Schema Query)

  defp query_call?(name) when is_binary(name) do
    case String.split(name, ".") do
      [_bare] ->
        false

      parts ->
        method = parts |> List.last() |> String.downcase()
        module = parts |> Enum.drop(-1) |> Enum.join(".")

        method in @query_functions and
          Enum.any?(@db_module_hints, &String.contains?(module, &1))
    end
  end

  defp query_call?(_), do: false
end
