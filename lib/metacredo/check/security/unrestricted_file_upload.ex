defmodule MetaCredo.Check.Security.UnrestrictedFileUpload do
  use MetaCredo.Check,
    category: :security,
    base_priority: :higher,
    explanations: [
      check: """
      Detects unrestricted file upload vulnerabilities (CWE-434).

      Identifies code patterns where file uploads are processed without proper
      validation of file type, size, or content, potentially allowing attackers
      to upload executable files or web shells.
      """,
      params: []
    ]

  @file_save_functions ~W[
    write write! copy copy! stream!
    save save! store store!
    File.write File.copy File.stream
    move_uploaded_file transferTo attach
    saveAs SaveAs DownloadTo
    put_object upload_file
    move rename
  ]

  @validation_indicators ~W[
    extname extension content_type mime_type
    file_type allowed_types valid_extension
    file_size size max_size limit
    validate_upload check_file verify_file
    allowed? valid? acceptable?
  ]

  @upload_patterns ~W[
    upload uploaded file attachment
    multipart form_data formdata
    plug_upload phoenix_upload
  ]

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc -> traverse(node, acc, source_file) end)

    issues
  end

  # Detect function definitions handling uploads without validation
  defp traverse({:function_def, meta, body} = node, issues, source_file)
       when is_list(meta) do
    func_name = Keyword.get(meta, :name, "")
    params = Keyword.get(meta, :params, [])

    if handles_file_upload?(func_name, params) do
      body_list = if is_list(body), do: body, else: [body]

      has_validation? = has_upload_validation?(body_list)
      has_save_op? = has_file_save_operation?(body_list)

      if has_save_op? and not has_validation? do
        line = Keyword.get(meta, :line)

        {node,
         [
           format_issue(source_file,
             message: "Unrestricted file upload: '#{func_name}' saves files without validation",
             trigger: func_name,
             line_no: line,
             severity: :error,
             metadata: %{cwe: 434, function: func_name}
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

  # Detect direct file saves with upload-like variables
  defp traverse({:function_call, meta, args} = node, issues, source_file)
       when is_list(meta) do
    func_name = Keyword.get(meta, :name, "")

    if file_save_function?(func_name) and involves_upload?(args) do
      line = Keyword.get(meta, :line)

      {node,
       [
         format_issue(source_file,
           message: "Potential unrestricted file upload: '#{func_name}' with uploaded content",
           trigger: func_name,
           line_no: line,
           metadata: %{cwe: 434, function: func_name}
         )
         | issues
       ]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _source_file), do: {node, issues}

  # --- Private Helpers ---

  defp handles_file_upload?(func_name, params) when is_binary(func_name) do
    func_lower = String.downcase(func_name)

    String.contains?(func_lower, "upload") or
      String.contains?(func_lower, "import") or
      String.contains?(func_lower, "attach") or
      has_upload_param?(params)
  end

  defp handles_file_upload?(_, _), do: false

  defp has_upload_param?(params) when is_list(params) do
    Enum.any?(params, fn
      {:param, _, name} when is_binary(name) ->
        name_lower = String.downcase(name)
        Enum.any?(@upload_patterns, &String.contains?(name_lower, &1))

      _ ->
        false
    end)
  end

  defp has_upload_param?(_), do: false

  defp file_save_function?(func_name) when is_binary(func_name) do
    func_lower = String.downcase(func_name)

    Enum.any?(@file_save_functions, fn pattern ->
      String.contains?(func_lower, String.downcase(pattern))
    end)
  end

  defp file_save_function?(_), do: false

  defp has_upload_validation?(body) when is_list(body) do
    Enum.any?(body, &contains_validation?/1)
  end

  defp contains_validation?(node) do
    case node do
      {:function_call, meta, _args} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")
        validation_function?(func_name)

      {:conditional, _meta, [condition | _branches]} ->
        contains_validation?(condition) or involves_size_or_type_check?(condition)

      {:binary_op, meta, [left, right]} when is_list(meta) ->
        operator = Keyword.get(meta, :operator)

        if operator in [:in, :==, :===, :>, :<, :>=, :<=] do
          involves_validation_variable?(left) or involves_validation_variable?(right)
        else
          contains_validation?(left) or contains_validation?(right)
        end

      {:case, _meta, _children} ->
        true

      {:block, _meta, statements} when is_list(statements) ->
        Enum.any?(statements, &contains_validation?/1)

      {:pipe, _meta, stages} when is_list(stages) ->
        Enum.any?(stages, &contains_validation?/1)

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

    Enum.any?(@validation_indicators, fn ind ->
      String.contains?(func_lower, String.downcase(ind))
    end)
  end

  defp validation_function?(_), do: false

  defp involves_size_or_type_check?(node) do
    case node do
      {:function_call, meta, _} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")
        func_lower = String.downcase(func_name)

        String.contains?(func_lower, "size") or
          String.contains?(func_lower, "type") or
          String.contains?(func_lower, "ext")

      {:attribute_access, _meta, children} when is_list(children) ->
        Enum.any?(children, &involves_validation_variable?/1)

      _ ->
        false
    end
  end

  defp involves_validation_variable?(node) do
    case node do
      {:variable, _meta, name} when is_binary(name) ->
        name_lower = String.downcase(name)
        Enum.any?(@validation_indicators, &String.contains?(name_lower, &1))

      {:function_call, meta, _} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")
        validation_function?(func_name)

      {:attribute_access, _meta, children} when is_list(children) ->
        Enum.any?(children, fn
          {:literal, _, attr} when is_binary(attr) or is_atom(attr) ->
            attr_lower = to_string(attr) |> String.downcase()
            Enum.any?(@validation_indicators, &String.contains?(attr_lower, &1))

          other ->
            involves_validation_variable?(other)
        end)

      _ ->
        false
    end
  end

  defp has_file_save_operation?(body) when is_list(body) do
    Enum.any?(body, &contains_file_save?/1)
  end

  defp contains_file_save?(node) do
    case node do
      {:function_call, meta, _args} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")
        file_save_function?(func_name)

      {:pipe, _meta, stages} when is_list(stages) ->
        Enum.any?(stages, &contains_file_save?/1)

      {:block, _meta, statements} when is_list(statements) ->
        Enum.any?(statements, &contains_file_save?/1)

      tuple when is_tuple(tuple) ->
        tuple |> Tuple.to_list() |> Enum.any?(&contains_file_save?/1)

      list when is_list(list) ->
        Enum.any?(list, &contains_file_save?/1)

      _ ->
        false
    end
  end

  defp involves_upload?(args) when is_list(args) do
    Enum.any?(args, fn
      {:variable, _meta, name} when is_binary(name) ->
        name_lower = String.downcase(name)
        Enum.any?(@upload_patterns, &String.contains?(name_lower, &1))

      {:attribute_access, _meta, children} when is_list(children) ->
        Enum.any?(children, fn
          {:variable, _, name} when is_binary(name) ->
            name_lower = String.downcase(name)
            Enum.any?(@upload_patterns, &String.contains?(name_lower, &1))

          _ ->
            false
        end)

      _ ->
        false
    end)
  end

  defp involves_upload?(_), do: false
end
