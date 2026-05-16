# CI / Diff-Based Analysis

MetaCredo supports diff-based analysis for CI/CD pipelines. Only files
changed in a pull request are checked, giving fast, focused feedback.

## Quick Start

```bash
# Analyze only changed files, fail on issues
mix metacredo --diff --strict

# With GitHub Actions inline PR annotations
mix metacredo --diff --format github --strict
```

## Diff Mode

When `--diff` is given, MetaCredo resolves the list of files changed
between two git refs and runs checks only on those files. This is much
faster than analyzing the entire project and avoids reporting pre-existing
issues that are unrelated to the current PR.

### How it works

1. `MetaCredo.Git.changed_files/2` runs
   `git diff --name-only --diff-filter=ACMR <base>...<head>`
2. The result is filtered to supported extensions (`.ex`, `.exs`, `.erl`,
   `.hrl`, `.py`, `.rb`, `.hs`)
3. The file list is passed as `:files_included` to the execution pipeline
4. Checks run only on those files

### Options

```
--diff                Enable diff-based mode
--base REF            Base git ref (default: origin/main)
--head REF            Head git ref (default: HEAD)
--format FORMAT       Output format: text (default), json, github
--strict              Only report normal+ priority issues
--only CATEGORIES     Comma-separated categories (security,warning,...)
--ignore CATEGORIES   Comma-separated categories to skip
```

### Examples

```bash
# Default: diff against origin/main
mix metacredo --diff

# Custom base branch
mix metacredo --diff --base origin/develop

# Strict mode + GitHub annotations
mix metacredo --diff --strict --format github

# Only security checks on changed files
mix metacredo --diff --only security --format github

# JSON output for downstream tooling
mix metacredo --diff --format json
```

## GitHub Actions Format

Use `--format github` to produce GitHub Actions workflow commands:

```
::error file=lib/repo.ex,line=42::HardcodedValue: Hardcoded URL found
::warning file=lib/worker.ex,line=15::MissingErrorHandling: Missing error handling
::notice file=lib/utils.ex,line=3::ModuleDoc: Module missing documentation
metacredo: 3 issue(s) found
```

GitHub renders these as inline annotations on the PR diff:

- `::error` for severity `:error` (red)
- `::warning` for severity `:warning` (yellow)
- `::notice` for severity `:info` and `:refactoring_opportunity` (grey)

## GitHub Actions Integration

### Standalone job

```yaml
metacredo:
  name: MetaCredo Analysis
  if: github.event_name == 'pull_request'
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
      with:
        fetch-depth: 0  # Required for git diff

    - uses: erlef/setup-beam@v1
      with:
        elixir-version: '1.19'
        otp-version: '28'

    - name: Restore deps cache
      uses: actions/cache@v4
      with:
        path: deps
        key: ${{ runner.os }}-mix-${{ hashFiles('**/mix.lock') }}

    - run: mix deps.get
    - run: mix metacredo --diff --base origin/${{ github.base_ref }} --format github --strict
```

Notes:
- `fetch-depth: 0` is required so `git diff` can see the base branch.
- `origin/${{ github.base_ref }}` is the PR target (e.g. `origin/main`).

### Combined with Ragex

If your project uses Ragex, a single command runs both tools:

```yaml
- run: mix ragex.ci --base origin/${{ github.base_ref }} --format github
```

See the [Ragex CI guide](https://hexdocs.pm/ragex/CI.html) for details.

## Other CI Systems

### GitLab CI

```yaml
metacredo:
  stage: test
  only:
    - merge_requests
  script:
    - mix deps.get
    - mix metacredo --diff --base origin/$CI_MERGE_REQUEST_TARGET_BRANCH_NAME --strict
```

### Generic

```bash
#!/bin/bash
BASE="${CI_BASE_REF:-origin/main}"
mix metacredo --diff --base "$BASE" --strict
```

## API: MetaCredo.Git

The `MetaCredo.Git` module provides a lightweight git integration with no
external dependencies beyond the `git` binary:

```elixir
# Find the repo root
root = MetaCredo.Git.repo_root("/path/inside/repo")
# => "/path/to/repo"

# Get changed files
{:ok, files} = MetaCredo.Git.changed_files(root,
  base: "origin/main",
  head: "HEAD",
  extensions: [".ex", ".exs"]
)
# => {:ok, ["lib/foo.ex", "lib/bar.ex"]}

# Bang version (raises on error)
files = MetaCredo.Git.changed_files!(root)
```

### Options for changed_files/2

- `:base` -- base git ref (default: `"origin/main"`)
- `:head` -- head git ref (default: `"HEAD"`)
- `:filter` -- git diff status filter (default: `"ACMR"`, excludes deleted)
- `:extensions` -- list of file extensions to keep (default: all)

## Troubleshooting

### "fatal: bad revision 'origin/main...HEAD'"

Ensure the CI checkout fetches the full history (`fetch-depth: 0`) or
fetch the base branch explicitly:

```bash
git fetch origin main
mix metacredo --diff
```

### "No changed files found in diff"

Expected when only non-code files changed. The task exits with code 0.

### "--diff requires a git repository, but none was found"

The working directory is not inside a git repo. In CI, the checkout step
should handle this automatically.

---

**Version:** MetaCredo 0.2.0
**Last Updated:** May 2026
