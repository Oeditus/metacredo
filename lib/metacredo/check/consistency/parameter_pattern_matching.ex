defmodule MetaCredo.Check.Consistency.ParameterPatternMatching do
  use MetaCredo.Check,
    category: :consistency,
    base_priority: :low,
    explanations: [
      check: """
      Detects functions that destructure data in the body when they could
      destructure directly in the parameters. Pattern matching in function
      heads is more idiomatic and clearly communicates intent.

      For example, prefer `def foo(%{name: name})` over
      `def foo(map) do name = map.name end`.
      """
    ]

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc -> traverse(node, acc, source_file) end)

    issues
  end

  defp traverse(
         {:function_def, meta, children} = node,
         issues,
         source_file
       )
       when is_list(meta) and is_list(children) do
    name = Keyword.get(meta, :name, "anonymous")
    params = Keyword.get(meta, :params, [])
    param_names = extract_param_names(params)

    body_destructures = find_body_destructures(children, param_names)

    if body_destructures != [] do
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message:
            "Function '#{name}' destructures parameters in the body -- prefer pattern matching in function head",
          trigger: to_string(name),
          line_no: line
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _source_file), do: {node, issues}

  defp extract_param_names(params) when is_list(params) do
    Enum.flat_map(params, fn
      {:param, _meta, name} when is_binary(name) -> [name]
      {:variable, _meta, name} when is_binary(name) -> [name]
      _ -> []
    end)
  end

  defp extract_param_names(_), do: []

  # Find assignments in the body that destructure a parameter
  defp find_body_destructures(children, param_names) when is_list(children) do
    Enum.flat_map(children, &find_body_destructures(&1, param_names))
  end

  defp find_body_destructures(
         {:assignment, _meta,
          [
            _pattern,
            {:function_call, call_meta, [{:variable, _, var_name} | _]}
          ]},
         param_names
       )
       when is_list(call_meta) do
    fn_name = to_string(Keyword.get(call_meta, :name, ""))

    if var_name in param_names and field_access?(fn_name) do
      [var_name]
    else
      []
    end
  end

  # Match: name = param.field (dot access as binary_op or member_access)
  defp find_body_destructures(
         {:assignment, _meta,
          [
            _pattern,
            {:member_access, _ma_meta, [{:variable, _, var_name} | _]}
          ]},
         param_names
       ) do
    if var_name in param_names, do: [var_name], else: []
  end

  defp find_body_destructures({_type, _meta, children}, param_names)
       when is_list(children) do
    Enum.flat_map(children, &find_body_destructures(&1, param_names))
  end

  defp find_body_destructures(_, _param_names), do: []

  defp field_access?(fn_name) do
    String.contains?(fn_name, ".") or fn_name in ~W(Map.get Map.fetch! elem get_in)
  end
end
