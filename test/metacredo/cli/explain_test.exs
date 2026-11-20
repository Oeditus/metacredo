defmodule MetaCredo.CLI.ExplainTest do
  @moduledoc """
  Tests for `mix metacredo explain`'s reference resolution.

  `CLI.Explain.resolve/1` was extracted from the Mix task precisely so it
  could be tested without driving compilation, filesystem discovery and
  process exit codes -- but it shipped at 0% coverage. These tests exercise
  each of the four documented reference forms:

    * `FQN` -- e.g. `MetaCredo.Check.Security.HardcodedValue`
    * short name -- e.g. `HardcodedValue`
    * `file` -- a check's own source file
    * `file:line` -- a location inside an analysed file
  """

  use ExUnit.Case, async: true

  alias MetaCredo.CLI.Explain

  @check MetaCredo.Check.Security.HardcodedValue

  describe "resolve/1 with a fully-qualified name" do
    test "returns the module and a detected language" do
      {module, issue, language} = Explain.resolve("MetaCredo.Check.Security.HardcodedValue")

      assert module == @check
      assert issue == nil
      assert is_atom(language)
    end
  end

  describe "resolve/1 with a short name" do
    test "resolves a unique check by its terminal module segment" do
      {module, issue, _language} = Explain.resolve("HardcodedValue")

      assert module == @check
      assert issue == nil
    end

    test "returns nil for an unknown short name" do
      {module, _issue, _language} = Explain.resolve("NoSuchCheckAnywhere")

      assert module == nil
    end
  end

  describe "resolve/1 with a file path" do
    test "resolves a check module from its own source file" do
      {module, issue, _language} =
        Explain.resolve("lib/metacredo/check/security/hardcoded_value.ex")

      assert module == @check
      assert issue == nil
    end

    test "resolves a check module from an absolute path outside the project" do
      # `path_to_check_module/1` falls back to matching on the basename, so an
      # external path still resolves rather than failing outright.
      {module, _issue, _language} =
        Explain.resolve("/tmp/somewhere/hardcoded_value.ex")

      assert module == @check
    end
  end

  describe "resolve/1 with file:line" do
    @tag :tmp_dir
    test "returns an issue when a check fires at the given line", %{tmp_dir: dir} do
      path = Path.join(dir, "demo.ex")

      # `ModuleDoc` reliably carries a line (the module definition) where a
      # literal-based check may not -- Metastatic does not attach `:line` to
      # every node (see `MetaCredo.Check.Utils.line_of/2`).
      File.write!(path, "defmodule Demo do\n  def noop, do: :ok\nend\n")

      {module, issue, language} = Explain.resolve("#{path}:1")

      assert module != nil
      assert issue != nil
      assert issue.line_no == 1
      assert is_atom(language)
    end

    @tag :tmp_dir
    test "falls back to the file's check module when nothing fires at that line",
         %{tmp_dir: dir} do
      path = Path.join(dir, "hardcoded_value.ex")
      File.write!(path, "defmodule Demo do\n  def noop, do: :ok\nend\n")

      {module, issue, _language} = Explain.resolve("#{path}:999")

      # No issue at line 999, so the module comes from the file path.
      assert issue == nil
      assert module == @check
    end
  end

  describe "detect_project_language/0" do
    test "returns an atom for the current project" do
      assert Explain.detect_project_language() == :elixir
    end
  end
end
