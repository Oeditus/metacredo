defmodule MetaCredo.Check.SameValueOperandsTest do
  @moduledoc """
  Regression tests for the "operation on identical operands" checks across
  languages.

  ## The defect these tests pin down

  `Warning.OperationOnSameValues` and `Warning.BoolOperationOnSameValues` both
  decided whether two operands were identical with a plain structural
  comparison:

      left == right

  That comparison is only correct for an adapter that leaves position metadata
  off its nodes. The Rust adapter stamps `line:`/`col:` on *every* node, so
  `x - x` parses to two `:variable` nodes that differ solely in position:

      {:variable, [scope: :local, line: 3, col: 20], "x"}
      {:variable, [scope: :local, line: 3, col: 24], "x"}

  The equality test was therefore always false and neither check ever fired on
  Rust source -- silently, with no error, on a construct both checks advertise
  as cross-language. Elixir nodes carry no position metadata, which is why the
  defect was invisible to the existing Elixir-only tests.

  These tests parse *real* source through the Metastatic adapters rather than
  hand-building ASTs, because a hand-built fixture without position metadata
  cannot reproduce the bug at all.
  """

  use ExUnit.Case, async: true

  alias MetaCredo.CheckCase

  alias MetaCredo.Check.Warning.{
    BoolOperationOnSameValues,
    OperationOnSameValues
  }

  # These tests parse real Rust source, so they need the Rust toolchain that
  # backs the Metastatic adapter. CI installs only Elixir/OTP; see
  # `CheckCase.language_available?/1`.
  @rust_skip CheckCase.skip_unless_available(:rust)
  @elixir_skip CheckCase.skip_unless_available(:elixir)

  describe "OperationOnSameValues on Rust" do
    @describetag skip: @rust_skip
    test "detects `x - x` (always 0)" do
      issues = run_rust(OperationOnSameValues, "fn f(x: i64) -> i64 { x - x }")

      CheckCase.assert_issue(issues, message: ~r/always 0/)
    end

    test "detects `x / x` (always 1)" do
      issues = run_rust(OperationOnSameValues, "fn f(x: i64) -> i64 { x / x }")

      CheckCase.assert_issue(issues, message: ~r/always 1/)
    end

    test "detects identical literal operands on different lines" do
      source = """
      fn f() -> i64 {
          5 - 5
      }
      """

      issues = run_rust(OperationOnSameValues, source)

      CheckCase.assert_issue(issues, message: ~r/always 0/)
    end

    test "ignores `x - y` (different operands)" do
      issues = run_rust(OperationOnSameValues, "fn f(x: i64, y: i64) -> i64 { x - y }")

      CheckCase.assert_no_issues(issues)
    end

    test "ignores `x + x` (not a constant result)" do
      issues = run_rust(OperationOnSameValues, "fn f(x: i64) -> i64 { x + x }")

      CheckCase.assert_no_issues(issues)
    end

    test "ignores operands that differ only in field name" do
      issues = run_rust(OperationOnSameValues, "fn f(p: P) -> i64 { p.a - p.b }")

      CheckCase.assert_no_issues(issues)
    end
  end

  describe "BoolOperationOnSameValues on Rust" do
    @describetag skip: @rust_skip
    test "detects `x && x`" do
      issues = run_rust(BoolOperationOnSameValues, "fn f(x: bool) -> bool { x && x }")

      CheckCase.assert_issue(issues, message: ~r/identical operands/i)
    end

    test "detects `x || x`" do
      issues = run_rust(BoolOperationOnSameValues, "fn f(x: bool) -> bool { x || x }")

      CheckCase.assert_issue(issues, trigger: "or")
    end

    test "ignores `x && y` (different operands)" do
      issues = run_rust(BoolOperationOnSameValues, "fn f(x: bool, y: bool) -> bool { x && y }")

      CheckCase.assert_no_issues(issues)
    end

    test "ignores non-boolean `x + x`" do
      issues = run_rust(BoolOperationOnSameValues, "fn f(x: i64) -> i64 { x + x }")

      CheckCase.assert_no_issues(issues)
    end
  end

  describe "Elixir behaviour is unchanged" do
    @describetag skip: @elixir_skip
    test "OperationOnSameValues still detects `x - x`" do
      issues = run_elixir(OperationOnSameValues, "def f(x), do: x - x")

      CheckCase.assert_issue(issues, message: ~r/always 0/)
    end

    test "OperationOnSameValues still ignores `x - y`" do
      issues = run_elixir(OperationOnSameValues, "def f(x, y), do: x - y")

      CheckCase.assert_no_issues(issues)
    end

    test "BoolOperationOnSameValues still detects `x and x`" do
      issues = run_elixir(BoolOperationOnSameValues, "def f(x), do: x and x")

      CheckCase.assert_issue(issues, message: ~r/identical operands/i)
    end

    test "BoolOperationOnSameValues still ignores `x and y`" do
      issues = run_elixir(BoolOperationOnSameValues, "def f(x, y), do: x and y")

      CheckCase.assert_no_issues(issues)
    end
  end

  # -- Helpers --

  defp run_rust(check, source) do
    run(check, source, :rust, "sample.rs")
  end

  defp run_elixir(check, source) do
    run(check, source, :elixir, "sample.ex")
  end

  defp run(check, source, language, filename) do
    case CheckCase.source_file_from_source(source, language, filename) do
      {:ok, source_file} ->
        check.run(source_file, [])

      {:error, reason} ->
        flunk("Could not parse #{language} fixture (#{inspect(reason)}):\n#{source}")
    end
  end
end
