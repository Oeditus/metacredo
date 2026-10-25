defmodule MetaCredo.Check.Security.PathTraversal do
  use MetaCredo.Check,
    category: :security,
    base_priority: :higher,
    confidence: :low,
    tags: [:security, :user_input],
    explanations: [
      check: """
      Detects potential Path Traversal vulnerabilities (CWE-22).

      Identifies code patterns where user input is used in file path
      operations without proper validation, allowing attackers to access
      files outside the intended directory via ../ sequences.
      """,
      params: [],
      examples: [
        elixir: [
          wrong: """
          # Attacker can pass "../../etc/passwd" as filename
          def download(conn, %{"name" => filename}) do
            content = File.read!("/var/uploads/" <> filename)
            send_resp(conn, 200, content)
          end
          """,
          correct: """
          # Canonicalize the path and verify it stays within the allowed directory
          @upload_dir "/var/uploads"

          def download(conn, %{"name" => filename}) do
            safe_path = Path.expand(filename, @upload_dir)

            if String.starts_with?(safe_path, @upload_dir) and File.exists?(safe_path) do
              send_file(conn, 200, safe_path)
            else
              send_resp(conn, 400, "Invalid filename")
            end
          end
          """
        ]
      ]
    ]

  @file_functions ~W[
    read read! write write! stream! open
    read_file read_file! write_file
    readFile writeFile readFileSync writeFileSync
    file_get_contents file_put_contents fopen
    File.read File.write File.stream File.open
    Path.join Path.expand Path.absname
    send_file send_download download
    include require require_once include_once
    readdir opendir scandir glob
    unlink delete rm remove
    copy cp rename mv move
    mkdir rmdir
  ]

  @path_functions ~W[
    join expand absname relative_to
    Path.join Path.expand Path.absname
    path.join path.resolve path.normalize
    os.path.join os.path.abspath
    Paths.get File.separator
  ]

  @user_input_patterns ~W[
    params request args query body
    input user filename file path
    name document image upload
    get post
  ]

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc -> traverse(node, acc, source_file) end)

    issues
  end

  # Detect file/path operations with tainted arguments.
  #
  # The two branches differ only in message and severity, so the predicate is
  # resolved first and the issue is built once.
  defp traverse({:function_call, meta, args} = node, issues, source_file)
       when is_list(meta) do
    func_name = Keyword.get(meta, :name, "")

    case tainted_path_operation(func_name, args) do
      nil ->
        {node, issues}

      {severity, message} ->
        issue =
          format_issue(source_file,
            message: message,
            trigger: func_name,
            line_no: CheckUtils.line_of(meta),
            severity: severity,
            metadata: %{cwe: 22, function: func_name}
          )

        {node, [issue | issues]}
    end
  end

  defp traverse({:binary_op, meta, [left, right]} = node, issues, source_file)
       when is_list(meta) do
    operator = Keyword.get(meta, :operator)

    if operator in [:concat, :<>, :+, :/] do
      line = CheckUtils.line_of(meta)

      cond do
        looks_like_path?(left) and contains_user_input?(right) ->
          {node,
           [
             format_issue(source_file,
               message: "Potential path traversal: path concatenation with user input",
               trigger: "<>",
               line_no: line,
               metadata: %{cwe: 22}
             )
             | issues
           ]}

        looks_like_path?(right) and contains_user_input?(left) ->
          {node,
           [
             format_issue(source_file,
               message: "Potential path traversal: user input concatenated with path",
               trigger: "<>",
               line_no: line,
               metadata: %{cwe: 22}
             )
             | issues
           ]}

        true ->
          {node, issues}
      end
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _source_file), do: {node, issues}

  defp tainted_path_operation(func_name, args) do
    cond do
      CheckUtils.safe_stdlib_call?(func_name) ->
        nil

      file_function?(func_name) and has_tainted_arg?(args) ->
        {:error,
         "Potential path traversal: file operation with user-controlled path in '#{func_name}'"}

      path_function?(func_name) and has_tainted_arg?(args) ->
        {:warning,
         "Potential path traversal: '#{func_name}' with user-controlled input -- validate result"}

      true ->
        nil
    end
  end

  # Detect path concatenation with user input
  # --- Private Helpers ---

  defp file_function?(func_name), do: matches_any?(func_name, @file_functions)

  defp path_function?(func_name), do: matches_any?(func_name, @path_functions)

  defp has_tainted_arg?(args) when is_list(args) do
    Enum.any?(args, &contains_user_input?/1)
  end

  defp has_tainted_arg?(_), do: false

  # Case-insensitive substring match of `func_name` against any pattern.
  defp matches_any?(func_name, patterns) when is_binary(func_name) do
    func_lower = String.downcase(func_name)
    Enum.any?(patterns, &String.contains?(func_lower, String.downcase(&1)))
  end

  defp contains_user_input?(node) do
    case node do
      {:variable, _meta, name} when is_binary(name) ->
        user_input_variable?(name)

      {:function_call, meta, _args} when is_list(meta) ->
        func_name = Keyword.get(meta, :name, "")
        user_input_function?(func_name)

      {:attribute_access, _meta, children} when is_list(children) ->
        Enum.any?(children, &contains_user_input?/1)

      {:binary_op, _meta, [left, right]} ->
        contains_user_input?(left) or contains_user_input?(right)

      {:map_access, _meta, [_map, key]} ->
        contains_user_input?(key)

      _ ->
        false
    end
  end

  defp user_input_variable?(name) when is_binary(name) do
    name_lower = String.downcase(name)
    Enum.any?(@user_input_patterns, &String.contains?(name_lower, &1))
  end

  defp user_input_function?(func_name) when is_binary(func_name) do
    func_lower = String.downcase(func_name)
    Enum.any?(@user_input_patterns, &String.contains?(func_lower, &1))
  end

  defp user_input_function?(_), do: false

  defp looks_like_path?({:literal, meta, value}) when is_list(meta) and is_binary(value) do
    String.contains?(value, "/") or
      String.contains?(value, "\\") or
      String.starts_with?(value, ".") or
      String.ends_with?(value, [".txt", ".json", ".xml", ".html", ".log", ".conf", ".cfg"])
  end

  defp looks_like_path?({:variable, _meta, name}) when is_binary(name) do
    name_lower = String.downcase(name)

    String.contains?(name_lower, "path") or
      String.contains?(name_lower, "dir") or
      String.contains?(name_lower, "file") or
      String.contains?(name_lower, "folder")
  end

  defp looks_like_path?(_), do: false
end
