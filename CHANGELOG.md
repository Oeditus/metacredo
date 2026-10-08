# Changelog

## Unreleased

### Enhancements & Noise Reduction
- **`test/` trees are excluded by default**: `MetaCredo.Config.default/0` now includes `~r"(^|/)test/"` in its `files.excluded` patterns, so `mix metacredo` no longer analyses test files unless you opt in. Checks are tuned for production code, and test files legitimately contain patterns (hardcoded credentials, `assert_raise`, magic numbers, etc.) that otherwise flood the report with false positives. The pattern also covers nested (`lib/test/`) and umbrella (`apps/*/test/`) trees while leaving paths that merely contain the substring `test` (e.g. `lib/latest/`, `lib/contest/`, `test_helper.exs`) untouched. The exclusion is treated as a *default*: explicitly targeting a path via `--path test/` or `--files-included test/` (or listing it in `files.included`) lifts it and analyses the tests, while all other exclusions still apply. `mix metacredo.gen.config`'s generated template is updated to match, and the pattern is exposed as `MetaCredo.Config.test_exclusion_pattern/0`.
- **Curated default check set**: MetaCredo now ships with a much quieter default configuration.
  - **Unsound name-substring security heuristics**: `Security.PathTraversal`, `Security.SSRFVulnerability`, `Security.InsecureDirectObjectReference`, `Security.MissingAuthorization`, `Security.XSSVulnerability`, `Security.UnrestrictedFileUpload`, `Security.InlineJavascript`. These flagged calls whose names merely contained fragments like `get`, `rm`, `file`, `raw`, `id`, or `param` (e.g. `format_issue` matched `rm`; `params_get` matched `get`; `has_raw_content?` matched `raw`).
  - **Unsound database heuristic**: `Warning.NPlusOneQuery` (its `database_function?/1` matched any call containing `get`/`find`/`fetch`/`load`/`select`, so `Map.get` inside a `reduce` tripped it).
  - **Unsound observability/state heuristics**: `Observability.MissingTelemetryInAuthPlug` and `Warning.ImperativeStatusHandling`.
  - **Weak/redundant structural checks**: `Design.LowCohesion` (variable-sharing heuristic), `Warning.CallbackHell` (redundant with `DeepNesting` + `ComplexConditional` + `HighComplexity`).
  - **Legitimate-idiom checks**: `Warning.DebugLeftover` (flagged `IO.puts`/`IO.write` output in CLI/library code).
  - **Until skip-list lands**: `Readability.Specs`.
  All of these remain available via explicit opt-in in `.metacredo.exs`.

### Bug Fixes
- **`Readability.NestedFunctionCalls` false positives on pipe chains**: the check counted every desugared pipe step as a nesting level, so a linear pipeline like `input |> String.trim() |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.join(" | ")` was reported as "Nested function call depth 4-8" and told to "use pipes" -- when pipes were already in use. Pipe steps (Metastatic marks them `pipe: true` when desugaring `x |> f(y)` to `f(x, y)`) are no longer counted as nesting levels, while genuinely nested calls *inside* a pipe step are still reported.
- **`Design.TagTodo` / `Design.TagFixme` false positives outside comments**
- **`Design.TagTodo` / `Design.TagFixme` now accept a configurable tag regexp**: both checks take a `tags` param (a list of strings or regexes, e.g. `[tags: ["TODO", ~r/XXX/]]` in `.metacredo.exs`). String entries match literally; regex entries are used as-is. Defaults remain `["TODO"]` and `["FIXME"]`. The reported `trigger` is now the actual matched text, so custom tags surface their own name.
- **`Readability.ModuleDoc` false positives on macro-generated docs**
- **`Readability.Specs` noise on behaviour callbacks and Mix tasks**: the check no longer requires `@spec` for behaviour/OTP callbacks (`init/1`, `handle_call/3`, `handle_info/2`, `mount/3`, `render/1`, `perform/1`, `__using__/1`, etc.) or for `Mix.Task.run/1`, whose contracts are defined by the behaviour or framework. (Reduced Specs findings from 82 to 8 in this repo.)
- **`Warning.DebugLeftover` false positives on legitimate output**: `IO.puts`, `IO.write`, `print`, `println`, `puts`, and `pp` are no longer flagged, since they are the intended output mechanism in CLI tools, scripts, and libraries. Only genuine debug leftovers (`IO.inspect`, `dbg`, `binding`, `IEx.pry`, `console.log`, etc.) are reported. (Reduced DebugLeftover findings from 46 to 0 in this repo.)

## v0.6.1
### Bug Fixes
- **`mix metacredo` ignored `.metacredo.exs`'s `included` scope by default**: when neither `--path` nor `--files-included` was given, the CLI task unconditionally defaulted analysis to the current directory (`"."`), silently overriding the configured `files.included` (e.g. `["lib/", "src/", "web/"]`) and sweeping `deps/`, `_build/`, and other non-source directories into the report. `mix metacredo` (and `mix metacredo --diff`, which shares the same option resolution) now correctly falls back to the config's `included` paths whenever `--path` is omitted.
- **`excluded` regex patterns silently failed to match relative paths without a leading path separator**: the default (and generated) `excluded` patterns (`~r"/deps/"`, `~r"/_build/"`, `~r"/node_modules/"`, `~r"/\.git/"`) required a literal `/` immediately before the directory name. `Path.wildcard/1` strips a leading `"./"` from a relative `included` entry, so results like `"deps/foo/lib/bar.ex"` (no leading `/`) were never excluded even when correctly listed in `excluded`. Patterns are now anchored with `(^|/)` so they match both relative (`"deps/..."`) and nested/absolute (`".../deps/..."`) paths. Both `MetaCredo.Config.default/0` and `mix metacredo.gen.config`'s generated template are updated.

## v0.6.0

### Enhancements & Fine-Grained Tuning
- **Umbrella Switches (`no_db` and `no_user`)**:
  - Added CLI flags `--no-db` / `--no_db` and `--no-user` / `--no_user` to `mix metacredo`.
  - Added support for `no_db: true` and `no_user: true` (as well as `switches: %{...}`) in `.metacredo.exs`.
  - `--no-db` excludes all database-related checks (`NPlusOneQuery`, `SQLInjection`, `MissingPreload`, and `:db` tagged checks).
  - `--no-user` excludes all user input-related checks (`ImproperInputValidation`, `XSSVulnerability`, `MissingCSRFProtection`, `PathTraversal`, `InsecureDirectObjectReference`, `UnrestrictedFileUpload`, `SSRFVulnerability`, `SensitiveDataExposure`, `InlineJavascript`, `MissingAuthentication`, `MissingAuthorization`, `IncorrectAuthorization`, `ParameterPatternMatching`, and `:user_input` / `:user` tagged checks).

- **Default-Off & Opt-In Checks**:
  - **Hardcoded values in `.exs` files**: `MetaCredo.Check.Security.HardcodedValue` defaults `check_exs: false`, skipping `.exs` script/config files unless opted in with `check_exs: true`.
  - **Module documentation in `.exs` files**: `MetaCredo.Check.Readability.ModuleDoc` defaults `check_exs: false`, skipping `.exs` script/config files unless opted in with `check_exs: true`.
  - **Return-value checks**: `MetaCredo.Check.Warning.UnusedOperation` and `MetaCredo.Check.Warning.MissingErrorHandling` are disabled by default in `Config.default_disabled_checks/0` and require explicit opt-in in `.metacredo.exs`.

- **Global User Configuration (`--global` flag)**:
  - Added `mix metacredo.gen.config --global` to write configuration to the user's global config directory (e.g. `~/.config/metacredo/.metacredo.exs` or `$XDG_CONFIG_HOME/metacredo/.metacredo.exs`).
  - Added automatic fallback to global configuration file in `MetaCredo.Config.read/1` when no local configuration exists.

### Bug Fixes
- **ModuleDoc False-Positives**: Resolved false-positive "Module has no documentation" warnings for Elixir modules using `@moduledoc "..."` string attributes or `@moduledoc false`. Added AST assignment node inspection for `@moduledoc` attributes.

## v0.5.0

### Enhancements & Maintenance
- **Dependency Upgrade**: Updated `:metastatic` dependency constraint to `~> 0.30`.
- **Expanded Multi-Language Support**: Integrated `MetaCredo.Sources` with `Metastatic.Languages` single source of truth for language detection and file extensions, adding support for Cure (`.cure`), March (`.march`, `.mch`), JavaScript (`.js`, `.jsx`, `.mjs`, `.cjs`), and TypeScript (`.ts`, `.tsx`).
- **Cure Adapter Comments & Directives**: Configured Cure parser to preserve comments and enhanced inline directive handling (`# metacredo:disable-for-next-line`) for `.cure` source files.

## v0.4.3

- **Code Quality**: Applied system-wide code formatting and style improvements.

## v0.4.2

- **Encoding & Compatibility**: Added robust Unicode/Latin1 handling for source files with non-standard character encodings.

## v0.4.1

- **Refactoring**: Cleaned up internal helper functions and AST traversal routines.

## v0.4.0

- **Safety Enhancements**: Improved AST metadata handling to prevent potential crashes on non-standard AST metadata forms.

## v0.3.4

- **Check Refactor**: Rewrote `MetaCredo.Check.Observability.MissingTelemetryInObanWorker` check to use `callback_for` AST metadata for precise target method matching.

## v0.3.3

- **False Positive Reduction**: Updated security checks (`HardcodedValue`, `SQLInjection`, etc.) to skip literal strings found inside module and function documentation attributes (`@moduledoc`, `@doc`).

## v0.3.2

- **Defensive Traversal**: Added fallback protections against unexpected or malformed AST node structures during check execution.

## v0.3.1

- **Documentation**: HexDocs improvements and reference guide fixes.

## v0.3.0

- **Internal Analysis Engine**: Replaced delegations to `Metastatic.Analysis.*` with MetaCredo's own decoupled analysis engines:
  - `MetaCredo.Analysis.Complexity` (Cognitive, Cyclomatic, Halstead, LoC, Nesting)
  - `MetaCredo.Analysis.DeadCode`
  - `MetaCredo.Analysis.Duplication` (Fingerprinting & Similarity)
  - `MetaCredo.Analysis.Purity` (Side-effect detection)

## v0.2.0

- **Diff-Based Analysis**: Added `--diff`, `--base`, and `--head` options to analyze only git-modified files in PRs and commits.
- **GitHub Actions Integration**: Added `--format github` flag to produce GitHub Actions workflow commands and inline PR annotations (`::error`, `::warning`, `::notice`).
- **Git API**: Introduced `MetaCredo.Git` module with `changed_files/2` and `repo_root/1`.

## v0.1.1

- **Configuration Generator**: Added `mix metacredo.gen.config` Mix task to generate a customizable `.metacredo.exs` config file.

## v0.1.0

Initial release.

### Core Infrastructure
- `MetaCredo.Check` behaviour macro mirroring `Credo.Check` ergonomics.
- `MetaCredo.SourceFile` wrapping `Metastatic.Document` with source text.
- `MetaCredo.Issue` struct with priority/severity/exit status.
- `MetaCredo.Config` for `.metacredo.exs` configuration parsing.
- `MetaCredo.Execution` pipeline: source discovery, check execution, inline disable filtering.
- `MetaCredo.Sources` for multi-language file discovery and parsing.
- `MetaCredo.CLI.Output` with colored terminal output and JSON format.
- `mix metacredo` task with `--strict`, `--only`, `--ignore`, `--format`, and `explain` subcommand.
- `mix metacredo.gen.config` for generating default configuration.
- Inline disable comments via `# metacredo:disable-for-next-line` and `# metacredo:disable-for-this-file`.

### Checks -- 72 total

**Security (15):** HardcodedValue, SQLInjection, XSSVulnerability, PathTraversal,
SSRFVulnerability, SensitiveDataExposure, MissingCSRFProtection,
InsecureDirectObjectReference, UnrestrictedFileUpload, TOCTOU,
MissingAuthentication, MissingAuthorization, IncorrectAuthorization,
ImproperInputValidation, InlineJavascript.

**Warning (22):** MissingErrorHandling, SilentErrorCase, SwallowingException,
NPlusOneQuery, MissingPreload, UnmanagedTask, SyncOverAsync,
MissingHandleAsync, DirectStructUpdate, CallbackHell, BlockingInPlug,
MissingThrottle, InefficientFilter, ImperativeStatusHandling, UnusedOperation,
UnsafeExec, BoolOperationOnSameValues, OperationOnSameValues,
OperationWithConstantResult, LazyLogging, DebugLeftover, RaiseInsideRescue.

**Readability (13):** MagicNumber, DeepNesting, LongFunction,
ComplexConditional, LongParameterList, FunctionNames, ModuleNames,
VariableNames, ModuleDoc, SinglePipe, NestedFunctionCalls, Specs, LargeNumbers.

**Refactor (10):** SimplifyConditional, DeadCode, CodeDuplication,
NegatedConditionWithElse, DoubleBooleanNegation, AppendSingleItem,
PipeChainStart, FilterCount, UnlessWithElse, VariableRebinding.

**Design (5):** HighComplexity, LowCohesion, HighCoupling, TagTodo, TagFixme.

**Observability (5):** MissingTelemetryInObanWorker,
MissingTelemetryInLiveviewMount, MissingTelemetryInAuthPlug,
MissingTelemetryForExternalHttp, TelemetryInRecursiveFunction.
