defmodule MetaCredo.Check.Security.SQLInjection do
  use MetaCredo.Check,
    category: :security,
    base_priority: :higher,
    explanations: [
      check: """
      Detects potential SQL injection vulnerabilities (CWE-89).

      Identifies code patterns where user input or variables are concatenated
      or interpolated into SQL query strings instead of using parameterized
      queries.
      """,
      params: []
    ]

  @sql_keywords ~W[SELECT INSERT UPDATE DELETE FROM WHERE JOIN DROP CREATE ALTER TRUNCATE EXEC EXECUTE]

  @query_functions ~W[
    query execute exec run sql raw_query
    execute_query execute_sql run_sql
    Repo.query Ecto.Adapters.SQL.query
    cursor.execute connection.execute
    db.query db.execute db.run
    executeQuery executeUpdate executeSql
    Query Raw RawSQL
  ]

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc -> traverse(node, acc, source_file) end)

    issues
  end

  # Detect binary operations that concatenate SQL strings
  defp traverse({:binary_op, meta, [left, right]} = node, issues, source_file)
       when is_list(meta) do
    operator = Keyword.get(meta, :operator)

    if operator in [:concat, :<>, :+, :||] do
      {node, check_sql_concat(left, right, meta, issues, source_file)}
    else
      {node, issues}
    end
  end

  # Detect function calls to query functions with unsafe arguments
  defp traverse({:function_call, meta, args} = node, issues, source_file)
       when is_list(meta) do
    func_name = Keyword.get(meta, :name, "")

    if query_function?(func_name) and has_unsafe_sql_argument?(args) do
      line = Keyword.get(meta, :line)

      {node,
       [
         format_issue(source_file,
           message: "Potential SQL injection: unsafe string passed to '#{func_name}'",
           trigger: func_name,
           line_no: line,
           metadata: %{cwe: 89, function: func_name}
         )
         | issues
       ]}
    else
      {node, issues}
    end
  end

  # Detect string interpolation patterns containing SQL
  defp traverse({:literal, meta, value} = node, issues, source_file)
       when is_list(meta) and is_binary(value) do
    if Keyword.get(meta, :subtype) == :string and
         contains_sql_keywords?(value) and has_interpolation_markers?(value) do
      line = Keyword.get(meta, :line)

      {node,
       [
         format_issue(source_file,
           message: "Potential SQL injection: string interpolation in SQL query",
           trigger: truncate(value),
           line_no: line,
           metadata: %{cwe: 89}
         )
         | issues
       ]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _source_file), do: {node, issues}

  # --- Private Helpers ---

  defp check_sql_concat(left, right, meta, issues, source_file) do
    left_sql? = contains_sql_literal?(left)
    right_sql? = contains_sql_literal?(right)
    left_var? = variable_or_call?(left)
    right_var? = variable_or_call?(right)
    line = Keyword.get(meta, :line)

    cond do
      left_sql? and right_var? ->
        [
          format_issue(source_file,
            message: "Potential SQL injection: SQL string concatenated with variable/expression",
            trigger: "<>",
            line_no: line,
            metadata: %{cwe: 89}
          )
          | issues
        ]

      right_sql? and left_var? ->
        [
          format_issue(source_file,
            message: "Potential SQL injection: variable/expression concatenated with SQL string",
            trigger: "<>",
            line_no: line,
            metadata: %{cwe: 89}
          )
          | issues
        ]

      true ->
        issues
    end
  end

  defp contains_sql_literal?({:literal, meta, value}) when is_list(meta) and is_binary(value) do
    contains_sql_keywords?(value)
  end

  defp contains_sql_literal?({:binary_op, _meta, [left, right]}) do
    contains_sql_literal?(left) or contains_sql_literal?(right)
  end

  defp contains_sql_literal?(_), do: false

  defp contains_sql_keywords?(value) when is_binary(value) do
    upper = String.upcase(value)
    Enum.any?(@sql_keywords, &String.contains?(upper, &1))
  end

  defp variable_or_call?({:variable, _meta, _name}), do: true
  defp variable_or_call?({:function_call, _meta, _args}), do: true
  defp variable_or_call?({:attribute_access, _meta, _children}), do: true
  defp variable_or_call?(_), do: false

  defp query_function?(func_name) when is_binary(func_name) do
    func_lower = String.downcase(func_name)

    Enum.any?(@query_functions, fn pattern ->
      String.contains?(func_lower, String.downcase(pattern))
    end)
  end

  defp query_function?(_), do: false

  defp has_unsafe_sql_argument?(args) when is_list(args) do
    Enum.any?(args, fn
      {:binary_op, meta, _} when is_list(meta) ->
        Keyword.get(meta, :operator) in [:concat, :<>, :+, :||]

      {:literal, meta, value} when is_list(meta) and is_binary(value) ->
        contains_sql_keywords?(value) and has_interpolation_markers?(value)

      _ ->
        false
    end)
  end

  defp has_unsafe_sql_argument?(_), do: false

  defp has_interpolation_markers?(value) when is_binary(value) do
    dquote_plus = <<34, 32, 43>>
    dquote_pipe = <<34, 32, 124, 124>>

    String.contains?(value, "${") or
      String.contains?(value, ~S(#{)) or
      String.contains?(value, "{") or
      String.contains?(value, "' +") or
      String.contains?(value, dquote_plus) or
      String.contains?(value, "' ||") or
      String.contains?(value, dquote_pipe)
  end

  defp truncate(s) when byte_size(s) > 50, do: String.slice(s, 0, 47) <> "..."
  defp truncate(s), do: s
end
