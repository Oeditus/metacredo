defmodule MetaCredo.CLI.OutputGitHubTest do
  use ExUnit.Case, async: true

  alias MetaCredo.CLI.Output
  alias MetaCredo.Issue

  describe "print_github/1" do
    test "formats issues as GitHub Actions workflow commands" do
      issues = [
        %Issue{
          check: MetaCredo.Check.Security.HardcodedValue,
          category: :security,
          severity: :error,
          message: "Hardcoded URL found",
          filename: "lib/foo.ex",
          line_no: 42,
          column: 10
        },
        %Issue{
          check: MetaCredo.Check.Warning.MissingErrorHandling,
          category: :warning,
          severity: :warning,
          message: "Missing error handling",
          filename: "lib/bar.ex",
          line_no: 7
        }
      ]

      report = %{
        issues: issues,
        summary: %{total: 2, by_category: %{security: 1, warning: 1}}
      }

      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Output.print_github(report)
        end)

      assert output =~
               "::error file=lib/foo.ex,line=42,col=10::HardcodedValue: Hardcoded URL found"

      assert output =~
               "::warning file=lib/bar.ex,line=7::MissingErrorHandling: Missing error handling"

      assert output =~ "metacredo: 2 issue(s) found"
    end

    test "handles issues without line numbers" do
      issues = [
        %Issue{
          check: MetaCredo.Check.Readability.ModuleDoc,
          category: :readability,
          severity: :info,
          message: "Module missing documentation",
          filename: "lib/undocumented.ex"
        }
      ]

      report = %{
        issues: issues,
        summary: %{total: 1, by_category: %{readability: 1}}
      }

      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Output.print_github(report)
        end)

      assert output =~
               "::notice file=lib/undocumented.ex::ModuleDoc: Module missing documentation"

      refute output =~ "line="
    end

    test "reports zero issues" do
      report = %{
        issues: [],
        summary: %{total: 0, by_category: %{}}
      }

      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Output.print_github(report)
        end)

      assert output =~ "metacredo: 0 issue(s) found"
    end
  end
end
