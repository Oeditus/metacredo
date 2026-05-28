defmodule MetaCredo.Check.Warning.UnsafeExec do
  use MetaCredo.Check,
    category: :warning,
    base_priority: :high,
    explanations: [
      check: """
      Detects `System.cmd`, `os:cmd`, `:os.cmd`, or similar execution calls
      with user-controlled arguments. Passing user input to system commands
      can lead to command injection vulnerabilities.

      Use allow-lists, sanitize inputs, or avoid shelling out entirely.
      """,
      examples: [
        elixir: [
          wrong: """
          # Attacker can inject shell commands via `user_input`
          def render_pdf(user_input) do
            System.cmd("pandoc", [user_input, "-o", "output.pdf"])
          end
          """,
          correct: """
          # Validate input against an allow-list and use separate args (no shell)
          @allowed_formats ~w(markdown rst)

          def render_pdf(format) when format in @allowed_formats do
            System.cmd("pandoc", ["input." <> format, "-o", "output.pdf"])
          end

          def render_pdf(_), do: {:error, :invalid_format}
          """
        ]
      ]
    ]

  @exec_patterns ~W(cmd exec system eval shell)

  @user_input_patterns ~W(
    input param query body user request
    params args argv payload data
  )

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc -> traverse(node, acc, source_file) end)

    issues
  end

  defp traverse(
         {:function_call, meta, args} = node,
         issues,
         source_file
       )
       when is_list(meta) and is_list(args) do
    fn_name = CheckUtils.safe_name(meta)
    fn_lower = String.downcase(fn_name)

    if exec_function?(fn_lower) and has_user_input_arg?(args) do
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message:
            "Unsafe exec '#{fn_name}' with user-controlled argument -- risk of command injection",
          trigger: fn_name,
          line_no: line
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _source_file), do: {node, issues}

  defp exec_function?(fn_lower) do
    Enum.any?(@exec_patterns, &String.contains?(fn_lower, &1))
  end

  defp has_user_input_arg?(args) do
    Enum.any?(args, &user_input_node?/1)
  end

  defp user_input_node?({:variable, _meta, name}) when is_binary(name) do
    lower = String.downcase(name)
    Enum.any?(@user_input_patterns, &String.contains?(lower, &1))
  end

  defp user_input_node?({_type, _meta, children}) when is_list(children) do
    Enum.any?(children, &user_input_node?/1)
  end

  defp user_input_node?(_), do: false
end
