defmodule Mix.Tasks.MetacredoTest do
  use ExUnit.Case, async: false

  alias MetaCredo.Config
  alias Mix.Tasks.Metacredo, as: MetacredoTask

  setup do
    tmp_dir = Path.join(System.tmp_dir!(), "metacredo_task_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(tmp_dir)

    on_exit(fn ->
      File.rm_rf(tmp_dir)
    end)

    {:ok, tmp_dir: tmp_dir}
  end

  describe "mix metacredo.gen.config --global" do
    test "generates config file in global config directory", %{tmp_dir: tmp_dir} do
      global_dir = Path.join(tmp_dir, ".config")
      System.put_env("XDG_CONFIG_HOME", global_dir)

      try do
        expected_path = Config.global_config_path()
        refute File.exists?(expected_path)

        Mix.Tasks.Metacredo.Gen.Config.run(["--global"])

        assert File.exists?(expected_path)
        content = File.read!(expected_path)
        assert String.contains?(content, "no_db: false")
        assert String.contains?(content, "no_user: false")
        assert String.contains?(content, "MetaCredo.Check.Warning.MissingErrorHandling")
        assert String.contains?(content, "MetaCredo.Check.Warning.UnusedOperation")

        # The curated default policy must be reflected in the generated file:
        # noisy checks belong in the `disabled` section, not `enabled`.
        assert String.contains?(content, "MetaCredo.Check.Security.PathTraversal")
        assert String.contains?(content, "MetaCredo.Check.Design.LowCohesion")
        assert String.contains?(content, "MetaCredo.Check.Warning.CallbackHell")
        assert String.contains?(content, "MetaCredo.Check.Readability.Specs")

        # `disabled:` must appear before these check entries so they are
        # genuinely disabled rather than merely listed.
        [enabled_part, disabled_part] =
          String.split(content, "disabled: [", parts: 2)

        assert String.contains?(disabled_part, "MetaCredo.Check.Security.PathTraversal")
        refute String.contains?(enabled_part, "MetaCredo.Check.Security.PathTraversal")
      after
        System.delete_env("XDG_CONFIG_HOME")
      end
    end
  end

  describe "mix metacredo -- :files_included precedence (build_execution_opts/1)" do
    test "does not set :files_included when neither --path nor --files-included is given" do
      # Regression test: `mix metacredo` with no flags must leave
      # :files_included unset so `Execution.resolve_file_patterns/2` falls
      # back to the `included` list from `.metacredo.exs` (or its default).
      # A previous bug unconditionally defaulted this to `["."]`, silently
      # ignoring the configured `included` scope and sweeping `deps/`,
      # `_build/`, etc. into analysis regardless of configuration.
      execution_opts = MetacredoTask.build_execution_opts([])

      refute Keyword.has_key?(execution_opts, :files_included)
    end

    test "sets :files_included from --path when given" do
      execution_opts = MetacredoTask.build_execution_opts(path: "lib/my_app")

      assert Keyword.fetch!(execution_opts, :files_included) == ["lib/my_app"]
    end

    test "does not override an explicit --files-included value" do
      # `--files-included` is a list of filesystem paths, so entries stay
      # strings. (They were previously atomised by the shared `parse_list/1`
      # helper; that helper now only atomises `--only`/`--ignore` categories.)
      execution_opts = MetacredoTask.build_execution_opts(path: "lib/", files_included: "src/")

      assert Keyword.fetch!(execution_opts, :files_included) == ["src/"]
    end
  end

  describe "category and confidence validation" do
    test "--only accepts a known category" do
      opts = MetacredoTask.build_execution_opts(only: "security,warning")

      assert Keyword.fetch!(opts, :only) == [:security, :warning]
    end

    test "--ignore accepts a known category" do
      opts = MetacredoTask.build_execution_opts(ignore: "design")

      assert Keyword.fetch!(opts, :ignore) == [:design]
    end

    test "--only rejects a misspelled category instead of silently selecting none" do
      # A typo previously produced a nonsense atom, selected zero checks and
      # exited 0 -- a CI gate passing because of a misspelling.
      assert_raise Mix.Error, ~r/Unknown category: "securty"/, fn ->
        MetacredoTask.build_execution_opts(only: "securty")
      end
    end

    test "--ignore rejects an unknown category" do
      assert_raise Mix.Error, ~r/Unknown category/, fn ->
        MetacredoTask.build_execution_opts(ignore: "nonsense")
      end
    end

    test "--min-confidence accepts a known level" do
      opts = MetacredoTask.build_execution_opts(min_confidence: "high")

      assert Keyword.fetch!(opts, :min_confidence) == :high
    end

    test "--min-confidence is case-insensitive" do
      opts = MetacredoTask.build_execution_opts(min_confidence: "HIGH")

      assert Keyword.fetch!(opts, :min_confidence) == :high
    end

    test "--min-confidence rejects a misspelled level instead of silently disabling the filter" do
      assert_raise Mix.Error, ~r/Invalid --min-confidence value: "hgih"/, fn ->
        MetacredoTask.build_execution_opts(min_confidence: "hgih")
      end
    end
  end
end
