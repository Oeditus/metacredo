defmodule MetaCredo.Check.ConsistencyTest do
  use MetaCredo.CheckCase

  alias MetaCredo.Check.Consistency

  # ── ExceptionNames ──────────────────────────────────────────────────

  describe "ExceptionNames" do
    test "detects error-like class not ending in Error or Exception" do
      ast = container(:class, "InvalidInput", [literal_int(1)], line: 5)
      issues = run_check(Consistency.ExceptionNames, ast: ast)
      assert_issue(issues, message: ~r/Error.*Exception/i)
    end

    test "detects unauthorized class without proper suffix" do
      ast = container(:class, "Unauthorized", [literal_int(1)], line: 3)
      issues = run_check(Consistency.ExceptionNames, ast: ast)
      assert_issue(issues, trigger: "Unauthorized")
    end

    test "passes for class ending in Error" do
      ast = container(:class, "InvalidInputError", [literal_int(1)], line: 1)
      issues = run_check(Consistency.ExceptionNames, ast: ast)
      assert_no_issues(issues)
    end

    test "passes for class ending in Exception" do
      ast = container(:class, "TimeoutException", [literal_int(1)], line: 1)
      issues = run_check(Consistency.ExceptionNames, ast: ast)
      assert_no_issues(issues)
    end

    test "ignores non-error-like class names" do
      ast = container(:class, "UserController", [literal_int(1)], line: 1)
      issues = run_check(Consistency.ExceptionNames, ast: ast)
      assert_no_issues(issues)
    end

    test "ignores module containers (non-class)" do
      ast = container(:module, "InvalidInput", [literal_int(1)], line: 1)
      issues = run_check(Consistency.ExceptionNames, ast: ast)
      assert_no_issues(issues)
    end

    test "all issues are consistency category" do
      ast =
        block([
          container(:class, "BadRequest", [literal_int(1)], line: 1),
          container(:class, "Forbidden", [literal_int(1)], line: 5)
        ])

      issues = run_check(Consistency.ExceptionNames, ast: ast)
      assert_all_category(issues, :consistency)
    end
  end

  # ── ParameterPatternMatching ────────────────────────────────────────

  describe "ParameterPatternMatching" do
    test "detects body destructure via member_access on parameter" do
      body = [
        assign(
          var("user_name"),
          {:member_access, [field: "name"], [{:variable, [], "user"}]},
          line: 3
        )
      ]

      ast = function_def("greet", ["user"], body, line: 2)
      issues = run_check(Consistency.ParameterPatternMatching, ast: ast)
      assert_issue(issues, message: ~r/pattern matching in function head/i)
    end

    test "detects body destructure via field read on parameter" do
      # `user_name = opts.name` -- the adapter emits `opts.name` as
      # `Map.fetch!(opts, :name)`, and the target differs from the field.
      body = [
        assign(
          var("user_name"),
          call("Map.fetch!", [{:variable, [], "opts"}, literal_symbol(:name)],
            name: "Map.fetch!"
          ),
          line: 5
        )
      ]

      ast = function_def("process", ["opts"], body, line: 4)
      issues = run_check(Consistency.ParameterPatternMatching, ast: ast)
      assert_issue(issues, trigger: "process")
    end

    test "detects destructuring even when the target repeats the field name" do
      # `name = opts.name` is genuine destructuring: `name` is a field of the
      # `opts` parameter, so it belongs in the function head.
      body = [
        assign(
          var("name"),
          call("Map.fetch!", [{:variable, [], "opts"}, literal_symbol(:name)],
            name: "Map.fetch!"
          ),
          line: 5
        )
      ]

      ast = function_def("process", ["opts"], body, line: 4)
      issues = run_check(Consistency.ParameterPatternMatching, ast: ast)
      assert_issue(issues, trigger: "process")
    end

    test "passes when the field is a snake_case method name" do
      # `defaults = mod.param_defaults()` is a remote call, not a field read;
      # the adapter emits it as `Map.fetch!(mod, :param_defaults)`.
      body = [
        assign(
          var("defaults"),
          call("Map.fetch!", [{:variable, [], "opts"}, literal_symbol(:param_defaults)],
            name: "Map.fetch!"
          ),
          line: 5
        )
      ]

      ast = function_def("process", ["opts"], body, line: 4)
      issues = run_check(Consistency.ParameterPatternMatching, ast: ast)
      assert_no_issues(issues)
    end

    test "passes when a parameter is only read via Map.get" do
      # `Map.get(opts, :name)` is a lookup, not destructuring.
      body = [
        assign(
          var("name"),
          call("Map.get", [{:variable, [], "opts"}, literal_symbol(:name)], name: "Map.get"),
          line: 5
        )
      ]

      ast = function_def("process", ["opts"], body, line: 4)
      issues = run_check(Consistency.ParameterPatternMatching, ast: ast)
      assert_no_issues(issues)
    end

    test "passes when no body destructuring of params" do
      body = [
        assign(var("x"), literal_int(42), line: 3),
        call("IO.puts", [var("x")], line: 4)
      ]

      ast = function_def("simple", ["a"], body, line: 2)
      issues = run_check(Consistency.ParameterPatternMatching, ast: ast)
      assert_no_issues(issues)
    end

    test "passes for function without params" do
      body = [call("do_work", [], line: 2)]
      ast = function_def("work", [], body, line: 1)
      issues = run_check(Consistency.ParameterPatternMatching, ast: ast)
      assert_no_issues(issues)
    end

    test "ignores destructuring of non-parameter variables" do
      body = [
        assign(var("data"), call("fetch", []), line: 3),
        assign(
          var("name"),
          {:member_access, [field: "name"], [{:variable, [], "data"}]},
          line: 4
        )
      ]

      ast = function_def("process", ["id"], body, line: 2)
      issues = run_check(Consistency.ParameterPatternMatching, ast: ast)
      assert_no_issues(issues)
    end
  end
end
