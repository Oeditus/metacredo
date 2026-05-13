defmodule MetaCredo.Check do
  @moduledoc """
  Behaviour and macro for defining MetaCredo checks.

  Mirrors `Credo.Check` ergonomics but operates on MetaAST via Metastatic.

  ## Usage

      defmodule MetaCredo.Check.Security.HardcodedValue do
        use MetaCredo.Check,
          category: :security,
          base_priority: :high,
          param_defaults: [exclude_localhost: true],
          explanations: [
            check: "Detects hardcoded URLs, IPs, and sensitive values.",
            params: [
              exclude_localhost: "Skip localhost URLs (default: true)"
            ]
          ]

        @impl true
        def run(%SourceFile{} = source_file, params) do
          source_file
          |> SourceFile.ast()
          |> Metastatic.AST.prewalk([], &traverse(&1, &2, params))
          |> elem(1)
        end

        defp traverse({:literal, meta, value} = _node, issues, _params)
             when is_list(meta) and is_binary(value) do
          # ... detection logic ...
          issues
        end
      end
  """

  alias MetaCredo.{Issue, SourceFile}

  @type params :: Keyword.t()

  @doc "Runs the check on a source file. Returns a list of issues."
  @callback run(source_file :: SourceFile.t(), params :: params()) :: [Issue.t()]

  @doc "Returns the category for this check."
  @callback category() :: atom()

  @doc "Returns the base priority for this check."
  @callback base_priority() :: Issue.priority()

  @doc "Returns the explanations for this check."
  @callback explanations() :: Keyword.t()

  @doc "Returns the default values for params."
  @callback param_defaults() :: Keyword.t()

  @doc "Returns the tags for this check."
  @callback tags() :: [atom()]

  @doc "Returns a unique string ID for this check."
  @callback id() :: String.t()

  @optional_callbacks tags: 0

  @valid_categories [
    :consistency,
    :design,
    :readability,
    :refactor,
    :warning,
    :security,
    :performance,
    :observability
  ]

  @doc false
  defmacro __using__(opts) do
    category = Keyword.get(opts, :category, :warning)
    base_priority = Keyword.get(opts, :base_priority, :normal)
    explanations = Keyword.get(opts, :explanations, [])
    param_defaults = Keyword.get(opts, :param_defaults, [])
    tags = Keyword.get(opts, :tags, [])

    quote do
      @behaviour MetaCredo.Check

      alias MetaCredo.{Check, Issue, SourceFile}
      alias Metastatic.AST

      @impl true
      def category, do: unquote(category)

      @impl true
      def base_priority, do: unquote(base_priority)

      @impl true
      def explanations, do: unquote(explanations)

      @impl true
      def param_defaults, do: unquote(param_defaults)

      @impl true
      def tags, do: unquote(tags)

      @impl true
      def id, do: to_string(__MODULE__)

      defoverridable category: 0,
                     base_priority: 0,
                     explanations: 0,
                     param_defaults: 0,
                     tags: 0,
                     id: 0

      @doc false
      def format_issue(source_file, opts) do
        Check.format_issue(__MODULE__, source_file, opts)
      end

      @doc false
      def params_get(params, key) do
        Check.params_get(params, key, __MODULE__)
      end
    end
  end

  # -- Helper functions --

  @doc """
  Creates an `Issue` struct from check module, source file, and options.

  Options:
  - `:message` (required) - The issue message
  - `:trigger` - The text fragment causing the issue
  - `:line_no` - Line number
  - `:column` - Column number
  - `:severity` - Override severity
  - `:priority` - Override priority
  - `:metadata` - Additional metadata map
  """
  @spec format_issue(module(), SourceFile.t(), Keyword.t()) :: Issue.t()
  def format_issue(check_module, %SourceFile{} = source_file, opts) do
    category = check_module.category()

    %Issue{
      check: check_module,
      category: category,
      severity: Keyword.get(opts, :severity, :warning),
      priority: Keyword.get(opts, :priority, check_module.base_priority()),
      message: Keyword.fetch!(opts, :message),
      trigger: Keyword.get(opts, :trigger),
      line_no: Keyword.get(opts, :line_no),
      column: Keyword.get(opts, :column),
      filename: source_file.filename,
      exit_status: Keyword.get(opts, :exit_status, Issue.exit_status_for(category)),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Retrieves a parameter value, falling back to the check's defaults.
  """
  @spec params_get(params(), atom(), module()) :: term()
  def params_get(params, key, check_module) do
    defaults = check_module.param_defaults()
    Keyword.get(params, key, Keyword.get(defaults, key))
  end

  @doc "Returns the list of valid check categories."
  @spec valid_categories() :: [atom()]
  def valid_categories, do: @valid_categories
end
