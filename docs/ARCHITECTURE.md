# Architecture

MetaCredo is a cross-language static analysis tool. It parses source into
Metastatic's unified MetaAST, runs a set of checks over that representation,
and reports issues. Because every language is normalised to the same AST shape,
a check written once runs on Elixir, Python, Ruby, Erlang, JavaScript and the
rest without per-language code.

## Layers

The dependency direction is strictly downward — a layer never calls up.

```
  Mix.Tasks.Metacredo / MetaCredo (public API)
        │
        ▼
  MetaCredo.Execution            orchestration: discover → run → filter → sort
        │
        ├──▶ MetaCredo.Sources    file discovery + parsing (Metastatic adapters)
        │        └──▶ MetaCredo.SourceFile   wraps a Metastatic.Document
        │
        ├──▶ MetaCredo.Config     .metacredo.exs parsing, enabled-check resolution
        │
        ├──▶ MetaCredo.Check.*    the checks themselves (one module per check)
        │        └──▶ MetaCredo.Check.Utils   shared name/line/doc heuristics
        │
        └──▶ MetaCredo.CLI.Output / CLI.Explain   rendering
```

### `MetaCredo.Execution`

The single entry point (`run/1`). It resolves file patterns, discovers and
parses source files, resolves which checks to run, runs them, then applies a
linear chain of filters: inline `metacredo:disable` comments → `--strict` →
`--min-confidence` → `--diff-lines` → sort. Each filter is a named function
with an explicit no-op clause, so they can be tested in isolation.

A check that raises is caught per-file and recorded in `check_failures` rather
than killing the run; the report surfaces the count so a partial run is never
mistaken for a clean one.

### `MetaCredo.Sources` / `MetaCredo.SourceFile`

`Sources.find/1` expands the configured include patterns, applies exclusions,
and parses each file through `Task.async_stream` with bounded concurrency
(`@max_parse_concurrency 8` — each task holds a full AST in memory). A file
that fails to parse is logged and skipped, never fatal.

`SourceFile` wraps the resulting `Metastatic.Document` together with the raw
source, its lines, and the detected language, so checks can read either the
AST or the text.

### `MetaCredo.Check` and the checks

A check is a module that `use MetaCredo.Check, category: ..., base_priority:
..., explanations: [...]` and implements `run/2`. The `__using__` macro
generates `category/0`, `base_priority/0`, `explanations/0`, `param_defaults/0`,
`tags/0`, `confidence/0` and `id/0`, plus a moduledoc assembled from the
declared explanations.

Checks declare a `confidence` (`:high` structural, `:medium` heuristic,
`:low` name-substring). Low-confidence checks are the ones disabled by default
in `Config.default_disabled_checks/0`; `--min-confidence high` filters them out
at report time.

`MetaCredo.Check.Utils` holds the shared, easily-wrong helpers:
`safe_stdlib_call?/1` (never flag `Map.get` as an HTTP "get"), `line_of/2`
(fall back to the enclosing function when a node has no `:line`),
`doc_string_contents/1` (skip `@moduledoc` prose), and `terminator?/1`
(shared by both dead-code detectors).

### Analysis modules

`MetaCredo.Analysis.*` are a separate, programmatic API (complexity,
duplication, dead code, purity) that operates on documents directly rather than
through the check pipeline. They are used by the corresponding `Design.*` and
`Refactor.*` checks and are also callable from user code.

### `MetaCredo.CLI`

`Output` renders a report (terminal, JSON, or GitHub Actions workflow commands).
`Explain` resolves `mix metacredo explain <ref>` targets — a fully-qualified
name, a short name, a file path, or `file:line` — and is kept separate from the
Mix task so it can be tested without driving compilation.

## Testing strategy

- **`check_conformance_test.exs`** parses every check's own documented `wrong`
  example and asserts the check fires on it (and stays silent on `correct`).
  This makes the checks' documentation executable and catches doc drift.
- **`classifier_boundaries_test.exs`** asserts the *precision* half: names that
  look like a heuristic's target but are not (`do_stop_instance`,
  `log_dllb_output`, `Dllb.Query.update`) must produce no finding.
- **`analysis/complexity_test.exs`** is a table-driven test over the six pure
  metric modules, which are functions of a fixed 3-tuple AST shape.
- **`cli/explain_test.exs`** covers the four reference-resolution paths.

## Configuration

`.metacredo.exs` (or `config/.metacredo.exs`, or the XDG global config) is
evaluated with `Code.eval_file/1` and normalised by `Config`. A malformed config
logs a warning and falls back to defaults rather than crashing.
