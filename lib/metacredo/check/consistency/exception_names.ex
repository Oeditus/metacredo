defmodule MetaCredo.Check.Consistency.ExceptionNames do
  use MetaCredo.Check,
    category: :consistency,
    base_priority: :normal,
    explanations: [
      check: """
      Detects exception or error container names that do not end in "Error"
      or "Exception". Consistent naming makes it easier to identify error
      types at a glance.

      For example, `InvalidInput` should be `InvalidInputError`.
      """
    ]

  @error_indicators ~w(
    invalid unauthorized forbidden
    not_found timeout conflict
    unavailable bad failed
    missing malformed rejected
    denied expired overflow
    underflow violation fault
  )

  @valid_suffixes ["Error", "Exception"]

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc -> traverse(node, acc, source_file) end)

    issues
  end

  defp traverse(
         {:container, meta, _children} = node,
         issues,
         source_file
       )
       when is_list(meta) do
    container_type = Keyword.get(meta, :container_type)
    name = to_string(Keyword.get(meta, :name, ""))

    if container_type == :class and suggests_error?(name) and not has_valid_suffix?(name) do
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message:
            "Exception container '#{name}' should end in 'Error' or 'Exception' for consistency",
          trigger: name,
          line_no: line
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _source_file), do: {node, issues}

  defp suggests_error?(name) do
    lower = name |> String.replace(~r/([A-Z])/, " \\1") |> String.downcase() |> String.trim()
    Enum.any?(@error_indicators, &String.contains?(lower, &1))
  end

  defp has_valid_suffix?(name) do
    Enum.any?(@valid_suffixes, &String.ends_with?(name, &1))
  end
end
