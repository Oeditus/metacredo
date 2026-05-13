defmodule MetaCredo.Check.Design.LowCohesion do
  use MetaCredo.Check,
    category: :design,
    base_priority: :normal,
    param_defaults: [min_functions: 3, max_disjoint_groups: 2],
    explanations: [
      check: """
      Detects modules where functions don't share data or variables,
      indicating the module lacks cohesion and may have multiple
      responsibilities. Consider splitting into focused modules.

      Functions are grouped by the variables they reference. If the number
      of disjoint groups exceeds the threshold, the module has low cohesion.
      """,
      params: [
        min_functions:
          "Minimum number of functions in a module before checking cohesion (default: 3)",
        max_disjoint_groups: "Maximum allowed disjoint function groups (default: 2)"
      ],
      examples: [
        elixir: [
          wrong: """
          # Three completely unrelated responsibilities in one module
          defmodule Utils do
            def format_date(date), do: ...
            def parse_date(str), do: ...
            def charge_card(amount, token), do: ...
            def send_welcome_email(user), do: ...
          end
          """,
          correct: """
          # Each module has a single focused responsibility
          defmodule DateFormatter do
            def format(date), do: ...
            def parse(str), do: ...
          end

          defmodule Billing do
            def charge(amount, token), do: ...
          end

          defmodule Mailer do
            def send_welcome(user), do: ...
          end
          """
        ]
      ]
    ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    min_functions = params_get(params, :min_functions)
    max_groups = params_get(params, :max_disjoint_groups)

    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc ->
        traverse(node, acc, source_file, min_functions, max_groups)
      end)

    issues
  end

  # Check container nodes (modules/classes)
  defp traverse({:container, meta, children} = node, issues, source_file, min_fns, max_groups)
       when is_list(meta) and is_list(children) do
    name = Keyword.get(meta, :name, "anonymous")
    functions = extract_functions(children)

    if length(functions) >= min_fns do
      groups = count_disjoint_groups(functions)

      if groups > max_groups do
        line = Keyword.get(meta, :line)

        issue =
          format_issue(source_file,
            message:
              "Module '#{name}' has #{groups} disjoint function groups (max: #{max_groups}) -- consider splitting into focused modules",
            trigger: to_string(name),
            line_no: line,
            metadata: %{disjoint_groups: groups}
          )

        {node, [issue | issues]}
      else
        {node, issues}
      end
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _sf, _mf, _mg), do: {node, issues}

  defp extract_functions(children) when is_list(children) do
    Enum.flat_map(children, fn
      {:function_def, meta, body} when is_list(meta) ->
        name = Keyword.get(meta, :name, "anonymous")
        vars = collect_variables(body, MapSet.new())
        [{name, vars}]

      _ ->
        []
    end)
  end

  # Collect all variable references in a subtree
  defp collect_variables({:variable, _meta, name}, acc), do: MapSet.put(acc, name)

  defp collect_variables({:attribute_access, _meta, [{:variable, _, obj}, attr]}, acc)
       when obj in ["self", "this", "@"] do
    MapSet.put(acc, attr)
  end

  defp collect_variables({_type, _meta, children}, acc) when is_list(children),
    do: Enum.reduce(children, acc, &collect_variables/2)

  defp collect_variables(list, acc) when is_list(list),
    do: Enum.reduce(list, acc, &collect_variables/2)

  defp collect_variables(_, acc), do: acc

  # Count disjoint groups using union-find on shared variables
  defp count_disjoint_groups(functions) do
    indexed = Enum.with_index(functions)
    n = length(functions)

    # Initialize union-find
    uf = Map.new(0..(n - 1), fn i -> {i, i} end)

    # Union functions that share variables
    uf =
      for {{_name1, vars1}, i} <- indexed,
          {{_name2, vars2}, j} <- indexed,
          i < j,
          MapSet.size(MapSet.intersection(vars1, vars2)) > 0,
          reduce: uf do
        acc -> union(acc, i, j)
      end

    # Count distinct roots
    0..(n - 1)
    |> Enum.map(&find(uf, &1))
    |> Enum.uniq()
    |> length()
  end

  defp find(uf, i) do
    parent = Map.get(uf, i, i)
    if parent == i, do: i, else: find(uf, parent)
  end

  defp union(uf, i, j) do
    ri = find(uf, i)
    rj = find(uf, j)
    if ri != rj, do: Map.put(uf, ri, rj), else: uf
  end
end
