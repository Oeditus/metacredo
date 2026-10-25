defmodule MetaCredo.Issue do
  @moduledoc """
  Represents a single issue found during analysis.

  Mirrors `Credo.Issue` but operates on MetaAST nodes.
  """

  # `:ignore` sorts below every real priority.
  @ignore_priority -100

  @type priority :: :higher | :high | :normal | :low | :ignore
  @type severity :: :error | :warning | :info | :refactoring_opportunity

  @typedoc """
  How sure the check is that the finding is real.

    * `:high` -- AST-structural: the shape is unambiguous
      (`DoubleBooleanNegation`, `FilterCount`, `UnlessWithElse`).
    * `:medium` -- structural but heuristic in places (complexity, nesting).
    * `:low` -- name-substring heuristic (`PathTraversal`, `SSRFVulnerability`,
      `ImperativeStatusHandling`). These are the checks that are disabled by
      default; when enabled, `--min-confidence` keeps the noise down.
  """
  @type confidence :: :high | :medium | :low

  @type t :: %__MODULE__{
          check: module(),
          category: atom(),
          severity: severity(),
          priority: priority() | integer(),
          confidence: confidence(),
          message: String.t(),
          trigger: String.t() | nil,
          line_no: pos_integer() | nil,
          column: pos_integer() | nil,
          filename: String.t() | nil,
          exit_status: non_neg_integer(),
          metadata: map()
        }

  @enforce_keys [:check, :category, :message]
  defstruct [
    :check,
    :category,
    :trigger,
    :line_no,
    :column,
    :filename,
    severity: :warning,
    priority: :normal,
    confidence: :medium,
    message: "",
    exit_status: 0,
    metadata: %{}
  ]

  @category_exit_status %{
    consistency: 1,
    design: 2,
    readability: 4,
    refactor: 8,
    warning: 16,
    security: 32,
    performance: 64,
    observability: 128
  }

  @doc "Returns the default exit status for a given category."
  @spec exit_status_for(atom()) :: non_neg_integer()
  def exit_status_for(category) do
    Map.get(@category_exit_status, category, 0)
  end

  @priority_values %{
    higher: 40,
    high: 20,
    normal: 10,
    low: 1,
    ignore: @ignore_priority
  }

  @doc "Converts a priority atom to its numeric value."
  @spec priority_value(priority() | integer()) :: integer()
  def priority_value(priority) when is_integer(priority), do: priority
  def priority_value(priority), do: Map.get(@priority_values, priority, 0)

  @confidence_values %{high: 3, medium: 2, low: 1}

  @doc """
  Returns the numeric rank of a confidence level (`:high` > `:medium` > `:low`).
  """
  @spec confidence_value(confidence()) :: 1..3
  def confidence_value(confidence), do: Map.get(@confidence_values, confidence, 2)

  @doc "Parses a confidence level from a string or atom, or returns `nil`."
  @spec parse_confidence(String.t() | atom() | nil) :: confidence() | nil
  def parse_confidence(level) when level in [:high, :medium, :low], do: level
  def parse_confidence("high"), do: :high
  def parse_confidence("medium"), do: :medium
  def parse_confidence("low"), do: :low
  def parse_confidence(_), do: nil
end
