defmodule MetaCredo.Config do
  @moduledoc """
  Parses and manages `.metacredo.exs` configuration files.

  Configuration follows the same shape as `.credo.exs`:

      %{
        configs: [
          %{
            name: "default",
            files: %{
              included: ["lib/", "src/"],
              excluded: ["deps/", "_build/"]
            },
            checks: %{
              enabled: [
                {MetaCredo.Check.Security.HardcodedValue, []},
                {MetaCredo.Check.Warning.MissingErrorHandling, []}
              ],
              disabled: []
            }
          }
        ]
      }
  """

  require Logger

  @type config :: %{
          name: String.t(),
          files: %{included: [String.t()], excluded: [String.t()]},
          checks: %{enabled: [{module(), Keyword.t()}], disabled: [{module(), Keyword.t()}]}
        }

  @default_config %{
    name: "default",
    files: %{
      included: ["lib/", "src/", "web/"],
      excluded: [
        ~r"/_build/",
        ~r"/deps/",
        ~r"/node_modules/",
        ~r"/\.git/"
      ]
    },
    checks: %{
      enabled: :all,
      disabled: []
    }
  }

  @doc "Reads and parses the configuration file, falling back to defaults."
  @spec read(String.t() | nil) :: config()
  def read(config_file \\ nil) do
    path = config_file || find_config_file()

    if path && File.exists?(path) do
      parse_file(path)
    else
      @default_config
    end
  end

  @doc "Returns the default configuration."
  @spec default() :: config()
  def default, do: @default_config

  @doc "Returns the list of enabled checks from config."
  @spec enabled_checks(config()) :: [{module(), Keyword.t()}]
  def enabled_checks(%{checks: %{enabled: :all}}) do
    all_checks()
    |> Enum.map(fn mod -> {mod, []} end)
  end

  def enabled_checks(%{checks: %{enabled: enabled, disabled: disabled}}) do
    disabled_modules = Enum.map(disabled, fn {mod, _} -> mod end)

    enabled
    |> Enum.reject(fn {mod, _} -> mod in disabled_modules end)
  end

  @doc "Returns the file patterns from config."
  @spec file_patterns(config()) :: %{included: [String.t()], excluded: [term()]}
  def file_patterns(%{files: files}), do: files

  @doc "Returns the path to the default configuration file."
  @spec default_config_path() :: String.t()
  def default_config_path, do: ".metacredo.exs"

  # -- Private --

  defp find_config_file do
    [".metacredo.exs", "config/.metacredo.exs"]
    |> Enum.find(&File.exists?/1)
  end

  defp parse_file(path) do
    case Code.eval_file(path) do
      {%{configs: [config | _]}, _binding} ->
        normalize_config(config)

      {config, _binding} when is_map(config) ->
        normalize_config(config)

      _ ->
        Logger.warning("Invalid config file #{path}, using defaults")
        @default_config
    end
  rescue
    e ->
      Logger.warning("Failed to read config #{path}: #{inspect(e)}, using defaults")
      @default_config
  end

  defp normalize_config(config) do
    %{
      name: Map.get(config, :name, "default"),
      files: Map.get(config, :files, @default_config.files),
      checks: Map.get(config, :checks, @default_config.checks)
    }
  end

  defp all_checks do
    {:ok, modules} = :application.get_key(:metacredo, :modules)

    modules
    |> Enum.filter(fn mod ->
      module_name = to_string(mod)
      String.starts_with?(module_name, "Elixir.MetaCredo.Check.") and check_module?(mod)
    end)
  rescue
    _ -> []
  end

  defp check_module?(mod) do
    function_exported?(mod, :run, 2) and function_exported?(mod, :category, 0)
  end
end
