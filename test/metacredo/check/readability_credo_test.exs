defmodule MetaCredo.Check.ReadabilityCredoTest do
  use MetaCredo.CheckCase

  alias MetaCredo.Check.Readability

  # -- FunctionNames --------------------------------------------------------

  describe "Readability.FunctionNames" do
    test "detects camelCase function name" do
      ast = function_def("myFunction", ["x"], [literal_int(1)], line: 3)
      issues = run_check(Readability.FunctionNames, ast: ast)
      assert_issue(issues, trigger: "myFunction", category: :readability)
    end

    test "passes for snake_case function name" do
      ast = function_def("my_function", ["x"], [literal_int(1)], line: 1)
      issues = run_check(Readability.FunctionNames, ast: ast)
      assert_no_issues(issues)
    end

    test "passes for function names ending with ? or !" do
      for name <- ["valid?", "save!"] do
        ast = function_def(name, ["x"], [literal_int(1)], line: 1)
        issues = run_check(Readability.FunctionNames, ast: ast)
        assert_no_issues(issues)
      end
    end

    test "detects PascalCase function name" do
      ast = function_def("DoSomething", ["x"], [literal_int(1)], line: 5)
      issues = run_check(Readability.FunctionNames, ast: ast)
      assert_issue(issues, trigger: "DoSomething")
    end
  end

  # -- ModuleNames ----------------------------------------------------------

  describe "Readability.ModuleNames" do
    test "detects snake_case module name" do
      ast = container(:module, "my_module", [literal_int(1)], line: 1)
      issues = run_check(Readability.ModuleNames, ast: ast)
      assert_issue(issues, trigger: "my_module", category: :readability)
    end

    test "passes for PascalCase module name" do
      ast = container(:module, "MyModule", [literal_int(1)], line: 1)
      issues = run_check(Readability.ModuleNames, ast: ast)
      assert_no_issues(issues)
    end

    test "passes for dotted PascalCase module name" do
      ast = container(:module, "MyApp.UserAccount", [literal_int(1)], line: 1)
      issues = run_check(Readability.ModuleNames, ast: ast)
      assert_no_issues(issues)
    end

    test "detects lowercase module name" do
      ast = container(:module, "badname", [literal_int(1)], line: 2)
      issues = run_check(Readability.ModuleNames, ast: ast)
      assert_issue(issues, trigger: "badname")
    end
  end

  # -- VariableNames --------------------------------------------------------

  describe "Readability.VariableNames" do
    test "detects camelCase variable" do
      ast = var("myVar", line: 5)
      issues = run_check(Readability.VariableNames, ast: ast)
      assert_issue(issues, trigger: "myVar", category: :readability)
    end

    test "passes for snake_case variable" do
      ast = var("my_var", line: 1)
      issues = run_check(Readability.VariableNames, ast: ast)
      assert_no_issues(issues)
    end

    test "passes for underscore-prefixed variable" do
      ast = var("_unused", line: 1)
      issues = run_check(Readability.VariableNames, ast: ast)
      assert_no_issues(issues)
    end

    test "detects UPPER_CASE variable" do
      ast = var("MY_VAR", line: 3)
      issues = run_check(Readability.VariableNames, ast: ast)
      assert_issue(issues, trigger: "MY_VAR")
    end
  end

  # -- ModuleDoc ------------------------------------------------------------

  describe "Readability.ModuleDoc" do
    test "detects module without doc comment" do
      ast =
        container(
          :module,
          "NoDocs",
          [
            function_def("foo", [], [literal_int(1)])
          ],
          line: 1
        )

      issues = run_check(Readability.ModuleDoc, ast: ast)
      assert_issue(issues, trigger: "NoDocs", category: :readability)
    end

    test "passes for module with doc comment" do
      doc = {:comment, [comment_kind: :doc], "Module documentation"}

      ast =
        container(
          :module,
          "Documented",
          [
            doc,
            function_def("foo", [], [literal_int(1)])
          ],
          line: 1
        )

      issues = run_check(Readability.ModuleDoc, ast: ast)
      assert_no_issues(issues)
    end
  end

  # -- SinglePipe -----------------------------------------------------------

  describe "Readability.SinglePipe" do
    test "detects single-step pipe" do
      ast = {:pipe, [line: 3], [var("x"), call("String.upcase", [])]}
      issues = run_check(Readability.SinglePipe, ast: ast)
      assert_issue(issues, trigger: "|>", category: :readability)
    end

    test "passes for multi-step pipe" do
      inner_pipe = {:pipe, [line: 3], [var("x"), call("String.trim", [])]}
      ast = {:pipe, [line: 3], [inner_pipe, call("String.upcase", [])]}
      issues = run_check(Readability.SinglePipe, ast: ast)
      assert_no_issues(issues)
    end
  end

  # -- NestedFunctionCalls --------------------------------------------------

  describe "Readability.NestedFunctionCalls" do
    test "detects deeply nested calls" do
      # foo(bar(baz(qux(x)))) -- depth 3
      innermost = call("qux", [var("x")])
      inner = call("baz", [innermost])
      mid = call("bar", [inner])
      ast = call("foo", [mid], line: 7)

      issues = run_check(Readability.NestedFunctionCalls, ast: ast)
      assert_issue(issues, message: ~r/nested/i)
    end

    test "passes for shallow nesting" do
      # foo(bar(x)) -- depth 1
      inner = call("bar", [var("x")])
      ast = call("foo", [inner], line: 1)

      issues = run_check(Readability.NestedFunctionCalls, ast: ast)
      assert_no_issues(issues)
    end

    test "respects custom max_nesting param" do
      inner = call("bar", [var("x")])
      ast = call("foo", [inner], line: 1)

      issues = run_check(Readability.NestedFunctionCalls, ast: ast, params: [max_nesting: 0])
      assert_issue(issues, message: ~r/nested/i)
    end
  end

  # -- Specs ----------------------------------------------------------------

  describe "Readability.Specs" do
    test "detects public function without @spec" do
      ast =
        container(
          :module,
          "NoSpecs",
          [
            function_def("public_func", ["x"], [literal_int(1)], line: 3, visibility: :public)
          ],
          line: 1
        )

      issues = run_check(Readability.Specs, ast: ast)
      assert_issue(issues, trigger: "public_func", category: :readability)
    end

    test "passes when @spec precedes public function" do
      spec = {:type_annotation, [annotation_type: :spec, line: 2], []}

      ast =
        container(
          :module,
          "HasSpecs",
          [
            spec,
            function_def("public_func", ["x"], [literal_int(1)], line: 3, visibility: :public)
          ],
          line: 1
        )

      issues = run_check(Readability.Specs, ast: ast)
      assert_no_issues(issues)
    end

    test "skips private functions" do
      ast =
        container(
          :module,
          "Private",
          [
            function_def("private_func", ["x"], [literal_int(1)], line: 3, visibility: :private)
          ],
          line: 1
        )

      issues = run_check(Readability.Specs, ast: ast)
      assert_no_issues(issues)
    end
  end

  # -- LargeNumbers ---------------------------------------------------------

  describe "Readability.LargeNumbers" do
    test "detects large number without separators" do
      ast = literal_int(100_000, subtype: :integer, line: 5)
      issues = run_check(Readability.LargeNumbers, ast: ast)
      assert_issue(issues, trigger: "100000", category: :readability)
    end

    test "passes for small numbers" do
      ast = literal_int(999, subtype: :integer, line: 1)
      issues = run_check(Readability.LargeNumbers, ast: ast)
      assert_no_issues(issues)
    end

    test "passes for numbers with separator flag" do
      ast = literal_int(100_000, subtype: :integer, has_separator: true, line: 1)
      issues = run_check(Readability.LargeNumbers, ast: ast)
      assert_no_issues(issues)
    end
  end
end
