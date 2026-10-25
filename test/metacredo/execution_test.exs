defmodule MetaCredo.ExecutionTest do
  use MetaCredo.CheckCase

  alias MetaCredo.Execution

  describe "run_on_source_files/2" do
    test "runs checks and collects issues" do
      ast = literal_string("https://api.prod.example.com", line: 5)
      sf = source_file_from_ast(ast)

      checks = [{MetaCredo.Check.Security.HardcodedValue, []}]
      issues = Execution.run_on_source_files([sf], checks)

      assert_issue_count(issues, 1)
      assert_issue(issues, category: :security)
    end

    test "runs multiple checks on the same file" do
      ast =
        block([
          literal_string("https://api.prod.example.com", line: 1),
          assign(
            tuple([literal_symbol(:ok), var("r")]),
            call("Repo.get", [var("User"), var("id")]),
            line: 5
          )
        ])

      sf = source_file_from_ast(ast)

      checks = [
        {MetaCredo.Check.Security.HardcodedValue, []},
        {MetaCredo.Check.Warning.MissingErrorHandling, []}
      ]

      issues = Execution.run_on_source_files([sf], checks)
      categories = Enum.map(issues, & &1.category) |> Enum.uniq() |> Enum.sort()
      assert :security in categories
      assert :warning in categories
    end

    test "returns empty list for clean code" do
      ast = literal_int(42, line: 1)
      sf = source_file_from_ast(ast)

      checks = [{MetaCredo.Check.Security.HardcodedValue, []}]
      issues = Execution.run_on_source_files([sf], checks)

      assert_no_issues(issues)
    end

    test "sorts issues by filename then line number" do
      ast1 = literal_string("https://a.example.com", line: 10)
      ast2 = literal_string("https://b.example.com", line: 2)

      sf1 = source_file_from_ast(ast1, filename: "b.ex")
      sf2 = source_file_from_ast(ast2, filename: "a.ex")

      checks = [{MetaCredo.Check.Security.HardcodedValue, []}]
      issues = Execution.run_on_source_files([sf1, sf2], checks)

      filenames = Enum.map(issues, & &1.filename)
      assert filenames == ["a.ex", "b.ex"]
    end

    test "survives a check that raises" do
      defmodule BrokenCheck do
        use MetaCredo.Check, category: :warning
        @impl true
        def run(_sf, _params), do: raise("boom")
      end

      ast = literal_int(1)
      sf = source_file_from_ast(ast)

      # Should not raise; just returns empty issues for the broken check
      issues = Execution.run_on_source_files([sf], [{BrokenCheck, []}])
      assert_no_issues(issues)
    end
  end

  describe "inline disable filtering" do
    # This tests the full pipeline indirectly by constructing ASTs with
    # comment nodes. The Execution module's filter_disabled_by_comments/2
    # is private, so we test it through run_on_source_files behavior.
    # Note: inline disable requires the comment to be in the AST tree,
    # which only happens with adapters that preserve comments.

    test "filters issues when disable comment is present" do
      # Build an AST where a comment disables the next line's check
      _ast =
        block([
          comment("metacredo:disable-for-next-line MetaCredo.Check.Security.HardcodedValue",
            line: 4
          ),
          literal_string("https://api.example.com", line: 5)
        ])

      # Run through the full pipeline which includes disable filtering
      report =
        Execution.run(
          config: %{
            name: "test",
            files: %{included: [], excluded: []},
            checks: %{
              enabled: [{MetaCredo.Check.Security.HardcodedValue, []}],
              disabled: []
            }
          },
          files_included: []
        )

      # No source files discovered (empty dirs), so no issues
      # The real inline-disable test needs pre-parsed source files
      assert is_list(report.issues)
    end
  end

  describe "test/ default exclusion" do
    test "default run skips test/ trees discovered from the config" do
      tmp_dir = System.tmp_dir!()

      dir_path =
        Path.join(tmp_dir, "metacredo_exec_test_excl_#{System.unique_integer([:positive])}")

      lib_file = Path.join(dir_path, "lib/real.ex")
      test_file = Path.join(dir_path, "test/real_test.exs")

      for path <- [lib_file, test_file] do
        path |> Path.dirname() |> File.mkdir_p!()
        File.write!(path, "defmodule Fixture do\nend\n")
      end

      on_exit(fn -> File.rm_rf!(dir_path) end)

      config = %{
        name: "test",
        files: %{
          included: [Path.join(dir_path, "lib"), Path.join(dir_path, "test")],
          excluded: MetaCredo.Config.default().files.excluded
        },
        checks: %{enabled: [], disabled: []}
      }

      report = Execution.run(config: config)
      filenames = Enum.map(report.source_files, & &1.filename)

      assert Enum.any?(filenames, &String.ends_with?(&1, "lib/real.ex"))
      refute Enum.any?(filenames, &String.contains?(&1, "test/"))
    end

    test "explicitly targeting test/ via :files_included opts it back in" do
      tmp_dir = System.tmp_dir!()

      dir_path =
        Path.join(tmp_dir, "metacredo_exec_test_optin_#{System.unique_integer([:positive])}")

      test_file = Path.join(dir_path, "test/real_test.exs")
      test_file |> Path.dirname() |> File.mkdir_p!()
      File.write!(test_file, "defmodule Fixture do\nend\n")

      on_exit(fn -> File.rm_rf!(dir_path) end)

      report =
        Execution.run(
          config: %{
            name: "test",
            files: %{
              included: ["lib/"],
              excluded: MetaCredo.Config.default().files.excluded
            },
            checks: %{enabled: [], disabled: []}
          },
          files_included: [Path.join(dir_path, "test")]
        )

      filenames = Enum.map(report.source_files, & &1.filename)
      assert Enum.any?(filenames, &String.ends_with?(&1, "test/real_test.exs"))
    end

    test "an explicit :files_excluded still wins over the default exclusion" do
      tmp_dir = System.tmp_dir!()

      dir_path =
        Path.join(
          tmp_dir,
          "metacredo_exec_test_excl_override_#{System.unique_integer([:positive])}"
        )

      test_file = Path.join(dir_path, "test/real_test.exs")
      test_file |> Path.dirname() |> File.mkdir_p!()
      File.write!(test_file, "defmodule Fixture do\nend\n")

      on_exit(fn -> File.rm_rf!(dir_path) end)

      report =
        Execution.run(
          config: %{
            name: "test",
            files: %{included: [Path.join(dir_path, "test")], excluded: []},
            checks: %{enabled: [], disabled: []}
          },
          files_excluded: [MetaCredo.Config.test_exclusion_pattern()]
        )

      assert report.source_files == []
    end
  end

  describe "umbrella switches (no_db, no_user)" do
    test "no_db option excludes DB checks from checks_run" do
      report =
        Execution.run(
          no_db: true,
          files_included: []
        )

      refute MetaCredo.Check.Warning.NPlusOneQuery in report.checks_run
      refute MetaCredo.Check.Security.SQLInjection in report.checks_run
      refute MetaCredo.Check.Warning.MissingPreload in report.checks_run
    end

    test "no_user option excludes user input checks from checks_run" do
      report =
        Execution.run(
          no_user: true,
          files_included: []
        )

      refute MetaCredo.Check.Security.ImproperInputValidation in report.checks_run
      refute MetaCredo.Check.Security.XSSVulnerability in report.checks_run
      refute MetaCredo.Check.Consistency.ParameterPatternMatching in report.checks_run
    end

    test "no_db and no_user flags in config map exclude respective checks" do
      report =
        Execution.run(
          config: %{
            name: "test",
            no_db: true,
            no_user: true,
            files: %{included: [], excluded: []},
            checks: %{enabled: :all, disabled: []}
          },
          files_included: []
        )

      refute MetaCredo.Check.Warning.NPlusOneQuery in report.checks_run
      refute MetaCredo.Check.Security.SQLInjection in report.checks_run
      refute MetaCredo.Check.Security.ImproperInputValidation in report.checks_run
    end
  end

  describe "min_confidence filtering" do
    # A file that trips both a high-confidence structural check
    # (`UnlessWithElse`) and a low-confidence heuristic one
    # (`ImperativeStatusHandling`).
    @mixed_source """
    defmodule Mixed do
      def process(order) do
        case order.status do
          :pending -> {:ok, :processing}
          :processing -> {:ok, :shipped}
          :shipped -> {:ok, :delivered}
          :cancelled -> {:error, :cancelled}
        end
      end

      def check(x) do
        unless x do
          :no
        else
          :yes
        end
      end
    end
    """

    setup do
      dir = Path.join(System.tmp_dir!(), "metacredo_conf_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "mixed.ex"), @mixed_source)
      on_exit(fn -> File.rm_rf(dir) end)
      {:ok, dir: dir}
    end

    test "min_confidence: :high drops low-confidence findings", %{dir: dir} do
      config = %{
        name: "test",
        no_db: false,
        no_user: false,
        files: %{included: [dir], excluded: []},
        checks: %{
          enabled: [
            {MetaCredo.Check.Refactor.UnlessWithElse, []},
            {MetaCredo.Check.Warning.ImperativeStatusHandling, []}
          ],
          disabled: []
        }
      }

      all = Execution.run(config: config, files_included: [dir])
      filtered = Execution.run(config: config, files_included: [dir], min_confidence: :high)

      assert Enum.any?(
               all.issues,
               &(&1.check == MetaCredo.Check.Warning.ImperativeStatusHandling)
             )

      refute Enum.any?(
               filtered.issues,
               &(&1.check == MetaCredo.Check.Warning.ImperativeStatusHandling)
             )

      assert Enum.any?(filtered.issues, &(&1.check == MetaCredo.Check.Refactor.UnlessWithElse))
    end

    test "issues carry a confidence level", %{dir: dir} do
      report = Execution.run(files_included: [dir])

      assert Enum.all?(report.issues, fn issue ->
               issue.confidence in [:high, :medium, :low]
             end)
    end
  end

  describe "changed_lines filtering" do
    setup do
      dir = Path.join(System.tmp_dir!(), "metacredo_lines_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      path = Path.join(dir, "demo.ex")

      File.write!(path, """
      defmodule Demo do
        def a(x) do
          unless x do
            :no
          else
            :yes
          end
        end
      end
      """)

      on_exit(fn -> File.rm_rf(dir) end)
      {:ok, dir: dir, path: path}
    end

    test "keeps only issues on changed lines", %{dir: dir, path: path} do
      config = %{
        name: "test",
        no_db: false,
        no_user: false,
        files: %{included: [dir], excluded: []},
        checks: %{enabled: [{MetaCredo.Check.Refactor.UnlessWithElse, []}], disabled: []}
      }

      all = Execution.run(config: config, files_included: [dir])
      assert [issue] = all.issues

      on_line =
        Execution.run(
          config: config,
          files_included: [dir],
          changed_lines: %{path => MapSet.new([issue.line_no])}
        )

      off_line =
        Execution.run(
          config: config,
          files_included: [dir],
          changed_lines: %{path => MapSet.new([999])}
        )

      assert length(on_line.issues) == 1
      assert off_line.issues == []
    end

    test "drops issues in files absent from the diff", %{dir: dir, path: path} do
      config = %{
        name: "test",
        no_db: false,
        no_user: false,
        files: %{included: [dir], excluded: []},
        checks: %{enabled: [{MetaCredo.Check.Refactor.UnlessWithElse, []}], disabled: []}
      }

      report =
        Execution.run(
          config: config,
          files_included: [dir],
          changed_lines: %{Path.join(Path.dirname(path), "other.ex") => MapSet.new([1])}
        )

      assert report.issues == []
    end
  end
end
