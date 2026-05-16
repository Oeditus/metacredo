defmodule MetaCredo.Analysis.DeadCode.Result do
  @moduledoc """
  Result structure for dead code analysis.

  Contains information about detected dead code locations, their types,
  and suggestions for remediation.

  ## Fields

  - `:has_dead_code?` - Boolean indicating if any dead code was found
  - `:dead_locations` - List of dead code locations with details
  - `:summary` - Human-readable summary of findings
  - `:total_dead_statements` - Count of dead statements detected
  - `:by_type` - Map of dead code counts by type
  """

  @type dead_location :: %{
          type: dead_code_type(),
          reason: String.t(),
          confidence: :high | :medium | :low,
          suggestion: String.t(),
          context: term()
        }

  @type dead_code_type ::
          :unreachable_after_return
          | :constant_conditional
          | :unused_function
          | :unreachable_code

  @type t :: %__MODULE__{
          has_dead_code?: boolean(),
          dead_locations: [dead_location()],
          summary: String.t(),
          total_dead_statements: non_neg_integer(),
          by_type: %{dead_code_type() => non_neg_integer()}
        }

  defstruct has_dead_code?: false,
            dead_locations: [],
            summary: "No dead code detected",
            total_dead_statements: 0,
            by_type: %{}

  @spec new([dead_location()]) :: t()
  def new([]), do: %__MODULE__{}

  def new([_ | _] = dead_locations) do
    by_type = count_by_type(dead_locations)

    %__MODULE__{
      has_dead_code?: true,
      dead_locations: dead_locations,
      summary: build_summary(dead_locations, by_type),
      total_dead_statements: length(dead_locations),
      by_type: by_type
    }
  end

  @spec no_dead_code() :: t()
  def no_dead_code, do: new([])

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = result) do
    %{
      has_dead_code: result.has_dead_code?,
      summary: result.summary,
      total_dead_statements: result.total_dead_statements,
      by_type: result.by_type,
      locations: result.dead_locations
    }
  end

  # Private helpers

  defp count_by_type(locations) do
    Enum.reduce(locations, %{}, fn %{type: type}, acc ->
      Map.update(acc, type, 1, &(&1 + 1))
    end)
  end

  defp build_summary(locations, by_type) do
    total = length(locations)

    parts =
      Enum.map_join(by_type, ", ", fn {type, count} ->
        "#{count} #{format_type(type)}"
      end)

    "Found #{total} dead code location(s): #{parts}"
  end

  defp format_type(:unreachable_after_return), do: "unreachable after return"
  defp format_type(:constant_conditional), do: "constant conditional"
  defp format_type(:unused_function), do: "unused function"
  defp format_type(:unreachable_code), do: "unreachable code"
  defp format_type(other), do: to_string(other)
end
