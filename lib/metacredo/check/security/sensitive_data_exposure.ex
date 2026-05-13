defmodule MetaCredo.Check.Security.SensitiveDataExposure do
  use MetaCredo.Check,
    category: :security,
    base_priority: :high,
    explanations: [
      check: """
      Detects exposure of sensitive information to unauthorized actors (CWE-200).

      Identifies code patterns where sensitive data such as passwords, tokens,
      secrets, or PII is logged, inspected, or otherwise exposed.
      """,
      params: []
    ]

  @logging_functions ~W[
    log info debug warn error warning notice
    Logger.info Logger.debug Logger.warn Logger.error
    IO.puts IO.inspect IO.write
    puts print println printf echo
    console.log console.warn console.error console.debug
    print_r var_dump
    Log.d Log.i Log.w Log.e
    logger.info logger.debug logger.warn logger.error
  ]

  @sensitive_field_patterns ~W[
    password passwd pwd secret token api_key
    apikey access_token refresh_token auth
    credential private_key secret_key
    ssn social_security credit_card card_number
    cvv cvc pin otp verification_code
    session_id csrf bearer jwt
    password_hash encrypted_password
  ]

  @sensitive_object_patterns ~W[
    user account credentials session
    auth authentication authorization
    payment billing card customer
    config secrets env environment
  ]

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc -> traverse(node, acc, source_file) end)

    issues
  end

  # Detect logging calls with potentially sensitive data
  defp traverse({:function_call, meta, args} = node, issues, source_file)
       when is_list(meta) do
    func_name = Keyword.get(meta, :name, "")
    line = Keyword.get(meta, :line)

    cond do
      logging_function?(func_name) and not CheckUtils.safe_stdlib_call?(func_name) ->
        sensitive_items =
          args
          |> Enum.flat_map(&check_sensitive_in_arg/1)
          |> Enum.uniq()

        if sensitive_items == [] do
          {node, issues}
        else
          {node,
           [
             format_issue(source_file,
               message:
                 "Potential sensitive data in '#{func_name}': #{Enum.join(sensitive_items, ", ")}",
               trigger: func_name,
               line_no: line,
               metadata: %{cwe: 200, function: func_name, sensitive_items: sensitive_items}
             )
             | issues
           ]}
        end

      func_name in ["inspect", "Kernel.inspect", "toString", "to_string", "__str__"] ->
        case args do
          [arg] ->
            if sensitive_object?(arg) do
              {node,
               [
                 format_issue(source_file,
                   message:
                     "Potential sensitive data exposure: '#{func_name}' on sensitive object",
                   trigger: func_name,
                   line_no: line,
                   metadata: %{cwe: 200, function: func_name}
                 )
                 | issues
               ]}
            else
              {node, issues}
            end

          _ ->
            {node, issues}
        end

      true ->
        {node, issues}
    end
  end

  defp traverse(node, issues, _source_file), do: {node, issues}

  # --- Private Helpers ---

  defp check_sensitive_in_arg(arg) do
    case arg do
      {:variable, _meta, name} when is_binary(name) ->
        if sensitive_variable?(name), do: [name], else: []

      {:function_call, meta, inner_args} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")

        if func_name in ["inspect", "Kernel.inspect"] or
             String.contains?(func_name, ["struct", "map", "attributes"]) do
          Enum.flat_map(inner_args, &check_sensitive_in_arg/1)
        else
          []
        end

      {:attribute_access, _meta, children} when is_list(children) ->
        check_sensitive_attribute_chain(children)

      {:map, _meta, pairs} when is_list(pairs) ->
        Enum.flat_map(pairs, fn
          {key, _val} when is_binary(key) ->
            if sensitive_field?(key), do: [key], else: []

          {{:literal, _, key}, _val} when is_binary(key) ->
            if sensitive_field?(key), do: [key], else: []

          _ ->
            []
        end)

      {:binary_op, _meta, [left, right]} ->
        check_sensitive_in_arg(left) ++ check_sensitive_in_arg(right)

      {:literal, meta, value} when is_list(meta) and is_binary(value) ->
        if contains_sensitive_interpolation?(value),
          do: ["interpolated sensitive data"],
          else: []

      _ ->
        []
    end
  end

  defp check_sensitive_attribute_chain(children) do
    Enum.flat_map(children, fn
      {:literal, _, attr} when is_binary(attr) or is_atom(attr) ->
        attr_str = to_string(attr)
        if sensitive_field?(attr_str), do: [attr_str], else: []

      {:variable, _, name} when is_binary(name) ->
        if sensitive_variable?(name), do: [name], else: []

      _ ->
        []
    end)
  end

  defp logging_function?(func_name) when is_binary(func_name) do
    func_lower = String.downcase(func_name)

    Enum.any?(@logging_functions, fn pattern ->
      String.contains?(func_lower, String.downcase(pattern))
    end)
  end

  defp logging_function?(_), do: false

  defp sensitive_variable?(name) when is_binary(name) do
    name_lower = String.downcase(name)

    Enum.any?(@sensitive_field_patterns, &String.contains?(name_lower, &1)) or
      Enum.any?(@sensitive_object_patterns, &String.contains?(name_lower, &1))
  end

  defp sensitive_field?(name) when is_binary(name) or is_atom(name) do
    name_lower = name |> to_string() |> String.downcase()
    Enum.any?(@sensitive_field_patterns, &String.contains?(name_lower, &1))
  end

  defp sensitive_object?({:variable, _meta, name}) when is_binary(name) do
    name_lower = String.downcase(name)
    Enum.any?(@sensitive_object_patterns, &String.contains?(name_lower, &1))
  end

  defp sensitive_object?({:attribute_access, _meta, children}) when is_list(children) do
    Enum.any?(children, fn
      {:variable, _, name} when is_binary(name) ->
        name_lower = String.downcase(name)
        Enum.any?(@sensitive_object_patterns, &String.contains?(name_lower, &1))

      _ ->
        false
    end)
  end

  defp sensitive_object?(_), do: false

  defp contains_sensitive_interpolation?(value) when is_binary(value) do
    value_lower = String.downcase(value)
    Enum.any?(@sensitive_field_patterns, &String.contains?(value_lower, &1))
  end
end
