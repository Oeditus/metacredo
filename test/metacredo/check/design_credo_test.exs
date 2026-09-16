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

    test "does not flag TODO inside a string literal" do
      source = ~S(def msg, do: "TODO: not a comment") <> "\n"

      issues =
        run_check(Design.TagTodo,
          ast: literal_int(1),
          source: source,
          params: [include_source_scan: true]
        )

      assert_no_issues(issues)
    end

    test "does not flag TODO in a variable or function name" do
      source = "def todo_list, do: :ok\n"

      issues =
        run_check(Design.TagTodo,
          ast: literal_int(1),
          source: source,
          params: [include_source_scan: true]
        )

      assert_no_issues(issues)
    end

    test "does not flag TODO mentioned in @moduledoc prose" do
      source = ~S(@moduledoc "has TODO inside a string, not a comment") <> "\n"

      issues =
        run_check(Design.TagTodo,
          ast: literal_int(1),
          source: source,
          params: [include_source_scan: true]
        )

      assert_no_issues(issues)
    end

    test "flags a TODO that follows code on the same line" do
      source = "x = 1  # TODO: trailing comment\n"

      issues =
        run_check(Design.TagTodo,
          ast: literal_int(1),
          source: source,
          params: [include_source_scan: true]
        )

      assert_issue(issues, trigger: "TODO", line_no: 1)
    end

    test "does not treat a # inside a string as a comment start" do
      source = ~S(msg = "a # b TODO here") <> "\n"

      issues =
        run_check(Design.TagTodo,
          ast: literal_int(1),
          source: source,
          params: [include_source_scan: true]
        )

      assert_no_issues(issues)
    end

    test "accepts a custom regexp via the :tags param" do
      source = "# XXX: needs attention\n# TODO: normal\n"

      issues =
        run_check(Design.TagTodo,
          ast: literal_int(1),
          source: source,
          params: [include_source_scan: true, tags: [~r/XXX/]]
        )

      assert_issue_count(issues, 1)
      assert_issue(issues, trigger: "XXX", line_no: 1)
    end

    test "accepts a mix of literal strings and regexes in :tags" do
      source = "# XXX: needs attention\n# HACK: temporary\n# TODO: normal\n"

      issues =
        run_check(Design.TagTodo,
          ast: literal_int(1),
          source: source,
          params: [include_source_scan: true, tags: ["TODO", ~r/XXX/]]
        )

      assert_issue_count(issues, 2)
      assert_issue(issues, trigger: "XXX", line_no: 1)
      assert_issue(issues, trigger: "TODO", line_no: 3)
    end

    test "string tags match literally, not as regexes" do
      # "T.DO" as a string must not match "TODO"; as a regex it would.
      source = "# TODO: normal\n"

      issues =
        run_check(Design.TagTodo,
          ast: literal_int(1),
          source: source,
          params: [include_source_scan: true, tags: ["T.DO"]]
        )

      assert_no_issues(issues)
    end

    test "empty :tags disables the check" do
      source = "# TODO: normal\n"

      issues =
        run_check(Design.TagTodo,
          ast: literal_int(1),
          source: source,
          params: [include_source_scan: true, tags: []]
        )

      assert_no_issues(issues)
    end

    test "custom tag is also matched in comment AST nodes" do
      ast = comment("XXX: revisit", line: 7)

      issues =
        run_check(Design.TagTodo,
          ast: ast,
          params: [include_source_scan: false, tags: [~r/XXX/]]
        )

      assert_issue(issues, trigger: "XXX", line_no: 7)
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

    test "does not flag FIXME inside a string literal" do
      source = ~S(def msg, do: "FIXME: not a comment") <> "\n"

      issues =
        run_check(Design.TagFixme,
          ast: literal_int(1),
          source: source,
          params: [include_source_scan: true]
        )

      assert_no_issues(issues)
    end

    test "does not flag FIXME in a variable or function name" do
      source = "def fixme_list, do: :ok\n"

      issues =
        run_check(Design.TagFixme,
          ast: literal_int(1),
          source: source,
          params: [include_source_scan: true]
        )

      assert_no_issues(issues)
    end

    test "flags a FIXME that follows code on the same line" do
      source = "y = 2  # FIXME: broken\n"

      issues =
        run_check(Design.TagFixme,
          ast: literal_int(2),
          source: source,
          params: [include_source_scan: true]
        )

      assert_issue(issues, trigger: "FIXME", line_no: 1)
    end

    test "does not treat a # inside a string as a comment start" do
      source = ~S(msg = "a # b FIXME here") <> "\n"

      issues =
        run_check(Design.TagFixme,
          ast: literal_int(1),
          source: source,
          params: [include_source_scan: true]
        )

      assert_no_issues(issues)
    end

    test "accepts a custom regexp via the :tags param" do
      source = "# HACK: temporary\n# FIXME: broken\n"

      issues =
        run_check(Design.TagFixme,
          ast: literal_int(1),
          source: source,
          params: [include_source_scan: true, tags: [~r/HACK/]]
        )

      assert_issue_count(issues, 1)
      assert_issue(issues, trigger: "HACK", line_no: 1)
    end

    test "string tags match literally, not as regexes" do
      source = "# FIXME: broken\n"

      issues =
        run_check(Design.TagFixme,
          ast: literal_int(1),
          source: source,
          params: [include_source_scan: true, tags: ["F.XME"]]
        )

      assert_no_issues(issues)
    end

    test "empty :tags disables the check" do
      source = "# FIXME: broken\n"

      issues =
        run_check(Design.TagFixme,
          ast: literal_int(1),
          source: source,
          params: [include_source_scan: true, tags: []]
        )

      assert_no_issues(issues)
    end
  end
end
