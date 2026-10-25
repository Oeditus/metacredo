defmodule MetaCredo.Check.Warning.SwallowingException do
  use MetaCredo.Check,
    category: :warning,
    base_priority: :high,
    confidence: :low,
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
          # Inspect the *whole* rescue body, not just its last statement: a
          # `Logger.error(...)` followed by `:error` would otherwise be
          # reported as silent.
          body = if is_list(body_list), do: body_list, else: Keyword.get(arm_meta, :body)

          not (has_logging?(body) or has_reraise?(body) or propagates_error?(body))

        _ ->
          false
      end)

    if silent_catches != [] do
      line = CheckUtils.line_of(meta)

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

  # Returning a tagged error tuple is a *third* legitimate way to surface a
  # rescued exception, alongside logging and re-raising: the caller receives
  # the error and decides what to do. Treating `rescue e -> {:error, e}` as a
  # silent swallow produced a flood of false positives on idiomatic code.
  defp propagates_error?({:tuple, _meta, elements}) when is_list(elements) do
    Enum.any?(elements, &error_tag?/1)
  end

  defp propagates_error?({:block, _meta, statements}) when is_list(statements) do
    Enum.any?(statements, &propagates_error?/1)
  end

  defp propagates_error?(statements) when is_list(statements) do
    Enum.any?(statements, &propagates_error?/1)
  end

  defp propagates_error?({:early_return, _meta, [value]}), do: propagates_error?(value)

  defp propagates_error?(_), do: false

  defp error_tag?({:literal, meta, value}) when is_list(meta) do
    Keyword.get(meta, :subtype) == :symbol and to_string(value) in ["error", "exception"]
  end

  defp error_tag?(_), do: false

  # Recursively check for logging function calls.
  #
  # `Logger.debug(fn -> "..." end)` is the *lazy* logging form, and the call
  # node's arguments are a `:lambda` wrapping the message. The generic tuple
  # clause below would find it, but the specific `:function_call` clause
  # short-circuits on the call name alone -- so a lazy log call was reported
  # as if the rescue clause did nothing.
  defp has_logging?({:block, _meta, statements}) when is_list(statements) do
    Enum.any?(statements, &has_logging?/1)
  end

  # A rescue body arrives as a *bare list* of statements, not wrapped in a
  # `:block` node. Without this clause every multi-statement rescue body fell
  # through to the catch-all and was reported as silent.
  defp has_logging?(statements) when is_list(statements) do
    Enum.any?(statements, &has_logging?/1)
  end

  defp has_logging?({:function_call, call_meta, args}) when is_list(call_meta) do
    func_name = Keyword.get(call_meta, :name, "")
    logging_name?(func_name) or has_logging?(args)
  end

  defp has_logging?(tuple) when is_tuple(tuple) do
    tuple |> Tuple.to_list() |> Enum.any?(&has_logging?/1)
  end

  defp has_logging?(_), do: false

  defp logging_name?(name) when is_binary(name) do
    lower = String.downcase(name)
    Enum.any?(@logging_names, &String.contains?(lower, &1))
  end

  defp logging_name?(name) when is_atom(name), do: logging_name?(Atom.to_string(name))
  defp logging_name?(_), do: false

  defp has_reraise?({:block, _meta, statements}) when is_list(statements) do
    Enum.any?(statements, &has_reraise?/1)
  end

  defp has_reraise?(statements) when is_list(statements) do
    Enum.any?(statements, &has_reraise?/1)
  end

  defp has_reraise?({:function_call, call_meta, args}) when is_list(call_meta) do
    func_name = Keyword.get(call_meta, :name, "")
    reraise_name?(func_name) or has_reraise?(args)
  end

  defp has_reraise?(tuple) when is_tuple(tuple) do
    tuple |> Tuple.to_list() |> Enum.any?(&has_reraise?/1)
  end

  defp has_reraise?(_), do: false

  defp reraise_name?(name) when is_binary(name) do
    lower = String.downcase(name)
    Enum.any?(@reraise_names, &String.contains?(lower, &1))
  end

  defp reraise_name?(name) when is_atom(name), do: reraise_name?(Atom.to_string(name))
  defp reraise_name?(_), do: false
end
