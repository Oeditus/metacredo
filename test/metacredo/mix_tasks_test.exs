defmodule Mix.Tasks.MetacredoTest do
  use ExUnit.Case, async: false

  alias MetaCredo.Config

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
end
