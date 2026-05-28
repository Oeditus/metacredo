defmodule MetaCredo.Check.Security.HardcodedValue do
  use MetaCredo.Check,
    category: :security,
    base_priority: :high,
    param_defaults: [exclude_localhost: true, exclude_local_ips: true],
    explanations: [
      check: """
      Detects hardcoded URLs, IP addresses, and other sensitive values in
      string literals. Move these values to configuration files or
      environment variables.

      This is a universal anti-pattern across all languages.
      """,
      params: [
        exclude_localhost: "Skip localhost/127.0.0.1 URLs (default: true)",
        exclude_local_ips: "Skip private IP ranges (default: true)"
      ],
      examples: [
        elixir: [
          wrong: """
          # Hardcoded URL embedded directly in the call
          def fetch_data do
            HTTPoison.get!("https://api.example.com/v1/data")
          end
          """,
          correct: """
          # URL read from application configuration
          def fetch_data do
            url = Application.fetch_env!(:my_app, :api_url)
            HTTPoison.get!(url)
          end
          """
        ]
      ]
    ]

  @url_pattern ~r/^https?:\/\/[^\s]+$/
  @ip_pattern ~r/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/

  @impl true
  def run(%SourceFile{} = source_file, params) do
    exclude_localhost = params_get(params, :exclude_localhost)
    exclude_local_ips = params_get(params, :exclude_local_ips)
    ast = SourceFile.ast(source_file)
    doc_strings = CheckUtils.doc_string_contents(ast)
    ctx = {source_file, exclude_localhost, exclude_local_ips, doc_strings}

    {_, issues} =
      AST.prewalk(ast, [], fn node, acc -> traverse(node, acc, ctx) end)

    issues
  end

  defp traverse({:literal, meta, value} = node, issues, ctx)
       when is_list(meta) and is_binary(value) do
    {_, _, _, doc_strings} = ctx

    if Keyword.get(meta, :subtype) == :string and
         not CheckUtils.doc_string?(doc_strings, value) do
      {node, check_value(value, meta, issues, ctx)}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _ctx), do: {node, issues}

  defp check_value(value, meta, issues, {source_file, exclude_localhost, exclude_local_ips, _}) do
    line = Keyword.get(meta, :line)

    cond do
      url?(value) and not (exclude_localhost and localhost_url?(value)) ->
        [
          format_issue(source_file,
            message: "Hardcoded URL found -- move to configuration",
            trigger: truncate(value),
            line_no: line,
            metadata: %{type: :url}
          )
          | issues
        ]

      ip?(value) and not (exclude_local_ips and local_ip?(value)) ->
        [
          format_issue(source_file,
            message: "Hardcoded IP address found -- move to configuration",
            trigger: value,
            line_no: line,
            metadata: %{type: :ip}
          )
          | issues
        ]

      true ->
        issues
    end
  end

  defp url?(s), do: Regex.match?(@url_pattern, s)
  defp ip?(s), do: Regex.match?(@ip_pattern, s) and valid_ip?(s)

  defp valid_ip?(ip) do
    ip
    |> String.split(".")
    |> Enum.all?(fn octet ->
      case Integer.parse(octet) do
        {n, ""} when n >= 0 and n <= 255 -> true
        _ -> false
      end
    end)
  end

  defp localhost_url?(url),
    do: String.contains?(url, ["localhost", "127.0.0.1", "0.0.0.0"])

  defp local_ip?(ip) do
    String.starts_with?(ip, "127.") or String.starts_with?(ip, "192.168.") or
      String.starts_with?(ip, "10.") or ip == "0.0.0.0"
  end

  defp truncate(s) when byte_size(s) > 40, do: String.slice(s, 0, 37) <> "..."
  defp truncate(s), do: s
end
