defmodule MetaCredo.Check.Readability.Specs do
  use MetaCredo.Check,
    category: :readability,
    base_priority: :normal,
    explanations: [
      check: """
      Detects public functions without a preceding `@spec` type annotation.
      Typespecs improve documentation, enable Dialyzer analysis, and make
      function contracts explicit.
      """,
      examples: [
        elixir: [
          wrong: """
          # No spec -- callers can't tell what types are accepted or returned
          defmodule Pricing do
            def calculate_discount(price, rate) do
              price * (1 - rate)
            end
          end
          """,
          correct: """
          @spec calculate_discount(number(), float()) :: float()
          def calculate_discount(price, rate) do
            price * (1 - rate)
          end
          """
        ]
      ]
    ]

  @impl true
  def run(%SourceFile{} = source_file, _params) do
    source_file
    |> SourceFile.ast()
    |> collect_issues(source_file)
  end

  defp collect_issues(ast, source_file) do
    {_, issues} =
      AST.prewalk(ast, [], fn node, acc ->
        traverse(node, acc, source_file)
      end)

    issues
  end

  # Behaviour/OTP callbacks and framework entry points that legitimately do
  # not carry `@spec`s in user code: the contract is defined by the behaviour
  # (or the framework), and re-specifying it adds noise without value.
  @callback_names ~W(
    __using__ __before_compile__ __after_compile__
    init call handle_call handle_cast handle_info handle_continue
    handle_event handle_async terminate code_change format_status
    mount render update before_compile after_compile
    run perform changeset validate to_string inspect
    child_spec start_link start stop
  )

  # Check containers (modules) for function_defs preceded by type_annotations
  defp traverse({:container, _meta, children} = node, issues, source_file)
       when is_list(children) do
    new_issues = check_children(children, source_file)
    {node, new_issues ++ issues}
  end

  defp traverse(node, issues, _sf), do: {node, issues}

  defp check_children(children, source_file) do
    skip_callbacks? = behaviour_module?(children) or mix_task?(children)
    check_sequential(children, false, source_file, [], skip_callbacks?)
  end

  defp check_sequential([], _spec_seen, _source_file, acc, _skip), do: acc

  defp check_sequential(
         [{:type_annotation, meta, _children} | rest],
         _spec_seen,
         source_file,
         acc,
         skip
       )
       when is_list(meta) do
    is_spec = Keyword.get(meta, :annotation_type) == :spec
    check_sequential(rest, is_spec, source_file, acc, skip)
  end

  defp check_sequential(
         [{:function_def, meta, _children} | rest],
         spec_seen,
         source_file,
         acc,
         skip
       )
       when is_list(meta) do
    visibility = Keyword.get(meta, :visibility, :public)
    name = Keyword.get(meta, :name, "anonymous")

    acc =
      if visibility == :public and not spec_seen and
           not (skip and callback_name?(name)) do
        line = CheckUtils.line_of(meta)

        issue =
          format_issue(source_file,
            message: "Public function '#{name}' has no @spec",
            trigger: to_string(name),
            line_no: line
          )

        [issue | acc]
      else
        acc
      end

    check_sequential(rest, false, source_file, acc, skip)
  end

  defp check_sequential([_ | rest], _spec_seen, source_file, acc, skip) do
    check_sequential(rest, false, source_file, acc, skip)
  end

  # A module that declares a behaviour (via `@behaviour` or `use` of a
  # behaviour-providing macro) is expected to implement callbacks whose
  # contracts are already specified by that behaviour.
  defp behaviour_module?(children) when is_list(children) do
    Enum.any?(children, fn
      {:assignment, meta, [{:variable, _, var_name} | _]} when is_list(meta) ->
        var_name in ["@behaviour", "@impl"]

      {:import, meta, _} when is_list(meta) ->
        Keyword.get(meta, :import_type) == :use

      _ ->
        false
    end)
  end

  defp mix_task?(children) when is_list(children) do
    Enum.any?(children, fn
      {:import, meta, _} when is_list(meta) ->
        Keyword.get(meta, :source) == "Mix.Task"

      _ ->
        false
    end)
  end

  defp callback_name?(name) when is_binary(name), do: name in @callback_names
  defp callback_name?(name) when is_atom(name), do: Atom.to_string(name) in @callback_names
  defp callback_name?(_), do: false
end
