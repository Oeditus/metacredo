defmodule MetaCredo.Check.Security.TOCTOU do
  use MetaCredo.Check,
    category: :security,
    base_priority: :high,
    explanations: [
      check: """
      Detects Time-of-Check-Time-of-Use (TOCTOU) race condition
      vulnerabilities (CWE-367).

      Identifies patterns where a check function (exists?, stat, access) is
      followed by a use function (read, write, open) on the same resource,
      creating a race condition window between check and use.
      """,
      params: [],
      examples: [
        elixir: [
          wrong: """
          # Race window between exists? check and read -- another process may
          # delete or replace the file between the two calls
          if File.exists?(path) do
            content = File.read!(path)
            process(content)
          end
          """,
          correct: """
          # Act on the result of the operation itself, not a prior check
          case File.read(path) do
            {:ok, content} -> process(content)
            {:error, :enoent} -> handle_missing(path)
            {:error, reason} -> handle_error(reason)
          end
          """
        ]
      ]
    ]

  @check_functions %{
    file_check: ~W[
      exists? File.exists? file_exists? path.exists
      os.path.exists os.path.isfile os.path.isdir
      existsSync fs.existsSync File.exist?
      file.exists Path.exists File::exists
      access stat os.Stat fs.stat fs.statSync
    ],
    permission_check: ~W[
      can_access? has_permission? is_authorized?
      check_permission check_access verify_access
      is_writable? is_readable? File.readable?
      File.writable? os.access
    ],
    resource_check: ~W[
      is_available? resource_exists? connection_alive?
      is_connected? socket.connected? is_open? is_valid?
    ]
  }

  @use_functions %{
    file_check: ~W[
      read read! File.read File.read!
      File.write File.write! File.rm File.rm!
      File.open open readFile readFileSync
      fs.readFile fs.readFileSync fs.writeFile
      fs.writeFileSync File.open File::open
      os.Open os.Remove unlink os.unlink
      delete File.delete
    ],
    permission_check: ~W[execute perform do_action run invoke call apply],
    resource_check: ~W[use consume send receive write read execute]
  }

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc -> traverse(node, acc, source_file) end)

    issues
  end

  # Detect check-then-use patterns in conditionals
  defp traverse({:conditional, meta, [condition | branches]} = node, issues, source_file)
       when is_list(meta) and is_list(branches) do
    case extract_check_info(condition) do
      nil ->
        {node, issues}

      check_info ->
        new_issues =
          branches
          |> Enum.flat_map(&find_use_in_branch(&1, check_info, meta, source_file))

        {node, new_issues ++ issues}
    end
  end

  # Detect sequential check-then-use in blocks
  defp traverse({:block, meta, statements} = node, issues, source_file)
       when is_list(meta) and is_list(statements) do
    new_issues = find_sequential_toctou(statements, source_file)
    {node, new_issues ++ issues}
  end

  defp traverse(node, issues, _source_file), do: {node, issues}

  # --- Check Info Extraction ---

  defp extract_check_info({:function_call, meta, args}) when is_list(meta) do
    name = Keyword.get(meta, :name, "")
    check_type = find_check_type(name)

    if check_type do
      resources = extract_resources(args)
      %{type: check_type, function: name, resources: resources}
    else
      nil
    end
  end

  defp extract_check_info(
         {:attribute_access, meta, [receiver, {:function_call, call_meta, args}]}
       )
       when is_list(meta) and is_list(call_meta) do
    method_name = Keyword.get(call_meta, :name, "")
    full_name = build_method_name(receiver, method_name)
    check_type = find_check_type(full_name) || find_check_type(method_name)

    if check_type do
      resources = extract_resources([receiver | args])
      %{type: check_type, function: full_name, resources: resources}
    else
      nil
    end
  end

  defp extract_check_info({:unary_op, meta, [operand]}) when is_list(meta) do
    if Keyword.get(meta, :operator) in [:not, :!] do
      extract_check_info(operand)
    else
      nil
    end
  end

  defp extract_check_info(_), do: nil

  defp find_check_type(name) do
    Enum.find_value(@check_functions, fn {type, functions} ->
      if name in functions or ends_with_any?(name, functions), do: type, else: nil
    end)
  end

  defp ends_with_any?(name, functions) do
    Enum.any?(functions, fn func ->
      String.ends_with?(name, func) or String.ends_with?(name, "." <> func)
    end)
  end

  defp build_method_name({:variable, _, name}, method) when is_binary(name),
    do: "#{name}.#{method}"

  defp build_method_name({:variable, _, name}, method) when is_atom(name),
    do: "#{name}.#{method}"

  defp build_method_name(_, method), do: method

  defp extract_resources(args) when is_list(args) do
    Enum.flat_map(args, fn
      {:variable, _, name} -> [name]
      {:literal, meta, value} when is_list(meta) -> [value]
      _ -> []
    end)
  end

  # --- Use Detection ---

  defp find_use_in_branch(nil, _check_info, _meta, _sf), do: []

  defp find_use_in_branch({:block, _, statements}, check_info, meta, sf)
       when is_list(statements) do
    Enum.flat_map(statements, &find_use_in_node(&1, check_info, meta, sf))
  end

  defp find_use_in_branch(node, check_info, meta, sf),
    do: find_use_in_node(node, check_info, meta, sf)

  defp find_use_in_node({:function_call, call_meta, args}, check_info, parent_meta, sf)
       when is_list(call_meta) do
    name = Keyword.get(call_meta, :name, "")
    use_functions = Map.get(@use_functions, check_info.type, [])

    if use_function?(name, use_functions) and same_resource?(args, check_info.resources) do
      line = Keyword.get(parent_meta, :line)

      [
        format_issue(sf,
          message:
            "TOCTOU vulnerability: '#{check_info.function}' check followed by '#{name}' use",
          trigger: check_info.function,
          line_no: line,
          metadata: %{
            cwe: 367,
            check_function: check_info.function,
            use_function: name,
            resource: List.first(check_info.resources)
          }
        )
      ]
    else
      Enum.flat_map(args, &find_use_in_node(&1, check_info, parent_meta, sf))
    end
  end

  defp find_use_in_node({:conditional, _, children}, check_info, meta, sf)
       when is_list(children) do
    Enum.flat_map(children, &find_use_in_branch(&1, check_info, meta, sf))
  end

  defp find_use_in_node({:block, _, statements}, check_info, meta, sf)
       when is_list(statements) do
    Enum.flat_map(statements, &find_use_in_node(&1, check_info, meta, sf))
  end

  defp find_use_in_node({:assignment, _, [_target, value]}, check_info, meta, sf) do
    find_use_in_node(value, check_info, meta, sf)
  end

  defp find_use_in_node(
         {:attribute_access, _, [receiver, {:function_call, call_meta, args}]},
         check_info,
         parent_meta,
         sf
       )
       when is_list(call_meta) do
    method_name = Keyword.get(call_meta, :name, "")
    full_name = build_method_name(receiver, method_name)
    use_functions = Map.get(@use_functions, check_info.type, [])

    if (use_function?(full_name, use_functions) or use_function?(method_name, use_functions)) and
         same_resource?([receiver | args], check_info.resources) do
      line = Keyword.get(parent_meta, :line)

      [
        format_issue(sf,
          message:
            "TOCTOU vulnerability: '#{check_info.function}' check followed by '#{full_name}' use",
          trigger: check_info.function,
          line_no: line,
          metadata: %{cwe: 367, check_function: check_info.function, use_function: full_name}
        )
      ]
    else
      find_use_in_node(receiver, check_info, parent_meta, sf) ++
        Enum.flat_map(args, &find_use_in_node(&1, check_info, parent_meta, sf))
    end
  end

  defp find_use_in_node(_, _check_info, _meta, _sf), do: []

  # --- Sequential Detection ---

  defp find_sequential_toctou(statements, sf) do
    statements
    |> Enum.with_index()
    |> Enum.flat_map(fn {stmt, idx} ->
      case extract_check_from_statement(stmt) do
        nil ->
          []

        check_info ->
          statements
          |> Enum.drop(idx + 1)
          |> Enum.take(5)
          |> Enum.flat_map(&find_use_in_sequential(&1, check_info, sf))
      end
    end)
  end

  defp extract_check_from_statement({:assignment, _, [_target, value]}),
    do: extract_check_info(value)

  defp extract_check_from_statement({:function_call, _, _} = node), do: extract_check_info(node)
  defp extract_check_from_statement(_), do: nil

  defp find_use_in_sequential({:function_call, meta, args}, check_info, sf)
       when is_list(meta) do
    name = Keyword.get(meta, :name, "")
    use_functions = Map.get(@use_functions, check_info.type, [])

    if use_function?(name, use_functions) and same_resource?(args, check_info.resources) do
      line = Keyword.get(meta, :line)

      [
        format_issue(sf,
          message:
            "TOCTOU vulnerability: '#{check_info.function}' check followed by '#{name}' use in sequential statements",
          trigger: check_info.function,
          line_no: line,
          metadata: %{cwe: 367, check_function: check_info.function, use_function: name}
        )
      ]
    else
      []
    end
  end

  defp find_use_in_sequential({:assignment, _, [_target, value]}, check_info, sf) do
    find_use_in_sequential(value, check_info, sf)
  end

  defp find_use_in_sequential(_, _check_info, _sf), do: []

  # --- Shared Helpers ---

  defp use_function?(name, use_functions) do
    name in use_functions or
      Enum.any?(use_functions, fn func ->
        String.ends_with?(name, func) or String.ends_with?(name, "." <> func)
      end)
  end

  defp same_resource?(_args, []), do: true

  defp same_resource?(args, resources) when is_list(resources) do
    arg_resources =
      Enum.flat_map(args, fn
        {:variable, _, name} -> [name]
        {:literal, _, value} -> [value]
        _ -> []
      end)

    Enum.any?(arg_resources, &Enum.member?(resources, &1))
  end
end
