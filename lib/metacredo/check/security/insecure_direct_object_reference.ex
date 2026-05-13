defmodule MetaCredo.Check.Security.InsecureDirectObjectReference do
  use MetaCredo.Check,
    category: :security,
    base_priority: :high,
    explanations: [
      check: """
      Detects Insecure Direct Object Reference (IDOR) vulnerabilities (CWE-639).

      Identifies code patterns where user-supplied IDs are used to directly
      access resources without verifying ownership or authorization, enabling
      horizontal privilege escalation.
      """,
      params: [],
      examples: [
        wrong: """
        # Any authenticated user can fetch any post by ID
        def show(conn, %{"id" => id}) do
          post = Repo.get!(Post, id)
          render(conn, :show, post: post)
        end
        """,
        correct: """
        # Scope the query to the current user's owned resources
        def show(conn, %{"id" => id}) do
          post =
            conn.assigns.current_user
            |> Ecto.assoc(:posts)
            |> Repo.get!(id)

          render(conn, :show, post: post)
        end
        """
      ]
    ]

  @fetch_functions ~W[
    get get! get_by find find! find_by
    findById findByPk findOne first
    retrieve load fetch lookup
    Repo.get Repo.get! Repo.get_by
    objects.get objects.filter
  ]

  @ownership_indicators ~W[
    user_id owner_id created_by author_id
    belongs_to current_user owner
    where user: filter user
    scope user policy authorize
  ]

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc -> traverse(node, acc, source_file) end)

    issues
  end

  # Detect fetch operations with user-supplied IDs
  defp traverse({:function_call, meta, args} = node, issues, source_file)
       when is_list(meta) do
    func_name = Keyword.get(meta, :name, "")

    if fetch_function?(func_name) and not CheckUtils.safe_stdlib_call?(func_name) and
         has_user_supplied_id?(args) do
      line = Keyword.get(meta, :line)

      {node,
       [
         format_issue(source_file,
           message:
             "Potential IDOR: '#{func_name}' with user-supplied ID without ownership check",
           trigger: func_name,
           line_no: line,
           metadata: %{cwe: 639, function: func_name}
         )
         | issues
       ]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _source_file), do: {node, issues}

  # --- Private Helpers ---

  defp fetch_function?(func_name) when is_binary(func_name) do
    func_lower = String.downcase(func_name)

    Enum.any?(@fetch_functions, fn pattern ->
      String.contains?(func_lower, String.downcase(pattern))
    end)
  end

  defp fetch_function?(_), do: false

  defp has_user_supplied_id?(args) when is_list(args) do
    Enum.any?(args, fn
      {:variable, _meta, name} when is_binary(name) ->
        name_lower = String.downcase(name)
        String.contains?(name_lower, "id") or String.contains?(name_lower, "param")

      {:map_access, _meta, _} ->
        true

      {:attribute_access, _meta, children} when is_list(children) ->
        Enum.any?(children, fn
          {:literal, _, attr} when is_binary(attr) or is_atom(attr) ->
            attr_lower = to_string(attr) |> String.downcase()

            Enum.any?(@ownership_indicators, fn ind ->
              String.contains?(attr_lower, ind)
            end)
            |> Kernel.not()

          _ ->
            false
        end)

      _ ->
        false
    end)
  end

  defp has_user_supplied_id?(_), do: false
end
