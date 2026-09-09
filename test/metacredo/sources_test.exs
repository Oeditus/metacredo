defmodule MetaCredo.SourcesTest do
  # Uses `File.cd!/2` to reproduce the exact real-world scenario (relative
  # `included: ["."]`, as used whenever `mix metacredo` runs without an
  # explicit `--path`), which briefly changes the OS-level current
  # directory -- kept `async: false` so it can't race other tests.
  use ExUnit.Case, async: false

  alias MetaCredo.{Config, Sources}

  describe "find/1 -- default exclude patterns against a relative project root" do
    test "excludes deps/_build/node_modules/.git even when included is \".\"" do
      tmp_dir = System.tmp_dir!()

      dir_path =
        Path.join(tmp_dir, "metacredo_sources_test_#{System.unique_integer([:positive])}")

      lib_file = Path.join(dir_path, "lib/real.ex")
      dep_file = Path.join(dir_path, "deps/some_dep/lib/dep.ex")
      build_file = Path.join(dir_path, "_build/dev/lib/some_dep/dep.ex")
      node_modules_file = Path.join(dir_path, "node_modules/pkg/index.js")

      for path <- [lib_file, dep_file, build_file] do
        path |> Path.dirname() |> File.mkdir_p!()
        File.write!(path, "defmodule Fixture do\nend\n")
      end

      node_modules_file |> Path.dirname() |> File.mkdir_p!()
      File.write!(node_modules_file, "module.exports = {};\n")

      on_exit(fn -> File.rm_rf!(dir_path) end)

      # `included: ["."]` mirrors what `mix metacredo` used to default to
      # (before the --path fallback bug was fixed) when no --path/config
      # scope was given -- the whole project tree, relying entirely on the
      # `excluded` patterns to keep deps/build artifacts out.
      excluded = Config.default().files.excluded

      source_files =
        File.cd!(dir_path, fn ->
          Sources.find(%{included: ["."], excluded: excluded})
        end)

      filenames = Enum.map(source_files, & &1.filename)

      assert Enum.any?(filenames, &String.ends_with?(&1, "lib/real.ex"))
      refute Enum.any?(filenames, &String.contains?(&1, "deps/"))
      refute Enum.any?(filenames, &String.contains?(&1, "_build/"))
    end
  end
end
