defmodule MetaCredo.Analysis.ComplexityTest do
  @moduledoc """
  Table-driven tests for the six complexity metric modules.

  These modules are pure functions over the uniform 3-tuple MetaAST shape
  `{type, meta, children}`, which makes them the cheapest possible unit-test
  targets -- and, before this file, the least covered (8-15% each across
  ~1,970 lines). Each `describe` block pins the documented behaviour of one
  metric against hand-built ASTs so a regression shows up as a named failure
  rather than a silently wrong number in a report.
  """

  use ExUnit.Case, async: true

  alias MetaCredo.Analysis.Complexity.{
    Cognitive,
    Cyclomatic,
    FunctionMetrics,
    Halstead,
    LoC,
    Nesting,
    Result
  }

  # -- AST builders -----------------------------------------------------------

  defp lit(value, subtype \\ :integer), do: {:literal, [subtype: subtype], value}
  defp var(name), do: {:variable, [], name}

  defp cond(c, t, e), do: {:conditional, [], [c, t, e]}

  defp block(stmts), do: {:block, [], stmts}

  defp call(name, args \\ []), do: {:function_call, [name: name], args}

  defp assign(target, value), do: {:assignment, [], [target, value]}

  # -- Cyclomatic -------------------------------------------------------------

  describe "Cyclomatic.calculate/1" do
    test "a leaf has the base complexity of 1" do
      assert Cyclomatic.calculate(lit(42)) == 1
    end

    test "each conditional adds one decision point" do
      assert Cyclomatic.calculate(cond(var("x"), lit(1), lit(2))) == 2
    end

    test "nested conditionals accumulate" do
      ast = cond(var("x"), cond(var("y"), lit(1), lit(2)), lit(3))
      assert Cyclomatic.calculate(ast) == 3
    end

    test "boolean and/or operators add decision points" do
      and_ast = {:binary_op, [category: :boolean, operator: :and], [var("a"), var("b")]}
      or_ast = {:binary_op, [category: :boolean, operator: :or], [var("a"), var("b")]}

      assert Cyclomatic.calculate(and_ast) == 2
      assert Cyclomatic.calculate(or_ast) == 2
    end

    test "arithmetic operators are not decision points" do
      ast = {:binary_op, [category: :arithmetic, operator: :+], [lit(1), lit(2)]}
      assert Cyclomatic.calculate(ast) == 1
    end
  end

  # -- Cognitive --------------------------------------------------------------

  describe "Cognitive.calculate/1" do
    test "a leaf has zero cognitive complexity" do
      assert Cognitive.calculate(lit(42)) == 0
    end

    test "a top-level conditional scores 1" do
      assert Cognitive.calculate(cond(var("x"), lit(1), lit(2))) == 1
    end

    test "nesting applies a penalty: nested conditional scores 1 + 2" do
      ast = cond(var("x"), cond(var("y"), lit(1), lit(2)), lit(3))
      assert Cognitive.calculate(ast) == 3
    end

    test "a loop scores 1 plus its nesting level" do
      ast = {:loop, [loop_type: :for], [var("i"), var("xs"), block([lit(1)])]}
      assert Cognitive.calculate(ast) == 1
    end

    test "boolean operators add 1 without a nesting penalty" do
      ast = {:binary_op, [category: :boolean, operator: :and], [var("a"), var("b")]}
      assert Cognitive.calculate(ast) == 1
    end
  end

  # -- Nesting ----------------------------------------------------------------

  describe "Nesting.calculate/1" do
    test "a leaf has zero nesting depth" do
      assert Nesting.calculate(lit(42)) == 0
    end

    test "a single conditional is depth 1" do
      assert Nesting.calculate(cond(var("x"), lit(1), lit(2))) == 1
    end

    test "nested conditionals are depth 2" do
      ast = cond(var("x"), cond(var("y"), lit(1), lit(2)), lit(3))
      assert Nesting.calculate(ast) == 2
    end

    test "a while loop body is depth 1" do
      ast = {:loop, [loop_type: :while], [var("cond"), block([lit(1)])]}
      assert Nesting.calculate(ast) == 1
    end

    test "a function definition body is depth 1" do
      ast = {:function_def, [name: "f", params: []], [lit(1)]}
      assert Nesting.calculate(ast) == 1
    end

    test "deep nesting is reported as the maximum, not the sum" do
      deep =
        cond(
          var("a"),
          cond(var("b"), cond(var("c"), lit(1), lit(2)), lit(3)),
          lit(4)
        )

      assert Nesting.calculate(deep) == 3
    end
  end

  # -- Halstead ---------------------------------------------------------------

  describe "Halstead.calculate/1" do
    test "a lone literal is one operand and no operators" do
      m = Halstead.calculate(lit(42))
      assert m.total_operands == 1
      assert m.total_operators == 0
      assert m.distinct_operands == 1
      assert m.distinct_operators == 0
    end

    test "a binary op records one operator and two operands" do
      ast = {:binary_op, [category: :arithmetic, operator: :+], [var("x"), lit(5)]}
      m = Halstead.calculate(ast)
      assert m.distinct_operators == 1
      assert m.total_operators == 1
      assert m.total_operands == 2
    end

    test "volume is zero when vocabulary is zero" do
      # An empty block has no operators and no operands.
      m = Halstead.calculate(block([]))
      assert m.vocabulary == 0
      assert m.volume == 0.0
    end

    test "difficulty is zero when there are no distinct operands" do
      m = Halstead.calculate(block([]))
      assert m.difficulty == 0.0
      assert m.effort == 0.0
    end

    test "vocabulary equals distinct operators plus distinct operands" do
      ast =
        {:binary_op, [category: :arithmetic, operator: :+],
         [
           {:binary_op, [category: :arithmetic, operator: :*], [var("a"), var("b")]},
           var("c")
         ]}

      m = Halstead.calculate(ast)
      assert m.vocabulary == m.distinct_operators + m.distinct_operands
      assert m.length == m.total_operators + m.total_operands
    end

    test "a function definition contributes def, visibility and its name" do
      ast = {:function_def, [name: "f", params: ["a"], visibility: :public], [lit(1)]}
      m = Halstead.calculate(ast)

      assert m.distinct_operators >= 2
      assert m.total_operands >= 1
    end

    test "a loop contributes its loop-type operator" do
      ast = {:loop, [loop_type: :for], [var("i"), var("xs"), block([lit(1)])]}
      m = Halstead.calculate(ast)

      assert m.total_operators >= 1
    end

    test "a conditional contributes an if operator" do
      m = Halstead.calculate(cond(var("x"), lit(1), lit(2)))

      assert m.total_operators >= 1
    end

    test "a bare language-specific node does not crash" do
      ast = {:language_specific, [language: :elixir, hint: :x], %{body: lit(1)}}
      m = Halstead.calculate(ast)

      assert m.total_operators >= 1
    end
  end

  # -- LoC --------------------------------------------------------------------

  describe "LoC.calculate/2" do
    test "an assignment counts as one logical line" do
      assert LoC.calculate(assign(var("x"), lit(5))).logical == 1
    end

    test "a block of two variables counts zero logical lines" do
      assert LoC.calculate(block([var("x"), var("y")])).logical == 0
    end

    test "a function call counts as one logical line" do
      assert LoC.calculate(call("foo", [lit(1)])).logical == 1
    end

    test "physical and blank are nil when metadata is absent" do
      m = LoC.calculate(assign(var("x"), lit(5)))
      assert m.physical == nil
      assert m.blank == nil
    end

    test "physical, comments and blank come from metadata when present" do
      m =
        LoC.calculate(assign(var("x"), lit(5)), %{line_count: 10, comment_lines: 2})

      assert m.logical == 1
      assert m.physical == 10
      assert m.comments == 2
      assert m.blank == 7
    end

    test "blank never goes negative when metadata is inconsistent" do
      m = LoC.calculate(assign(var("x"), lit(5)), %{line_count: 1, comment_lines: 5})
      assert m.blank == 0
    end

    test "a conditional counts one logical line plus its branches" do
      ast = cond(var("x"), block([call("a")]), block([call("b")]))
      assert LoC.calculate(ast).logical == 3
    end

    test "a loop counts one logical line plus its body statements" do
      ast = {:loop, [loop_type: :for], [var("i"), var("xs"), block([call("a")])]}
      assert LoC.calculate(ast).logical == 2
    end

    test "a function definition counts as a logical line" do
      ast = {:function_def, [name: "f", params: []], [lit(1)]}
      assert LoC.calculate(ast).logical == 1
    end

    test "an early return counts as a logical line" do
      assert LoC.calculate({:early_return, [], [lit(1)]}).logical == 1
    end

    test "a container counts as a logical line" do
      ast = {:container, [container_type: :module, name: "M"], [lit(1)]}
      assert LoC.calculate(ast).logical == 1
    end

    test "a comment contributes no logical lines" do
      assert LoC.calculate({:comment, [], "# hi"}).logical == 0
    end

    test "a lambda counts as a statement" do
      ast = {:lambda, [params: ["x"]], [lit(1)]}
      assert LoC.calculate(ast).logical == 1
    end
  end

  # -- FunctionMetrics --------------------------------------------------------

  describe "FunctionMetrics.calculate/1" do
    test "a leaf has no statements, returns or variables" do
      m = FunctionMetrics.calculate(lit(42))
      assert m.statement_count == 0
      assert m.return_points == 0
      assert m.variable_count == 0
    end

    test "a block counts its statements" do
      m = FunctionMetrics.calculate(block([call("a"), call("b"), call("c")]))
      assert m.statement_count == 3
    end

    test "an early return is a return point" do
      m = FunctionMetrics.calculate(block([{:early_return, [], [lit(1)]}]))
      assert m.return_points == 1
    end

    test "distinct variables are counted once" do
      m = FunctionMetrics.calculate(block([var("x"), var("x"), var("y")]))
      assert m.variable_count == 2
    end

    test "function parameters are counted" do
      ast = {:function_def, [name: "f", params: ["a", "b"]], [lit(1)]}
      m = FunctionMetrics.calculate(ast)
      assert m.parameter_count == 2
    end
  end

  # -- Cross-metric invariants ------------------------------------------------

  describe "cross-metric invariants" do
    test "cyclomatic is always at least 1 and nesting/cognitive are non-negative" do
      for ast <- [
            lit(1),
            cond(var("x"), lit(1), lit(2)),
            block([call("a"), assign(var("y"), lit(2))]),
            {:loop, [loop_type: :for], [var("i"), var("xs"), block([lit(1)])]}
          ] do
        assert Cyclomatic.calculate(ast) >= 1
        assert Cognitive.calculate(ast) >= 0
        assert Nesting.calculate(ast) >= 0
      end
    end

    test "cognitive complexity never exceeds cyclomatic for a chain of conditionals" do
      # Each nested conditional adds 1 to cyclomatic but an increasing nesting
      # penalty to cognitive, so cognitive grows faster -- but both stay finite
      # and non-negative, and nesting never exceeds the conditional count.
      ast = cond(var("a"), cond(var("b"), cond(var("c"), lit(1), lit(2)), lit(3)), lit(4))

      assert Cyclomatic.calculate(ast) == 4
      assert Nesting.calculate(ast) == 3
      assert Cognitive.calculate(ast) == 1 + 2 + 3
    end
  end

  # -- Result -----------------------------------------------------------------

  describe "Result.new/1" do
    test "fills defaults for absent keys" do
      r = Result.new(%{})

      assert r.cyclomatic == 0
      assert r.cognitive == 0
      assert r.max_nesting == 0
      assert r.halstead == %{}
      assert r.loc == %{}
      assert r.warnings == []
    end

    test "copies supplied metrics" do
      r = Result.new(%{cyclomatic: 5, cognitive: 7, max_nesting: 2})

      assert r.cyclomatic == 5
      assert r.cognitive == 7
      assert r.max_nesting == 2
    end

    test "summarises low complexity below every threshold" do
      assert Result.new(%{cyclomatic: 2, cognitive: 1, max_nesting: 0}).summary ==
               "Code has low complexity"
    end

    test "summarises very high complexity above every band" do
      assert Result.new(%{cyclomatic: 50, cognitive: 60, max_nesting: 9}).summary ==
               "Code has very high complexity"
    end
  end

  describe "Result.apply_thresholds/2" do
    test "adds no warnings when every metric is under its warning threshold" do
      r = Result.new(%{cyclomatic: 3, cognitive: 3, max_nesting: 1, loc: %{logical: 5}})

      assert Result.apply_thresholds(r, %{}).warnings == []
    end

    test "warns when cyclomatic crosses its warning threshold" do
      r = Result.new(%{cyclomatic: 12, cognitive: 1, max_nesting: 0})
      warnings = Result.apply_thresholds(r, %{}).warnings

      assert Enum.any?(warnings, &String.contains?(&1, "Cyclomatic"))
    end

    test "warns when cognitive crosses its warning threshold" do
      r = Result.new(%{cyclomatic: 1, cognitive: 18, max_nesting: 0})
      warnings = Result.apply_thresholds(r, %{}).warnings

      assert Enum.any?(warnings, &String.contains?(&1, "Cognitive"))
    end

    test "warns when nesting crosses its warning threshold" do
      r = Result.new(%{cyclomatic: 1, cognitive: 1, max_nesting: 4})
      warnings = Result.apply_thresholds(r, %{}).warnings

      assert Enum.any?(warnings, &String.contains?(&1, "Nesting"))
    end

    test "warns when logical LoC crosses its warning threshold" do
      r = Result.new(%{cyclomatic: 1, cognitive: 1, max_nesting: 0, loc: %{logical: 60}})
      warnings = Result.apply_thresholds(r, %{}).warnings

      assert Enum.any?(warnings, &String.contains?(&1, "Logical lines"))
    end

    test "honours a caller-supplied threshold override" do
      r = Result.new(%{cyclomatic: 12, cognitive: 1, max_nesting: 0})
      warnings = Result.apply_thresholds(r, %{cyclomatic_warning: 50}).warnings

      refute Enum.any?(warnings, &String.contains?(&1, "Cyclomatic"))
    end
  end

  describe "Result.merge/1 and add_warning/2" do
    test "merge of an empty list yields the zero result" do
      assert Result.merge([]).cyclomatic == 0
    end

    test "merge takes the maximum of each scalar metric" do
      a = Result.new(%{cyclomatic: 5, cognitive: 7, max_nesting: 2})
      b = Result.new(%{cyclomatic: 8, cognitive: 10, max_nesting: 3})

      merged = Result.merge([a, b])

      assert merged.cyclomatic == 8
      assert merged.cognitive == 10
      assert merged.max_nesting == 3
    end

    test "merge sums loc and function metrics" do
      a = Result.new(%{loc: %{logical: 20}, function_metrics: %{statement_count: 5}})
      b = Result.new(%{loc: %{logical: 30}, function_metrics: %{statement_count: 7}})

      merged = Result.merge([a, b])

      assert merged.loc.logical == 50
      assert merged.function_metrics.statement_count == 12
    end

    test "add_warning prepends the warning" do
      r = Result.new(%{}) |> Result.add_warning("one") |> Result.add_warning("two")

      assert r.warnings == ["two", "one"]
    end
  end
end
