defmodule MetaCredo.Git do
  @moduledoc """
  Lightweight git helpers for diff-based analysis.

  Resolves the list of changed files between two git refs so that
  `mix metacredo --diff` can scope analysis to only modified code.
  """

  @doc """
  Returns the list of files changed between `base` and `head` refs.

  Only files that still exist on disk are returned (added, copied,
  modified, renamed -- not deleted).

  ## Options

  - `:base` - Base git ref (default: `"origin/main"`)
  - `:head` - Head git ref (default: `"HEAD"`)
  - `:filter` - Git diff filter string (default: `"ACMR"`)
  - `:extensions` - Optional list of extensions to keep (e.g. `[".ex", ".py"]`)

  ## Examples

      iex> MetaCredo.Git.changed_files("/path/to/repo")
      {:ok, ["lib/foo.ex", "lib/bar.ex"]}
  """
  @spec changed_files(String.t(), keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def changed_files(repo_root, opts \\ []) do
    base = Keyword.get(opts, :base, "origin/main")
    head = Keyword.get(opts, :head, "HEAD")
    filter = Keyword.get(opts, :filter, "ACMR")
    extensions = Keyword.get(opts, :extensions)

    args = [
      "--no-pager",
      "diff",
      "--name-only",
      "--diff-filter=#{filter}",
      "#{base}...#{head}"
    ]

    case System.cmd("git", args, cd: repo_root, stderr_to_stdout: true) do
      {output, 0} ->
        files =
          output
          |> String.split("\n", trim: true)
          |> maybe_filter_extensions(extensions)

        {:ok, files}

      {error, _code} ->
        {:error, String.trim(error)}
    end
  end

  @doc """
  Like `changed_files/2` but raises on error.
  """
  @spec changed_files!(String.t(), keyword()) :: [String.t()]
  def changed_files!(repo_root, opts \\ []) do
    case changed_files(repo_root, opts) do
      {:ok, files} -> files
      {:error, reason} -> raise "Failed to resolve git diff: #{reason}"
    end
  end

  @doc """
  Returns the git repository root for the given path, or `nil`.
  """
  @spec repo_root(String.t()) :: String.t() | nil
  def repo_root(path) do
    dir = if File.dir?(path), do: path, else: Path.dirname(path)

    case System.cmd("git", ["rev-parse", "--show-toplevel"], cd: dir, stderr_to_stdout: true) do
      {root, 0} -> String.trim(root)
      _ -> nil
    end
  end

  # Private functions

  defp maybe_filter_extensions(files, nil), do: files
  defp maybe_filter_extensions(files, []), do: files

  defp maybe_filter_extensions(files, extensions) do
    Enum.filter(files, fn f -> Path.extname(f) in extensions end)
  end
end
