defmodule MetaCredo.Check.Design.HighCoupling do
  use MetaCredo.Check,
    category: :design,
    base_priority: :high,
    confidence: :low,
    param_defaults: [max_dependencies: 10],
    explanations: [
      check: """
      Detects modules with too many external dependencies (imports/aliases).
      High efferent coupling makes modules difficult to test, maintain, and
      reason about. Consider applying dependency inversion or splitting the module.

      Assessment:
      - < 5 dependencies: Excellent
      - 5-9: Good, monitor growth
      - 10-19: Fair, consider refactoring
      - 20+: Poor, major refactoring needed
      """,
      params: [
        max_dependencies: "Maximum allowed external dependencies (default: 10)"
      ],
      examples: [
        elixir: [
          wrong: """
          # One module touching 12 external concerns -- changes ripple everywhere
          defmodule OrderPipeline do
            alias Orders.Repo
            alias Orders.Mailer
            alias Orders.Stripe
            alias Orders.Slack
            alias Orders.S3
            alias Orders.Pdf
            alias Orders.Metrics
            alias Orders.Cache
            alias Orders.Queue
            alias Orders.Sms
            alias Orders.Analytics
            alias Orders.Audit

            def run(order) do
              :ok
            end
          end
          """,
          correct: """
          # Introduce a facade or context module; push external calls to adapters
          defmodule OrderPipeline do
            alias Orders.Billing
            alias Orders.Notifications
            alias Orders.Storage

            def run(order) do
              with {:ok, _} <- Billing.charge(order),
                   {:ok, _} <- Storage.persist(order),
                   :ok <- Notifications.confirm(order) do
                {:ok, order}
              end
            end
          end
          """
        ]
      ]
    ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    max_deps = params_get(params, :max_dependencies)

    {_, issues} =
      source_file
      |> SourceFile.ast()
      |> AST.prewalk([], fn node, acc ->
        traverse(node, acc, source_file, max_deps)
      end)

    issues
  end

  defp traverse({:container, meta, children} = node, issues, source_file, max_deps)
       when is_list(meta) and is_list(children) do
    name = Keyword.get(meta, :name, "anonymous")

    deps =
      children
      |> extract_dependencies()
      |> Enum.reject(&language_builtin?/1)
      |> Enum.uniq()
      |> Enum.sort()

    dep_count = length(deps)

    if dep_count > max_deps do
      line = CheckUtils.line_of(meta)

      issue =
        format_issue(source_file,
          message:
            "Module '#{name}' has #{dep_count} external dependencies (max: #{max_deps}) -- reduce coupling",
          trigger: to_string(name),
          line_no: line,
          metadata: %{dependency_count: dep_count, dependencies: deps}
        )

      {node, [issue | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _sf, _max), do: {node, issues}

  # Language built-ins are not *external* dependencies: coupling to `Enum`,
  # `String`, `File`, or `Elixir` says nothing about how hard a module is to
  # test or change. Counting them inflated every module's score and made the
  # check fire on almost anything of moderate size.
  @builtin_modules ~W[
    Elixir Kernel Enum String File Path System Map MapSet Keyword List Tuple
    Integer Float Atom Bitwise Base Regex Range Stream Access Module Code Macro
    Process Agent GenServer Supervisor Task Registry Application Logger Mix
    IO Inspect Protocol Date Time DateTime NaiveDateTime Calendar URI
  ]

  defp language_builtin?(module), do: module in @builtin_modules

  # `Map.fetch!/2` and friends are Metastatic's encoding of *field access*,
  # not a dependency on the `Map` module.
  @field_access_sentinels ~W(Map.fetch! Map.fetch Map.get elem get_in)

  defp field_access_sentinel?(name), do: name in @field_access_sentinels

  # A dependency must look like a module: PascalCase, or dotted.
  defp module_name?(name) when is_binary(name) do
    String.match?(name, ~r/^[A-Z]/) or String.match?(name, ~r/^[a-z_]+\.[A-Z]/)
  end

  defp extract_dependencies(children) when is_list(children) do
    Enum.flat_map(children, &extract_deps_from_node/1)
  end

  # External module reference: Module.function
  defp extract_deps_from_node({:attribute_access, _meta, [{:variable, _, module}, _func]})
       when module not in ["self", "this", "@"] do
    [module]
  end

  # `alias`/`import`/`require` of an external module.
  defp extract_deps_from_node({:import, meta, _children}) when is_list(meta) do
    case Keyword.get(meta, :source) do
      source when is_binary(source) -> Enum.filter([source], &module_name?/1)
      _ -> []
    end
  end

  # Qualified function call (e.g. "Math.sqrt")
  defp extract_deps_from_node({:function_call, meta, args})
       when is_list(meta) and is_list(args) do
    name = Keyword.get(meta, :name, "")

    deps =
      if is_binary(name) and String.contains?(name, ".") and not field_access_sentinel?(name) do
        [name |> String.split(".") |> hd()]
      else
        []
      end

    # Only module-shaped names (PascalCase or dotted) count as dependencies;
    # a bare `function_call` key from a generic node must not leak through.
    deps = Enum.filter(deps, &module_name?/1)

    deps ++ Enum.flat_map(args, &extract_deps_from_node/1)
  end

  defp extract_deps_from_node({:function_def, _meta, children}) when is_list(children),
    do: Enum.flat_map(children, &extract_deps_from_node/1)

  defp extract_deps_from_node({:block, _meta, stmts}) when is_list(stmts),
    do: Enum.flat_map(stmts, &extract_deps_from_node/1)

  defp extract_deps_from_node({:conditional, _meta, children}) when is_list(children),
    do: Enum.flat_map(children, &extract_deps_from_node/1)

  defp extract_deps_from_node({:assignment, _meta, [_target, value]}),
    do: extract_deps_from_node(value)

  defp extract_deps_from_node({_type, _meta, children}) when is_list(children),
    do: Enum.flat_map(children, &extract_deps_from_node/1)

  defp extract_deps_from_node(_), do: []
end
