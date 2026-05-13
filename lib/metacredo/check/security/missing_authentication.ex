defmodule MetaCredo.Check.Security.MissingAuthentication do
  use MetaCredo.Check,
    category: :security,
    base_priority: :higher,
    explanations: [
      check: """
      Detects critical functions without authentication checks (CWE-306).

      Identifies endpoints or functions that perform sensitive operations
      (admin, delete, update, payment, etc.) but lack apparent authentication
      verification via plugs, decorators, or middleware.
      """,
      params: []
    ]

  @critical_action_names ~w[
    admin dashboard settings config configuration
    delete destroy remove purge
    update modify edit patch
    create new insert
    export import backup restore
    password reset token api_key
    payment checkout billing subscription
    user users account accounts
  ]

  @authentication_indicators ~w[
    authenticate authenticated? ensure_authenticated
    login logged_in? current_user
    require_login require_auth session
    token bearer jwt oauth
    api_key authorized verify_token
    before_action plug guardian
    @login_required @authenticated @authorize
    PreAuthorize Secured RolesAllowed
  ]

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc -> traverse(node, acc, source_file) end)

    issues
  end

  # Detect function definitions for critical actions without auth
  defp traverse({:function_def, meta, body} = node, issues, source_file)
       when is_list(meta) do
    func_name = Keyword.get(meta, :name, "")

    if critical_action?(func_name) do
      body_list = if is_list(body), do: body, else: [body]

      if has_authentication_check?(body_list) do
        {node, issues}
      else
        line = Keyword.get(meta, :line)

        {node,
         [
           format_issue(source_file,
             message:
               "Missing authentication: critical function '#{func_name}' without auth check",
             trigger: func_name,
             line_no: line,
             severity: :error,
             metadata: %{cwe: 306, function: func_name}
           )
           | issues
         ]}
      end
    else
      {node, issues}
    end
  end

  # Detect controller modules without module-level auth
  defp traverse({:container, meta, body} = node, issues, source_file)
       when is_list(meta) do
    container_name = Keyword.get(meta, :name, "")

    if controller_module?(container_name) do
      body_list = if is_list(body), do: body, else: [body]

      has_module_auth? = has_module_level_auth?(body_list)
      has_critical? = has_critical_action_functions?(body_list)

      if has_critical? and not has_module_auth? do
        line = Keyword.get(meta, :line)

        {node,
         [
           format_issue(source_file,
             message:
               "Potential missing authentication: controller '#{container_name}' without module-level auth",
             trigger: container_name,
             line_no: line,
             metadata: %{cwe: 306, module: container_name}
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

  defp traverse(node, issues, _source_file), do: {node, issues}

  # --- Private Helpers ---

  defp critical_action?(func_name) when is_binary(func_name) do
    func_lower = String.downcase(func_name)
    Enum.any?(@critical_action_names, &String.contains?(func_lower, &1))
  end

  defp critical_action?(_), do: false

  defp controller_module?(name) when is_binary(name) do
    name_lower = String.downcase(name)

    String.contains?(name_lower, "controller") or
      String.contains?(name_lower, "handler") or
      String.contains?(name_lower, "api") or
      String.contains?(name_lower, "endpoint") or
      String.contains?(name_lower, "view")
  end

  defp controller_module?(_), do: false

  defp has_authentication_check?(body) when is_list(body) do
    Enum.any?(body, &contains_auth_check?/1)
  end

  defp contains_auth_check?(node) do
    case node do
      {:function_call, meta, _args} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")
        auth_indicator?(func_name)

      {:conditional, _meta, [condition | _branches]} ->
        involves_auth?(condition)

      {:block, _meta, statements} when is_list(statements) ->
        Enum.any?(statements, &contains_auth_check?/1)

      {:pipe, _meta, stages} when is_list(stages) ->
        Enum.any?(stages, &contains_auth_check?/1)

      tuple when is_tuple(tuple) ->
        tuple |> Tuple.to_list() |> Enum.any?(&contains_auth_check?/1)

      list when is_list(list) ->
        Enum.any?(list, &contains_auth_check?/1)

      _ ->
        false
    end
  end

  defp auth_indicator?(name) when is_binary(name) do
    name_lower = String.downcase(name)

    Enum.any?(@authentication_indicators, fn ind ->
      String.contains?(name_lower, String.downcase(ind))
    end)
  end

  defp auth_indicator?(_), do: false

  defp involves_auth?(node) do
    case node do
      {:variable, _meta, name} when is_binary(name) ->
        name_lower = String.downcase(name)
        String.contains?(name_lower, "user") or String.contains?(name_lower, "auth")

      {:function_call, meta, _} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")
        auth_indicator?(func_name)

      {:attribute_access, _meta, children} when is_list(children) ->
        Enum.any?(children, &involves_auth?/1)

      _ ->
        false
    end
  end

  defp has_module_level_auth?(body) when is_list(body) do
    Enum.any?(body, fn
      {:function_call, meta, _args} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")
        func_lower = String.downcase(func_name)

        String.contains?(func_lower, "plug") or
          String.contains?(func_lower, "before_action") or
          String.contains?(func_lower, "use") or
          auth_indicator?(func_name)

      _ ->
        false
    end)
  end

  defp has_critical_action_functions?(body) when is_list(body) do
    Enum.any?(body, fn
      {:function_def, meta, _} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")
        critical_action?(func_name)

      _ ->
        false
    end)
  end
end
