defmodule MetaCredo.CheckConformanceTest do
  @moduledoc """
  Conformance tests generated from each check's own documented examples.

  Every check declares `explanations: [examples: [elixir: [wrong: ..., correct: ...]]]`
  in its `use MetaCredo.Check` block. Those snippets are the tool's public
  documentation -- if a check does not actually fire on its documented `wrong`
  example (or fires on its documented `correct` one), the docs are lying.

  This test parses every example with the real Metastatic adapter and asserts
  the documented behaviour. It gives all 72 checks a smoke test for near-zero
  marginal authoring cost, and catches both regressions and doc drift.

  Examples that the adapter cannot parse (pseudo-code, incomplete snippets)
  are skipped rather than failed.

  ## Known upstream adapter defects

  Metastatic 0.30 mis-parses two common Elixir constructs, emitting a
  `Map.fetch!/2` call in place of the real node:

    1. the `&(&1.field)` capture shorthand -- emitted as a call rather than a
       lambda accessor;
    2. a **remote** call in a pipe, e.g. `value |> String.trim()` (a local
       `value |> trim()` is parsed correctly).

  Any example using either construct yields an AST no check can reason about,
  so those examples are skipped here and tracked as an upstream issue rather
  than worked around in MetaCredo.
  """

  use ExUnit.Case, async: true

  alias MetaCredo.CheckCase

  # `expr |> Module.fun(...)` -- a remote call as a pipe stage.
  @remote_pipe ~r/\|>\s*[A-Z]\w*(\.[A-Z]\w*)*\.\w+/
  # `&(&1.field)` -- the capture shorthand.
  @capture_shorthand ~r/&\(\s*&\d+\./

  # Examples that are illustrative pseudo-code rather than compilable source:
  # a bare `...` body, or a snippet whose top level is a fragment (a lone
  # `case`, a struct literal) that no check can meaningfully analyse on its
  # own. These are documentation, not fixtures.
  @pseudo_code ~r/^\s*\.\.\.\s*$|\bdo:\s*\.\.\.|,\s*do:\s*\.\.\./m

  setup_all do
    checks =
      Path.wildcard("lib/metacredo/check/**/*.ex")
      |> Enum.map(&path_to_module/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(&check_module?/1)

    {:ok, checks: checks, enabled: Enum.filter(checks, &default_enabled?/1)}
  end

  describe "documented examples (default-enabled checks)" do
    # These two tests encode a *goal*, not a guarantee: they surface checks
    # whose documented `wrong` example does not actually trigger them. The
    # These tests are the suite's reason for existing: they assert that every
    # check actually fires on its own documented `wrong` example (and stays
    # quiet on its `correct` one). They found and drove fixes for sixteen
    # checks that were silently dead on real Elixir code.
    test "every check fires on its documented `wrong` example", %{enabled: checks} do
      failures = Enum.flat_map(checks, &wrong_example_failures/1)

      assert failures == [],
             """
             #{length(failures)} check(s) did not fire on their own documented \
             `wrong` example:

             #{Enum.map_join(failures, "\n", &format_failure/1)}
             """
    end

    test "no check fires on its documented `correct` example", %{enabled: checks} do
      failures = Enum.flat_map(checks, &correct_example_failures/1)

      assert failures == [],
             """
             #{length(failures)} check(s) fired on their own documented \
             `correct` example:

             #{Enum.map_join(failures, "\n", &format_failure/1)}
             """
    end
  end

  describe "documented examples (opt-in checks)" do
    @describetag :opt_in

    test "every opt-in check fires on its documented `wrong` example", %{checks: checks} do
      # Opt-in checks are disabled by default because their name-substring
      # heuristics are approximate (see `Config.default_disabled_checks/0`).
      # That is a statement about their *precision*, not their *recall*: a
      # documented example must still trigger the check, so this is enforced.
      failures =
        checks
        |> Enum.reject(&default_enabled?/1)
        |> Enum.flat_map(&wrong_example_failures/1)

      assert failures == [],
             """
             #{length(failures)} opt-in check(s) did not fire on their own \
             documented `wrong` example:

             #{Enum.map_join(failures, "\n", &format_failure/1)}
             """
    end
  end

  # -- Private --

  # `lib/metacredo/check/security/xss_vulnerability.ex` ->
  # `MetaCredo.Check.Security.XSSVulnerability`. The module name cannot be
  # derived from the path by camelization alone (acronyms like `XSS` and
  # `TOCTOU` would be mangled), so we read the `defmodule` line instead.
  defp path_to_module(path) do
    with {:ok, source} <- File.read(path),
         [_, name] <- Regex.run(~r/^defmodule\s+([\w.]+)\s+do/m, source) do
      Module.concat([name])
    else
      _ -> nil
    end
  end

  defp check_module?(mod) do
    Code.ensure_loaded?(mod) and function_exported?(mod, :run, 2) and
      function_exported?(mod, :category, 0)
  end

  defp default_enabled?(mod) do
    mod not in MetaCredo.Config.default_disabled_checks()
  end

  defp wrong_example_failures(check) do
    for {language, snippets} <- examples(check),
        wrong = snippets[:wrong],
        is_binary(wrong),
        not known_adapter_defect?(wrong),
        {:ok, []} <- [CheckCase.run_example(check, wrong, language)] do
      {check, language, :wrong, wrong}
    end
  end

  defp correct_example_failures(check) do
    for {language, snippets} <- examples(check),
        correct = snippets[:correct],
        is_binary(correct),
        not known_adapter_defect?(correct),
        {:ok, issues} <- [CheckCase.run_example(check, correct, language)],
        is_list(issues),
        issues != [] do
      {check, language, :correct, correct, issues}
    end
  end

  defp known_adapter_defect?(source) do
    Regex.match?(@capture_shorthand, source) or Regex.match?(@remote_pipe, source) or
      Regex.match?(@pseudo_code, source)
  end

  defp examples(check) do
    if function_exported?(check, :explanations, 0) do
      check.explanations()
      |> Keyword.get(:examples, [])
      |> Enum.filter(fn {_lang, snippets} -> Keyword.keyword?(snippets) end)
    else
      []
    end
  end

  defp format_failure({check, language, kind, source}) when is_binary(source) do
    "  * #{inspect(check)} (#{language}) -- `#{kind}` example:\n" <> indent(source)
  end

  defp format_failure({check, language, kind, source, issues}) when is_binary(source) do
    "  * #{inspect(check)} (#{language}) -- `#{kind}` example produced " <>
      "#{length(issues)} issue(s):\n" <>
      Enum.map_join(issues, "", fn issue -> "      - #{issue.message}\n" end) <>
      indent(source)
  end

  defp format_failure(other), do: "  * " <> inspect(other) <> "\n"

  defp indent(source) do
    source
    |> String.split("\n")
    |> Enum.map_join("\n", &"      | #{&1}")
    |> Kernel.<>("\n")
  end
end
