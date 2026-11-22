defmodule MetaCredo.Check.JsTsCallShapeTest do
  @moduledoc """
  Regression tests for the JavaScript/TypeScript `:function_call` child shape.

  ## The defect these tests pin down

  Adapters disagree about where a call's callee lives. Elixir, Erlang, Python,
  Ruby, Rust and Go record it only in the `:name` metadata, so a
  `:function_call` node's children are exactly the arguments. The JavaScript
  and TypeScript adapters *additionally* emit the callee as the **first
  child**:

      axios.get(targetUrl)   ->  children [callee, targetUrl]
      foo()                  ->  children [callee]

  Three checks inspected "the first argument" by taking `hd(args)`:

    * `Security.SSRFVulnerability` -- examined the callee instead of the URL
    * `Security.SensitiveDataExposure` -- examined the callee instead of the
      logged value
    * `Warning.UnsafeExec` -- walked the callee when testing for tainted input

  On JS/TS source all three therefore looked at the wrong node and reported
  nothing -- silently, with no error, on constructs they advertise as
  cross-language. Every existing test built its fixtures for the
  callee-in-metadata shape, so the defect was invisible until the checks were
  run against genuinely parsed JS/TS.

  These tests parse *real* source through the Metastatic adapters, because a
  hand-built fixture in the Elixir shape cannot reproduce the bug at all.
  """

  use ExUnit.Case, async: true

  alias MetaCredo.Check.Utils, as: CheckUtils

  alias MetaCredo.Check.Security.{
    SensitiveDataExposure,
    SSRFVulnerability
  }

  alias MetaCredo.Check.Warning.UnsafeExec

  alias MetaCredo.{CheckCase, SourceFile}

  @typescript_skip CheckCase.skip_unless_available(:typescript)

  # -- CheckUtils.call_arguments/2 and callee_node?/2 --

  describe "call_arguments/2" do
    test "passes arguments through unchanged for the callee-in-metadata shape" do
      arg = {:variable, [], "x"}

      assert CheckUtils.call_arguments([name: "foo"], [arg]) == [arg]
    end

    test "drops a leading variable callee that matches the :name metadata" do
      callee = {:variable, [], "fetch"}
      arg = {:variable, [], "url"}

      assert CheckUtils.call_arguments([name: "fetch"], [callee, arg]) == [arg]
    end

    test "drops a leading member_access callee" do
      callee = {:function_call, [name: "member_access"], []}
      arg = {:variable, [], "url"}

      assert CheckUtils.call_arguments([name: "axios.get"], [callee, arg]) == [arg]
    end

    test "returns [] for a zero-argument call whose only child is the callee" do
      callee = {:variable, [], "foo"}

      assert CheckUtils.call_arguments([name: "foo"], [callee]) == []
    end

    test "returns [] for a call with no children" do
      assert CheckUtils.call_arguments([name: "foo"], []) == []
    end

    test "does not drop a leading child that is not the callee" do
      arg = {:variable, [], "url"}

      assert CheckUtils.call_arguments([name: "fetch"], [arg]) == [arg]
    end
  end

  describe "callee_node?/2" do
    test "true for a variable matching the :name metadata" do
      assert CheckUtils.callee_node?([name: "fetch"], {:variable, [], "fetch"})
    end

    test "false for a variable that does not match the :name metadata" do
      refute CheckUtils.callee_node?([name: "fetch"], {:variable, [], "url"})
    end

    test "true for a member_access pseudo-call when the node has a real name" do
      assert CheckUtils.callee_node?(
               [name: "axios.get"],
               {:function_call, [name: "member_access"], []}
             )
    end

    test "false when the node itself is member_access" do
      refute CheckUtils.callee_node?(
               [name: "member_access"],
               {:function_call, [name: "member_access"], []}
             )
    end

    test "false for a literal" do
      refute CheckUtils.callee_node?([name: "foo"], {:literal, [subtype: :integer], 1})
    end
  end

  # -- The checks that were silently dead on JS/TS --

  describe "checks on parsed TypeScript source" do
    @describetag skip: @typescript_skip

    test "SSRFVulnerability inspects the URL argument, not the callee" do
      source = """
      export async function proxy(targetUrl: string) {
        return await axios.get(targetUrl);
      }
      """

      issues = run(SSRFVulnerability, source, "a.ts")

      CheckCase.assert_issue(issues, message: ~r/SSRF|user-controlled/i)
    end

    test "SensitiveDataExposure inspects the logged value, not the callee" do
      source = """
      export function f(profile: any) {
        console.log(profile.password);
      }
      """

      issues = run(SensitiveDataExposure, source, "a.ts")

      CheckCase.assert_issue(issues, message: ~r/sensitive|password/i)
    end

    test "UnsafeExec inspects the command argument, not the callee" do
      source = """
      export function f(user_input: string) {
        exec("pandoc " + user_input);
      }
      """

      issues = run(UnsafeExec, source, "a.ts")

      CheckCase.assert_issue(issues, message: ~r/exec|command/i)
    end
  end

  defp run(check, source, filename) do
    case SourceFile.parse(source, filename, :typescript) do
      {:ok, source_file} -> check.run(source_file, [])
      {:error, reason} -> flunk("failed to parse fixture: #{inspect(reason)}")
    end
  end
end
