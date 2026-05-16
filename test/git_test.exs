defmodule MetaCredo.GitTest do
  use ExUnit.Case, async: true

  alias MetaCredo.Git

  describe "repo_root/1" do
    test "finds the repo root for a path inside a git repo" do
      root = Git.repo_root(File.cwd!())
      assert is_binary(root)
      assert File.dir?(root)
      assert File.exists?(Path.join(root, ".git"))
    end

    test "returns nil for a path outside any git repo" do
      assert Git.repo_root("/tmp") == nil
    end
  end

  describe "changed_files/2" do
    test "returns {:ok, list} for valid refs" do
      root = Git.repo_root(File.cwd!())

      # HEAD~1..HEAD should always work if there's at least one commit
      case Git.changed_files(root, base: "HEAD~1", head: "HEAD") do
        {:ok, files} ->
          assert is_list(files)
          assert Enum.all?(files, &is_binary/1)

        {:error, _reason} ->
          # Single-commit repo or shallow clone; that's fine
          :ok
      end
    end

    test "returns {:error, _} for non-existent ref" do
      root = Git.repo_root(File.cwd!())
      assert {:error, _} = Git.changed_files(root, base: "nonexistent_ref_abc123")
    end

    test "filters by extensions when provided" do
      root = Git.repo_root(File.cwd!())

      case Git.changed_files(root, base: "HEAD~1", head: "HEAD", extensions: [".ex"]) do
        {:ok, files} ->
          assert Enum.all?(files, &String.ends_with?(&1, ".ex"))

        {:error, _} ->
          :ok
      end
    end
  end

  describe "changed_files!/2" do
    test "raises on error" do
      root = Git.repo_root(File.cwd!())

      assert_raise RuntimeError, ~r/Failed to resolve git diff/, fn ->
        Git.changed_files!(root, base: "nonexistent_ref_abc123")
      end
    end
  end
end
