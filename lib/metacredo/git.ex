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

    with :ok <- validate_ref(base),
         :ok <- validate_ref(head),
         :ok <- validate_filter(filter) do
      git_diff_switches = [
        "--no-pager",
        "diff",
        "--name-only",
        "--diff-filter=#{filter}",
        "#{base}...#{head}"
      ]

      run_diff(repo_root, git_diff_switches, extensions)
    end
  end

  defp run_diff(repo_root, git_diff_switches, extensions) do
    case System.cmd("git", git_diff_switches, cd: repo_root, stderr_to_stdout: true) do
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
  Returns the lines **added or modified** in each changed file.

  Unlike `changed_files/2`, which reports whole files, this narrows analysis to
  the lines a pull request actually touched -- the difference between a CI
  check people read and one they ignore.

  Returns `{:ok, %{relative_path => MapSet.of(line_numbers)}}`, or
  `{:error, reason}`.

  ## Options

  Same as `changed_files/2`: `:base`, `:head`, `:filter`, `:extensions`.

  ## Examples

      iex> MetaCredo.Git.changed_lines("/path/to/repo")
      {:ok, %{"lib/foo.ex" => MapSet.new([12, 13, 40])}}
  """
  @spec changed_lines(String.t(), keyword()) ::
          {:ok, %{String.t() => MapSet.t()}} | {:error, term()}
  def changed_lines(repo_root, opts \\ []) do
    base = Keyword.get(opts, :base, "origin/main")
    head = Keyword.get(opts, :head, "HEAD")
    filter = Keyword.get(opts, :filter, "ACMR")
    extensions = Keyword.get(opts, :extensions)

    with :ok <- validate_ref(base),
         :ok <- validate_ref(head),
         :ok <- validate_filter(filter) do
      git_diff_switches = [
        "--no-pager",
        "diff",
        "--unified=0",
        "--diff-filter=#{filter}",
        "#{base}...#{head}"
      ]

      case System.cmd("git", git_diff_switches, cd: repo_root, stderr_to_stdout: true) do
        {output, 0} ->
          {:ok, output |> parse_unified_diff() |> maybe_filter_line_extensions(extensions)}

        {error, _code} ->
          {:error, String.trim(error)}
      end
    end
  end

  @doc "Like `changed_lines/2` but raises on error."
  @spec changed_lines!(String.t(), keyword()) :: %{String.t() => MapSet.t()}
  def changed_lines!(repo_root, opts \\ []) do
    case changed_lines(repo_root, opts) do
      {:ok, lines} -> lines
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

  # Git refs are passed to `System.cmd/3` as discrete argv entries (never
  # through a shell), but a ref beginning with `-` would still be interpreted
  # as an option. Validate the shape before use.
  @ref_pattern ~r/^[A-Za-z0-9._\/~^@{}\-]+$/
  @filter_pattern ~r/^[ACDMRTUXB*]+$/

  defp validate_ref(ref) when is_binary(ref) do
    if Regex.match?(@ref_pattern, ref) and not String.starts_with?(ref, "-"),
      do: :ok,
      else: {:error, "invalid git ref: #{inspect(ref)}"}
  end

  defp validate_ref(ref), do: {:error, "invalid git ref: #{inspect(ref)}"}

  defp validate_filter(filter) when is_binary(filter) do
    if Regex.match?(@filter_pattern, filter),
      do: :ok,
      else: {:error, "invalid diff filter: #{inspect(filter)}"}
  end

  defp validate_filter(filter), do: {:error, "invalid diff filter: #{inspect(filter)}"}

  defp maybe_filter_extensions(files, nil), do: files
  defp maybe_filter_extensions(files, []), do: files

  defp maybe_filter_extensions(files, extensions) do
    Enum.filter(files, fn f -> Path.extname(f) in extensions end)
  end

  # -- Unified diff parsing --

  @hunk_header ~r/^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/

  # Parses `git diff --unified=0` output into `%{path => MapSet of line numbers}`.
  #
  # With `-U0` each hunk header is followed immediately by the added lines, so
  # the added range is exactly `+start,count`.
  defp parse_unified_diff(output) do
    output
    |> String.split("\n")
    |> Enum.reduce({nil, %{}}, &parse_diff_line/2)
    |> elem(1)
  end

  # `+++ b/path` starts a new file section; `/dev/null` means a deletion.
  defp parse_diff_line("+++ b/" <> path, {_current, acc}) do
    {path, Map.put_new(acc, path, MapSet.new())}
  end

  defp parse_diff_line("+++ " <> _deleted, {_current, acc}) do
    {nil, acc}
  end

  defp parse_diff_line(line, {path, acc}) when is_binary(path) do
    case Regex.run(@hunk_header, line) do
      [_, start] -> {path, add_range(acc, path, start, "1")}
      [_, start, count] -> {path, add_range(acc, path, start, count)}
      _ -> {path, acc}
    end
  end

  defp parse_diff_line(_line, acc), do: acc

  defp add_range(acc, path, start, count) do
    start = String.to_integer(start)
    count = String.to_integer(count)

    if count == 0 do
      acc
    else
      lines = MapSet.new(start..(start + count - 1))
      Map.update(acc, path, lines, &MapSet.union(&1, lines))
    end
  end

  defp maybe_filter_line_extensions(map, nil), do: map
  defp maybe_filter_line_extensions(map, []), do: map

  defp maybe_filter_line_extensions(map, extensions) do
    Map.filter(map, fn {path, _lines} -> Path.extname(path) in extensions end)
  end
end
