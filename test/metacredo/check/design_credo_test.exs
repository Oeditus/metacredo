defmodule MetaCredo.Check.DesignCredoTest do
  use MetaCredo.CheckCase

  alias MetaCredo.Check.Design

  # ── TagTodo ─────────────────────────────────────────────────────────

  describe "TagTodo" do
    test "detects TODO in comment AST node" do
      ast = comment("TODO: implement this feature", line: 5)
      issues = run_check(Design.TagTodo, ast: ast, params: [include_source_scan: false])
      assert_issue(issues, trigger: "TODO", line_no: 5)
    end

    test "detects TODO in source lines" do
      source = "# TODO: fix later\nx = 1"

      issues =
        run_check(Design.TagTodo,
          ast: literal_int(1),
          source: source,
          params: [include_source_scan: true]
        )

      assert_issue(issues, trigger: "TODO", line_no: 1)
    end

    test "detects case-insensitive TODO in comment" do
      ast = comment("todo: cleanup needed", line: 10)
      issues = run_check(Design.TagTodo, ast: ast, params: [include_source_scan: false])
      assert_issue(issues, message: ~r/TODO/i)
    end

    test "ignores comments without TODO" do
      ast = comment("This is a regular comment", line: 1)
      issues = run_check(Design.TagTodo, ast: ast, params: [include_source_scan: false])
      assert_no_issues(issues)
    end

    test "deduplicates AST and source line matches on same line" do
      source = "# TODO: fix this"
      ast = comment("TODO: fix this", line: 1)

      issues =
        run_check(Design.TagTodo,
          ast: ast,
          source: source,
          params: [include_source_scan: true]
        )

      assert_issue_count(issues, 1)
    end
  end

  # ── TagFixme ────────────────────────────────────────────────────────

  describe "TagFixme" do
    test "detects FIXME in comment AST node" do
      ast = comment("FIXME: this is broken", line: 8)
      issues = run_check(Design.TagFixme, ast: ast, params: [include_source_scan: false])
      assert_issue(issues, trigger: "FIXME", line_no: 8)
    end

    test "detects FIXME in source lines" do
      source = "# FIXME: broken logic\ny = 2"

      issues =
        run_check(Design.TagFixme,
          ast: literal_int(2),
          source: source,
          params: [include_source_scan: true]
        )

      assert_issue(issues, trigger: "FIXME", line_no: 1)
    end

    test "detects case-insensitive FIXME" do
      ast = comment("fixme: urgent bug", line: 3)
      issues = run_check(Design.TagFixme, ast: ast, params: [include_source_scan: false])
      assert_issue(issues, message: ~r/FIXME/i)
    end

    test "ignores comments without FIXME" do
      ast = comment("Normal comment", line: 1)
      issues = run_check(Design.TagFixme, ast: ast, params: [include_source_scan: false])
      assert_no_issues(issues)
    end

    test "all issues are design category" do
      ast =
        block([
          comment("FIXME: first", line: 1),
          comment("FIXME: second", line: 2)
        ])

      issues = run_check(Design.TagFixme, ast: ast, params: [include_source_scan: false])
      assert_all_category(issues, :design)
    end
  end
end
