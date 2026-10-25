defmodule MetaCredo.Check.Security.HardcodedValue do
  use MetaCredo.Check,
    category: :security,
    base_priority: :high,
    tags: [:security],
    param_defaults: [exclude_localhost: true, exclude_local_ips: true, check_exs: false],
    explanations: [
      check: """
      Detects hardcoded URLs, IP addresses, and other sensitive values in
      string literals. Move these values to configuration files or
      environment variables.

      This is a universal anti-pattern across all languages.
      """,
      params: [
        exclude_localhost: "Skip localhost/127.0.0.1 URLs (default: true)",
        exclude_local_ips: "Skip private IP ranges (default: true)",
        check_exs: "Check hardcoded values in .exs script/config files (default: false)"
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

  @truncate_limit 40
  @truncate_keep 37

  @url_pattern ~r/^https?:\/\/[^\s]+$/
  @ip_pattern ~r/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/

  @impl true
  def run(%SourceFile{} = source_file, params) do
    check_exs = params_get(params, :check_exs)

    if not check_exs and String.ends_with?(source_file.filename, ".exs") do
      []
    else
      exclude_localhost = params_get(params, :exclude_localhost)
      exclude_local_ips = params_get(params, :exclude_local_ips)
      ast = SourceFile.ast(source_file)
      doc_strings = CheckUtils.doc_string_contents(ast)
      ctx = {source_file, exclude_localhost, exclude_local_ips, doc_strings}

      {_, issues} =
        AST.prewalk(ast, [], fn node, acc -> traverse(node, acc, ctx) end)

      issues
    end
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
    case classify_value(value, exclude_localhost, exclude_local_ips) do
      nil ->
        issues

      {type, message} ->
        [
          format_issue(source_file,
            message: message,
            trigger: truncate(value),
            line_no: CheckUtils.line_of(meta),
            metadata: %{type: type}
          )
          | issues
        ]
    end
  end

  # Classifies a string literal as a hardcoded URL or IP, honouring the
  # `exclude_localhost` / `exclude_local_ips` params. Returns `nil` when the
  # value is not reportable.
  defp classify_value(value, exclude_localhost, exclude_local_ips) do
    cond do
      url?(value) and not (exclude_localhost and localhost_url?(value)) ->
        {:url, "Hardcoded URL found -- move to configuration"}

      ip?(value) and not (exclude_local_ips and local_ip?(value)) ->
        {:ip, "Hardcoded IP address found -- move to configuration"}

      true ->
        nil
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

  defp truncate(s) when byte_size(s) > @truncate_limit,
    do: String.slice(s, 0, @truncate_keep) <> "..."

  defp truncate(s), do: s
end
