defmodule MetaCredo.Check.Security.ImproperInputValidation do
  use MetaCredo.Check,
    category: :security,
    base_priority: :high,
    explanations: [
      check: """
      Detects improper input validation patterns (CWE-20).

      Identifies code patterns where user input is used in sensitive operations
      without apparent validation or sanitization, such as using params
      directly without changeset validation.
      """,
      params: []
    ]

  @user_input_sources ~W[
    params request args query body
    input form data payload
    get post put patch
  ]

  @validation_functions ~W[
    validate valid? changeset cast
    schema validate_required validate_format
    validate_length validate_inclusion
    sanitize clean filter escape
    permit strong_parameters
    Bean Validator DataAnnotation
    Joi Yup zod
  ]

  @sensitive_operations ~W[
    query execute run eval
    send call request
    write save insert update delete
    open read file path
    create new build
  ]

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc -> traverse(node, acc, source_file) end)

    issues
  end

  # Detect function definitions that use input without validation
  defp traverse({:function_def, meta, body} = node, issues, source_file)
       when is_list(meta) do
    func_name = Keyword.get(meta, :name, "")
    params = Keyword.get(meta, :params, [])

    if has_input_params?(params) do
      body_list = if is_list(body), do: body, else: [body]

      has_validation? = has_input_validation?(body_list)
      has_sensitive_use? = has_sensitive_input_use?(body_list)

      if has_sensitive_use? and not has_validation? do
        line = Keyword.get(meta, :line)

        {node,
         [
           format_issue(source_file,
             message:
               "Improper input validation: '#{func_name}' uses input in sensitive operations without validation",
             trigger: func_name,
             line_no: line,
             metadata: %{cwe: 20, function: func_name}
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

  # Detect direct use of user input in sensitive function calls
  defp traverse({:function_call, meta, args} = node, issues, source_file)
       when is_list(meta) do
    func_name = Keyword.get(meta, :name, "")

    if sensitive_operation?(func_name) and has_direct_input_argument?(args) do
      line = Keyword.get(meta, :line)

      {node,
       [
         format_issue(source_file,
           message:
             "Potential improper input validation: user input passed directly to '#{func_name}'",
           trigger: func_name,
           line_no: line,
           metadata: %{cwe: 20, function: func_name}
         )
         | issues
       ]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _source_file), do: {node, issues}

  # --- Private Helpers ---

  defp has_input_params?(params) when is_list(params) do
    Enum.any?(params, fn
      {:param, _, name} when is_binary(name) ->
        name_lower = String.downcase(name)
        Enum.any?(@user_input_sources, &String.contains?(name_lower, &1))

      _ ->
        false
    end)
  end

  defp has_input_params?(_), do: false

  defp has_input_validation?(body) when is_list(body) do
    Enum.any?(body, &contains_validation?/1)
  end

  defp contains_validation?(node) do
    case node do
      {:function_call, meta, _args} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")
        validation_function?(func_name)

      {:pipe, _meta, stages} when is_list(stages) ->
        Enum.any?(stages, &contains_validation?/1)

      {:block, _meta, statements} when is_list(statements) ->
        Enum.any?(statements, &contains_validation?/1)

      {:conditional, _meta, [condition | _branches]} ->
        type_check?(condition) or contains_validation?(condition)

      {:case, _meta, _} ->
        true

      {:with, _meta, _} ->
        true

      tuple when is_tuple(tuple) ->
        tuple |> Tuple.to_list() |> Enum.any?(&contains_validation?/1)

      list when is_list(list) ->
        Enum.any?(list, &contains_validation?/1)

      _ ->
        false
    end
  end

  defp validation_function?(func_name) when is_binary(func_name) do
    func_lower = String.downcase(func_name)

    Enum.any?(@validation_functions, fn pattern ->
      String.contains?(func_lower, String.downcase(pattern))
    end)
  end

  defp validation_function?(_), do: false

  defp type_check?(node) do
    case node do
      {:function_call, meta, _args} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")
        func_lower = String.downcase(func_name)

        String.contains?(func_lower, "is_") or
          String.contains?(func_lower, "type") or
          String.contains?(func_lower, "match")

      _ ->
        false
    end
  end

  defp has_sensitive_input_use?(body) when is_list(body) do
    Enum.any?(body, &contains_sensitive_input_use?/1)
  end

  defp contains_sensitive_input_use?(node) do
    case node do
      {:function_call, meta, args} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")
        sensitive_operation?(func_name) and has_direct_input_argument?(args)

      {:pipe, _meta, stages} when is_list(stages) ->
        Enum.any?(stages, &contains_sensitive_input_use?/1)

      {:block, _meta, statements} when is_list(statements) ->
        Enum.any?(statements, &contains_sensitive_input_use?/1)

      tuple when is_tuple(tuple) ->
        tuple |> Tuple.to_list() |> Enum.any?(&contains_sensitive_input_use?/1)

      list when is_list(list) ->
        Enum.any?(list, &contains_sensitive_input_use?/1)

      _ ->
        false
    end
  end

  defp sensitive_operation?(func_name) when is_binary(func_name) do
    func_lower = String.downcase(func_name)
    Enum.any?(@sensitive_operations, &String.contains?(func_lower, &1))
  end

  defp sensitive_operation?(_), do: false

  defp has_direct_input_argument?(args) when is_list(args) do
    Enum.any?(args, fn
      {:variable, _meta, name} when is_binary(name) ->
        name_lower = String.downcase(name)
        Enum.any?(@user_input_sources, &String.contains?(name_lower, &1))

      {:map_access, _meta, _} ->
        true

      {:attribute_access, _meta, children} when is_list(children) ->
        Enum.any?(children, fn
          {:variable, _, name} when is_binary(name) ->
            name_lower = String.downcase(name)
            Enum.any?(@user_input_sources, &String.contains?(name_lower, &1))

          _ ->
            false
        end)

      _ ->
        false
    end)
  end

  defp has_direct_input_argument?(_), do: false
end
