defmodule MetaCredo.ConfigTest do
  use ExUnit.Case, async: true

  alias MetaCredo.Config

  describe "default/0" do
    test "returns a valid config map" do
      config = Config.default()
      assert config.name == "default"
      assert is_map(config.files)
      assert is_list(config.files.included)
      assert is_list(config.files.excluded)
    end

    test "default includes standard directories" do
      config = Config.default()
      assert "lib/" in config.files.included
    end

    test "default excludes build artifacts" do
      config = Config.default()

      assert Enum.any?(config.files.excluded, fn
               %Regex{} = r -> Regex.match?(r, "/_build/")
               _ -> false
             end)
    end

    test "default excludes match build/dep/vcs directories even without a leading path separator" do
      # Regression test: `Path.wildcard/1` results for a top-level `included`
      # entry (e.g. ".") return paths like "deps/foo/lib/bar.ex", with no
      # leading "/" before "deps" -- the exclude patterns must still match
      # these, not just absolute-style paths like "/project/deps/foo.ex".
      config = Config.default()

      matches? = fn path ->
        Enum.any?(config.files.excluded, fn
          %Regex{} = r -> Regex.match?(r, path)
          _ -> false
        end)
      end

      assert matches?.("deps/foo/lib/bar.ex")
      assert matches?.("_build/dev/lib/foo.ex")
      assert matches?.("node_modules/foo/index.js")
      assert matches?.(".git/HEAD")
      # still matches when nested under an absolute/relative prefix
      assert matches?.("/home/me/project/deps/foo/lib/bar.ex")
    end

    test "default includes disabled checks for error handling and unused operations" do
      disabled = Config.default_disabled_checks()
      assert MetaCredo.Check.Warning.MissingErrorHandling in disabled
      assert MetaCredo.Check.Warning.UnusedOperation in disabled
    end

    test "global_config_path returns expected path under user config directory" do
      path = Config.global_config_path()

      assert String.ends_with?(path, ".config/metacredo/.metacredo.exs") or
               String.contains?(path, "metacredo/.metacredo.exs")
    end
  end

  describe "read/1" do
    test "returns default when no config file exists" do
      config = Config.read("/nonexistent/.metacredo.exs")
      assert config.name == "default"
    end

    test "reads a valid config file" do
      path = Path.join(System.tmp_dir!(), "test_metacredo_#{:rand.uniform(100_000)}.exs")

      try do
        File.write!(path, """
        %{
          configs: [
            %{
              name: "test",
              no_db: true,
              no_user: true,
              files: %{included: ["src/"], excluded: []},
              checks: %{enabled: :all, disabled: []}
            }
          ]
        }
        """)

        config = Config.read(path)
        assert config.name == "test"
        assert config.no_db == true
        assert config.no_user == true
        assert config.files.included == ["src/"]
      after
        File.rm(path)
      end
    end

    test "falls back to defaults on malformed file" do
      path = Path.join(System.tmp_dir!(), "bad_metacredo_#{:rand.uniform(100_000)}.exs")

      try do
        File.write!(path, "not a valid config")

        config = Config.read(path)
        assert config.name == "default"
      after
        File.rm(path)
      end
    end
  end

  describe "enabled_checks/1" do
    test "returns all checks except default_disabled when enabled is :all" do
      config = Config.default()
      checks = Config.enabled_checks(config)
      modules = Enum.map(checks, &elem(&1, 0))
      refute MetaCredo.Check.Warning.MissingErrorHandling in modules
      refute MetaCredo.Check.Warning.UnusedOperation in modules
    end

    test "filters out disabled checks" do
      config = %{
        checks: %{
          enabled: [
            {MetaCredo.Check.Security.HardcodedValue, []},
            {MetaCredo.Check.Warning.MissingErrorHandling, []}
          ],
          disabled: [
            {MetaCredo.Check.Security.HardcodedValue, []}
          ]
        }
      }

      checks = Config.enabled_checks(config)
      modules = Enum.map(checks, &elem(&1, 0))
      refute MetaCredo.Check.Security.HardcodedValue in modules
      assert MetaCredo.Check.Warning.MissingErrorHandling in modules
    end
  end

  describe "file_patterns/1" do
    test "extracts file patterns from config" do
      config = %{files: %{included: ["lib/"], excluded: ["test/"]}}
      patterns = Config.file_patterns(config)
      assert patterns.included == ["lib/"]
      assert patterns.excluded == ["test/"]
    end
  end
end
