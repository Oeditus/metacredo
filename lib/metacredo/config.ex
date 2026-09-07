defmodule MetaCredo.Config do
  @moduledoc """
  Parses and manages `.metacredo.exs` configuration files.

  Configuration follows a map structure similar to `.credo.exs`:

      %{
        configs: [
          %{
            name: "default",
            files: %{
              included: ["lib/", "src/", "web/"],
              excluded: [
                ~r"/_build/",
                ~r"/deps/",
                ~r"/node_modules/"
              ]
            },
            checks: %{
              enabled: [
                {MetaCredo.Check.Security.HardcodedValue, [exclude_localhost: true]},
                {MetaCredo.Check.Warning.MissingErrorHandling, []},
                {MetaCredo.Check.Readability.MagicNumber, [ignored_numbers: [0, 1, -1, 2]]}
              ],
              disabled: [
                {MetaCredo.Check.Readability.ModuleDoc, []}
              ]
            }
          }
        ]
      }

  Configuration files are resolved in order from `.metacredo.exs` or `config/.metacredo.exs`.
  Run `mix metacredo.gen.config` to generate a complete configuration file listing all checks.
  """

  require Logger

  @type config :: %{
          name: String.t(),
          no_db: boolean(),
          no_user: boolean(),
          files: %{included: [String.t()], excluded: [String.t() | Regex.t()]},
          checks: %{
            enabled: [{module(), Keyword.t()}] | :all,
            disabled: [{module(), Keyword.t()}]
          }
        }

  @doc "Reads and parses the configuration file, falling back to defaults."
  @spec read(String.t() | nil) :: config()
  def read(config_file \\ nil) do
    path = config_file || find_config_file()

    if path && File.exists?(path) do
      parse_file(path)
    else
      default()
    end
  end

  @doc "Returns the default configuration."
  @spec default() :: config()
  def default do
    %{
      name: "default",
      no_db: false,
      no_user: false,
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
        disabled: Enum.map(default_disabled_checks(), &{&1, []})
      }
    }
  end

  @doc "Returns default disabled checks."
  @spec default_disabled_checks() :: [module()]
  def default_disabled_checks do
    [
      MetaCredo.Check.Security.MissingAuthentication,
      MetaCredo.Check.Security.MissingCSRFProtection,
      MetaCredo.Check.Security.IncorrectAuthorization,
      MetaCredo.Check.Security.ImproperInputValidation,
      MetaCredo.Check.Warning.MissingErrorHandling,
      MetaCredo.Check.Warning.UnusedOperation
    ]
  end

  @doc "Returns the list of enabled checks from config."
  @spec enabled_checks(config()) :: [{module(), Keyword.t()}]
  def enabled_checks(%{checks: %{enabled: :all, disabled: disabled}}) do
    disabled_modules = Enum.map(disabled, fn {mod, _} -> mod end)

    all_checks()
    |> Enum.map(fn mod -> {mod, []} end)
    |> Enum.reject(fn {mod, _} -> mod in disabled_modules end)
  end

  def enabled_checks(%{checks: %{enabled: :all}}) do
    disabled_modules = default_disabled_checks()

    all_checks()
    |> Enum.map(fn mod -> {mod, []} end)
    |> Enum.reject(fn {mod, _} -> mod in disabled_modules end)
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

  @doc "Returns the path to the global user configuration file."
  @spec global_config_path() :: String.t()
  def global_config_path do
    config_dir =
      System.get_env("XDG_CONFIG_HOME") ||
        Path.join(System.user_home!(), ".config")

    Path.join([config_dir, "metacredo", ".metacredo.exs"])
  end

  # -- Private --

  defp find_config_file do
    [".metacredo.exs", "config/.metacredo.exs", global_config_path()]
    |> Enum.find(&File.exists?/1)
  end

  defp parse_file(path) do
    # credo:disable-for-next-line
    case Code.eval_file(path) do
      {%{configs: [config | _]}, _binding} ->
        normalize_config(config)

      {config, _binding} when is_map(config) ->
        normalize_config(config)

      _ ->
        Logger.warning("Invalid config file #{path}, using defaults")
        default()
    end
  rescue
    e ->
      Logger.warning("Failed to read config #{path}: #{inspect(e)}, using defaults")
      default()
  end

  defp normalize_config(config) do
    switches = Map.get(config, :switches, %{})

    %{
      name: Map.get(config, :name, "default"),
      files: Map.get(config, :files, default().files),
      checks: Map.get(config, :checks, default().checks),
      no_db: Map.get(config, :no_db, Map.get(switches, :no_db, false)),
      no_user: Map.get(config, :no_user, Map.get(switches, :no_user, false))
    }
  end

  defp all_checks do
    # Try multiple strategies to discover check modules:
    # 1. Application modules list (works in releases)
    # 2. Code.all_available/0 (works in Mix tasks, Elixir 1.16+)
    # 3. Fallback to hardcoded list
    modules =
      case :application.get_key(:metacredo, :modules) do
        {:ok, mods} when mods != [] -> mods
        _ -> discover_loaded_modules()
      end

    modules
    |> Enum.filter(fn mod ->
      module_name = to_string(mod)
      String.starts_with?(module_name, "Elixir.MetaCredo.Check.") and check_module?(mod)
    end)
    |> Enum.sort()
  end

  defp discover_loaded_modules do
    :code.all_loaded()
    |> Enum.map(fn {mod, _} -> mod end)
    |> Enum.filter(fn mod ->
      mod_str = to_string(mod)
      String.starts_with?(mod_str, "Elixir.MetaCredo.Check.")
    end)
  end

  defp check_module?(mod) do
    Code.ensure_loaded?(mod) and
      function_exported?(mod, :run, 2) and function_exported?(mod, :category, 0)
  end
end
