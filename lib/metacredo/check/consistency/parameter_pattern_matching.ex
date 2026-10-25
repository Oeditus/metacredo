defmodule MetaCredo.Check.Consistency.ParameterPatternMatching do
  use MetaCredo.Check,
    category: :consistency,
    base_priority: :low,
    confidence: :low,
    tags: [:user_input],
    explanations: [
      check: """
      Detects functions that destructure data in the body when they could
      destructure directly in the parameters. Pattern matching in function
      heads is more idiomatic and clearly communicates intent.

      For example, prefer `def foo(%{name: name})` over
      `def foo(map) do name = map.name end`.
      """,
      examples: [
        elixir: [
          wrong: """
          # Destructuring deferred to the body -- intent is buried
          def greet(user) do
            name = user.name
            role = user.role
            "Hello \#{name} (\#{role})"
          end
          """,
          correct: """
          # Shape of the input is explicit in the function head
          def greet(%{name: name, role: role}) do
            "Hello \#{name} (\#{role})"
          end
          """
        ]
      ]
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

    # Parameters already pattern-matched in the head (`%SourceFile{} = sf`)
    # need no further destructuring, so they are excluded entirely.
    param_names =
      params
      |> extract_param_names()
      |> Enum.uniq()

    body_destructures = find_body_destructures(children, param_names)

    if body_destructures != [] do
      line = CheckUtils.line_of(meta)

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

  # Find assignments in the body that destructure a parameter.
  #
  # Metastatic represents both `x = expr` and Elixir's own `user.name` field
  # access as `:inline_match` / `Map.fetch!` nodes, so both shapes must be
  # recognised -- matching only `:assignment` silently missed every real
  # Elixir function.
  #
  # The adapter cannot distinguish `user.name` from the remote call
  # `user.name()` (both become `Map.fetch!(user, :name)`), so a bare field
  # read is only reported when the assignment target *differs* from the
  # field -- i.e. it is genuine destructuring rather than a same-name read.
  defp find_body_destructures(children, param_names) when is_list(children) do
    Enum.flat_map(children, &find_body_destructures(&1, param_names))
  end

  defp find_body_destructures({:inline_match, _meta, [pattern, value]}, param_names),
    do: destructure_source(pattern, value, param_names)

  defp find_body_destructures({:assignment, _meta, [pattern, value]}, param_names),
    do: destructure_source(pattern, value, param_names)

  defp find_body_destructures({_type, _meta, children}, param_names)
       when is_list(children) do
    Enum.flat_map(children, &find_body_destructures(&1, param_names))
  end

  defp find_body_destructures(_, _param_names), do: []

  # `check_module.category()` is emitted identically to `check_module.category`;
  # the adapter loses the distinction. Two guards keep the signal meaningful:
  #
  #   1. the field must look like a struct attribute (short, single lowercase
  #      word) -- `param_defaults` is compound, so it is a function name; and
  #   2. the receiver must not be named like a module/behaviour holder
  #      (`check_module`, `mod`, `repo`), which is conventionally called rather
  #      than read field-by-field.
  defp destructure_source(
         {:variable, _, _target},
         {:function_call, call_meta, [{:variable, _, var_name}, {:literal, _, key} | rest]},
         param_names
       )
       when is_list(call_meta) do
    fn_name = to_string(Keyword.get(call_meta, :name, ""))

    if rest == [] and field_destructure?(fn_name, key, var_name, param_names),
      do: [var_name],
      else: []
  end

  defp destructure_source(
         {:variable, _, _target},
         {:member_access, meta, [{:variable, _, var_name} | _]},
         param_names
       )
       when is_list(meta) do
    field = Keyword.get(meta, :field, "")

    if var_name in param_names and field_like?(field),
      do: [var_name],
      else: []
  end

  defp destructure_source(_pattern, _value, _param_names), do: []

  # A struct/map field is a short, single-word, lowercase identifier.
  # `param_defaults` and `has_upload_param` are compound, so they are treated
  # as function names instead.
  @max_field_len 12

  defp field_like?(field) do
    field = to_string(field)

    byte_size(field) <= @max_field_len and not String.contains?(field, "_") and
      String.match?(field, ~r/^[a-z][a-z0-9]*$/)
  end

  # `Map.fetch!(recv, :field)` is how the Elixir adapter encodes `recv.field`.
  defp field_read?(fn_name, key) do
    fn_name in ~W(Map.fetch! Map.fetch) and is_atom(key)
  end

  # A parameter named like a module/behaviour holder is called, not read.
  @module_holder_suffixes ~W(module mod repo schema behaviour behavior)

  defp module_holder?(name) do
    name = String.downcase(name)
    Enum.any?(@module_holder_suffixes, &String.contains?(name, &1))
  end

  defp field_destructure?(fn_name, key, var_name, param_names) do
    var_name in param_names and field_read?(fn_name, key) and field_like?(key) and
      not module_holder?(var_name)
  end
end
