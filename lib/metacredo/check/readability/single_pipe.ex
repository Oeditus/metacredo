defmodule MetaCredo.Check.Readability.SinglePipe do
  use MetaCredo.Check,
    category: :readability,
    base_priority: :low,
    explanations: [
      check: """
      Detects single-step pipe chains (`value |> func`). A single pipe
      adds visual noise without improving readability -- use a direct
      function call instead.
      """
    ]

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    source_file
    |> SourceFile.ast()
    |> find_single_pipes(source_file, [])
  end

  # When we encounter a pipe, measure the full chain and skip into non-pipe children
  defp find_single_pipes({:pipe, meta, _children} = node, source_file, acc)
       when is_list(meta) do
    chain_len = pipe_chain_length(node)

    acc =
      if chain_len == 1 do
        line = Keyword.get(meta, :line)

        issue =
          format_issue(source_file,
            message: "Single-step pipe chain -- use a direct function call instead",
            trigger: "|>",
            line_no: line
          )

        [issue | acc]
      else
        acc
      end

    # Recurse into non-pipe leaf nodes of the chain
    node
    |> collect_non_pipe_children()
    |> Enum.reduce(acc, fn child, inner_acc ->
      find_single_pipes(child, source_file, inner_acc)
    end)
  end

  defp find_single_pipes({_type, _meta, children}, source_file, acc) when is_list(children) do
    Enum.reduce(children, acc, fn child, inner_acc ->
      find_single_pipes(child, source_file, inner_acc)
    end)
  end

  defp find_single_pipes(list, source_file, acc) when is_list(list) do
    Enum.reduce(list, acc, fn child, inner_acc ->
      find_single_pipes(child, source_file, inner_acc)
    end)
  end

  defp find_single_pipes(_other, _source_file, acc), do: acc

  defp pipe_chain_length({:pipe, _meta, [left, _right]}) do
    1 + pipe_chain_length(left)
  end

  defp pipe_chain_length(_), do: 0

  # Collect all non-pipe children from a pipe chain
  defp collect_non_pipe_children({:pipe, _meta, [left, right]}) do
    collect_non_pipe_children(left) ++ [right]
  end

  defp collect_non_pipe_children(node), do: [node]
end
