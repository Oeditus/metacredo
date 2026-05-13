defmodule MetaCredo.Check.Security.MissingCSRFProtection do
  use MetaCredo.Check,
    category: :security,
    base_priority: :high,
    explanations: [
      check: """
      Detects state-changing endpoints without CSRF protection (CWE-352).

      Identifies code patterns where state-changing HTTP operations (POST, PUT,
      PATCH, DELETE) are handled without CSRF token validation.
      """,
      params: [],
      examples: [
        wrong: """
        # POST handler with no CSRF token validation
        def create(conn, params) do
          Accounts.create_user(params)
          redirect(conn, to: ~p"/users")
        end
        """,
        correct: """
        # Phoenix includes Plug.CSRFProtection by default in the browser pipeline;
        # ensure it is not bypassed and include the CSRF meta tag in your layout.
        # In forms, use Phoenix.HTML.Tag.csrf_meta_tag/0 or the built-in form helper.
        def create(conn, params) do
          # CSRF is validated automatically by the browser pipeline plug
          Accounts.create_user(params)
          redirect(conn, to: ~p"/users")
        end
        """
      ]
    ]

  @state_changing_methods ~W[post put patch delete]

  @csrf_indicators ~W[
    csrf token protect_from_forgery
    verify_authenticity_token antiforgery
    ValidateAntiForgeryToken csurf
    csrf_protect csrf_token csrf_exempt
    x-csrf-token _csrf
  ]

  @state_changing_actions ~W[
    create update delete destroy
    save insert remove edit
    post put patch
  ]

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc -> traverse(node, acc, source_file) end)

    issues
  end

  # Detect function definitions for state-changing actions without CSRF check
  defp traverse({:function_def, meta, body} = node, issues, source_file)
       when is_list(meta) do
    func_name = Keyword.get(meta, :name, "")

    if state_changing_action?(func_name) do
      body_list = if is_list(body), do: body, else: [body]

      if has_csrf_check?(body_list) do
        {node, issues}
      else
        line = Keyword.get(meta, :line)

        {node,
         [
           format_issue(source_file,
             message: "Potential missing CSRF protection: state-changing action '#{func_name}'",
             trigger: func_name,
             line_no: line,
             metadata: %{cwe: 352, function: func_name}
           )
           | issues
         ]}
      end
    else
      {node, issues}
    end
  end

  # Detect route definitions for state-changing methods
  defp traverse({:function_call, meta, _args} = node, issues, source_file)
       when is_list(meta) do
    func_name = Keyword.get(meta, :name, "")
    func_lower = String.downcase(func_name)

    if func_lower in @state_changing_methods do
      line = Keyword.get(meta, :line)

      {node,
       [
         format_issue(source_file,
           message:
             "Potential missing CSRF protection: #{String.upcase(func_name)} route handler",
           trigger: func_name,
           line_no: line,
           metadata: %{cwe: 352, method: func_name}
         )
         | issues
       ]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _source_file), do: {node, issues}

  # --- Private Helpers ---

  defp state_changing_action?(func_name) when is_binary(func_name) do
    func_lower = String.downcase(func_name)
    Enum.any?(@state_changing_actions, &String.contains?(func_lower, &1))
  end

  defp state_changing_action?(_), do: false

  defp has_csrf_check?(body) when is_list(body) do
    Enum.any?(body, &contains_csrf_check?/1)
  end

  defp contains_csrf_check?(node) do
    case node do
      {:function_call, meta, _args} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")
        csrf_indicator?(func_name)

      {:block, _meta, statements} when is_list(statements) ->
        Enum.any?(statements, &contains_csrf_check?/1)

      tuple when is_tuple(tuple) ->
        tuple |> Tuple.to_list() |> Enum.any?(&contains_csrf_check?/1)

      list when is_list(list) ->
        Enum.any?(list, &contains_csrf_check?/1)

      _ ->
        false
    end
  end

  defp csrf_indicator?(name) when is_binary(name) do
    name_lower = String.downcase(name)

    Enum.any?(@csrf_indicators, fn ind ->
      String.contains?(name_lower, String.downcase(ind))
    end)
  end

  defp csrf_indicator?(_), do: false
end
