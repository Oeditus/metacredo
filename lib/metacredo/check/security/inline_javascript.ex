defmodule MetaCredo.Check.Security.InlineJavascript do
  use MetaCredo.Check,
    category: :security,
    base_priority: :high,
    explanations: [
      check: """
      Detects inline executable code in templates/strings (XSS/injection risk).

      Identifies patterns where inline JavaScript handlers (onclick, onerror),
      script tags, dangerouslySetInnerHTML, or similar dangerous patterns appear
      in string literals. Prefer CSP-compliant external scripts or phx-*
      bindings in Phoenix.
      """,
      params: [],
      examples: [
        elixir: [
          wrong: """
          # Inline event handlers are an XSS vector and violate CSP
          html = "<button onclick=\"doThing()\">Click</button>"
          send_resp(conn, 200, html)
          """,
          correct: """
          # Use Phoenix LiveView bindings -- no inline JS needed
          # In a .heex template:
          #   <button phx-click="do_thing">Click</button>
          # External JS attaches behaviour via event listeners on data attributes,
          # keeping markup CSP-safe and event handlers out of the HTML string.
          """
        ]
      ]
    ]

  @dangerous_patterns [
    "<script>",
    "</script>",
    "dangerouslysetinnerhtml",
    "html.raw",
    "javascript:",
    "onclick=",
    "onerror="
  ]

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    ast = SourceFile.ast(source_file)
    doc_strings = CheckUtils.doc_string_contents(ast)

    {_, issues} =
      AST.prewalk(ast, [], fn node, acc -> traverse(node, acc, source_file, doc_strings) end)

    issues
  end

  # Detect string literals containing inline script patterns
  defp traverse({:literal, meta, content} = node, issues, source_file, doc_strings)
       when is_list(meta) and is_binary(content) do
    if Keyword.get(meta, :subtype) == :string and
         not MapSet.member?(doc_strings, content) do
      content_lower = String.downcase(content)

      if Enum.any?(@dangerous_patterns, &String.contains?(content_lower, &1)) do
        line = Keyword.get(meta, :line)

        {node,
         [
           format_issue(source_file,
             message: "Inline JavaScript in string literal -- XSS vulnerability",
             trigger: truncate(content),
             line_no: line,
             severity: :error,
             metadata: %{pattern: :inline_script}
           )
           | issues
         ]}
      else
        {node, issues}
      end
    else
      {node, issues}
    end
  end

  # Detect dangerous function calls
  defp traverse({:function_call, meta, args} = node, issues, source_file, _doc_strings)
       when is_list(meta) do
    fn_name = Keyword.get(meta, :name, "")
    fn_lower = String.downcase(fn_name)

    cond do
      String.contains?(fn_lower, [
        "dangerouslysetinnerhtml",
        "html.raw",
        "javascript_tag"
      ]) ->
        line = Keyword.get(meta, :line)

        {node,
         [
           format_issue(source_file,
             message: "Using '#{fn_name}' to inject HTML/JS -- potential XSS vulnerability",
             trigger: fn_name,
             line_no: line,
             severity: :error,
             metadata: %{function: fn_name}
           )
           | issues
         ]}

      has_script_in_args?(args) ->
        line = Keyword.get(meta, :line)

        {node,
         [
           format_issue(source_file,
             message: "Function call contains inline script -- verify proper escaping",
             trigger: fn_name,
             line_no: line,
             metadata: %{function: fn_name}
           )
           | issues
         ]}

      true ->
        {node, issues}
    end
  end

  defp traverse(node, issues, _source_file, _doc_strings), do: {node, issues}

  # --- Private Helpers ---

  defp has_script_in_args?(args) when is_list(args) do
    Enum.any?(args, fn
      {:literal, meta, content} when is_list(meta) and is_binary(content) ->
        Keyword.get(meta, :subtype) == :string and
          String.contains?(String.downcase(content), ["<script>", "</script>"])

      _ ->
        false
    end)
  end

  defp has_script_in_args?(_), do: false

  defp truncate(s) when byte_size(s) > 40, do: String.slice(s, 0, 37) <> "..."
  defp truncate(s), do: s
end
