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

  @doc """
  Prints explanation for a check module.

  When `issue` is provided (typically from a `file:lineno` invocation), the
  relevant code snippet is shown first, ±3 lines around the flagged line.

  `language` controls which language-keyed examples entry is rendered.
  When `nil`, the examples section is omitted entirely.
  """
  @spec print_explanation(module(), MetaCredo.Issue.t() | nil, atom() | nil) :: :ok
  def print_explanation(check_module, issue \\ nil, language \\ nil) do
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

    print_code_snippet(issue)

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

      if language do
        if examples = Keyword.get(explanations, :examples) do
          print_examples(examples, language)
        end
      end
    end

    IO.puts("")
    :ok
  end

  # -- Private --

  # Renders ±3 lines of context around the flagged line from the issue's file.
  # The flagged line is highlighted in yellow with a `>>` pointer; surrounding
  # lines are dimmed. Does nothing when no issue or line info is available.
  defp print_code_snippet(%{filename: filename, line_no: line_no})
       when is_binary(filename) and is_integer(line_no) do
    case File.read(filename) do
      {:ok, source} ->
        lines = source |> String.split("\n") |> Enum.with_index(1)
        from = max(1, line_no - 3)
        to = line_no + 3
        context = Enum.filter(lines, fn {_l, n} -> n >= from and n <= to end)

        IO.puts("")
        IO.puts(colorize("    CODE IN QUESTION", :bright))
        IO.puts("")
        IO.puts("      " <> colorize("#{filename}:#{line_no}", :faint))
        IO.puts("")

        Enum.each(context, fn {line, n} ->
          num = String.pad_leading(to_string(n), 4)

          if n == line_no do
            IO.puts(colorize("    >> #{num}\u2502 #{line}", :yellow))
          else
            IO.puts(IO.ANSI.faint() <> "       #{num}\u2502 #{line}" <> IO.ANSI.reset())
          end
        end)

      {:error, _} ->
        :ok
    end
  end

  defp print_code_snippet(_), do: :ok

  # Renders the :examples section from a check's explanations keyword list.
  # Expects `examples` to be a keyword list keyed by language atom, each value
  # being a keyword list with optional :wrong and :correct keys, e.g.:
  #
  #   examples: [
  #     elixir: [
  #       wrong: "value |> String.upcase()",
  #       correct: "String.upcase(value)"
  #     ],
  #     erlang: [
  #       wrong: "string:to_upper(Value)",
  #       correct: "string:uppercase(Value)"
  #     ]
  #   ]
  #
  # If no entry exists for `language`, the section is omitted.
  defp print_examples(examples, language) do
    case Keyword.get(examples, language) do
      nil ->
        :ok

      lang_examples ->
        wrong = Keyword.get(lang_examples, :wrong)
        correct = Keyword.get(lang_examples, :correct)

        if wrong || correct do
          IO.puts("")
          IO.puts(colorize("    EXAMPLES", :bright))
          lang_str = to_string(language)

          if wrong do
            IO.puts("")
            IO.puts(colorize("      Wrong:", :red))
            IO.puts("")
            render_code_snippet(wrong, lang_str)
          end

          if correct do
            IO.puts("")
            IO.puts(colorize("      Correct:", :green))
            IO.puts("")
            render_code_snippet(correct, lang_str)
          end
        end
    end
  end

  # Syntax-highlights `code` as `lang` via Marcli and prints each line with
  # six spaces of indentation.
  defp render_code_snippet(code, lang) do
    md = "```#{lang}\n#{String.trim(code)}\n```\n"

    md
    |> Marcli.render()
    |> String.split("\n")
    |> Enum.each(&IO.puts("      " <> &1))
  end

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
