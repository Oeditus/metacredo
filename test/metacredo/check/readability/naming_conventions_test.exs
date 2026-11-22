defmodule MetaCredo.Check.Readability.NamingConventionsTest do
  @moduledoc """
  Regression tests for language-aware naming conventions.

  ## The defect these tests pin down

  `Readability.FunctionNames` and `Readability.VariableNames` hardcoded
  Elixir's `snake_case` and ran it on *every* language:

      @snake_case ~r/^[a-z_][a-z0-9_]*[!?]?$/

  `Readability.ModuleNames` likewise applied PascalCase to every `:container`
  node. That is correct for Elixir and wrong for the C-family adapters, which
  Metastatic gained as first-class languages:

    * JavaScript, TypeScript and Go name functions and variables in
      `camelCase`, so `processUserData` was reported as "not in snake_case" --
      a finding on *correctly written* code, in every JS/TS/Go file;
    * Go opens every file with a lower-case `package` clause, which the
      adapter reports as a `:container` of type `:module`, so `ModuleNames`
      reported "not in PascalCase" for `package main` in every Go file, and
      `ModuleDoc` demanded documentation for something that is not a module
      definition.

  Every test here parses *real* source through the Metastatic adapters, because
  the language is carried by the parsed `SourceFile` and a hand-built AST
  fixture cannot reproduce the defect.
  """

  use ExUnit.Case, async: true

  alias MetaCredo.Check.Utils
  alias MetaCredo.CheckCase

  alias MetaCredo.Check.Readability.{
    FunctionNames,
    ModuleDoc,
    ModuleNames,
    VariableNames
  }

  @go_skip CheckCase.skip_unless_available(:go)
  @typescript_skip CheckCase.skip_unless_available(:typescript)
  @elixir_skip CheckCase.skip_unless_available(:elixir)

  describe "naming_convention/1" do
    test "classifies the C-family adapters as camelCase" do
      assert Utils.naming_convention(:javascript) == :camel_case
      assert Utils.naming_convention(:typescript) == :camel_case
      assert Utils.naming_convention(:go) == :camel_case
    end

    test "keeps snake_case for the languages that use it" do
      for language <- [:elixir, :erlang, :python, :ruby, :rust, :haskell, :cure] do
        assert Utils.naming_convention(language) == :snake_case,
               "expected #{language} to use snake_case"
      end
    end

    test "camel_case?/1 accepts camelCase and rejects snake_case and PascalCase" do
      assert Utils.camel_case?("processUserData")
      assert Utils.camel_case?("process")
      assert Utils.camel_case?("_unused")
      assert Utils.camel_case?("$element")
      assert Utils.camel_case?("parseHTTPResponse")

      refute Utils.camel_case?("process_user_data")
      refute Utils.camel_case?("ProcessUserData")
      refute Utils.camel_case?("")
    end

    test "conventional_name?/2 dispatches on the language" do
      assert Utils.conventional_name?("processUserData", :go)
      refute Utils.conventional_name?("process_user_data", :go)

      assert Utils.conventional_name?("process_user_data", :elixir)
      refute Utils.conventional_name?("processUserData", :elixir)
    end

    test "convention_label/1 names the convention for issue messages" do
      assert Utils.convention_label(:go) == "camelCase"
      assert Utils.convention_label(:elixir) == "snake_case"
    end
  end

  describe "FunctionNames on Go" do
    @describetag skip: @go_skip

    test "does not report camelCase Go functions" do
      source = """
      package main

      func processUserData(name string) string {
      \treturn name
      }
      """

      issues = run(FunctionNames, source, :go, "probe.go")

      CheckCase.assert_no_issues(issues)
    end

    test "reports snake_case Go functions" do
      source = """
      package main

      func process_user_data(name string) string {
      \treturn name
      }
      """

      issues = run(FunctionNames, source, :go, "probe.go")

      CheckCase.assert_issue(issues, message: ~r/is not in camelCase/)
    end
  end

  describe "FunctionNames on TypeScript" do
    @describetag skip: @typescript_skip

    test "does not report camelCase TypeScript functions" do
      source = """
      export function processUserData(name: string): string {
        return name;
      }
      """

      issues = run(FunctionNames, source, :typescript, "probe.ts")

      CheckCase.assert_no_issues(issues)
    end

    test "reports snake_case TypeScript functions" do
      source = """
      export function process_user_data(name: string): string {
        return name;
      }
      """

      issues = run(FunctionNames, source, :typescript, "probe.ts")

      CheckCase.assert_issue(issues, message: ~r/is not in camelCase/)
    end
  end

  describe "VariableNames on Go and TypeScript" do
    @describetag skip: @go_skip

    test "does not report camelCase Go variables" do
      source = """
      package main

      func main() {
      \tmaxRetries := 3
      \t_ = maxRetries
      }
      """

      CheckCase.assert_no_issues(run(VariableNames, source, :go, "probe.go"))
    end

    test "reports snake_case Go variables" do
      source = """
      package main

      func main() {
      \tmax_retries := 3
      \t_ = max_retries
      }
      """

      issues = run(VariableNames, source, :go, "probe.go")

      CheckCase.assert_issue(issues, message: ~r/is not in camelCase/)
    end

    @tag skip: @typescript_skip
    test "does not report camelCase TypeScript variables" do
      source = """
      const userId: number = 42;
      let isValid: boolean = true;
      """

      CheckCase.assert_no_issues(run(VariableNames, source, :typescript, "probe.ts"))
    end

    @tag skip: @typescript_skip
    test "reports snake_case TypeScript variables" do
      source = """
      const user_id: number = 42;
      """

      issues = run(VariableNames, source, :typescript, "probe.ts")

      CheckCase.assert_issue(issues, message: ~r/is not in camelCase/)
    end
  end

  describe "ModuleNames and ModuleDoc on Go" do
    @describetag skip: @go_skip

    test "a lower-case `package` clause is not a PascalCase violation" do
      source = """
      package main

      func main() {}
      """

      CheckCase.assert_no_issues(run(ModuleNames, source, :go, "probe.go"))
    end

    test "a `package` clause is not required to be documented" do
      source = """
      package http

      func Serve() {}
      """

      CheckCase.assert_no_issues(run(ModuleDoc, source, :go, "probe.go"))
    end
  end

  describe "Elixir is unaffected" do
    @describetag skip: @elixir_skip

    test "camelCase Elixir functions are still reported" do
      source = """
      defmodule Probe do
        def processUserData(user), do: user
      end
      """

      issues = run(FunctionNames, source, :elixir, "probe.ex")

      CheckCase.assert_issue(issues, message: ~r/is not in snake_case/)
    end

    test "snake_case Elixir functions are not reported" do
      source = """
      defmodule Probe do
        def process_user_data(user), do: user
      end
      """

      CheckCase.assert_no_issues(run(FunctionNames, source, :elixir, "probe.ex"))
    end

    test "non-PascalCase Elixir module names are still reported" do
      source = """
      defmodule my_app.user_account do
      end
      """

      issues = run(ModuleNames, source, :elixir, "probe.ex")

      CheckCase.assert_issue(issues, message: ~r/is not in PascalCase/)
    end
  end

  # -- Helpers --

  defp run(check, source, language, filename) do
    case CheckCase.source_file_from_source(source, language, filename) do
      {:ok, source_file} -> check.run(source_file, [])
      {:error, reason} -> flunk("could not parse #{filename}: #{inspect(reason)}")
    end
  end
end
