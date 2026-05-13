defmodule MetaCredo.Check.Readability.DeepNesting do
  use MetaCredo.Check,
    category: :readability,
    base_priority: :normal,
    param_defaults: [max_nesting: 4],
    explanations: [
      check: """
      Detects functions with nesting depth exceeding a threshold.
      Deeply nested code (conditionals inside loops inside conditionals, etc.)
      is harder to understand and should be refactored into smaller functions.
      """,
      params: [
        max_nesting: "Maximum allowed nesting depth (default: 4)"
      ],
      examples: [
        wrong: """
        def handle(conn, params) do
          if authenticated?(conn) do
            case fetch_resource(params) do
              {:ok, resource} ->
                if authorized?(conn, resource) do
                  case validate(resource) do
                    :ok -> render(conn, resource)
                    {:error, reason} -> error(conn, reason)
                  end
                else
                  forbidden(conn)
                end
              {:error, _} -> not_found(conn)
            end
          else
            unauthorized(conn)
          end
        end
        """,
        correct: """
        def handle(conn, params) do
          with :ok <- check_auth(conn),
               {:ok, resource} <- fetch_resource(params),
               :ok <- check_authz(conn, resource),
               :ok <- validate(resource) do
            render(conn, resource)
          end
        end

        defp check_auth(conn), do: if authenticated?(conn), do: :ok, else: {:error, :unauthorized}
        defp check_authz(conn, res), do: if authorized?(conn, res), do: :ok, else: {:error, :forbidden}
        """
      ]
    ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    max_nesting = params_get(params, :max_nesting)

    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc ->
        traverse(node, acc, source_file, max_nesting)
      end)

    issues
  end

  defp traverse({:function_def, meta, children} = node, issues, source_file, max_nesting)
       when is_list(meta) do
    name = Keyword.get(meta, :name, "anonymous")
    depth = max_depth(children, 0)

    if depth > max_nesting do
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message: "Function '#{name}' has nesting depth #{depth} (max allowed: #{max_nesting})",
          trigger: to_string(name),
          line_no: line
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _sf, _max), do: {node, issues}

  # Calculate max nesting depth in an AST subtree
  defp max_depth({:conditional, _meta, branches}, current) when is_list(branches) do
    branches
    |> Enum.map(&max_depth(&1, current + 1))
    |> Enum.max(fn -> current end)
  end

  defp max_depth({:loop, _meta, children}, current) when is_list(children) do
    children
    |> Enum.map(&max_depth(&1, current + 1))
    |> Enum.max(fn -> current end)
  end

  defp max_depth({:exception_handling, _meta, children}, current) when is_list(children) do
    children
    |> Enum.map(&max_depth(&1, current + 1))
    |> Enum.max(fn -> current end)
  end

  defp max_depth({:pattern_match, _meta, [_scrutinee | arms]}, current) when is_list(arms) do
    arms
    |> Enum.map(&max_depth(&1, current + 1))
    |> Enum.max(fn -> current end)
  end

  defp max_depth({:lambda, _meta, children}, current) when is_list(children) do
    children
    |> Enum.map(&max_depth(&1, current + 1))
    |> Enum.max(fn -> current end)
  end

  defp max_depth({:block, _meta, stmts}, current) when is_list(stmts) do
    stmts
    |> Enum.map(&max_depth(&1, current))
    |> Enum.max(fn -> current end)
  end

  defp max_depth({_type, _meta, children}, current) when is_list(children) do
    children
    |> Enum.map(&max_depth(&1, current))
    |> Enum.max(fn -> current end)
  end

  defp max_depth(list, current) when is_list(list) do
    list
    |> Enum.map(&max_depth(&1, current))
    |> Enum.max(fn -> current end)
  end

  defp max_depth(_, current), do: current
end
