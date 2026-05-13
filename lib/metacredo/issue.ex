defmodule MetaCredo.Issue do
  @moduledoc """
  Represents a single issue found during analysis.

  Mirrors `Credo.Issue` but operates on MetaAST nodes.
  """

  @type priority :: :higher | :high | :normal | :low | :ignore
  @type severity :: :error | :warning | :info | :refactoring_opportunity

  @type t :: %__MODULE__{
          check: module(),
          category: atom(),
          severity: severity(),
          priority: priority() | integer(),
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
    ignore: -100
  }

  @doc "Converts a priority atom to its numeric value."
  @spec priority_value(priority() | integer()) :: integer()
  def priority_value(priority) when is_integer(priority), do: priority
  def priority_value(priority), do: Map.get(@priority_values, priority, 0)
end
