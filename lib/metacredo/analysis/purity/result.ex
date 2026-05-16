defmodule MetaCredo.Analysis.Purity.Result do
  @moduledoc """
  Result structure for purity analysis.
  """

  @enforce_keys [:pure?, :effects, :confidence]
  defstruct pure?: true,
            effects: [],
            confidence: :high,
            impure_locations: [],
            summary: "",
            unknown_calls: []

  @type effect ::
          :io | :mutation | :random | :time | :network | :database | :exception | :unknown

  @type confidence :: :high | :medium | :low
  @type location :: {:line, non_neg_integer(), effect()}

  @type t :: %__MODULE__{
          pure?: boolean(),
          effects: [effect()],
          confidence: confidence(),
          impure_locations: [location()],
          summary: String.t(),
          unknown_calls: [String.t()]
        }

  @spec pure() :: t()
  def pure do
    %__MODULE__{
      pure?: true,
      effects: [],
      confidence: :high,
      impure_locations: [],
      summary: "Function is pure",
      unknown_calls: []
    }
  end

  @spec impure([effect()], [location()]) :: t()
  def impure(effects, locations) do
    %__MODULE__{
      pure?: false,
      effects: Enum.uniq(effects),
      confidence: :high,
      impure_locations: locations,
      summary: build_summary(effects),
      unknown_calls: []
    }
  end

  @spec unknown([String.t()]) :: t()
  def unknown(calls) do
    %__MODULE__{
      pure?: false,
      effects: [],
      confidence: :low,
      impure_locations: [],
      summary: "Function purity unknown - contains unclassified calls: #{Enum.join(calls, ", ")}",
      unknown_calls: calls
    }
  end

  @spec merge([t()]) :: t()
  def merge(results) do
    pure? = Enum.all?(results, & &1.pure?)
    effects = results |> Enum.flat_map(& &1.effects) |> Enum.uniq()
    locations = results |> Enum.flat_map(& &1.impure_locations) |> Enum.uniq()
    unknown = results |> Enum.flat_map(& &1.unknown_calls) |> Enum.uniq()

    confidence =
      cond do
        pure? and Enum.empty?(unknown) -> :high
        not Enum.empty?(unknown) -> :low
        true -> :medium
      end

    summary =
      cond do
        pure? -> "Function is pure"
        not Enum.empty?(effects) -> build_summary(effects)
        not Enum.empty?(unknown) -> "Function purity unknown - contains unclassified calls"
        true -> "Function may be impure"
      end

    %__MODULE__{
      pure?: pure?,
      effects: effects,
      confidence: confidence,
      impure_locations: locations,
      summary: summary,
      unknown_calls: unknown
    }
  end

  defp build_summary([]), do: "Function is pure"

  defp build_summary(effects) do
    effect_names = Enum.map_join(effects, ", ", &effect_to_string/1)
    "Function is impure due to #{effect_names}"
  end

  defp effect_to_string(:io), do: "I/O operations"
  defp effect_to_string(:mutation), do: "mutations"
  defp effect_to_string(:random), do: "random operations"
  defp effect_to_string(:time), do: "time operations"
  defp effect_to_string(:network), do: "network operations"
  defp effect_to_string(:database), do: "database operations"
  defp effect_to_string(:exception), do: "exception handling"
  defp effect_to_string(:unknown), do: "unknown operations"
end
