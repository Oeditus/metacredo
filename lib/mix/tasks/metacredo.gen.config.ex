defmodule Mix.Tasks.Metacredo.Gen.Config do
  @shortdoc "Generate a default .metacredo.exs configuration file"
  @moduledoc """
  Generates a `.metacredo.exs` configuration file in the current directory.

  ## Usage

      $ mix metacredo.gen.config
  """

  use Mix.Task

  @config_template """
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
          enabled: :all,
          disabled: []
        }
      }
    ]
  }
  """

  @impl Mix.Task
  def run(_argv) do
    path = MetaCredo.Config.default_config_path()

    if File.exists?(path) do
      Mix.shell().info("#{path} already exists, skipping.")
    else
      File.write!(path, @config_template)
      Mix.shell().info("Created #{path}")
    end
  end
end
