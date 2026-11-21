defmodule MetaCredo.Check.Readability.RustModulesTest do
  @moduledoc """
  Regression tests for `ModuleDoc` / `ModuleNames` on Rust `mod` items.

  ## The defect these tests pin down

  Rust declares modules in two forms:

      mod config;            # a declaration -- names another file, body is []
      mod inline { ... }     # a definition -- body holds the items

  `Metastatic.Adapters.Rust.ToMeta` maps both to a `:container` node with
  `container_type: :module`. The readability checks then applied Elixir's
  module rules to the *declaration*:

    * `ModuleDoc` reported "Module 'config' has no documentation" -- but a
      declaration cannot carry a doc comment, so the finding was
      unsatisfiable;
    * `ModuleNames` reported "Module name 'config' is not in PascalCase" --
      but Rust names modules in `snake_case`, so the name was already correct.

  On a seven-module crate this produced 16 false positives out of 35 findings.

  ## Why the fix keys on `rust_kind`, not on an empty body

  An empty body is *not* a safe discriminator: `defmodule Foo do end` (Elixir)
  and an empty Haskell module also produce empty-bodied containers, and the
  module rules do apply to those. `rust_kind: "Module"` is set by the Rust
  adapter alone, so it identifies a Rust `mod` precisely.
  """

  use ExUnit.Case, async: true

  alias MetaCredo.Check.Readability.{ModuleDoc, ModuleNames}
  alias MetaCredo.Check.Utils, as: CheckUtils
  alias MetaCredo.CheckCase

  describe "ModuleDoc on Rust" do
    test "does not report an undocumented `mod x;` declaration" do
      issues = run_rust(ModuleDoc, "mod config;")

      CheckCase.assert_no_issues(issues)
    end

    test "does not report an undocumented `pub mod x;` declaration" do
      issues = run_rust(ModuleDoc, "pub mod http;\n\nfn main() {}")

      CheckCase.assert_no_issues(issues)
    end

    test "does not report an undocumented inline `mod`" do
      issues = run_rust(ModuleDoc, "mod inline { pub fn f() {} }")

      CheckCase.assert_no_issues(issues)
    end

    test "still reports an undocumented struct" do
      issues = run_rust(ModuleDoc, "struct Settings { retries: u32 }")

      CheckCase.assert_issue(issues, message: ~r/Settings/)
    end

    test "still reports an undocumented enum" do
      issues = run_rust(ModuleDoc, "enum Status { Ready }")

      CheckCase.assert_issue(issues, message: ~r/Status/)
    end

    test "still reports an undocumented trait" do
      issues = run_rust(ModuleDoc, "trait Render { fn render(&self); }")

      CheckCase.assert_issue(issues, message: ~r/Render/)
    end

    test "still reports an undocumented impl block" do
      issues = run_rust(ModuleDoc, "impl Foo { fn f(&self) {} }")

      CheckCase.assert_issue(issues, message: ~r/Foo/)
    end
  end

  describe "ModuleNames on Rust" do
    test "does not report a snake_case `mod` declaration" do
      issues = run_rust(ModuleNames, "mod config;")

      CheckCase.assert_no_issues(issues)
    end

    test "does not report a snake_case inline `mod`" do
      issues = run_rust(ModuleNames, "mod http_client { pub fn f() {} }")

      CheckCase.assert_no_issues(issues)
    end

    test "still reports a snake_case struct (PascalCase is the Rust rule)" do
      issues = run_rust(ModuleNames, "struct settings { retries: u32 }")

      CheckCase.assert_issue(issues, message: ~r/settings/)
    end

    test "still reports a snake_case enum" do
      issues = run_rust(ModuleNames, "enum status { Ready }")

      CheckCase.assert_issue(issues, message: ~r/status/)
    end
  end

  describe "other languages are unchanged" do
    test "ModuleDoc still reports an undocumented Elixir module" do
      issues = run_elixir(ModuleDoc, "defmodule Foo do\nend")

      CheckCase.assert_issue(issues, message: ~r/Foo/)
    end

    test "ModuleDoc still reports an undocumented empty-bodied Elixir module" do
      # An empty body must not be mistaken for a Rust declaration.
      issues = run_elixir(ModuleDoc, "defmodule Empty do\nend")

      CheckCase.assert_issue(issues, message: ~r/Empty/)
    end

    test "ModuleNames still reports a non-PascalCase Elixir module" do
      # `defmodule my_app.foo` is not valid Elixir (the adapter falls back to
      # an "unknown" container name), so the fixture uses a single lowercase
      # segment, which is valid syntax and genuinely non-PascalCase.
      issues = run_elixir(ModuleNames, "defmodule my_app do\nend")

      CheckCase.assert_issue(issues, message: ~r/my_app/)
    end

    test "ModuleDoc still reports an undocumented Python class" do
      issues = run(ModuleDoc, "class Foo:\n    pass\n", :python, "a.py")

      CheckCase.assert_issue(issues, message: ~r/Foo/)
    end

    test "ModuleDoc still reports an undocumented Ruby module" do
      issues = run(ModuleDoc, "module Foo\nend\n", :ruby, "a.rb")

      CheckCase.assert_issue(issues, message: ~r/Foo/)
    end

    test "ModuleDoc still reports an undocumented Haskell module" do
      # The Haskell adapter reports the module name as "Main" for this
      # fixture, so the assertion matches on that rather than the source text.
      issues = run(ModuleDoc, "module Foo where\n", :haskell, "a.hs")

      CheckCase.assert_issue(issues, message: ~r/Main/)
    end
  end

  describe "CheckUtils.rust_mod?/1" do
    test "is true for a Rust module container" do
      assert CheckUtils.rust_mod?(container_type: :module, rust_kind: "Module", language: :rust)
    end

    test "is false for a Rust struct container" do
      refute CheckUtils.rust_mod?(container_type: :struct, rust_kind: "Struct", language: :rust)
    end

    test "is false for a Rust impl container" do
      refute CheckUtils.rust_mod?(container_type: :class, rust_kind: "Impl", language: :rust)
    end

    test "is false for a non-Rust module container" do
      refute CheckUtils.rust_mod?(container_type: :module, language: :elixir)
    end

    test "is false for empty metadata" do
      refute CheckUtils.rust_mod?([])
    end

    test "is false for non-list input" do
      refute CheckUtils.rust_mod?(nil)
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
