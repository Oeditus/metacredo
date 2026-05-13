defmodule MetaCredo.Check.Readability.LargeNumbers do
  use MetaCredo.Check,
    category: :readability,
    base_priority: :low,
    param_defaults: [min_digits: 5],
    explanations: [
      check: """
      Detects large integer literals (> 9999) without underscore separators.
      Use underscores to improve readability of large numbers
      (e.g. `1_000_000` instead of `1000000`).
      """,
      params: [
        min_digits: "Minimum number of digits to trigger the check (default: 5)"
      ],
      examples: [
        elixir: [
          wrong: """
          # Hard to tell at a glance how large these numbers are
          @max_connections 100000
          @timeout_ms 86400000
          budget = 1250000
          """,
          correct: """
          # Underscore separators make magnitude immediately obvious
          @max_connections 100_000
          @timeout_ms 86_400_000
          budget = 1_250_000
          """
        ]
      ]
    ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    min_digits = params_get(params, :min_digits)

    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc ->
        traverse(node, acc, source_file, min_digits)
      end)

    issues
  end

  defp traverse({:literal, meta, value} = node, issues, source_file, min_digits)
       when is_list(meta) and is_integer(value) do
    subtype = Keyword.get(meta, :subtype)
    has_separator = Keyword.get(meta, :has_separator, false)

    if subtype == :integer and abs(value) > 9999 and not has_separator and
         digit_count(value) >= min_digits do
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message:
            "Large number #{value} should use underscore separators for readability (e.g. #{format_with_underscores(value)})",
          trigger: to_string(value),
          line_no: line
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _sf, _min), do: {node, issues}

  defp digit_count(value) do
    value |> abs() |> Integer.to_string() |> String.length()
  end

  defp format_with_underscores(value) when value < 0 do
    "-" <> format_with_underscores(abs(value))
  end

  defp format_with_underscores(value) do
    value
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/.{3}(?=.)/, "\\0_")
    |> String.reverse()
  end
end
