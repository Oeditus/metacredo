defmodule MetaCredo.Check.WarningCredoTest do
  use MetaCredo.CheckCase

  alias MetaCredo.Check.Warning

  # ── UnusedOperation ─────────────────────────────────────────────────

  describe "UnusedOperation" do
    test "detects unused function call result in block" do
      ast =
        block([
          call("String.upcase", [var("name")], line: 3),
          call("do_something", [var("name")], line: 4)
        ])

      issues = run_check(Warning.UnusedOperation, ast: ast)
      assert_issue(issues, message: ~r/unused/i, line_no: 3)
    end

    test "ignores last statement in block" do
      ast =
        block([
          assign(var("x"), literal_int(1), line: 1),
          call("String.upcase", [var("name")], line: 2)
        ])

      issues = run_check(Warning.UnusedOperation, ast: ast)
      assert_no_issues(issues)
    end

    test "ignores side-effect calls like Logger" do
      ast =
        block([
          call("Logger.info", [literal_string("msg")], line: 1),
          call("do_work", [], line: 2)
        ])

      issues = run_check(Warning.UnusedOperation, ast: ast)
      assert_no_issues(issues)
    end

    test "ignores single-statement blocks" do
      ast = block([call("String.upcase", [var("name")], line: 1)])
      issues = run_check(Warning.UnusedOperation, ast: ast)
      assert_no_issues(issues)
    end
  end

  # ── UnsafeExec ──────────────────────────────────────────────────────

  describe "UnsafeExec" do
    test "detects System.cmd with user input variable" do
      ast = call("System.cmd", [literal_string("ls"), var("user_input")], line: 5)
      issues = run_check(Warning.UnsafeExec, ast: ast)
      assert_issue(issues, message: ~r/command injection/i)
    end

    test "detects os:cmd with param variable" do
      ast = call(":os.cmd", [var("request_params")], line: 10)
      issues = run_check(Warning.UnsafeExec, ast: ast)
      assert_issue(issues, message: ~r/Unsafe exec/i)
    end

    test "ignores exec with literal arguments" do
      ast = call("System.cmd", [literal_string("ls"), literal_string("-la")], line: 1)
      issues = run_check(Warning.UnsafeExec, ast: ast)
      assert_no_issues(issues)
    end

    test "ignores non-exec functions with user input" do
      ast = call("String.upcase", [var("user_input")], line: 1)
      issues = run_check(Warning.UnsafeExec, ast: ast)
      assert_no_issues(issues)
    end
  end

  # ── BoolOperationOnSameValues ───────────────────────────────────────

  describe "BoolOperationOnSameValues" do
    test "detects x and x" do
      ast = binop(:boolean, :and, var("flag"), var("flag"), line: 7)
      issues = run_check(Warning.BoolOperationOnSameValues, ast: ast)
      assert_issue(issues, message: ~r/identical operands/i)
    end

    test "detects x or x" do
      ast = binop(:boolean, :or, var("flag"), var("flag"), line: 3)
      issues = run_check(Warning.BoolOperationOnSameValues, ast: ast)
      assert_issue(issues, trigger: "or")
    end

    test "ignores x and y (different operands)" do
      ast = binop(:boolean, :and, var("a"), var("b"), line: 1)
      issues = run_check(Warning.BoolOperationOnSameValues, ast: ast)
      assert_no_issues(issues)
    end

    test "ignores non-boolean operations" do
      ast = binop(:arithmetic, :+, var("x"), var("x"), line: 1)
      issues = run_check(Warning.BoolOperationOnSameValues, ast: ast)
      assert_no_issues(issues)
    end
  end

  # ── OperationOnSameValues ───────────────────────────────────────────

  describe "OperationOnSameValues" do
    test "detects x - x (always 0)" do
      ast = binop(:arithmetic, :-, var("count"), var("count"), line: 12)
      issues = run_check(Warning.OperationOnSameValues, ast: ast)
      assert_issue(issues, message: ~r/always 0/)
    end

    test "detects x / x (always 1)" do
      ast = binop(:arithmetic, :/, var("total"), var("total"), line: 8)
      issues = run_check(Warning.OperationOnSameValues, ast: ast)
      assert_issue(issues, message: ~r/always 1/)
    end

    test "ignores x - y (different operands)" do
      ast = binop(:arithmetic, :-, var("a"), var("b"), line: 1)
      issues = run_check(Warning.OperationOnSameValues, ast: ast)
      assert_no_issues(issues)
    end

    test "ignores x + x (not a constant result)" do
      ast = binop(:arithmetic, :+, var("x"), var("x"), line: 1)
      issues = run_check(Warning.OperationOnSameValues, ast: ast)
      assert_no_issues(issues)
    end
  end

  # ── OperationWithConstantResult ─────────────────────────────────────

  describe "OperationWithConstantResult" do
    test "detects x * 0" do
      ast = binop(:arithmetic, :*, var("count"), literal_int(0), line: 5)
      issues = run_check(Warning.OperationWithConstantResult, ast: ast)
      assert_issue(issues, message: ~r/always 0/)
    end

    test "detects 0 * x" do
      ast = binop(:arithmetic, :*, literal_int(0), var("count"), line: 6)
      issues = run_check(Warning.OperationWithConstantResult, ast: ast)
      assert_issue(issues, trigger: "*")
    end

    test "detects x + 0" do
      ast = binop(:arithmetic, :+, var("count"), literal_int(0), line: 9)
      issues = run_check(Warning.OperationWithConstantResult, ast: ast)
      assert_issue(issues, message: ~r/no-op identity/)
    end

    test "detects 0 + x" do
      ast = binop(:arithmetic, :+, literal_int(0), var("count"), line: 10)
      issues = run_check(Warning.OperationWithConstantResult, ast: ast)
      assert_issue(issues, trigger: "+")
    end

    test "ignores x * 2 (non-zero)" do
      ast = binop(:arithmetic, :*, var("x"), literal_int(2), line: 1)
      issues = run_check(Warning.OperationWithConstantResult, ast: ast)
      assert_no_issues(issues)
    end

    test "ignores x - 0 (not checked)" do
      ast = binop(:arithmetic, :-, var("x"), literal_int(0), line: 1)
      issues = run_check(Warning.OperationWithConstantResult, ast: ast)
      assert_no_issues(issues)
    end
  end

  # ── LazyLogging ─────────────────────────────────────────────────────

  describe "LazyLogging" do
    test "detects Logger.info with string interpolation" do
      interp = {:string_interpolation, [line: 4], [literal_string("user: "), var("name")]}
      ast = call("Logger.info", [interp], line: 4)
      issues = run_check(Warning.LazyLogging, ast: ast)
      assert_issue(issues, message: ~r/lazy logging/i)
    end

    test "detects Logger.error with interpolation" do
      interp = {:string_interpolation, [line: 8], [literal_string("failed: "), var("reason")]}
      ast = call("Logger.error", [interp], line: 8)
      issues = run_check(Warning.LazyLogging, ast: ast)
      assert_issue(issues, trigger: "Logger.error")
    end

    test "ignores Logger.info with plain string" do
      ast = call("Logger.info", [literal_string("static message")], line: 1)
      issues = run_check(Warning.LazyLogging, ast: ast)
      assert_no_issues(issues)
    end

    test "ignores non-Logger calls with interpolation" do
      interp = {:string_interpolation, [], [literal_string("hi "), var("name")]}
      ast = call("String.upcase", [interp], line: 1)
      issues = run_check(Warning.LazyLogging, ast: ast)
      assert_no_issues(issues)
    end
  end

  # ── DebugLeftover ───────────────────────────────────────────────────

  describe "DebugLeftover" do
    test "detects IO.inspect" do
      ast = call("IO.inspect", [var("data")], line: 15)
      issues = run_check(Warning.DebugLeftover, ast: ast)
      assert_issue(issues, message: ~r/Debug call/i, trigger: "IO.inspect")
    end

    test "detects dbg()" do
      ast = call("dbg", [var("value")], line: 20)
      issues = run_check(Warning.DebugLeftover, ast: ast)
      assert_issue(issues, trigger: "dbg")
    end

    test "detects console.log" do
      ast = call("console.log", [literal_string("debug")], line: 5)
      issues = run_check(Warning.DebugLeftover, ast: ast)
      assert_issue(issues, message: ~r/remove before production/i)
    end

    test "ignores regular function calls" do
      ast = call("Repo.get", [var("User"), var("id")], line: 1)
      issues = run_check(Warning.DebugLeftover, ast: ast)
      assert_no_issues(issues)
    end
  end

  # ── RaiseInsideRescue ───────────────────────────────────────────────

  describe "RaiseInsideRescue" do
    test "detects bare raise inside rescue" do
      ast =
        {:exception_handling, [line: 3],
         [
           call("dangerous", []),
           {:match_arm, [pattern: var("e"), line: 5],
            [call("raise", [literal_string("new error")], line: 6)]}
         ]}

      issues = run_check(Warning.RaiseInsideRescue, ast: ast)
      assert_issue(issues, message: ~r/reraise/i)
    end

    test "detects bare throw inside rescue" do
      ast =
        {:exception_handling, [line: 1],
         [
           call("work", []),
           {:match_arm, [pattern: var("_e")], [call("throw", [literal_symbol(:abort)], line: 4)]}
         ]}

      issues = run_check(Warning.RaiseInsideRescue, ast: ast)
      assert_issue(issues, message: ~r/stack trace/i)
    end

    test "passes when reraise is used" do
      ast =
        {:exception_handling, [line: 1],
         [
           call("work", []),
           {:match_arm, [pattern: var("e")],
            [call("reraise", [var("e"), var("__STACKTRACE__")], line: 4)]}
         ]}

      issues = run_check(Warning.RaiseInsideRescue, ast: ast)
      assert_no_issues(issues)
    end

    test "passes when rescue has no raise/throw" do
      ast =
        {:exception_handling, [line: 1],
         [
           call("work", []),
           {:match_arm, [pattern: var("e")], [call("Logger.error", [var("e")], line: 4)]}
         ]}

      issues = run_check(Warning.RaiseInsideRescue, ast: ast)
      assert_no_issues(issues)
    end
  end
end
