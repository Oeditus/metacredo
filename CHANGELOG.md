# Changelog

## Unreleased

### CI classifier boundaries
- `Warning.SyncOverAsync` now uses semantic operation metadata and exact known I/O operations instead of name substrings. Logging, pure standard-library helpers, and query builders are not blocking calls; eagerly evaluated task arguments and actual waits remain checked.
- `Warning.ImperativeStatusHandling` no longer recommends FSMs from lifecycle names or predicates alone. Actual status assignments, map updates, and multi-state branches remain detectable.
- `Warning.MissingThrottle` requires request-boundary evidence rather than CRUD names alone. Module and function limiter scopes are isolated, ordinary request data cannot impersonate a limiter, and pure query construction is distinguished from execution.
- Added parsed-source and synthetic-AST regression coverage for false positives and genuine violations.

### New Features

- **`--baseline` / `--write-baseline`** — record the issues that already exist, then report only *new* ones. This is the practical way to adopt MetaCredo on a codebase that is not clean today: capture once, commit the file, and let CI fail only on regressions. Issues match on `{check, filename, line_no, message}`; a missing or malformed baseline is treated as empty so a stale path never silently hides findings. New module: `MetaCredo.Baseline`.
- **`--min-confidence high|medium|low`** — every `Issue` now carries a `confidence` level. `:high` is AST-structural (`DoubleBooleanNegation`, `FilterCount`, `UnlessWithElse`), `:medium` is structural-but-heuristic (`HighComplexity`, `DeepNesting`), and `:low` is name-substring (`PathTraversal`, `SSRFVulnerability`, `ImperativeStatusHandling`). Checks declare their level via `confidence:` in the `use MetaCredo.Check` block; 26 checks are tagged `:low` and 32 `:high`. This lets you enable a noisy opt-in check without drowning in its output.
- **`--diff-lines`** — narrows reporting to the lines a diff actually touched. Files are still analysed whole (a check needs surrounding context), but pre-existing findings elsewhere in a changed file are suppressed. Backed by `MetaCredo.Git.changed_lines/2`, which parses `git diff --unified=0`.
- **`mix metacredo explain file:line`** is now documented in the README, with the four supported reference forms and a worked example.

### Bug Fixes — checks that never fired on real Elixir code

The new conformance suite (below) drove fixes for **sixteen** checks that were silently dead or wrongly silent:

- **`Consistency.ParameterPatternMatching`** — matched only `:assignment`; the adapter emits `x = expr` as `:inline_match`, so it never fired on any real function.
- **`Refactor.DeadCode`** — `raise`/`throw`/`exit` are `:function_call` nodes, not `:early_return`; and a function body is a bare list, not a `:block`.
- **`Refactor.CodeDuplication`** — the fingerprint included `:line` metadata, so identical bodies at different lines never matched. `min_body_size` raised from 3 to 8: one-line predicates are identical by accident.
- **`Refactor.VariableRebinding`** — matched only `:assignment`, missing every real rebinding.
- **`Refactor.AppendSingleItem`** — matched only `:binary_op`; the adapter emits `a ++ b` as a `:function_call` named `"++"`.
- **`Refactor.UnlessWithElse`** — read `:conditional_kind`, which the adapter does not emit (it uses `original_form: :unless`).
- **`Refactor.NegatedConditionWithElse`** — reported every `cond` clause, because `cond` desugars to a chain of `if/else` nodes.
- **`Readability.ComplexConditional`** — counted the desugared nesting of `cond` as real complexity.
- **`Readability.MagicNumber`** — never descended into `:conditional`/`:inline_match`/`:container`, so most literals were unreachable. Module-attribute values are no longer reported.
- **`Readability.NestedFunctionCalls`** — `Enum.map/2` is emitted as `:collection_op`, which was not counted as a nesting level.
- **`Readability.LargeNumbers`** — reported correctly-separated numbers: the literal value is normalised (`30_000` and `30000` both arrive as `30000`), so the original spelling is now recovered from the source.
- **`Security.SensitiveDataExposure`** — `Logger` is in the stdlib *safe* list, so the check skipped every log call; `user.password` inside an interpolation is a `Map.fetch!` node, not a variable; and `:string_interpolation` was not descended into.
- **`Security.ImproperInputValidation`** — same `:string_interpolation` gap.
- **`Security.TOCTOU`** — `content = File.read!(path)` is an `:inline_match`, which was not descended into.
- **`Warning.MissingPreload`** — only handled inline `Enum.map(Repo.all(...), ...)`; the common `posts = Repo.all(Post); Enum.map(posts, ...)` shape was missed. The query heuristic also matched `Sources.find/1` and `Enum.map(source_files, ...)`, so it now requires a DB-ish module.
- **`Warning.SilentErrorCase`** — `case` is emitted as `:pattern_match`, and a bare `_` catch-all is the symbol literal `:_`.
- **`Warning.UnusedOperation`** — a function body is a bare list, not a `:block`.
- **`Warning.CallbackHell`** — only matched `:conditional`; `case` is `:pattern_match`.
- **`Warning.ImperativeStatusHandling`** — same `:pattern_match` gap, and `order.status` is `Map.fetch!(order, :status)`.
- **`Design.HighComplexity`** — counted zero decision points for a function body (`AST.prewalk/3` does not descend into a bare list).
- **`Design.HighCoupling`** — counted language built-ins (`Enum`, `String`, `Elixir`) and the field-access sentinel `Map.fetch!` as external dependencies, inflating every module's score.
- **`Observability.MissingTelemetryInObanWorker`** — required `callback_for` metadata the Elixir adapter does not emit; now also recognises a `use Oban.Worker` directive.
- **`Observability.MissingTelemetryForExternalHttp`** — did not recognise `get!`/`get?` as the `get` verb, and reported HTTP calls already wrapped in `:telemetry.span/3`.

### Bug Fixes — false positives

- **`Warning.SwallowingException`** — reported `rescue e -> {:error, e}` as a silent swallow; returning a tagged error tuple is a legitimate third option. Rescue bodies arrive as a bare statement list, so multi-statement handlers (including lazy `Logger.debug(fn -> ... end)`) were mis-read.
- **`Warning.LazyLogging`** — flagged calls that were *already* lazy.
- **`Warning.MissingThrottle`** — leaked its API-endpoint context between sibling functions, matched `update` inside `generate_summary`, and flagged predicate helpers. Endpoint detection is now whole-word, per-function, excludes predicates, and recognises a module-level `plug PlugAttack` limiter.
- **`Warning.UnsafeExec`** — matched `cmd` inside `System.cmd` itself and treated the argv variable *name* as user input.
- **`Warning.UnmanagedTask`** — flagged `Task.async_stream/2`, which is bounded and consumed synchronously.
- **`Warning.SyncOverAsync`** — reported blocking work already handed to a supervised task.
- **`Warning.BlockingInPlug`** — treated `Map.fetch!` (field access) as blocking I/O.
- **`Design.TagTodo` / `Design.TagFixme`** — no longer report on their own source files.

### Bug Fixes — `mix metacredo explain`

- **`explain` was silently running a full analysis instead of explaining.** `OptionParser.parse/2` in `:strict` mode raises `ParseError` on the bare word `explain`, which aborted the task before dispatch. The subcommand is now matched *before* `OptionParser` ever sees the arguments, and unknown switches raise a readable `Mix.Error` instead of an opaque stacktrace.
- **`explain <file>` failed for paths outside `lib/`.** `path_to_check_module/1` only stripped a leading `lib/`, so `explain /tmp/foo.ex` reported "not found". It now matches the trailing `MetaCredo/Check/...` segment when present and otherwise falls back to the basename.
- **`explain file:line` could not parse the file.** The Metastatic adapter registry was never started on that path, so every parse failed with `:noproc` and the code snippet was silently omitted.
- The explain machinery moved to `MetaCredo.CLI.Explain`, which also cuts `Mix.Tasks.Metacredo`'s dependency count from 22 to 16.

### Bug Fixes — diff mode
- **`--diff --format github` emitted absolute paths**, which GitHub Actions silently drops — inline PR annotations never appeared. Issue filenames are now rewritten to repo-relative form.
- **`--diff` analysed test files** even though a normal run excludes them. Diff mode derives its file list from git, not from a deliberate user opt-in, so it now passes `lift_test_exclusion: false` and the default `test/` exclusion stays in force.

### Bug Fixes — checks (continued)
- **`Security.SQLInjection`** required only *one* SQL keyword matched as a substring, so `document.createElement` (contains `EXEC`) and any prose containing `FROM` were reported at `:higher` priority. It now requires at least two distinct keywords matched on word boundaries, and skips `.exs` files (new `check_exs` param) as `HardcodedValue` already did.
- **`Warning.DirectStructUpdate`** never fired: `%User{user | field: v}` is emitted as `%`(User, Map.merge(...)), not `:record_update`.
- **`Warning.OperationWithConstantResult`** had two identical clauses; they are now a single table-driven implementation with one parameter fewer.

### Bug Fixes — analysis engines
- **`Analysis.Duplication.detect_in_list/2`** is now a comprehension over `duplicate_pairs/2`, and the unused `_threshold` binding is gone.
- **`Analysis.Purity.Effects.classify_function_call/1`** is table-driven instead of a five-branch `cond`.
- **`Analysis.Complexity.Result.generate_summary/1`** uses a complexity-band table instead of a nested `cond`.
- Swallowed exceptions in `Analysis.Duplication` and `Analysis.Duplication.Fingerprint` are now logged at `:debug` rather than discarded.

### Bug Fixes — umbrella switches
- **`--no-db` / `--no-user` matched on module-name substrings**, the very heuristic `Config.default_disabled_checks/0` documents as the reason for disabling seven checks. Selection is now driven purely by declared `tags` (`:db`, `:user_input`), and every DB/user-input check declares them.

### Bug Fixes — issue locations
- **Many checks emitted `line_no: nil`**, which broke `explain file:line`, the code-snippet renderer, and GitHub inline annotations. Metastatic attaches `:line` to only some nodes, so a shared `MetaCredo.Check.Utils.line_of/2` now falls back to the enclosing function. Applied across 64 check modules (86 call sites).

### Enhancements
- **`MetaCredo.CLI.Explain`** — the `explain` subcommand is now its own module, unit-testable without driving compilation or process exit codes.
- **`MetaCredo.Baseline`** — records and applies a baseline of pre-existing issues (see `--baseline` above).
- **`MetaCredo.CheckCase.run_example/4` and `source_file_from_source/3`** — run a check against real parsed source rather than a hand-built AST.
- **Check conformance suite** (`test/metacredo/check_conformance_test.exs`) — runs every check against its own documented `wrong`/`correct` examples through the real adapter, for both default-enabled and opt-in checks. It found and drove fixes for the sixteen dead checks listed above. Every example is now a complete compilation unit, so the suite is fully enforced rather than skipped.
- **`Git.changed_files/2` validates its refs** against a safe pattern and rejects a leading `-`, so a hostile `--base` cannot smuggle a git option. `changed_lines/2` does the same.
- **`Sources.parse_all/1`** caps parse concurrency at `min(8, schedulers_online)`; each task holds a full AST, so one parser per core was needlessly memory-hungry on large machines.
- **Coverage rose from 41.3% to 52.9%**, almost entirely from the conformance suite now being enforced.

### CI
- **`mix metacredo --strict` now runs as part of `mix quality.ci`** — the tool's own quality gate finally runs the tool.
- **Coverage floor enforced** in the `coverage` job (currently 51%); it can only ratchet up.
- **New `docs` job** builds `mix docs`, so broken doc references fail CI instead of surfacing at release.
- **`release.yml` now tests on Elixir 1.20 / OTP 29** (previously 1.18/27 — the least-tested combination) and uses `softprops/action-gh-release@v2`.

### Documentation
- README install snippet and logo URL updated to `0.7`; check count now reads "72 checks, 52 enabled by default".
- README documents `explain file:line`, confidence levels, and baseline mode.
- CI.md documents `--diff-lines`, `--min-confidence`, and the baseline workflow.
- `.credo.exs` `files.excluded` patterns anchored with `(^|/)`, matching the fix already applied to `MetaCredo.Config`.

### Enhancements & Noise Reduction
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
