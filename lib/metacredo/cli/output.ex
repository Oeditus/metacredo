defmodule MetaCredo.CLI.Output do
  @moduledoc """
  Terminal output formatting for MetaCredo analysis results.
  """

  @category_colors %{
    consistency: :cyan,
    design: :green,
    readability: :blue,
    refactor: :yellow,
    warning: :red,
    security: :red,
    performance: :magenta,
    observability: :cyan
  }

  @category_labels %{
    consistency: "[C]",
    design: "[D]",
    readability: "[R]",
    refactor: "[F]",
    warning: "[W]",
    security: "[S]",
    performance: "[P]",
    observability: "[O]"
  }

  @doc "Prints the full analysis report to stdout."
  @spec print_report(map()) :: :ok
  def print_report(report) do
    %{
      issues: issues,
      summary: summary,
      timing_ms: timing,
      source_files: files,
      checks_run: checks
    } = report

    file_count = length(files)
    check_count = length(checks)

    IO.puts("Checking #{file_count} source files ...")
    IO.puts("")

    if issues == [] do
      print_footer(file_count, check_count, timing, summary)
    else
      issues
      |> Enum.group_by(& &1.filename)
      |> Enum.sort()
      |> Enum.each(&print_file_issues/1)

      print_footer(file_count, check_count, timing, summary)
    end

    :ok
  end

  @doc "Formats issues as JSON string."
  @spec to_json(map()) :: String.t()
  def to_json(%{issues: issues, summary: summary, timing_ms: timing}) do
    data = %{
      issues:
        Enum.map(issues, fn i ->
          %{
            check: to_string(i.check),
            category: i.category,
            severity: i.severity,
            priority: i.priority,
            message: i.message,
            filename: i.filename,
            line_no: i.line_no,
            column: i.column,
            trigger: i.trigger
          }
        end),
      summary: summary,
      timing_ms: timing
    }

    :json.encode(data) |> IO.iodata_to_binary()
  end

  @doc "Prints explanation for a check module."
  @spec print_explanation(module()) :: :ok
  def print_explanation(check_module) do
    IO.puts("")
    IO.puts(colorize("  #{inspect(check_module)}", :bright))

    if function_exported?(check_module, :category, 0) do
      cat = check_module.category()
      label = Map.get(@category_labels, cat, "[?]")
      color = Map.get(@category_colors, cat, :default)
      IO.puts(colorize("  #{label} Category: #{cat}", color))
    end

    if function_exported?(check_module, :base_priority, 0) do
      IO.puts("    Priority: #{check_module.base_priority()}")
    end

    if function_exported?(check_module, :explanations, 0) do
      explanations = check_module.explanations()

      if check_text = Keyword.get(explanations, :check) do
        IO.puts("")
        IO.puts(colorize("    WHY IT MATTERS", :bright))
        IO.puts("")

        check_text
        |> String.split("\n")
        |> Enum.each(&IO.puts("      #{&1}"))
      end

      if params = Keyword.get(explanations, :params) do
        IO.puts("")
        IO.puts(colorize("    CONFIGURATION OPTIONS", :bright))
        IO.puts("")

        Enum.each(params, fn {key, desc} ->
          IO.puts("      #{key}: #{desc}")
        end)
      end
    end

    IO.puts("")
    :ok
  end

  # -- Private --

  defp print_file_issues({filename, issues}) do
    IO.puts(colorize("  #{filename}", :bright))

    Enum.each(issues, fn issue ->
      cat = issue.category
      color = Map.get(@category_colors, cat, :default)
      label = Map.get(@category_labels, cat, "[?]")

      line_info = if issue.line_no, do: ":#{issue.line_no}", else: ""
      col_info = if issue.column, do: ":#{issue.column}", else: ""

      IO.puts(
        "    #{colorize(label, color)} " <>
          colorize("#{line_info}#{col_info}", :faint) <>
          " #{issue.message}" <>
          trigger_suffix(issue.trigger) <>
          check_suffix(issue.check)
      )
    end)

    IO.puts("")
  end

  defp trigger_suffix(nil), do: ""
  defp trigger_suffix(trigger), do: colorize(" (#{trigger})", :faint)

  defp check_suffix(nil), do: ""

  defp check_suffix(check_module) when is_atom(check_module) do
    short = check_module |> inspect() |> String.split(".") |> List.last()
    colorize(" [#{short}]", :faint)
  end

  defp check_suffix(_), do: ""

  defp print_footer(file_count, check_count, timing, summary) do
    timing_s = if timing, do: Float.round(timing / 1000, 1), else: 0.0
    total = summary.total

    IO.puts("")

    IO.puts(
      "Analysis took #{timing_s} seconds (running #{check_count} checks on #{file_count} files)"
    )

    if total == 0 do
      IO.puts(colorize("#{file_count} source files, found no issues.", :green))
    else
      IO.puts(
        "#{file_count} source files, found #{total} issue#{if total == 1, do: "", else: "s"}."
      )

      IO.puts("")
      IO.puts(colorize("  Summary:", :bright))

      Enum.each(summary.by_category, fn {cat, count} ->
        color = Map.get(@category_colors, cat, :default)
        label = Map.get(@category_labels, cat, "[?]")
        IO.puts("    #{colorize(label, color)} #{cat}: #{count}")
      end)
    end

    IO.puts("")

    IO.puts(
      "Showing priority issues: " <>
        colorize("^", :red) <>
        " " <>
        colorize("^", :yellow) <>
        " " <>
        colorize(">", :blue) <>
        "  (use `mix metacredo explain` to explain issues, `mix metacredo --help` for options)."
    )
  end

  defp colorize(text, :bright), do: IO.ANSI.bright() <> text <> IO.ANSI.reset()
  defp colorize(text, :faint), do: IO.ANSI.faint() <> text <> IO.ANSI.reset()
  defp colorize(text, color), do: apply(IO.ANSI, color, []) <> text <> IO.ANSI.reset()
end
