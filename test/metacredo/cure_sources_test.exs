defmodule MetaCredo.CureSourcesTest do
  use MetaCredo.CheckCase

  alias MetaCredo.{Execution, SourceFile, Sources}

  @cure_available Code.ensure_loaded?(Metastatic.Adapters.Cure.ToMeta) and
                    Metastatic.Adapters.Cure.ToMeta.available?()

  describe "Cure language source discovery" do
    test "language_for detects .cure files" do
      assert Sources.language_for("app.cure") == :cure
      assert Sources.language_for("src/main.cure") == :cure
      assert Sources.language_for("/path/to/module.cure") == :cure
    end

    test "supported_extensions includes .cure" do
      assert ".cure" in Sources.supported_extensions()
    end

    @tag skip: if(not @cure_available, do: "Cure compiler is not available")
    test "Sources.find discovers .cure files from directory" do
      tmp_dir = System.tmp_dir!()
      dir_path = Path.join(tmp_dir, "cure_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir_path)

      cure_file = Path.join(dir_path, "sample.cure")
      File.write!(cure_file, "let x = 42\nlet y = 100\n")

      on_exit(fn -> File.rm_rf!(dir_path) end)

      source_files = Sources.find(dir_path)
      assert length(source_files) == 1
      [sf] = source_files
      assert sf.filename == cure_file
      assert sf.language == :cure
      assert sf.status == :valid
    end
  end

  describe "Cure source file parsing" do
    @describetag skip: if(not @cure_available, do: "Cure compiler is not available")

    test "parses valid Cure source into SourceFile" do
      code = """
      let name = "Metacredo"
      let count = 42
      """

      assert {:ok, %SourceFile{} = sf} = SourceFile.parse(code, "example.cure", :cure)
      assert sf.filename == "example.cure"
      assert sf.language == :cure
      assert sf.status == :valid
      assert sf.source == code
      assert length(sf.lines) == 3
    end

    test "handles clean Cure code with no issues" do
      code = "let x = 1\n"
      assert {:ok, %SourceFile{} = sf} = SourceFile.parse(code, "clean.cure", :cure)

      checks = [{MetaCredo.Check.Security.HardcodedValue, []}]
      issues = Execution.run_on_source_files([sf], checks)
      assert_no_issues(issues)
    end
  end

  describe "MetaCredo check execution on Cure sources" do
    @describetag skip: if(not @cure_available, do: "Cure compiler is not available")

    test "detects hardcoded values (security check) in Cure source" do
      code = """
      let api_url = "https://api.internal.company.com/v1"
      let token = "secret_12345"
      """

      assert {:ok, %SourceFile{} = sf} = SourceFile.parse(code, "config.cure", :cure)

      checks = [{MetaCredo.Check.Security.HardcodedValue, []}]
      issues = Execution.run_on_source_files([sf], checks)

      assert match?([_ | _], issues)
      assert_issue(issues, category: :security, check: MetaCredo.Check.Security.HardcodedValue)
    end

    test "detects TODO tags (design check) in Cure comments" do
      code = """
      # TODO: Refactor this calculation
      let total = 100
      """

      assert {:ok, %SourceFile{} = sf} = SourceFile.parse(code, "math.cure", :cure)

      checks = [{MetaCredo.Check.Design.TagTodo, []}]
      issues = Execution.run_on_source_files([sf], checks)

      assert_issue_count(issues, 1)
      assert_issue(issues, category: :design, check: MetaCredo.Check.Design.TagTodo)
    end

    test "runs multiple check categories on Cure source file" do
      code = """
      # TODO: Replace hardcoded URL
      let endpoint = "https://auth.service.internal"
      """

      assert {:ok, %SourceFile{} = sf} = SourceFile.parse(code, "auth.cure", :cure)

      checks = [
        {MetaCredo.Check.Security.HardcodedValue, []},
        {MetaCredo.Check.Design.TagTodo, []}
      ]

      issues = Execution.run_on_source_files([sf], checks)
      categories = Enum.map(issues, & &1.category) |> Enum.uniq() |> Enum.sort()

      assert :design in categories
      assert :security in categories
    end
  end

  describe "End-to-end MetaCredo execution for Cure sources" do
    @describetag skip: if(not @cure_available, do: "Cure compiler is not available")

    test "runs full MetaCredo analysis suite on Cure project directory" do
      tmp_dir = System.tmp_dir!()
      dir_path = Path.join(tmp_dir, "cure_project_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir_path)

      cure_file = Path.join(dir_path, "service.cure")

      code = """
      # TODO: Implement token verification
      let server_endpoint = "https://prod-api.example.com"
      """

      File.write!(cure_file, code)

      on_exit(fn -> File.rm_rf!(dir_path) end)

      report =
        Execution.run(
          config: %{
            name: "cure_test_config",
            files: %{included: [dir_path], excluded: []},
            checks: %{
              enabled: [
                {MetaCredo.Check.Security.HardcodedValue, []},
                {MetaCredo.Check.Design.TagTodo, []}
              ],
              disabled: []
            }
          },
          files_included: [dir_path]
        )

      assert length(report.source_files) == 1
      assert length(report.issues) >= 2

      cure_issues = Enum.filter(report.issues, &(&1.filename == cure_file))
      assert length(cure_issues) >= 2
    end

    test "respects inline disable comments in Cure source code files" do
      tmp_dir = System.tmp_dir!()
      dir_path = Path.join(tmp_dir, "cure_disable_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir_path)

      cure_file = Path.join(dir_path, "suppressed.cure")

      code = """
      # metacredo:disable-for-next-line MetaCredo.Check.Security.HardcodedValue
      let endpoint = "https://api.example.com"
      """

      File.write!(cure_file, code)

      on_exit(fn -> File.rm_rf!(dir_path) end)

      report =
        Execution.run(
          config: %{
            name: "cure_disable_config",
            files: %{included: [dir_path], excluded: []},
            checks: %{
              enabled: [{MetaCredo.Check.Security.HardcodedValue, []}],
              disabled: []
            }
          },
          files_included: [dir_path]
        )

      # The HardcodedValue check should be disabled for that line
      hardcoded_issues =
        Enum.filter(
          report.issues,
          &(&1.check == MetaCredo.Check.Security.HardcodedValue and &1.filename == cure_file)
        )

      assert hardcoded_issues == []
    end
  end
end
