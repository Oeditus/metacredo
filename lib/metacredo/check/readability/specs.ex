defmodule MetaCredo.Check.Readability.Specs do
  use MetaCredo.Check,
    category: :readability,
    base_priority: :normal,
    explanations: [
      check: """
      Detects public functions without a preceding `@spec` type annotation.
      Typespecs improve documentation, enable Dialyzer analysis, and make
      function contracts explicit.
      """,
      examples: [
        elixir: [
          wrong: """
          # No spec -- callers can't tell what types are accepted or returned
          def calculate_discount(price, rate) do
            price * (1 - rate)
          end
          """,
          correct: """
          @spec calculate_discount(number(), float()) :: float()
          def calculate_discount(price, rate) do
            price * (1 - rate)
          end
          """
        ]
      ]
    ]

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    source_file
    |> SourceFile.ast()
    |> collect_issues(source_file)
  end

  defp collect_issues(ast, source_file) do
    {_, issues} =
      AST.prewalk(ast, [], fn node, acc ->
        traverse(node, acc, source_file)
      end)

    issues
  end

  # Check containers (modules) for function_defs preceded by type_annotations
  defp traverse({:container, _meta, children} = node, issues, source_file)
       when is_list(children) do
    new_issues = check_children(children, source_file)
    {node, new_issues ++ issues}
  end

  defp traverse(node, issues, _sf), do: {node, issues}

  defp check_children(children, source_file) do
    check_sequential(children, false, source_file, [])
  end

  defp check_sequential([], _spec_seen, _source_file, acc), do: acc

  defp check_sequential(
         [{:type_annotation, meta, _children} | rest],
         _spec_seen,
         source_file,
         acc
       )
       when is_list(meta) do
    is_spec = Keyword.get(meta, :annotation_type) == :spec
    check_sequential(rest, is_spec, source_file, acc)
  end

  defp check_sequential(
         [{:function_def, meta, _children} | rest],
         spec_seen,
         source_file,
         acc
       )
       when is_list(meta) do
    visibility = Keyword.get(meta, :visibility, :public)

    acc =
      if visibility == :public and not spec_seen do
        name = Keyword.get(meta, :name, "anonymous")
        line = Keyword.get(meta, :line)

        issue =
          format_issue(source_file,
            message: "Public function '#{name}' has no @spec",
            trigger: to_string(name),
            line_no: line
          )

        [issue | acc]
      else
        acc
      end

    check_sequential(rest, false, source_file, acc)
  end

  defp check_sequential([_ | rest], _spec_seen, source_file, acc) do
    check_sequential(rest, false, source_file, acc)
  end
end
