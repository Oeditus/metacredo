defmodule MetaCredo.Check.Readability.LargeNumbers do
  use MetaCredo.Check,
    category: :readability,
    base_priority: :low,
    confidence: :high,
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

  # The smallest value that can benefit from underscore separators.
  @min_large 9999

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

    if large_unseparated_integer?(subtype, value, min_digits, meta, source_file) do
      line = CheckUtils.line_of(meta)

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

  defp large_unseparated_integer?(:integer, value, min_digits, meta, source_file) do
    abs(value) > @min_large and digit_count(value) >= min_digits and
      not has_separator?(meta, value, source_file)
  end

  defp large_unseparated_integer?(_subtype, _value, _min_digits, _meta, _source_file), do: false

  # `meta[:has_separator]` is not populated by every adapter, and the literal
  # `value` is the *normalized* integer -- `30_000` and `30000` both arrive as
  # `30000`. The original formatting must therefore be recovered from the
  # source text, otherwise correctly-separated numbers are reported.
  #
  # Integer literals frequently carry no `:line` metadata at all, so a
  # line-based lookup is not enough; fall back to scanning the whole source
  # for the separator-bearing spelling of this exact value.
  defp has_separator?(meta, value, %SourceFile{} = source_file) do
    Keyword.get(meta, :has_separator, false) or
      source_line_has_separator?(meta, source_file) or
      source_mentions_separated?(source_file, value)
  end

  defp has_separator?(_meta, _value, _source_file), do: false

  defp source_line_has_separator?(meta, source_file) do
    with line when is_integer(line) <- CheckUtils.line_of(meta),
         text when is_binary(text) <- SourceFile.line_at(source_file, line) do
      String.contains?(text, "_")
    else
      _ -> false
    end
  end

  defp source_mentions_separated?(%SourceFile{} = source_file, value) do
    case SourceFile.source(source_file) do
      source when is_binary(source) ->
        String.contains?(source, format_with_underscores(value))

      _ ->
        false
    end
  end

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
