defmodule MetaCredo.MixProject do
  use Mix.Project

  @app :metacredo
  @version "0.3.2"
  @source_url "https://github.com/Oeditus/metacredo"
  @homepage_url "https://oeditus.com"

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() not in [:dev, :test],
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls],
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_deps: :app_tree,
        plt_add_apps: [:mix, :ex_unit],
        plt_core_path: "priv/plts",
        list_unused_filters: true
      ],
      name: "MetaCredo",
      source_url: @source_url,
      homepage_url: @homepage_url
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ]
    ]
  end

  defp deps do
    [
      # Core dependency
      if System.get_env("LOCAL_METASTATIC") do
        {:metastatic, path: "../metastatic"}
      else
        {:metastatic, "~> 0.21"}
      end,

      # CLI output
      {:marcli, "~> 0.3"},

      # Development and documentation
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: :test, runtime: false},
      {:oeditus_credo, "~> 0.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      quality: ["format", "compile --warnings-as-errors", "credo", "dialyzer"],
      "quality.ci": [
        "format --check-formatted",
        "credo --strict",
        "compile --warnings-as-errors",
        "dialyzer"
      ]
    ]
  end

  defp description do
    """
    Cross-language static code analysis tool built on MetaAST.
    Provides 72 checks covering security (CWE Top 25), code quality,
    readability, design, consistency, observability, and refactoring.
    """
  end

  defp package do
    [
      name: @app,
      files: ~w(
        lib
        priv/images
        .formatter.exs
        mix.exs
        README.md
        CI.md
        LICENSE
        CHANGELOG.md
      ),
      licenses: ["MIT"],
      maintainers: ["Aleksei Matiushkin"],
      links: %{
        "GitHub" => @source_url,
        "Homepage" => @homepage_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md",
        "Documentation" => "https://hexdocs.pm/#{@app}"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      logo: "priv/images/logo-48x48.png",
      assets: %{"priv/images" => "assets"},
      extras: extras(),
      extra_section: "GUIDES",
      source_url: @source_url,
      source_ref: "v#{@version}",
      homepage_url: @homepage_url,
      formatters: ["html", "epub"],
      groups_for_modules: groups_for_modules(),
      nest_modules_by_prefix: [
        MetaCredo.Analysis.Complexity,
        MetaCredo.Analysis.DeadCode,
        MetaCredo.Analysis.Duplication,
        MetaCredo.Analysis.Purity,
        MetaCredo.Check.Consistency,
        MetaCredo.Check.Design,
        MetaCredo.Check.Observability,
        MetaCredo.Check.Readability,
        MetaCredo.Check.Refactor,
        MetaCredo.Check.Security,
        MetaCredo.Check.Warning,
        MetaCredo.CLI
      ],
      before_closing_body_tag: &before_closing_body_tag/1,
      authors: ["Aleksei Matiushkin"],
      canonical: "https://hexdocs.pm/#{@app}",
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
    ]
  end

  defp extras do
    [
      "README.md",
      "CI.md": [title: "CI / Diff-Based Analysis"],
      LICENSE: [title: "License"],
      "CHANGELOG.md": [title: "Changelog"]
    ]
  end

  defp groups_for_modules do
    [
      Core: [
        MetaCredo,
        MetaCredo.Check,
        MetaCredo.Config,
        MetaCredo.Git,
        MetaCredo.Execution,
        MetaCredo.Issue,
        MetaCredo.SourceFile,
        MetaCredo.Sources
      ],
      Analysis: [
        MetaCredo.Analysis.Complexity,
        MetaCredo.Analysis.Complexity.Cognitive,
        MetaCredo.Analysis.Complexity.Cyclomatic,
        MetaCredo.Analysis.Complexity.FunctionMetrics,
        MetaCredo.Analysis.Complexity.Halstead,
        MetaCredo.Analysis.Complexity.LoC,
        MetaCredo.Analysis.Complexity.Nesting,
        MetaCredo.Analysis.Complexity.Result,
        MetaCredo.Analysis.DeadCode,
        MetaCredo.Analysis.DeadCode.Result,
        MetaCredo.Analysis.Duplication,
        MetaCredo.Analysis.Duplication.Fingerprint,
        MetaCredo.Analysis.Duplication.Result,
        MetaCredo.Analysis.Duplication.Similarity,
        MetaCredo.Analysis.Duplication.Types,
        MetaCredo.Analysis.Purity,
        MetaCredo.Analysis.Purity.Effects,
        MetaCredo.Analysis.Purity.Result
      ],
      "Consistency Checks": [
        MetaCredo.Check.Consistency.ExceptionNames,
        MetaCredo.Check.Consistency.ParameterPatternMatching
      ],
      "Security Checks": [
        MetaCredo.Check.Security.HardcodedValue,
        MetaCredo.Check.Security.SQLInjection,
        MetaCredo.Check.Security.XSSVulnerability,
        MetaCredo.Check.Security.PathTraversal,
        MetaCredo.Check.Security.SSRFVulnerability,
        MetaCredo.Check.Security.SensitiveDataExposure,
        MetaCredo.Check.Security.MissingCSRFProtection,
        MetaCredo.Check.Security.InsecureDirectObjectReference,
        MetaCredo.Check.Security.UnrestrictedFileUpload,
        MetaCredo.Check.Security.TOCTOU,
        MetaCredo.Check.Security.MissingAuthentication,
        MetaCredo.Check.Security.MissingAuthorization,
        MetaCredo.Check.Security.IncorrectAuthorization,
        MetaCredo.Check.Security.ImproperInputValidation,
        MetaCredo.Check.Security.InlineJavascript
      ],
      "Warning Checks": [
        MetaCredo.Check.Warning.MissingErrorHandling,
        MetaCredo.Check.Warning.SilentErrorCase,
        MetaCredo.Check.Warning.SwallowingException,
        MetaCredo.Check.Warning.NPlusOneQuery,
        MetaCredo.Check.Warning.MissingPreload,
        MetaCredo.Check.Warning.UnmanagedTask,
        MetaCredo.Check.Warning.SyncOverAsync,
        MetaCredo.Check.Warning.MissingHandleAsync,
        MetaCredo.Check.Warning.DirectStructUpdate,
        MetaCredo.Check.Warning.CallbackHell,
        MetaCredo.Check.Warning.BlockingInPlug,
        MetaCredo.Check.Warning.MissingThrottle,
        MetaCredo.Check.Warning.InefficientFilter,
        MetaCredo.Check.Warning.ImperativeStatusHandling,
        MetaCredo.Check.Warning.UnusedOperation,
        MetaCredo.Check.Warning.UnsafeExec,
        MetaCredo.Check.Warning.BoolOperationOnSameValues,
        MetaCredo.Check.Warning.OperationOnSameValues,
        MetaCredo.Check.Warning.OperationWithConstantResult,
        MetaCredo.Check.Warning.LazyLogging,
        MetaCredo.Check.Warning.DebugLeftover,
        MetaCredo.Check.Warning.RaiseInsideRescue
      ],
      "Readability Checks": [
        MetaCredo.Check.Readability.MagicNumber,
        MetaCredo.Check.Readability.DeepNesting,
        MetaCredo.Check.Readability.LongFunction,
        MetaCredo.Check.Readability.ComplexConditional,
        MetaCredo.Check.Readability.LongParameterList,
        MetaCredo.Check.Readability.FunctionNames,
        MetaCredo.Check.Readability.ModuleNames,
        MetaCredo.Check.Readability.VariableNames,
        MetaCredo.Check.Readability.ModuleDoc,
        MetaCredo.Check.Readability.SinglePipe,
        MetaCredo.Check.Readability.NestedFunctionCalls,
        MetaCredo.Check.Readability.Specs,
        MetaCredo.Check.Readability.LargeNumbers
      ],
      "Refactor Checks": [
        MetaCredo.Check.Refactor.SimplifyConditional,
        MetaCredo.Check.Refactor.DeadCode,
        MetaCredo.Check.Refactor.CodeDuplication,
        MetaCredo.Check.Refactor.NegatedConditionWithElse,
        MetaCredo.Check.Refactor.DoubleBooleanNegation,
        MetaCredo.Check.Refactor.AppendSingleItem,
        MetaCredo.Check.Refactor.PipeChainStart,
        MetaCredo.Check.Refactor.FilterCount,
        MetaCredo.Check.Refactor.UnlessWithElse,
        MetaCredo.Check.Refactor.VariableRebinding
      ],
      "Design Checks": [
        MetaCredo.Check.Design.HighComplexity,
        MetaCredo.Check.Design.LowCohesion,
        MetaCredo.Check.Design.HighCoupling,
        MetaCredo.Check.Design.TagFixme,
        MetaCredo.Check.Design.TagTodo
      ],
      "Observability Checks": [
        MetaCredo.Check.Observability.MissingTelemetryInObanWorker,
        MetaCredo.Check.Observability.MissingTelemetryInLiveviewMount,
        MetaCredo.Check.Observability.MissingTelemetryInAuthPlug,
        MetaCredo.Check.Observability.MissingTelemetryForExternalHttp,
        MetaCredo.Check.Observability.TelemetryInRecursiveFunction
      ],
      Internals: [
        MetaCredo.Check.Utils,
        MetaCredo.CheckCase,
        MetaCredo.CLI.Output
      ]
    ]
  end

  defp before_closing_body_tag(:html) do
    """
    <script>
      document.addEventListener("keydown", function(e) {
        if (e.key === "/" && !e.ctrlKey && !e.metaKey) {
          e.preventDefault();
          document.querySelector(".search-input")?.focus();
        }
      });
    </script>
    """
  end

  defp before_closing_body_tag(_), do: ""
end
