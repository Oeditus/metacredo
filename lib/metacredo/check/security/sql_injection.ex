defmodule MetaCredo.Check.Security.SQLInjection do
  use MetaCredo.Check,
    category: :security,
    base_priority: :higher,
    tags: [:db, :security],
    param_defaults: [check_exs: false],
    explanations: [
      check: """
      Detects potential SQL injection vulnerabilities (CWE-89).

      Identifies code patterns where user input or variables are concatenated
      or interpolated into SQL query strings instead of using parameterized
      queries.

      A string literal is only treated as SQL when it contains at least two
      *distinct* SQL keywords matched on word boundaries, so HTML/JS heredocs
      and prose that merely mention a single keyword are not reported.
      """,
      params: [
        check_exs: "Check SQL patterns in .exs script/config files (default: false)"
      ],
      examples: [
        elixir: [
          wrong: """
          # Attacker can terminate the query and inject arbitrary SQL
          def search(conn, %{"term" => term}) do
            Repo.query!("SELECT * FROM products WHERE name = '" <> term <> "'")
          end
          """,
          correct: """
          # Always use parameterized queries or Ecto query composition
          def search(conn, %{"term" => term}) do
            from(p in Product, where: p.name == ^term) |> Repo.all()
          end

          # For raw SQL, use parameterized form:
          # Repo.query!("SELECT * FROM products WHERE name = $1", [term])
          """
        ]
      ]
    ]

  @truncate_limit 50
  @truncate_keep 47

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
  def run(%SourceFile{} = source_file, params) do
    # `.exs` files are scripts/configs: they routinely embed HTML/JS heredocs
    # and example query strings that are not executed as SQL. Mirrors the
    # `check_exs` opt-in used by `Security.HardcodedValue`.
    if not params_get(params, :check_exs) and
         String.ends_with?(source_file.filename || "", ".exs") do
      []
    else
      ast = SourceFile.ast(source_file)
      doc_strings = CheckUtils.doc_string_contents(ast)

      {_, issues} =
        AST.prewalk(ast, [], fn node, acc ->
          traverse(node, acc, source_file, doc_strings)
        end)

      issues
    end
  end

  # Detect binary operations that concatenate SQL strings
  defp traverse({:binary_op, meta, [left, right]} = node, issues, source_file, _doc_strings)
       when is_list(meta) do
    operator = Keyword.get(meta, :operator)

    if operator in [:concat, :<>, :+, :||] do
      {node, check_sql_concat(left, right, meta, issues, source_file)}
    else
      {node, issues}
    end
  end

  # Detect function calls to query functions with unsafe arguments
  defp traverse({:function_call, meta, args} = node, issues, source_file, _doc_strings)
       when is_list(meta) do
    func_name = Keyword.get(meta, :name, "")

    if query_function?(func_name) and not CheckUtils.safe_stdlib_call?(func_name) and
         has_unsafe_sql_argument?(args) do
      line = CheckUtils.line_of(meta)

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
  defp traverse({:literal, meta, value} = node, issues, source_file, doc_strings)
       when is_list(meta) and is_binary(value) do
    if Keyword.get(meta, :subtype) == :string and
         not CheckUtils.doc_string?(doc_strings, value) and
         contains_sql_keywords?(value) and has_interpolation_markers?(value) do
      line = CheckUtils.line_of(meta)

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

  defp traverse(node, issues, _source_file, _doc_strings), do: {node, issues}

  # --- Private Helpers ---

  defp check_sql_concat(left, right, meta, issues, source_file) do
    left_sql? = contains_sql_literal?(left)
    right_sql? = contains_sql_literal?(right)
    left_var? = variable_or_call?(left)
    right_var? = variable_or_call?(right)
    line = CheckUtils.line_of(meta)

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

  # A single SQL keyword appearing as a *substring* is far too weak a signal:
  # `document.createElement` contains "EXEC", and prose routinely contains
  # "FROM". Require at least two *distinct* keywords matched on word
  # boundaries before treating a literal as SQL at all.
  defp contains_sql_keywords?(value) when is_binary(value) do
    value
    |> String.upcase()
    |> then(fn upper -> Enum.count(@sql_keywords, &Regex.match?(keyword_regex(&1), upper)) end)
    |> Kernel.>=(2)
  end

  defp keyword_regex(keyword) do
    Regex.compile!("\\b" <> keyword <> "\\b")
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

  defp truncate(s) when byte_size(s) > @truncate_limit,
    do: String.slice(s, 0, @truncate_keep) <> "..."

  defp truncate(s), do: s
end
