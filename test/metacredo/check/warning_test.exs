defmodule MetaCredo.Check.WarningTest do
  use MetaCredo.CheckCase

  alias MetaCredo.Check.Warning

  # ── MissingErrorHandling ───────────────────────────────────────────

  describe "MissingErrorHandling" do
    test "detects {:ok, _} = function_call()" do
      ast =
        assign(
          tuple([literal_symbol(:ok), var("result")]),
          call("Repo.get", [var("User"), var("id")]),
          line: 10
        )

      issues = run_check(Warning.MissingErrorHandling, ast: ast)
      assert_issue(issues, category: :warning, line_no: 10)
    end

    test "detects {:ok, _} = nested in block" do
      ast =
        block([
          assign(
            tuple([literal_symbol(:ok), var("data")]),
            call("fetch_data", [var("url")]),
            line: 3
          )
        ])

      issues = run_check(Warning.MissingErrorHandling, ast: ast)
      assert_issue_count(issues, 1)
    end

    test "ignores regular variable assignments" do
      ast = assign(var("x"), literal_int(42), line: 5)
      issues = run_check(Warning.MissingErrorHandling, ast: ast)
      assert_no_issues(issues)
    end

    test "ignores {:ok, _} = literal (not a function call)" do
      ast =
        assign(
          tuple([literal_symbol(:ok), var("x")]),
          literal_int(42),
          line: 1
        )

      issues = run_check(Warning.MissingErrorHandling, ast: ast)
      assert_no_issues(issues)
    end
  end

  # ── SilentErrorCase ────────────────────────────────────────────────

  describe "SilentErrorCase" do
    test "detects conditional with only {:ok, _} arm and no error arm" do
      # SilentErrorCase matches :conditional nodes containing match_arm children
      ast =
        {:conditional, [line: 4],
         [
           call("do_work", []),
           match_arm(tuple([literal_symbol(:ok), var("result")]), [var("result")], line: 5)
         ]}

      issues = run_check(Warning.SilentErrorCase, ast: ast)
      assert_issue(issues, message: ~r/error/i)
    end

    test "passes when both :ok and :error arms present" do
      ast =
        {:conditional, [],
         [
           call("do_work", []),
           match_arm(tuple([literal_symbol(:ok), var("r")]), [var("r")]),
           match_arm(tuple([literal_symbol(:error), var("e")]), [var("e")])
         ]}

      issues = run_check(Warning.SilentErrorCase, ast: ast)
      assert_no_issues(issues)
    end
  end

  # ── SwallowingException ────────────────────────────────────────────

  describe "SwallowingException" do
    test "detects rescue with empty handler" do
      # SwallowingException looks for match_arm children directly in exception_handling
      ast =
        {:exception_handling, [line: 8],
         [
           call("dangerous", []),
           {:match_arm, [pattern: var("_e"), line: 10], []}
         ]}

      issues = run_check(Warning.SwallowingException, ast: ast)
      assert_issue(issues, message: ~r/swallow|exception/i)
    end

    test "passes when rescue handler has body" do
      ast =
        {:exception_handling, [],
         [
           call("dangerous", []),
           {:match_arm, [pattern: var("e")], [call("Logger.error", [var("e")])]}
         ]}

      issues = run_check(Warning.SwallowingException, ast: ast)
      assert_no_issues(issues)
    end
  end

  # ── NPlusOneQuery ──────────────────────────────────────────────────

  describe "NPlusOneQuery" do
    test "detects Repo call inside collection_op" do
      # NPlusOneQuery matches :collection_op nodes, not :function_call
      inner = call("Repo.get", [var("User"), var("id")], line: 7)
      lambda_body = {:lambda, [params: [{:param, [], "item"}]], [inner]}

      ast = {:collection_op, [op_type: :map, line: 6], [lambda_body, var("items")]}

      issues = run_check(Warning.NPlusOneQuery, ast: ast)
      assert_issue(issues, message: ~r/N\+1|query/i)
    end

    test "ignores Repo calls outside loops" do
      ast = call("Repo.get", [var("User"), var("id")], line: 3)
      issues = run_check(Warning.NPlusOneQuery, ast: ast)
      assert_no_issues(issues)
    end
  end

  # ── UnmanagedTask ──────────────────────────────────────────────────

  describe "UnmanagedTask" do
    test "detects Task.async without supervisor" do
      ast = call("Task.async", [var("fun")], line: 12)
      issues = run_check(Warning.UnmanagedTask, ast: ast)
      assert_issue(issues, message: ~r/Task|unsupervised/i)
    end

    test "passes for Task.Supervisor.async" do
      ast = call("Task.Supervisor.async", [var("sup"), var("fun")], line: 5)
      issues = run_check(Warning.UnmanagedTask, ast: ast)
      assert_no_issues(issues)
    end
  end

  # ── CallbackHell ───────────────────────────────────────────────────

  describe "CallbackHell" do
    test "detects deeply nested conditionals" do
      # CallbackHell matches :conditional nodes; 4 levels > default max of 3
      ast =
        conditional(
          var("a"),
          conditional(
            var("b"),
            conditional(
              var("c"),
              conditional(var("d"), literal_int(1), literal_int(2)),
              literal_int(3)
            ),
            literal_int(4)
          ),
          literal_int(5),
          line: 5
        )

      issues = run_check(Warning.CallbackHell, ast: ast)
      assert_issue(issues, message: ~r/nested|level/i)
    end

    test "passes for shallow nesting" do
      ast = conditional(var("a"), literal_int(1), literal_int(2), line: 1)
      issues = run_check(Warning.CallbackHell, ast: ast)
      assert_no_issues(issues)
    end
  end

  # ── InefficientFilter ──────────────────────────────────────────────

  describe "InefficientFilter" do
    test "detects Repo.all assigned then Enum.filter in block" do
      # InefficientFilter looks for assignment+collection_op pairs in blocks
      ast =
        block([
          assign(var("users"), call("Repo.all", [var("query")]), line: 9),
          {:collection_op, [op_type: :filter, line: 10],
           [
             {:lambda, [params: [{:param, [], "u"}]], [var("u")]},
             var("users")
           ]}
        ])

      issues = run_check(Warning.InefficientFilter, ast: ast)
      assert_issue(issues, message: ~r/filter|record/i)
    end

    test "ignores Enum.filter without Repo.all" do
      ast = call("Enum.filter", [var("list"), var("fun")], line: 1)
      issues = run_check(Warning.InefficientFilter, ast: ast)
      assert_no_issues(issues)
    end
  end

  # ── DirectStructUpdate ─────────────────────────────────────────────

  describe "DirectStructUpdate" do
    test "detects %User{user | field: val} pattern" do
      ast =
        {:record_update, [name: "User", line: 15],
         [
           var("user"),
           {:pair, [], [literal_symbol(:name), literal_string("new")]}
         ]}

      issues = run_check(Warning.DirectStructUpdate, ast: ast)
      assert_issue(issues, message: ~r/changeset|struct update/i)
    end
  end
end
