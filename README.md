# MetaCredo

Cross-language static code analysis tool built on [MetaAST](https://github.com/Oeditus/metastatic).

Write a check once, run it across Elixir, Python, Ruby, Haskell, Erlang, and
all other languages supported by Metastatic.

## Installation

Add `metacredo` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:metacredo, "~> 0.1", only: [:dev, :test], runtime: false}
  ]
end
```

## Usage

```sh
# Run all checks
$ mix metacredo

# Strict mode (only normal+ priority issues)
$ mix metacredo --strict

# Filter by category
$ mix metacredo --only security,warning

# JSON output
$ mix metacredo --format json

# Explain a specific check
$ mix metacredo explain MetaCredo.Check.Security.HardcodedValue

# Generate default configuration
$ mix metacredo.gen.config
```

## How It Works

MetaCredo operates on the **MetaAST** representation provided by Metastatic.
Source files are parsed into a language-agnostic AST using Metastatic's adapters
(Elixir, Python, Ruby, Haskell, Erlang), and then checks pattern-match against
the uniform `{type, keyword_meta, children}` node structure. This means every
check is cross-language by default.

## Check Categories (45 checks)

### Security `[S]` -- 15 checks

- `HardcodedValue` -- Hardcoded URLs, IPs, and sensitive values in string literals
- `SQLInjection` -- SQL string concatenation/interpolation with variables (CWE-89)
- `XSSVulnerability` -- raw(), html_safe, innerHTML, dangerouslySetInnerHTML (CWE-79)
- `PathTraversal` -- File operations with user-controlled paths (CWE-22)
- `SSRFVulnerability` -- HTTP requests with user-controlled URLs (CWE-918)
- `SensitiveDataExposure` -- Logging/inspecting passwords, tokens, PII (CWE-200)
- `MissingCSRFProtection` -- State-changing actions without CSRF validation (CWE-352)
- `InsecureDirectObjectReference` -- Direct DB lookups from user params (CWE-639)
- `UnrestrictedFileUpload` -- File uploads without type/size validation (CWE-434)
- `TOCTOU` -- File.exists? followed by file operations (CWE-367)
- `MissingAuthentication` -- Controllers/handlers without auth middleware (CWE-306)
- `MissingAuthorization` -- Sensitive operations without authorization (CWE-862)
- `IncorrectAuthorization` -- Auth-after-action bugs, negation patterns (CWE-863)
- `ImproperInputValidation` -- User input to sensitive ops without validation (CWE-20)
- `InlineJavascript` -- Inline script tags, onclick handlers, javascript: URIs

### Warning `[W]` -- 14 checks

- `MissingErrorHandling` -- `{:ok, _} = call()` without error handling
- `SilentErrorCase` -- case matching {:ok, _} without {:error, _} branch
- `SwallowingException` -- try/rescue without logging or re-raising
- `NPlusOneQuery` -- Database calls inside collection operations (N+1)
- `MissingPreload` -- Collection ops over DB results without eager loading
- `UnmanagedTask` -- Task.async without Task.Supervisor
- `SyncOverAsync` -- Blocking calls in GenServer/LiveView callbacks
- `MissingHandleAsync` -- Blocking in handle_event without async delegation
- `DirectStructUpdate` -- Struct updates bypassing changesets
- `CallbackHell` -- Deeply nested conditionals exceeding threshold
- `BlockingInPlug` -- Blocking I/O in Plug call/init middleware
- `MissingThrottle` -- Expensive operations without rate limiting
- `InefficientFilter` -- Repo.all then Enum.filter (filter in memory)
- `ImperativeStatusHandling` -- Imperative if/else chains on status codes

### Readability `[R]` -- 5 checks

- `MagicNumber` -- Numeric literals in expressions without named constants
- `DeepNesting` -- Functions with nesting depth exceeding threshold
- `LongFunction` -- Functions with too many statements
- `ComplexConditional` -- Deeply nested boolean operations
- `LongParameterList` -- Functions with too many parameters

### Refactor `[F]` -- 3 checks

- `SimplifyConditional` -- `if x do true else false end` patterns
- `DeadCode` -- Unreachable code after early returns
- `CodeDuplication` -- Duplicate function bodies (same AST structure)

### Design `[D]` -- 3 checks

- `HighComplexity` -- Functions with cyclomatic complexity exceeding threshold
- `LowCohesion` -- Modules where functions share no common data
- `HighCoupling` -- Modules with too many external dependencies

### Observability `[O]` -- 5 checks

- `MissingTelemetryInObanWorker` -- Oban worker perform/1 without telemetry
- `MissingTelemetryInLiveviewMount` -- LiveView mount/3 without telemetry
- `MissingTelemetryInAuthPlug` -- Auth plug call/2 without telemetry
- `MissingTelemetryForExternalHttp` -- HTTP client calls without telemetry wrapper
- `TelemetryInRecursiveFunction` -- Telemetry inside recursive functions (anti-pattern)

## Configuration

Create a `.metacredo.exs` file (or run `mix metacredo.gen.config`):

```elixir
%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "src/"],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      checks: %{
        enabled: :all,
        disabled: []
      }
    }
  ]
}
```

To selectively enable checks with parameters:

```elixir
checks: %{
  enabled: [
    {MetaCredo.Check.Security.HardcodedValue, [exclude_localhost: true]},
    {MetaCredo.Check.Warning.MissingErrorHandling, []},
    {MetaCredo.Check.Readability.MagicNumber, [ignored_numbers: [0, 1, -1, 2]]}
  ],
  disabled: []
}
```

## Inline Disable Comments

Use source comments to suppress specific checks:

```elixir
# metacredo:disable-for-next-line MetaCredo.Check.Security.HardcodedValue
@test_url "https://api.example.com"

# metacredo:disable-for-this-file
```

The comment must be represented as a `:comment` node in the MetaAST for
inline disabling to work. Metastatic's adapters that preserve comments
(e.g., the Cure adapter) support this out of the box.

## Writing Custom Checks

```elixir
defmodule MyApp.Check.CustomCheck do
  use MetaCredo.Check,
    category: :warning,
    base_priority: :normal,
    explanations: [
      check: "Detects a custom anti-pattern.",
      params: [threshold: "Maximum allowed occurrences (default: 3)"]
    ],
    param_defaults: [threshold: 3]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    threshold = params_get(params, :threshold)

    source_file
    |> SourceFile.ast()
    |> Metastatic.AST.prewalk([], fn node, acc ->
      # ... detection logic ...
      {node, acc}
    end)
    |> elem(1)
  end
end
```

Register custom checks in `.metacredo.exs`:

```elixir
checks: %{
  enabled: [
    {MyApp.Check.CustomCheck, [threshold: 5]}
  ]
}
```

## Relationship to Credo and OeditusCredo

- **Credo** operates on Elixir's native AST (`Macro` module). MetaCredo
  operates on the language-agnostic MetaAST.
- **OeditusCredo** provides Credo plugin checks for the Elixir community
  and remains available for Elixir-only projects.
- **MetaCredo** covers the same detection patterns as OeditusCredo but
  works across all languages supported by Metastatic.

## Roadmap

The following items are planned for future releases:

1. **Plugin system** for third-party checks (mirrors Credo plugins).
2. **LSP integration** for in-editor diagnostics.
3. **Auto-fix / code modification** via MetaAST transformations.
4. **CI/CD integrations** (GitHub Actions, GitLab CI, etc.).
5. **Extract analysis modules from metastatic core** in the next major
   release of metastatic, using deprecated re-exports to bridge the
   transition.

## License

MIT
