defmodule MetaCredo.Check.Security.MissingAuthorization do
  use MetaCredo.Check,
    category: :security,
    base_priority: :higher,
    confidence: :low,
    tags: [:security, :user_input],
    explanations: [
      check: """
      Detects sensitive operations without authorization checks (CWE-862).

      Identifies code patterns where data modification or access operations
      (delete, update, create) are performed without apparent authorization
      verification, enabling horizontal privilege escalation.
      """,
      params: [],
      examples: [
        elixir: [
          wrong: """
          # Authenticated user can delete ANY post, not just their own
          def delete(conn, %{"id" => id}) do
            Repo.delete!(Post |> Repo.get!(id))
            json(conn, %{ok: true})
          end
          """,
          correct: """
          # Verify ownership before performing the destructive operation
          def delete(conn, %{"id" => id}) do
            user = conn.assigns.current_user
            post = Repo.get!(Post, id)

            if post.user_id == user.id do
              Repo.delete!(post)
              json(conn, %{ok: true})
            else
              send_resp(conn, 403, "Forbidden")
            end
          end
          """
        ]
      ]
    ]

  @sensitive_operations ~W[
    delete delete! remove destroy
    update update! save put patch
    create insert insert! new
    Repo.delete Repo.update Repo.insert
    .delete .update .save .destroy
    deleteById updateById removeById
    delete_all update_all
  ]

  @authorization_indicators ~W[
    authorize authorized? can? permit? allowed?
    authorize! check_permission has_permission?
    current_user conn.assigns user_id owner
    policy policies ability abilities
    admin? is_admin role roles
    forbidden 403 unauthorized 401
    Bodyguard Canada CanCan Pundit
  ]

  @action_names ~W[
    delete destroy remove update edit
    create new index show
  ]

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc -> traverse(node, acc, source_file) end)

    issues
  end

  # Detect function definitions with sensitive operations but no auth
  defp traverse({:function_def, meta, body} = node, issues, source_file)
       when is_list(meta) do
    func_name = Keyword.get(meta, :name, "")

    if sensitive_action?(func_name) do
      body_list = if is_list(body), do: body, else: [body]

      has_auth? = has_authorization_check?(body_list)
      has_sensitive_op? = has_sensitive_operation?(body_list)

      if has_sensitive_op? and not has_auth? do
        line = CheckUtils.line_of(meta)

        {node,
         [
           format_issue(source_file,
             message:
               "Missing authorization: sensitive operation in '#{func_name}' without auth check",
             trigger: func_name,
             line_no: line,
             severity: :error,
             metadata: %{cwe: 862, function: func_name}
           )
           | issues
         ]}
      else
        {node, issues}
      end
    else
      {node, issues}
    end
  end

  # Detect direct sensitive operations with user-supplied IDs
  defp traverse({:function_call, meta, args} = node, issues, source_file)
       when is_list(meta) do
    func_name = Keyword.get(meta, :name, "")

    if sensitive_function?(func_name) and has_user_supplied_id?(args) do
      line = CheckUtils.line_of(meta)

      {node,
       [
         format_issue(source_file,
           message: "Potential missing authorization: '#{func_name}' with user-supplied ID",
           trigger: func_name,
           line_no: line,
           metadata: %{cwe: 862, function: func_name}
         )
         | issues
       ]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _source_file), do: {node, issues}

  # --- Private Helpers ---

  defp sensitive_action?(func_name) when is_binary(func_name) do
    func_lower = String.downcase(func_name)
    Enum.any?(@action_names, &String.contains?(func_lower, &1))
  end

  defp sensitive_action?(_), do: false

  defp sensitive_function?(func_name) when is_binary(func_name) do
    func_lower = String.downcase(func_name)

    Enum.any?(@sensitive_operations, fn op ->
      String.contains?(func_lower, String.downcase(op))
    end)
  end

  defp sensitive_function?(_), do: false

  defp has_authorization_check?(body) when is_list(body) do
    Enum.any?(body, &contains_authorization?/1)
  end

  # Node types whose children are scanned for authorization checks.
  @recursive_node_types [:block, :pipe]

  # A `case` over MetaAST node types: the branching is a grammar lookup table,
  # not tangled control flow. Suppressed deliberately.
  # metacredo:disable-for-next-line MetaCredo.Check.Design.HighComplexity
  defp contains_authorization?(node) do
    case node do
      {:function_call, meta, _args} when is_list(meta) ->
        auth_function?(Keyword.get(meta, :name, ""))

      {:conditional, _meta, [condition | _branches]} ->
        contains_authorization?(condition)

      {:binary_op, meta, [left, right]} when is_list(meta) ->
        if Keyword.get(meta, :operator) in [:==, :===, :!=, :!==] do
          involves_auth_variable?(left) or involves_auth_variable?(right)
        else
          contains_authorization?(left) or contains_authorization?(right)
        end

      {:attribute_access, _meta, children} when is_list(children) ->
        Enum.any?(children, &involves_auth_variable?/1)

      {:case, _meta, [_expr | arms]} ->
        Enum.any?(arms, &contains_authorization?/1)

      {type, _meta, children} when type in @recursive_node_types and is_list(children) ->
        Enum.any?(children, &contains_authorization?/1)

      tuple when is_tuple(tuple) ->
        tuple |> Tuple.to_list() |> Enum.any?(&contains_authorization?/1)

      list when is_list(list) ->
        Enum.any?(list, &contains_authorization?/1)

      _ ->
        false
    end
  end

  defp auth_function?(func_name) when is_binary(func_name) do
    func_lower = String.downcase(func_name)

    Enum.any?(@authorization_indicators, fn ind ->
      String.contains?(func_lower, String.downcase(ind))
    end)
  end

  defp auth_function?(_), do: false

  defp involves_auth_variable?({:variable, _meta, name}) when is_binary(name) do
    auth_variable_name?(name)
  end

  # Field access is emitted by Metastatic as `Map.fetch!(recv, :field)`.
  # Ownership checks are almost always comparisons of such accesses
  # (`post.user_id == user.id`), so the receiver *and* the field name both
  # have to be considered.
  defp involves_auth_variable?({:function_call, meta, args}) when is_list(meta) do
    case args do
      [{:variable, _, receiver}, {:literal, _, field}] ->
        auth_variable_name?(to_string(receiver)) or auth_variable_name?(to_string(field))

      _ ->
        Enum.any?(args, &involves_auth_variable?/1)
    end
  end

  defp involves_auth_variable?({:attribute_access, _meta, children}) when is_list(children) do
    Enum.any?(children, fn
      {:literal, _, attr} when is_binary(attr) or is_atom(attr) ->
        auth_variable_name?(to_string(attr))

      other ->
        involves_auth_variable?(other)
    end)
  end

  defp involves_auth_variable?(_), do: false

  @auth_variable_indicators ~W(user owner admin role permission id)

  defp auth_variable_name?(name) do
    lower = String.downcase(name)
    Enum.any?(@auth_variable_indicators, &String.contains?(lower, &1))
  end

  defp has_sensitive_operation?(body) when is_list(body) do
    Enum.any?(body, &contains_sensitive_operation?/1)
  end

  defp contains_sensitive_operation?(node) do
    case node do
      {:function_call, meta, _args} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")
        sensitive_function?(func_name)

      {:pipe, _meta, stages} when is_list(stages) ->
        Enum.any?(stages, &contains_sensitive_operation?/1)

      {:block, _meta, statements} when is_list(statements) ->
        Enum.any?(statements, &contains_sensitive_operation?/1)

      tuple when is_tuple(tuple) ->
        tuple |> Tuple.to_list() |> Enum.any?(&contains_sensitive_operation?/1)

      list when is_list(list) ->
        Enum.any?(list, &contains_sensitive_operation?/1)

      _ ->
        false
    end
  end

  defp has_user_supplied_id?(args) when is_list(args) do
    Enum.any?(args, fn
      {:variable, _meta, name} when is_binary(name) ->
        name_lower = String.downcase(name)
        String.contains?(name_lower, "id") or String.contains?(name_lower, "param")

      {:map_access, _meta, _} ->
        true

      {:attribute_access, _meta, _} ->
        true

      _ ->
        false
    end)
  end

  defp has_user_supplied_id?(_), do: false
end
