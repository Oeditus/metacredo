defmodule MetaCredo.Check.ReadabilityDesignTest do
  use MetaCredo.CheckCase

  alias MetaCredo.Check.{Readability, Design, Refactor, Observability}

  # ── MagicNumber ────────────────────────────────────────────────────

  describe "Readability.MagicNumber" do
    test "detects magic number in arithmetic" do
      ast = binop(:arithmetic, :+, var("x"), literal_int(42), line: 7)
      issues = run_check(Readability.MagicNumber, ast: ast)
      assert_issue(issues, trigger: "42", category: :readability)
    end

    test "ignores 0, 1, -1 by default" do
      for n <- [0, 1, -1] do
        ast = binop(:arithmetic, :+, var("x"), literal_int(n), line: 1)
        issues = run_check(Readability.MagicNumber, ast: ast)
        assert_no_issues(issues)
      end
    end

    test "respects custom ignored_numbers param" do
      ast = binop(:arithmetic, :*, var("x"), literal_int(100), line: 3)

      issues =
        run_check(Readability.MagicNumber, ast: ast, params: [ignored_numbers: [0, 1, -1, 100]])

      assert_no_issues(issues)
    end

    test "ignores numbers outside expressions" do
      ast = literal_int(42, line: 1)
      issues = run_check(Readability.MagicNumber, ast: ast)
      assert_no_issues(issues)
    end

    test "detects magic number in nested expression" do
      inner = binop(:arithmetic, :*, var("y"), literal_int(7))
      ast = binop(:arithmetic, :+, var("x"), inner, line: 5)
      issues = run_check(Readability.MagicNumber, ast: ast)
      assert_issue(issues, trigger: "7")
    end
  end

  # ── DeepNesting ────────────────────────────────────────────────────

  describe "Readability.DeepNesting" do
    test "detects deeply nested conditionals inside function_def" do
      # DeepNesting only triggers on :function_def nodes
      body =
        conditional(
          var("a"),
          conditional(
            var("b"),
            conditional(
              var("c"),
              conditional(
                var("d"),
                conditional(var("e"), literal_int(1), literal_int(2)),
                literal_int(3)
              ),
              literal_int(4)
            ),
            literal_int(5)
          ),
          literal_int(6)
        )

      ast = function_def("deep", ["x"], [body], line: 1)
      issues = run_check(Readability.DeepNesting, ast: ast)
      assert_issue(issues, message: ~r/nesting/i)
    end

    test "passes for shallow nesting in function_def" do
      body = conditional(var("a"), literal_int(1), literal_int(2))
      ast = function_def("shallow", ["x"], [body], line: 1)
      issues = run_check(Readability.DeepNesting, ast: ast)
      assert_no_issues(issues)
    end

    test "respects custom threshold" do
      body =
        conditional(
          var("a"),
          conditional(var("b"), literal_int(1), literal_int(2)),
          literal_int(3)
        )

      ast = function_def("nested", ["x"], [body], line: 1)
      issues = run_check(Readability.DeepNesting, ast: ast, params: [max_nesting: 1])
      assert_issue(issues, message: ~r/nesting/i)
    end
  end

  # ── LongFunction ───────────────────────────────────────────────────

  describe "Readability.LongFunction" do
    test "detects function with too many statements" do
      stmts = for i <- 1..55, do: assign(var("x#{i}"), literal_int(i), line: i)
      ast = function_def("big_func", ["a"], stmts, line: 1)

      issues = run_check(Readability.LongFunction, ast: ast)
      assert_issue(issues, message: ~r/statements|long/i)
    end

    test "passes for short functions" do
      stmts = [assign(var("x"), literal_int(1)), assign(var("y"), literal_int(2))]
      ast = function_def("small", ["a"], stmts, line: 1)

      issues = run_check(Readability.LongFunction, ast: ast)
      assert_no_issues(issues)
    end
  end

  # ── LongParameterList ──────────────────────────────────────────────

  describe "Readability.LongParameterList" do
    test "detects function with too many params" do
      params = ~W[a b c d e f g]
      ast = function_def("many_args", params, [literal_int(1)], line: 10)

      issues = run_check(Readability.LongParameterList, ast: ast)
      assert_issue(issues, message: ~r/param/i)
    end

    test "passes for functions with few params" do
      ast = function_def("ok_func", ["a", "b"], [literal_int(1)], line: 1)
      issues = run_check(Readability.LongParameterList, ast: ast)
      assert_no_issues(issues)
    end
  end

  # ── ComplexConditional ─────────────────────────────────────────────

  describe "Readability.ComplexConditional" do
    test "detects deeply nested boolean operations" do
      # (a and (b or (c and d)))
      inner = binop(:boolean, :and, var("c"), var("d"))
      mid = binop(:boolean, :or, var("b"), inner)
      outer = binop(:boolean, :and, var("a"), mid)

      ast = conditional(outer, literal_int(1), literal_int(2), line: 5)
      issues = run_check(Readability.ComplexConditional, ast: ast)
      assert_issue(issues, message: ~r/complex|conditional/i)
    end

    test "passes for simple conditions" do
      ast = conditional(var("flag"), literal_int(1), literal_int(2), line: 1)
      issues = run_check(Readability.ComplexConditional, ast: ast)
      assert_no_issues(issues)
    end
  end

  # ── SimplifyConditional ────────────────────────────────────────────

  describe "Refactor.SimplifyConditional" do
    test "detects if x do true else false end" do
      _ast_symbol =
        conditional(
          var("x"),
          literal_symbol(true, subtype: :boolean),
          literal_symbol(false, subtype: :boolean),
          line: 3
        )

      # literal_symbol uses :symbol subtype by default, but the check
      # should detect {:literal, [subtype: :boolean], true/false}
      ast_bool =
        conditional(
          var("x"),
          {:literal, [subtype: :boolean], true},
          {:literal, [subtype: :boolean], false},
          line: 3
        )

      issues = run_check(Refactor.SimplifyConditional, ast: ast_bool)
      assert_issue(issues, message: ~r/simplif/i)
    end
  end

  # ── HighComplexity ─────────────────────────────────────────────────

  describe "Design.HighComplexity" do
    test "detects highly complex function" do
      # Build a function with many decision points
      branches =
        for i <- 1..12 do
          conditional(var("x#{i}"), literal_int(i), literal_int(0))
        end

      ast = function_def("complex", ["x"], branches, line: 1)
      issues = run_check(Design.HighComplexity, ast: ast)
      assert_issue(issues, message: ~r/complexity|cyclomatic/i)
    end

    test "passes for simple functions" do
      ast = function_def("simple", ["x"], [literal_int(1)], line: 1)
      issues = run_check(Design.HighComplexity, ast: ast)
      assert_no_issues(issues)
    end
  end

  # ── HighCoupling ───────────────────────────────────────────────────

  describe "Design.HighCoupling" do
    test "detects module with too many qualified calls" do
      # HighCoupling extracts deps from qualified function calls (Module.func)
      calls = for i <- 1..12, do: call("Mod#{i}.func", [literal_int(i)])
      ast = container(:module, "BigModule", calls, line: 1)

      issues = run_check(Design.HighCoupling, ast: ast)
      assert_issue(issues, message: ~r/depend/i)
    end

    test "passes for module with few dependencies" do
      calls = [call("Ecto.Query.from", []), call("Logger.info", [literal_string("ok")])]
      ast = container(:module, "SmallModule", calls, line: 1)

      issues = run_check(Design.HighCoupling, ast: ast)
      assert_no_issues(issues)
    end
  end

  # ── Observability ──────────────────────────────────────────────────

  describe "Observability.MissingTelemetryInObanWorker" do
    test "detects perform/1 without telemetry" do
      ast =
        container(
          :module,
          "MyWorker",
          [
            import_node("Oban.Worker"),
            function_def(
              "perform",
              ["job"],
              [
                call("do_work", [var("job")], line: 10)
              ],
              line: 9
            )
          ],
          line: 1
        )

      issues = run_check(Observability.MissingTelemetryInObanWorker, ast: ast)
      assert_issue(issues, message: ~r/telemetry|oban/i)
    end
  end

  describe "Observability.TelemetryInRecursiveFunction" do
    test "detects telemetry inside recursive function" do
      ast =
        function_def(
          "process",
          ["list"],
          [
            call(":telemetry.execute", [literal_symbol(:event), var("m")], line: 5),
            call("process", [var("rest")], line: 6)
          ],
          line: 4
        )

      issues = run_check(Observability.TelemetryInRecursiveFunction, ast: ast)
      assert_issue(issues, message: ~r/telemetry.*recurs/i)
    end
  end
end
