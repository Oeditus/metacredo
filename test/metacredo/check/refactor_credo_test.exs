defmodule MetaCredo.Check.RefactorCredoTest do
  use MetaCredo.CheckCase

  alias MetaCredo.Check.Refactor

  # -- NegatedConditionWithElse ---------------------------------------------

  describe "Refactor.NegatedConditionWithElse" do
    test "detects if(!x) with else branch" do
      negated = {:unary_op, [operator: :!, line: 3], [var("x")]}

      ast =
        conditional(
          negated,
          literal_int(1),
          literal_int(2),
          line: 3
        )

      issues = run_check(Refactor.NegatedConditionWithElse, ast: ast)
      assert_issue(issues, trigger: "!", category: :refactor)
    end

    test "detects if(not x) with else branch" do
      negated = {:unary_op, [operator: :not, line: 3], [var("x")]}

      ast =
        conditional(
          negated,
          literal_int(1),
          literal_int(2),
          line: 3
        )

      issues = run_check(Refactor.NegatedConditionWithElse, ast: ast)
      assert_issue(issues, trigger: "not")
    end

    test "passes for negated condition without else" do
      negated = {:unary_op, [operator: :!, line: 1], [var("x")]}
      ast = conditional(negated, literal_int(1), nil, line: 1)

      issues = run_check(Refactor.NegatedConditionWithElse, ast: ast)
      assert_no_issues(issues)
    end

    test "passes for non-negated condition with else" do
      ast = conditional(var("x"), literal_int(1), literal_int(2), line: 1)
      issues = run_check(Refactor.NegatedConditionWithElse, ast: ast)
      assert_no_issues(issues)
    end
  end

  # -- DoubleBooleanNegation ------------------------------------------------

  describe "Refactor.DoubleBooleanNegation" do
    test "detects !!x pattern" do
      inner = {:unary_op, [operator: :!, line: 5], [var("x")]}
      ast = {:unary_op, [operator: :!, line: 5], [inner]}

      issues = run_check(Refactor.DoubleBooleanNegation, ast: ast)
      assert_issue(issues, trigger: "!!", category: :refactor)
    end

    test "passes for single negation" do
      ast = {:unary_op, [operator: :!, line: 1], [var("x")]}
      issues = run_check(Refactor.DoubleBooleanNegation, ast: ast)
      assert_no_issues(issues)
    end

    test "passes for non-! unary operators" do
      inner = {:unary_op, [operator: :-, line: 1], [literal_int(5)]}
      ast = {:unary_op, [operator: :-, line: 1], [inner]}

      issues = run_check(Refactor.DoubleBooleanNegation, ast: ast)
      assert_no_issues(issues)
    end
  end

  # -- AppendSingleItem -----------------------------------------------------

  describe "Refactor.AppendSingleItem" do
    test "detects list ++ [item]" do
      single_list = {:list, [line: 7], [literal_int(42)]}
      ast = {:binary_op, [operator: :++, line: 7], [var("items"), single_list]}

      issues = run_check(Refactor.AppendSingleItem, ast: ast)
      assert_issue(issues, trigger: "++", category: :refactor)
    end

    test "passes for list ++ multi-element list" do
      multi_list = {:list, [line: 1], [literal_int(1), literal_int(2)]}
      ast = {:binary_op, [operator: :++, line: 1], [var("items"), multi_list]}

      issues = run_check(Refactor.AppendSingleItem, ast: ast)
      assert_no_issues(issues)
    end

    test "passes for non-++ binary op" do
      single_list = {:list, [line: 1], [literal_int(42)]}
      ast = {:binary_op, [operator: :--, line: 1], [var("items"), single_list]}

      issues = run_check(Refactor.AppendSingleItem, ast: ast)
      assert_no_issues(issues)
    end
  end

  # -- PipeChainStart -------------------------------------------------------

  describe "Refactor.PipeChainStart" do
    test "detects pipe starting with literal" do
      ast = {:pipe, [line: 4], [literal_string("hello"), call("String.upcase", [])]}
      issues = run_check(Refactor.PipeChainStart, ast: ast)
      assert_issue(issues, trigger: "|>", category: :refactor)
    end

    test "detects pipe chain starting with literal (multi-step)" do
      inner = {:pipe, [line: 4], [literal_int(42), call("Integer.to_string", [])]}
      ast = {:pipe, [line: 4], [inner, call("String.upcase", [])]}

      issues = run_check(Refactor.PipeChainStart, ast: ast)
      assert_issue(issues, trigger: "|>")
    end

    test "passes for pipe starting with variable" do
      ast = {:pipe, [line: 1], [var("data"), call("String.trim", [])]}
      issues = run_check(Refactor.PipeChainStart, ast: ast)
      assert_no_issues(issues)
    end

    test "passes for pipe starting with function call" do
      ast = {:pipe, [line: 1], [call("get_data", []), call("process", [])]}
      issues = run_check(Refactor.PipeChainStart, ast: ast)
      assert_no_issues(issues)
    end
  end

  # -- FilterCount ----------------------------------------------------------

  describe "Refactor.FilterCount" do
    test "detects Enum.filter |> Enum.count" do
      filter = call("Enum.filter", [var("list"), var("fun")], line: 10)
      count = call("Enum.count", [], line: 10)
      ast = {:pipe, [line: 10], [filter, count]}

      issues = run_check(Refactor.FilterCount, ast: ast)
      assert_issue(issues, trigger: "Enum.count", category: :refactor)
    end

    test "passes for Enum.map |> Enum.count" do
      map_call = call("Enum.map", [var("list"), var("fun")], line: 1)
      count = call("Enum.count", [], line: 1)
      ast = {:pipe, [line: 1], [map_call, count]}

      issues = run_check(Refactor.FilterCount, ast: ast)
      assert_no_issues(issues)
    end

    test "passes for Enum.filter |> Enum.map" do
      filter = call("Enum.filter", [var("list"), var("fun")], line: 1)
      map_call = call("Enum.map", [var("fun2")], line: 1)
      ast = {:pipe, [line: 1], [filter, map_call]}

      issues = run_check(Refactor.FilterCount, ast: ast)
      assert_no_issues(issues)
    end
  end

  # -- UnlessWithElse -------------------------------------------------------

  describe "Refactor.UnlessWithElse" do
    test "detects unless with else" do
      ast =
        {:conditional, [conditional_kind: :unless, line: 8],
         [var("x"), literal_int(1), literal_int(2)]}

      issues = run_check(Refactor.UnlessWithElse, ast: ast)
      assert_issue(issues, trigger: "unless", category: :refactor)
    end

    test "passes for unless without else" do
      ast =
        {:conditional, [conditional_kind: :unless, line: 1], [var("x"), literal_int(1), nil]}

      issues = run_check(Refactor.UnlessWithElse, ast: ast)
      assert_no_issues(issues)
    end

    test "passes for regular if with else" do
      ast = conditional(var("x"), literal_int(1), literal_int(2), line: 1)
      issues = run_check(Refactor.UnlessWithElse, ast: ast)
      assert_no_issues(issues)
    end
  end

  # -- VariableRebinding ----------------------------------------------------

  describe "Refactor.VariableRebinding" do
    test "detects variable rebound in same block" do
      ast =
        block([
          assign(var("x"), literal_int(1), line: 1),
          assign(var("x"), literal_int(2), line: 2)
        ])

      issues = run_check(Refactor.VariableRebinding, ast: ast)
      assert_issue(issues, trigger: "x", category: :refactor)
    end

    test "passes for distinct variable names" do
      ast =
        block([
          assign(var("x"), literal_int(1), line: 1),
          assign(var("y"), literal_int(2), line: 2)
        ])

      issues = run_check(Refactor.VariableRebinding, ast: ast)
      assert_no_issues(issues)
    end

    test "ignores underscore-prefixed variables" do
      ast =
        block([
          assign(var("_temp"), literal_int(1), line: 1),
          assign(var("_temp"), literal_int(2), line: 2)
        ])

      issues = run_check(Refactor.VariableRebinding, ast: ast)
      assert_no_issues(issues)
    end
  end
end
