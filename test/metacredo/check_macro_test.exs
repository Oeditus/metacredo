defmodule MetaCredo.CheckMacroTest do
  use ExUnit.Case, async: true

  alias MetaCredo.{Check, Issue, SourceFile}

  # Define a test check module using the macro
  defmodule TestCheck do
    use MetaCredo.Check,
      category: :readability,
      base_priority: :high,
      param_defaults: [threshold: 10],
      tags: [:test, :example],
      explanations: [
        check: "A test check for verifying the macro.",
        params: [threshold: "The threshold value"]
      ]

    @impl true
    def run(%SourceFile{} = _source_file, _params), do: []
  end

  describe "use MetaCredo.Check" do
    test "defines category/0 callback" do
      assert TestCheck.category() == :readability
    end

    test "defines base_priority/0 callback" do
      assert TestCheck.base_priority() == :high
    end

    test "defines param_defaults/0 callback" do
      assert TestCheck.param_defaults() == [threshold: 10]
    end

    test "defines tags/0 callback" do
      assert TestCheck.tags() == [:test, :example]
    end

    test "defines explanations/0 callback" do
      explanations = TestCheck.explanations()
      assert Keyword.get(explanations, :check) =~ "test check"
      assert Keyword.has_key?(explanations, :params)
    end

    test "defines id/0 callback returning module name" do
      assert TestCheck.id() =~ "TestCheck"
    end

    test "defines format_issue/2 helper" do
      doc = Metastatic.Document.new({:literal, [subtype: :integer], 1}, :elixir)

      sf = %SourceFile{
        document: doc,
        filename: "test.ex",
        source: "",
        language: :elixir,
        lines: [],
        status: :valid
      }

      issue = TestCheck.format_issue(sf, message: "test msg", line_no: 5)
      assert %Issue{} = issue
      assert issue.check == TestCheck
      assert issue.category == :readability
      assert issue.message == "test msg"
      assert issue.line_no == 5
      assert issue.filename == "test.ex"
      assert issue.priority == :high
    end

    test "defines params_get/2 helper with defaults" do
      assert TestCheck.params_get([], :threshold) == 10
      assert TestCheck.params_get([threshold: 20], :threshold) == 20
      assert TestCheck.params_get([], :nonexistent) == nil
    end
  end

  describe "Check.format_issue/3" do
    test "creates Issue with correct fields" do
      doc = Metastatic.Document.new({:literal, [subtype: :integer], 1}, :elixir)

      sf = %SourceFile{
        document: doc,
        filename: "app.ex",
        source: "",
        language: :elixir
      }

      issue =
        Check.format_issue(TestCheck, sf,
          message: "Something wrong",
          trigger: "bad_code",
          line_no: 42,
          column: 10,
          severity: :error,
          metadata: %{detail: "extra"}
        )

      assert issue.check == TestCheck
      assert issue.category == :readability
      assert issue.severity == :error
      assert issue.priority == :high
      assert issue.message == "Something wrong"
      assert issue.trigger == "bad_code"
      assert issue.line_no == 42
      assert issue.column == 10
      assert issue.filename == "app.ex"
      assert issue.exit_status == Issue.exit_status_for(:readability)
      assert issue.metadata == %{detail: "extra"}
    end

    test "uses defaults for optional fields" do
      doc = Metastatic.Document.new({:literal, [subtype: :integer], 1}, :elixir)

      sf = %SourceFile{
        document: doc,
        filename: "x.ex",
        source: "",
        language: :elixir
      }

      issue = Check.format_issue(TestCheck, sf, message: "minimal")
      assert issue.severity == :warning
      assert issue.trigger == nil
      assert issue.line_no == nil
      assert issue.column == nil
      assert issue.metadata == %{}
    end
  end

  describe "Check.valid_categories/0" do
    test "returns all valid categories" do
      cats = Check.valid_categories()
      assert :security in cats
      assert :warning in cats
      assert :readability in cats
      assert :refactor in cats
      assert :design in cats
      assert :performance in cats
      assert :observability in cats
      assert :consistency in cats
    end
  end
end
