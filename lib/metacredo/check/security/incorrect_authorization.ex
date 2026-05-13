defmodule MetaCredo.Check.Security.IncorrectAuthorization do
  use MetaCredo.Check,
    category: :security,
    base_priority: :high,
    explanations: [
      check: """
      Detects incorrect authorization patterns (CWE-863).

      Identifies weak or flawed authorization logic such as authorization
      checks that appear after the sensitive operation, role-only checks
      without resource ownership verification, and default-allow patterns.
      """,
      params: []
    ]

  @sensitive_operations ~W[
    delete update insert create
    destroy save remove modify
    write transfer send execute
  ]

  @authorization_functions ~W[
    authorize can? permit? allowed?
    has_permission check_access verify_access
    authorize! policy
  ]

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc -> traverse(node, acc, source_file) end)

    issues
  end

  # Detect authorization-after-action (wrong order) in blocks
  defp traverse({:block, meta, statements} = node, issues, source_file)
       when is_list(meta) and is_list(statements) do
    order_issues = check_authorization_order(statements, source_file)
    {node, order_issues ++ issues}
  end

  # Detect role-only checks without resource verification in conditionals
  defp traverse({:conditional, meta, [condition | _branches]} = node, issues, source_file)
       when is_list(meta) do
    if role_only_check?(condition) do
      line = Keyword.get(meta, :line)

      {node,
       [
         format_issue(source_file,
           message:
             "Potential incorrect authorization: role-only check without resource ownership verification",
           trigger: "role check",
           line_no: line,
           metadata: %{cwe: 863}
         )
         | issues
       ]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _source_file), do: {node, issues}

  # --- Private Helpers ---

  defp check_authorization_order(statements, source_file) do
    {issues, _state} =
      Enum.reduce(statements, {[], %{auth_seen: false, op_seen: false}}, fn stmt,
                                                                            {issues, state} ->
        cond do
          sensitive_operation?(stmt) and not state.auth_seen ->
            {issues, %{state | op_seen: true}}

          authorization_check?(stmt) ->
            if state.op_seen do
              line = extract_line(stmt)

              issue =
                format_issue(source_file,
                  message:
                    "Incorrect authorization: authorization check appears AFTER sensitive operation",
                  trigger: "auth order",
                  line_no: line,
                  metadata: %{cwe: 863}
                )

              {[issue | issues], %{state | auth_seen: true}}
            else
              {issues, %{state | auth_seen: true}}
            end

          true ->
            {issues, state}
        end
      end)

    issues
  end

  defp sensitive_operation?(node) do
    case node do
      {:function_call, meta, _args} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")
        func_lower = String.downcase(func_name)
        Enum.any?(@sensitive_operations, &String.contains?(func_lower, &1))

      {:pipe, _meta, stages} when is_list(stages) ->
        Enum.any?(stages, &sensitive_operation?/1)

      _ ->
        false
    end
  end

  defp authorization_check?(node) do
    case node do
      {:function_call, meta, _args} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")
        func_lower = String.downcase(func_name)
        Enum.any?(@authorization_functions, &String.contains?(func_lower, &1))

      {:conditional, _meta, [condition | _]} ->
        involves_authorization?(condition)

      _ ->
        false
    end
  end

  defp involves_authorization?(node) do
    case node do
      {:function_call, meta, _args} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")
        func_lower = String.downcase(func_name)
        Enum.any?(@authorization_functions, &String.contains?(func_lower, &1))

      {:binary_op, _meta, [left, right]} ->
        involves_authorization?(left) or involves_authorization?(right)

      {:variable, _meta, name} when is_binary(name) ->
        name_lower = String.downcase(name)
        String.contains?(name_lower, "auth") or String.contains?(name_lower, "permission")

      _ ->
        false
    end
  end

  defp role_only_check?(condition) do
    has_role_check?(condition) and not has_resource_check?(condition)
  end

  defp has_role_check?(node) do
    case node do
      {:function_call, meta, _args} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")
        func_lower = String.downcase(func_name)

        String.contains?(func_lower, "role") or
          String.contains?(func_lower, "admin") or
          String.contains?(func_lower, "is_")

      {:binary_op, _meta, [left, right]} ->
        has_role_check?(left) or has_role_check?(right)

      {:attribute_access, _meta, children} when is_list(children) ->
        Enum.any?(children, fn
          {:literal, _, attr} when is_binary(attr) or is_atom(attr) ->
            attr_lower = to_string(attr) |> String.downcase()
            String.contains?(attr_lower, "role") or String.contains?(attr_lower, "admin")

          _ ->
            false
        end)

      _ ->
        false
    end
  end

  defp has_resource_check?(node) do
    case node do
      {:binary_op, meta, [left, right]} when is_list(meta) ->
        operator = Keyword.get(meta, :operator)

        if operator in [:==, :===] do
          involves_resource_ownership?(left) or involves_resource_ownership?(right)
        else
          has_resource_check?(left) or has_resource_check?(right)
        end

      {:function_call, meta, _args} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")
        func_lower = String.downcase(func_name)

        String.contains?(func_lower, "owner") or
          String.contains?(func_lower, "belongs") or
          String.contains?(func_lower, "policy")

      _ ->
        false
    end
  end

  defp involves_resource_ownership?(node) do
    case node do
      {:attribute_access, _meta, children} when is_list(children) ->
        Enum.any?(children, fn
          {:literal, _, attr} when is_binary(attr) or is_atom(attr) ->
            attr_lower = to_string(attr) |> String.downcase()
            String.contains?(attr_lower, "user_id") or String.contains?(attr_lower, "owner")

          _ ->
            false
        end)

      _ ->
        false
    end
  end

  defp extract_line(node) do
    case node do
      {_, meta, _} when is_list(meta) -> Keyword.get(meta, :line)
      _ -> nil
    end
  end
end
