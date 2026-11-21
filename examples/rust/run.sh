#!/usr/bin/env bash
#
# Run MetaCredo against the Rust example crate in this directory.
#
# Usage:
#   ./run.sh                 # analyse examples/rust/src (text output)
#   ./run.sh --strict        # only normal+ priority issues
#   ./run.sh --format json   # machine-readable output
#   ./run.sh --suggest       # also run the checks disabled by default
#
# Any arguments are passed through to `mix metacredo` unchanged. The analysis
# path is always pinned to examples/rust/src, so an extra `--path` flag is not
# needed (and will be overridden).
#
# The script runs from the repository root, because `mix metacredo` must be
# invoked inside the MetaCredo Mix project itself.

set -euo pipefail

EXAMPLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${EXAMPLE_DIR}/../.." && pwd)"
TARGET="${EXAMPLE_DIR}/src"

# `code:root_dir/0` for a *working* Erlang installation, or empty on failure.
#
# ERL_ROOTDIR is cleared for the probe: the whole point is to find a real
# installation while the inherited value is broken, and an `erl` that honours
# the broken value would fail exactly like the one we are trying to replace.
erl_root_dir() {
  env -u ERL_ROOTDIR "$1" -noshell -eval 'io:format("~s", [code:root_dir()]), halt(0).' \
    2>/dev/null || true
}

# Some environments leave ERL_ROOTDIR pointing at an OTP *release* (for
# example a `yoke` release whose erts/bin directory was prepended to PATH).
# Every `mix` invocation then aborts with:
#   cannot get bootfile .../start.boot
# Note that probing `erl` on PATH is not enough to detect this: the release's
# own `erl` wrapper is a shell script that *sets* the broken ERL_ROOTDIR and
# then succeeds, hiding the problem until `mix` runs. Likewise ERL_ROOTDIR may
# be unset in the caller's environment and still be set by that wrapper. The
# only reliable probe is therefore to ask `mix` itself.
needs_erl_repair() {
  ! mix --version >/dev/null 2>&1
}

if needs_erl_repair; then
  CANDIDATES=()

  # mise / asdf installs.
  for pattern in \
    "${HOME}/.local/share/mise/installs/erlang"/*/ \
    "${HOME}/.asdf/installs/erlang"/*/; do
    [ -d "${pattern}" ] && CANDIDATES+=("${pattern}bin/erl")
  done

  # Explicit opt-in override, checked last so it wins.
  [ -n "${METACREDO_ERL:-}" ] && CANDIDATES+=("${METACREDO_ERL}")

  for candidate in "${CANDIDATES[@]}"; do
    [ -x "${candidate}" ] || continue
    DETECTED_ROOT="$(erl_root_dir "${candidate}")"
    [ -n "${DETECTED_ROOT}" ] || continue
    [ -f "${DETECTED_ROOT}/bin/start.boot" ] || continue

    echo "note: repairing ERL_ROOTDIR -> ${DETECTED_ROOT}" >&2
    export ERL_ROOTDIR="${DETECTED_ROOT}"

    # Stop at the first candidate that actually satisfies `mix`.
    needs_erl_repair || break
  done

  if needs_erl_repair; then
    echo "error: \`mix\` cannot start (ERL_ROOTDIR=${ERL_ROOTDIR:-<unset>})." >&2
    echo "       Set METACREDO_ERL to the path of a real 'erl' binary and retry." >&2
    exit 1
  fi
fi

cd "${REPO_ROOT}"

echo "Analysing ${TARGET} ..." >&2

exec mix metacredo --path "${TARGET}" "$@"
