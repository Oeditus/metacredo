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
      # `--files-included` is parsed via the pre-existing `parse_list/1`
      # helper (also used for `--only`/`--ignore` categories), which turns
      # each comma-separated entry into an atom -- that quirk is unrelated
      # to this regression and preserved as-is here; the point of this test
      # is only that an explicit `--files-included` still wins over `--path`.
      execution_opts = MetacredoTask.build_execution_opts(path: "lib/", files_included: "src/")

      assert Keyword.fetch!(execution_opts, :files_included) == [:"src/"]
    end
  end
end
