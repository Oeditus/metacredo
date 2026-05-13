defmodule MetaCredo.Check.Refactor.CodeDuplication do
  use MetaCredo.Check,
    category: :refactor,
    base_priority: :normal,
    param_defaults: [min_body_size: 3],
    explanations: [
      check: """
      Detects duplicate function bodies within the same module by comparing
      normalized AST structure. Functions with identical logic should be
      consolidated into a shared helper.
      """,
      params: [
        min_body_size:
          "Minimum number of AST nodes in a function body to consider for duplication (default: 3)"
      ],
      examples: [
        wrong: """
        # Identical logic copy-pasted across two functions
        def format_admin_name(user) do
          first = String.capitalize(user.first_name)
          last = String.upcase(user.last_name)
          "\#{first} \#{last}"
        end

        def format_customer_name(user) do
          first = String.capitalize(user.first_name)
          last = String.upcase(user.last_name)
          "\#{first} \#{last}"
        end
        """,
        correct: """
        # Extract the shared logic into a single private helper
        def format_admin_name(user), do: format_name(user)
        def format_customer_name(user), do: format_name(user)

        defp format_name(user) do
          first = String.capitalize(user.first_name)
          last = String.upcase(user.last_name)
          "\#{first} \#{last}"
        end
        """
      ]
    ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    min_body_size = params_get(params, :min_body_size)

    functions =
      source_file
      |> SourceFile.ast()
      |> collect_functions([])

    functions
    |> Enum.filter(fn {_name, _line, body} -> ast_size(body) >= min_body_size end)
    |> find_duplicates()
    |> Enum.flat_map(fn {names, line} ->
      names_str = Enum.join(names, ", ")

      [
        format_issue(source_file,
          message:
            "Duplicate function bodies detected: #{names_str} -- extract shared logic into a helper",
          trigger: names_str,
          line_no: line,
          severity: :refactoring_opportunity
        )
      ]
    end)
  end

  # Collect all function definitions with their names and bodies
  defp collect_functions({:function_def, meta, children} = _node, acc) when is_list(meta) do
    name = Keyword.get(meta, :name, "anonymous")
    line = Keyword.get(meta, :line)
    [{name, line, children} | acc]
  end

  defp collect_functions({:block, _meta, stmts}, acc) when is_list(stmts) do
    Enum.reduce(stmts, acc, &collect_functions/2)
  end

  defp collect_functions({:container, _meta, children}, acc) when is_list(children) do
    Enum.reduce(children, acc, &collect_functions/2)
  end

  defp collect_functions({_type, _meta, children}, acc) when is_list(children) do
    Enum.reduce(children, acc, &collect_functions/2)
  end

  defp collect_functions(_, acc), do: acc

  # Find groups of functions with identical normalized AST
  defp find_duplicates(functions) do
    functions
    |> Enum.group_by(fn {_name, _line, body} -> fingerprint(body) end)
    |> Enum.filter(fn {_fp, group} -> length(group) > 1 end)
    |> Enum.map(fn {_fp, group} ->
      names = Enum.map(group, fn {name, _line, _body} -> to_string(name) end)
      line = group |> hd() |> elem(1)
      {names, line}
    end)
  end

  # Generate a structural fingerprint by normalizing variable names
  defp fingerprint(ast) do
    ast
    |> normalize_ast()
    |> :erlang.phash2()
  end

  # Normalize AST by replacing variable names with placeholders
  defp normalize_ast({:variable, meta, _name}), do: {:variable, meta, "_"}

  defp normalize_ast({type, meta, children}) when is_list(children) do
    {type, meta, Enum.map(children, &normalize_ast/1)}
  end

  defp normalize_ast(list) when is_list(list), do: Enum.map(list, &normalize_ast/1)
  defp normalize_ast(other), do: other

  # Count nodes in AST
  defp ast_size({_type, _meta, children}) when is_list(children),
    do: 1 + Enum.reduce(children, 0, fn c, acc -> acc + ast_size(c) end)

  defp ast_size(list) when is_list(list),
    do: Enum.reduce(list, 0, fn c, acc -> acc + ast_size(c) end)

  defp ast_size(_), do: 1
end
