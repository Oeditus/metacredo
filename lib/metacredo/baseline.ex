defmodule MetaCredo.Baseline do
  @moduledoc """
  Records and applies a baseline of pre-existing issues.

  A baseline lets you adopt MetaCredo on a legacy codebase without drowning in
  findings: capture the current state once, then report only issues introduced
  *after* that point.

      # Record the current state
      $ mix metacredo --write-baseline .metacredo.baseline.json

      # Report only issues not present in the baseline
      $ mix metacredo --baseline .metacredo.baseline.json --strict

  ## Matching

  Issues are matched on `{check, filename, line_no, message}`. Line numbers
  shift as code moves, so the baseline is deliberately *not* keyed on line
  alone -- a finding that moved but did not change is still considered
  pre-existing.

  ## Format

  A JSON object with a `version` and an `issues` array. The file is written
  deterministically (sorted keys, stable ordering) so it diffs cleanly in
  version control.
  """

  alias MetaCredo.Issue

  @version 1

  @typedoc "The stable identity of an issue, used for baseline matching."
  @type key :: {module(), String.t() | nil, pos_integer() | nil, String.t()}

  @doc """
  Returns the baseline key for an issue.
  """
  @spec key(Issue.t()) :: key()
  def key(%Issue{} = issue) do
    {issue.check, issue.filename, issue.line_no, issue.message}
  end

  @doc """
  Serialises `issues` to the baseline JSON format.
  """
  @spec encode([Issue.t()]) :: String.t()
  def encode(issues) do
    data = %{
      "version" => @version,
      "issues" =>
        issues
        |> Enum.map(&to_map/1)
        |> Enum.uniq()
        |> Enum.sort_by(&{&1["check"], &1["filename"] || "", &1["line_no"] || 0, &1["message"]})
    }

    :json.encode(data) |> IO.iodata_to_binary()
  end

  @doc """
  Writes a baseline file, creating parent directories as needed.

  Returns `:ok` or `{:error, reason}`.
  """
  @spec write(Path.t(), [Issue.t()]) :: :ok | {:error, term()}
  def write(path, issues) do
    with :ok <- File.mkdir_p(Path.dirname(path)) do
      File.write(path, encode(issues) <> "\n")
    end
  end

  @doc """
  Reads a baseline file into a `MapSet` of keys.

  Returns `{:ok, keys}` or `{:error, reason}`.
  """
  @spec read(Path.t()) :: {:ok, MapSet.t(key())} | {:error, term()}
  def read(path) do
    with {:ok, contents} <- File.read(path),
         {:ok, data} <- decode(contents) do
      keys =
        data
        |> Map.get("issues", [])
        |> Enum.map(&from_map/1)
        |> MapSet.new()

      {:ok, keys}
    end
  end

  @doc """
  Removes every issue already present in the baseline at `path`.

  A missing or unreadable baseline is treated as empty (nothing is filtered),
  so a stale path never silently hides findings.
  """
  @spec filter([Issue.t()], Path.t()) :: [Issue.t()]
  def filter(issues, path) do
    case read(path) do
      {:ok, keys} -> Enum.reject(issues, &MapSet.member?(keys, key(&1)))
      {:error, _reason} -> issues
    end
  end

  # -- Private --

  defp to_map(%Issue{} = issue) do
    %{
      "check" => to_string(issue.check),
      "filename" => issue.filename,
      "line_no" => issue.line_no,
      "message" => issue.message
    }
  end

  defp from_map(%{"check" => check} = map) do
    {
      check |> String.split(".") |> Module.concat(),
      map["filename"],
      map["line_no"],
      map["message"]
    }
  end

  defp decode(contents) do
    case :json.decode(contents) do
      %{} = data -> {:ok, data}
      _ -> {:error, :invalid_baseline}
    end
  rescue
    _ -> {:error, :invalid_baseline}
  end
end
