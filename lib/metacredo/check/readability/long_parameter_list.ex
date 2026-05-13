defmodule MetaCredo.Check.Readability.LongParameterList do
  use MetaCredo.Check,
    category: :readability,
    base_priority: :normal,
    param_defaults: [max_params: 5],
    explanations: [
      check: """
      Detects functions with too many parameters. Long parameter lists are
      hard to remember and use correctly. Consider grouping related parameters
      into a struct, map, or keyword list.
      """,
      params: [
        max_params: "Maximum allowed parameters per function (default: 5)"
      ]
    ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    max_params = params_get(params, :max_params)

    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc ->
        traverse(node, acc, source_file, max_params)
      end)

    issues
  end

  defp traverse({:function_def, meta, _children} = node, issues, source_file, max_params)
       when is_list(meta) do
    name = Keyword.get(meta, :name, "anonymous")
    param_list = Keyword.get(meta, :params, [])
    param_count = length(param_list)

    if param_count > max_params do
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message:
            "Function '#{name}' has #{param_count} parameters (max allowed: #{max_params}) -- consider grouping into a struct or map",
          trigger: to_string(name),
          line_no: line
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _sf, _max), do: {node, issues}
end
