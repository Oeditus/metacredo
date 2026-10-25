defmodule MetaCredo.Check.Security.SensitiveDataExposure do
  use MetaCredo.Check,
    category: :security,
    base_priority: :high,
    confidence: :low,
    tags: [:security, :user_input],
    explanations: [
      check: """
      Detects exposure of sensitive information to unauthorized actors (CWE-200).

      Identifies code patterns where sensitive data such as passwords, tokens,
      secrets, or PII is logged, inspected, or otherwise exposed.
      """,
      params: [],
      examples: [
        elixir: [
          wrong: """
          # Logs a password in plaintext -- visible to anyone with log access
          Logger.info("User login attempt: \#{user.email}, password: \#{user.password}")
          IO.inspect(credentials, label: "credentials")
          """,
          correct: """
          # Log only non-sensitive identifiers
          Logger.info("User login attempt", user_id: user.id, email: user.email)
          # Never log passwords, tokens, secrets, or PII in plaintext
          """
        ]
      ]
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
    line = CheckUtils.line_of(meta)

    cond do
      # NOTE: `safe_stdlib_call?/1` is deliberately *not* consulted here.
      # It exists to stop stdlib calls being mistaken for I/O *sources*, but
      # `Logger` is a sink: logging sensitive data through it is exactly what
      # this check looks for.
      logging_function?(func_name) ->
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

  # A `case` over MetaAST node types: the branching is a grammar lookup table,
  # not tangled control flow.
  defp check_sensitive_in_arg(arg) do
    case arg do
      {:variable, _meta, name} when is_binary(name) ->
        if sensitive_variable?(name), do: [name], else: []

      {:function_call, meta, inner_args} when is_list(meta) ->
        check_sensitive_call(Keyword.get(meta, :name, ""), inner_args)

      {:attribute_access, _meta, children} when is_list(children) ->
        check_sensitive_attribute_chain(children)

      # `"...#{user.password}..."` -- descend into the interpolated parts.
      {:string_interpolation, _meta, parts} when is_list(parts) ->
        Enum.flat_map(parts, &check_sensitive_in_arg/1)

      {:map, _meta, pairs} when is_list(pairs) ->
        Enum.flat_map(pairs, &check_sensitive_pair/1)

      {:binary_op, _meta, [left, right]} ->
        check_sensitive_in_arg(left) ++ check_sensitive_in_arg(right)

      {:literal, meta, value} when is_list(meta) and is_binary(value) ->
        check_sensitive_literal(value)

      _ ->
        []
    end
  end

  defp check_sensitive_literal(value) do
    if contains_sensitive_interpolation?(value),
      do: ["interpolated sensitive data"],
      else: []
  end

  # `user.password` is emitted as `Map.fetch!(user, :password)`, so the *field*
  # name is the sensitive part, not the receiver. `inspect`/`struct`-style
  # calls are descended into wholesale.
  defp check_sensitive_call(func_name, inner_args) do
    cond do
      func_name in ~W(Map.fetch! Map.fetch Map.get) ->
        inner_args
        |> Enum.drop(1)
        |> Enum.flat_map(&field_name/1)
        |> Enum.filter(&sensitive_field?/1)

      func_name in ["inspect", "Kernel.inspect"] or
          String.contains?(func_name, ["struct", "map", "attributes"]) ->
        Enum.flat_map(inner_args, &check_sensitive_in_arg/1)

      true ->
        []
    end
  end

  defp check_sensitive_pair({key, _val}) when is_binary(key) do
    if sensitive_field?(key), do: [key], else: []
  end

  defp check_sensitive_pair({{:literal, _, key}, _val}) when is_binary(key) do
    if sensitive_field?(key), do: [key], else: []
  end

  defp check_sensitive_pair(_), do: []

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

  # Extracts the field name from a `Map.fetch!(recv, :field)` argument.
  defp field_name({:literal, meta, value}) when is_list(meta) do
    if Keyword.get(meta, :subtype) == :symbol, do: [to_string(value)], else: []
  end

  defp field_name(_), do: []

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
