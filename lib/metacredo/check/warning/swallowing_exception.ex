defmodule MetaCredo.Check.Warning.SwallowingException do
  use MetaCredo.Check,
    category: :warning,
    base_priority: :high,
    explanations: [
      check: """
      Detects `try/rescue` blocks where the rescue clause neither logs the
      exception nor re-raises it. Swallowing exceptions silently hides errors
      and makes debugging nearly impossible.

      Always log with `Logger` or re-raise with `reraise/2`.
      """,
      examples: [
        elixir: [
          wrong: """
          # The exception disappears into the void -- no trace, no alert
          try do
            risky_call()
          rescue
            _e -> :ok  # silent swallow
          end
          """,
          correct: """
          # At minimum, log the exception before returning a fallback
          try do
            risky_call()
          rescue
            e ->
              Logger.error("risky_call failed", error: Exception.message(e))
              :error
          end
          """
        ]
      ]
    ]

  @logging_names ~W(log error warn warning info debug)
  @reraise_names ~W(raise reraise throw)

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc -> traverse(node, acc, source_file) end)

    issues
  end

  # exception_handling: {:exception_handling, meta, children}
  # children contains the try body and match_arm nodes for rescue clauses
  defp traverse(
         {:exception_handling, meta, children} = node,
         issues,
         source_file
       )
       when is_list(meta) and is_list(children) do
    catch_clauses =
      Enum.filter(children, fn
        {:match_arm, _, _} -> true
        _ -> false
      end)

    silent_catches =
      Enum.filter(catch_clauses, fn
        {:match_arm, arm_meta, body_list} ->
          body =
            if is_list(body_list), do: List.last(body_list), else: Keyword.get(arm_meta, :body)

          not (has_logging?(body) or has_reraise?(body))

        _ ->
          false
      end)

    if silent_catches != [] do
      line = Keyword.get(meta, :line)

      issue =
        format_issue(source_file,
          message:
            "Exception handler swallows exception without logging or re-raising -- errors will be hidden",
          trigger: "rescue",
          line_no: line
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _source_file), do: {node, issues}

  # Recursively check for logging function calls
  defp has_logging?({:block, _meta, statements}) when is_list(statements) do
    Enum.any?(statements, &has_logging?/1)
  end

  defp has_logging?({:function_call, call_meta, _args}) when is_list(call_meta) do
    func_name = Keyword.get(call_meta, :name, "")
    logging_name?(func_name)
  end

  defp has_logging?(tuple) when is_tuple(tuple) do
    tuple |> Tuple.to_list() |> Enum.any?(&has_logging?/1)
  end

  defp has_logging?(list) when is_list(list), do: Enum.any?(list, &has_logging?/1)
  defp has_logging?(_), do: false

  defp logging_name?(name) when is_binary(name) do
    lower = String.downcase(name)
    Enum.any?(@logging_names, &String.contains?(lower, &1))
  end

  defp logging_name?(name) when is_atom(name), do: logging_name?(Atom.to_string(name))
  defp logging_name?(_), do: false

  # Recursively check for re-raise calls
  defp has_reraise?({:block, _meta, statements}) when is_list(statements) do
    Enum.any?(statements, &has_reraise?/1)
  end

  defp has_reraise?({:function_call, call_meta, _args}) when is_list(call_meta) do
    func_name = Keyword.get(call_meta, :name, "")
    reraise_name?(func_name)
  end

  defp has_reraise?(tuple) when is_tuple(tuple) do
    tuple |> Tuple.to_list() |> Enum.any?(&has_reraise?/1)
  end

  defp has_reraise?(list) when is_list(list), do: Enum.any?(list, &has_reraise?/1)
  defp has_reraise?(_), do: false

  defp reraise_name?(name) when is_binary(name) do
    lower = String.downcase(name)
    Enum.any?(@reraise_names, &String.contains?(lower, &1))
  end

  defp reraise_name?(name) when is_atom(name), do: reraise_name?(Atom.to_string(name))
  defp reraise_name?(_), do: false
end
