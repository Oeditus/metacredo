defmodule MetaCredo.Check.Design.TagRustTest do
  @moduledoc """
  Regression tests for `TagTodo` / `TagFixme` on Rust source.

  ## The defect these tests pin down

  `TagScan.comment_marker/1` maps each language to its comment syntax and
  falls through to `:none` for anything unlisted. Rust was never added to that
  table, so `// TODO:` in a `.rs` file produced no match and both tag checks
  were silently dead on Rust -- they reported nothing at all, on a comment
  form they handle correctly for JavaScript and TypeScript.

  These tests parse real Rust source through the Metastatic adapter, because
  the defect lived in the source-line scan path rather than in AST traversal.
  """

  use ExUnit.Case, async: true

  alias MetaCredo.Check.Design.{TagFixme, TagTodo}
  alias MetaCredo.CheckCase

  describe "TagTodo on Rust" do
    test "detects a whole-line `// TODO` comment" do
      source = """
      // TODO: replace this with a real implementation
      fn main() {}
      """

      issues = run_rust(TagTodo, source)

      CheckCase.assert_issue(issues, message: ~r/TODO/)
    end

    test "detects a trailing `// TODO` comment" do
      source = """
      fn main() {
          let x = 1; // TODO: name this constant
      }
      """

      issues = run_rust(TagTodo, source)

      CheckCase.assert_issue(issues, message: ~r/TODO/)
    end

    test "reports the correct line number" do
      source = """
      fn main() {
          // TODO: line three
      }
      """

      issues = run_rust(TagTodo, source)

      CheckCase.assert_issue(issues, line_no: 2)
    end

    test "ignores `//` inside a string literal" do
      source = """
      fn main() {
          let url = "http://example.com/TODO";
      }
      """

      issues = run_rust(TagTodo, source)

      CheckCase.assert_no_issues(issues)
    end

    test "ignores a TODO in an ordinary comment" do
      source = """
      // this is just a note
      fn main() {}
      """

      issues = run_rust(TagTodo, source)

      CheckCase.assert_no_issues(issues)
    end

    test "ignores a TODO in a string literal" do
      source = """
      fn main() {
          let label = "TODO";
      }
      """

      issues = run_rust(TagTodo, source)

      CheckCase.assert_no_issues(issues)
    end

    test "honours the custom `tags` param" do
      source = """
      // XXX: revisit this
      fn main() {}
      """

      issues = run_rust(TagTodo, source, tags: ["TODO", ~r/XXX/])

      CheckCase.assert_issue(issues, message: ~r/TODO/)
    end
  end

  describe "TagFixme on Rust" do
    test "detects a `// FIXME` comment" do
      source = """
      // FIXME: this panics on empty input
      fn main() {}
      """

      issues = run_rust(TagFixme, source)

      CheckCase.assert_issue(issues, message: ~r/FIXME/)
    end

    test "ignores a FIXME in a string literal" do
      source = """
      fn main() {
          let label = "FIXME";
      }
      """

      issues = run_rust(TagFixme, source)

      CheckCase.assert_no_issues(issues)
    end
  end

  describe "other languages are unchanged" do
    test "TagTodo still detects an Elixir comment" do
      issues = run_elixir(TagTodo, "# TODO: fix\nx = 1\n")

      CheckCase.assert_issue(issues, message: ~r/TODO/)
    end

    test "TagTodo still detects a JavaScript comment" do
      issues = run(TagTodo, "// TODO: fix\nconst x = 1;\n", :javascript, "sample.js", [])

      CheckCase.assert_issue(issues, message: ~r/TODO/)
    end
  end

  # -- Helpers --

  defp run_rust(check, source, params \\ []) do
    run(check, source, :rust, "sample.rs", params)
  end

  defp run_elixir(check, source, params \\ []) do
    run(check, source, :elixir, "sample.ex", params)
  end

  defp run(check, source, language, filename, params) do
    case CheckCase.source_file_from_source(source, language, filename) do
      {:ok, source_file} ->
        check.run(source_file, params)

      {:error, reason} ->
        flunk("Could not parse #{language} fixture (#{inspect(reason)}):\n#{source}")
    end
  end
end
