defmodule MetaCredo.Analysis.DeadCode do
  @moduledoc """
  Programmatic intraprocedural dead code detection API.

  Identifies unreachable code, unused functions, and other patterns
  that result in dead code. Works across all supported languages
  by operating on the unified MetaAST representation.

  ## Dead Code Types

  - **Unreachable after return** -- Code following early_return nodes
  - **Constant conditionals** -- Branches that can never execute
  - **Unused functions** -- Function definitions never called (module context)

  ## Usage

      alias Metastatic.Document
      alias MetaCredo.Analysis.DeadCode

      doc = Document.new(ast, :python)
      {:ok, result} = DeadCode.analyze(doc)

      result.has_dead_code?         # => true
      result.total_dead_statements  # => 1
      result.dead_locations         # => [%{type: :unreachable_after_return, ...}]
  """

  alias MetaCredo.Analysis.DeadCode.Result
  alias Metastatic.Document

  use MetaCredo.Analysis.Analyzer,
    doc: """
    Analyzes a document for dead code.

    Returns `{:ok, result}` where result is a `MetaCredo.Analysis.DeadCode.Result` struct.

    ## Options

    - `:detect_unused_functions` - Enable unused function detection (default: false)
    - `:min_confidence` - Minimum confidence level to report (default: :low)
    """

  @impl MetaCredo.Analysis.Analyzer
  def handle_analyze(%Document{ast: ast} = _doc, opts \\ []) do
    dead_locations =
      []
      |> detect_unreachable_after_return(ast, [])
      |> detect_constant_conditionals(ast)
      |> filter_by_confidence(opts)

    {:ok, Result.new(dead_locations)}
  end

  # Detect code unreachable after early_return nodes
  defp detect_unreachable_after_return(locations, ast, path) do
    case ast do
      {:block, _meta, statements} when is_list(statements) ->
        check_block_for_unreachable(locations, statements, path)

      {:conditional, _meta, [_cond, then_branch, else_branch]} ->
        locations
        |> detect_unreachable_after_return(then_branch, [:then | path])
        |> detect_unreachable_after_return(else_branch, [:else | path])

      {:loop, meta, children} when is_list(meta) and is_list(children) ->
        body = List.last(children)
        detect_unreachable_after_return(locations, body, [:loop_body | path])

      {:lambda, _meta, [body]} ->
        detect_unreachable_after_return(locations, body, [:lambda_body | path])

      {:exception_handling, _meta, [try_block, catches, else_block]} ->
        locations
        |> detect_unreachable_after_return(try_block, [:try | path])
        |> detect_unreachable_in_catches(catches, path)
        |> detect_unreachable_after_return(else_block, [:else | path])

      _ ->
        locations
    end
  end

  defp check_block_for_unreachable(locations, statements, path) do
    {locations, _} =
      Enum.reduce(statements, {locations, false}, fn stmt, {locs, found_return} ->
        cond do
          found_return ->
            new_loc = %{
              type: :unreachable_after_return,
              reason: "Code after early return is unreachable",
              confidence: :high,
              suggestion: "Remove unreachable code",
              context: %{path: Enum.reverse(path), ast: stmt}
            }

            {[new_loc | locs], true}

          match?({:early_return, _, _}, stmt) ->
            {detect_unreachable_after_return(locs, stmt, path), true}

          true ->
            {detect_unreachable_after_return(locs, stmt, path), false}
        end
      end)

    locations
  end

  defp detect_unreachable_in_catches(locations, catches, path) when is_list(catches) do
    Enum.reduce(catches, locations, fn catch_clause, locs ->
      detect_unreachable_after_return(locs, catch_clause, [:catch | path])
    end)
  end

  defp detect_unreachable_in_catches(locations, nil, _path), do: locations

  defp detect_constant_conditionals(locations, ast) do
    walk_for_conditionals(ast, locations)
  end

  defp walk_for_conditionals(
         {:conditional, _meta, [condition, then_branch, else_branch]},
         locations
       ) do
    locations =
      case evaluate_constant_condition(condition) do
        {:constant, true} when not is_nil(else_branch) ->
          new_loc = %{
            type: :constant_conditional,
            reason: "Else branch unreachable due to constant true condition",
            confidence: :high,
            suggestion: "Remove else branch or fix condition",
            context: %{condition: condition, dead_branch: :else, ast: else_branch}
          }

          [new_loc | locations]

        {:constant, true} ->
          locations

        {:constant, false} ->
          new_loc = %{
            type: :constant_conditional,
            reason: "Then branch unreachable due to constant false condition",
            confidence: :high,
            suggestion: "Remove then branch or fix condition",
            context: %{condition: condition, dead_branch: :then, ast: then_branch}
          }

          [new_loc | locations]

        :not_constant ->
          locations
      end

    locations = walk_for_conditionals(then_branch, locations)
    if is_nil(else_branch), do: locations, else: walk_for_conditionals(else_branch, locations)
  end

  defp walk_for_conditionals({:block, _meta, statements}, locations) when is_list(statements) do
    Enum.reduce(statements, locations, &walk_for_conditionals/2)
  end

  defp walk_for_conditionals({:loop, meta, children}, locations)
       when is_list(meta) and is_list(children) do
    Enum.reduce(children, locations, &walk_for_conditionals/2)
  end

  defp walk_for_conditionals({:lambda, _meta, [body]}, locations),
    do: walk_for_conditionals(body, locations)

  defp walk_for_conditionals(
         {:exception_handling, _meta, [try_block, catches, else_block]},
         locations
       ) do
    locations = walk_for_conditionals(try_block, locations)

    locations =
      if is_nil(else_block), do: locations, else: walk_for_conditionals(else_block, locations)

    if is_list(catches),
      do: Enum.reduce(catches, locations, &walk_for_conditionals/2),
      else: locations
  end

  defp walk_for_conditionals({:binary_op, _meta, [left, right]}, locations) do
    locations = walk_for_conditionals(left, locations)
    walk_for_conditionals(right, locations)
  end

  defp walk_for_conditionals({:unary_op, _meta, [operand]}, locations),
    do: walk_for_conditionals(operand, locations)

  defp walk_for_conditionals({:function_call, _meta, args}, locations) when is_list(args),
    do: Enum.reduce(args, locations, &walk_for_conditionals/2)

  defp walk_for_conditionals({:assignment, _meta, [target, value]}, locations) do
    locations = walk_for_conditionals(target, locations)
    walk_for_conditionals(value, locations)
  end

  defp walk_for_conditionals({:inline_match, _meta, [pattern, value]}, locations) do
    locations = walk_for_conditionals(pattern, locations)
    walk_for_conditionals(value, locations)
  end

  defp walk_for_conditionals(nil, locations), do: locations
  defp walk_for_conditionals(_, locations), do: locations

  defp evaluate_constant_condition({:literal, meta, value}) when is_list(meta) do
    subtype = Keyword.get(meta, :subtype)

    case {subtype, value} do
      {:boolean, bool} when is_boolean(bool) -> {:constant, bool}
      {:integer, 0} -> {:constant, false}
      {:integer, n} when n != 0 -> {:constant, true}
      {:null, _} -> {:constant, false}
      {:string, ""} -> {:constant, false}
      {:string, _} -> {:constant, true}
      _ -> :not_constant
    end
  end

  defp evaluate_constant_condition(_), do: :not_constant

  defp filter_by_confidence(locations, opts) do
    min_confidence = Keyword.get(opts, :min_confidence, :low)
    confidence_order = %{high: 3, medium: 2, low: 1}
    min_level = Map.get(confidence_order, min_confidence, 1)

    Enum.filter(locations, fn %{confidence: conf} ->
      Map.get(confidence_order, conf, 0) >= min_level
    end)
  end
end
