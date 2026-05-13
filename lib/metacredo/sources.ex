defmodule MetaCredo.Sources do
  @moduledoc """
  Discovers and parses source files for analysis.

  Maps file extensions to languages, uses `Metastatic.Adapter` to parse
  source code into MetaAST, and wraps results in `MetaCredo.SourceFile` structs.
  """

  alias MetaCredo.SourceFile

  require Logger

  @extension_map %{
    ".ex" => :elixir,
    ".exs" => :elixir,
    ".erl" => :erlang,
    ".hrl" => :erlang,
    ".py" => :python,
    ".rb" => :ruby,
    ".hs" => :haskell
  }

  @doc """
  Finds and parses source files matching the given configuration.

  Also accepts a plain string or list of strings for convenience:

      MetaCredo.Sources.find("lib/")
      MetaCredo.Sources.find(["lib/", "src/"])
  """
  @spec find(map() | String.t() | [String.t()]) :: [SourceFile.t()]
  def find(%{included: included, excluded: excluded}) do
    included
    |> Enum.flat_map(&expand_path/1)
    |> Enum.reject(&excluded?(&1, excluded))
    |> Enum.filter(&supported?/1)
    |> Enum.uniq()
    |> parse_all()
  end

  def find(paths) when is_list(paths) do
    find(%{included: paths, excluded: []})
  end

  def find(path) when is_binary(path) do
    find(%{included: [path], excluded: []})
  end

  @doc "Returns the language for a file based on its extension."
  @spec language_for(String.t()) :: atom() | nil
  def language_for(filename) do
    ext = Path.extname(filename)
    Map.get(@extension_map, ext)
  end

  @doc "Returns the set of supported file extensions."
  @spec supported_extensions() :: [String.t()]
  def supported_extensions, do: Map.keys(@extension_map)

  # -- Private --

  defp expand_path(path) do
    cond do
      File.regular?(path) ->
        [path]

      File.dir?(path) ->
        extensions = Map.keys(@extension_map)
        patterns = Enum.map(extensions, &"#{path}/**/*#{&1}")

        patterns
        |> Enum.flat_map(&Path.wildcard/1)
        |> Enum.filter(&File.regular?/1)

      String.contains?(path, "*") ->
        Path.wildcard(path)

      true ->
        []
    end
  end

  defp excluded?(path, excluded) do
    Enum.any?(excluded, fn
      %Regex{} = regex -> Regex.match?(regex, path)
      pattern when is_binary(pattern) -> String.contains?(path, pattern)
      _ -> false
    end)
  end

  defp supported?(filename) do
    language_for(filename) != nil
  end

  defp parse_all(filenames) do
    filenames
    |> Task.async_stream(
      fn filename ->
        language = language_for(filename)

        case File.read(filename) do
          {:ok, source} -> SourceFile.parse(source, filename, language)
          {:error, reason} -> {:error, {:read_failed, filename, reason}}
        end
      end,
      timeout: 30_000,
      ordered: false
    )
    |> Enum.reduce([], fn
      {:ok, {:ok, source_file}}, acc ->
        [source_file | acc]

      {:ok, {:error, reason}}, acc ->
        Logger.debug("Skipping file: #{inspect(reason)}")
        acc

      {:exit, reason}, acc ->
        Logger.debug("File parsing timed out: #{inspect(reason)}")
        acc
    end)
    |> Enum.reverse()
  end
end
