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
              files: %{included: ["src/"], excluded: []},
              checks: %{enabled: :all, disabled: []}
            }
          ]
        }
        """)

        config = Config.read(path)
        assert config.name == "test"
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
    test "returns all checks when enabled is :all" do
      config = %{checks: %{enabled: :all, disabled: []}}
      # Returns whatever is registered; may be empty in test env
      checks = Config.enabled_checks(config)
      assert is_list(checks)
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
