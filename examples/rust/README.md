# MetaCredo Rust example

A deliberately flawed Rust crate used to exercise MetaCredo's cross-language
checks. Every module contains a specific anti-pattern, so a single run
produces findings across several categories.

## Running

```sh
# From the repository root:
./examples/rust/run.sh

# Pass any `mix metacredo` flags through:
./examples/rust/run.sh --strict
./examples/rust/run.sh --format json
./examples/rust/run.sh --suggest
```

The script pins the analysis path to `examples/rust/src` and runs `mix
metacredo` from the repository root. It also recovers from a broken
`ERL_ROOTDIR` (see *Troubleshooting*).

You can also invoke MetaCredo directly:

```sh
mix metacredo --path examples/rust/src
```

## What each module demonstrates

| File | Seeded anti-pattern | Checks that fire |
|---|---|---|
| `src/config.rs` | hardcoded API URL; undocumented `struct Settings` | `HardcodedValue`, `ModuleDoc` ×2 |
| `src/http.rs` | hardcoded URL + hardcoded IP | `HardcodedValue` ×2 |
| `src/dedup.rs` | `end - end`, `count / count`, `value * 0` | `OperationOnSameValues` ×2, `OperationWithConstantResult` |
| `src/naming.rs` | `processUserData`, `GetUserById`, `userId`, `maxRetries` | `FunctionNames` ×2, `VariableNames` ×4 |
| `src/nesting.rs` | five-deep nested `if` | `DeepNesting` |
| `src/numbers.rs` | `3600`, `100000`, `1250000` | `MagicNumber`, `LargeNumbers` ×2 |
| `src/unreachable.rs` | statements after `return` | `DeadCode` ×2, `MagicNumber` |

## Expected output

A default run reports **21 issues across 8 files** with **zero check
failures**:

```
warning:      3
readability: 13
refactor:     2
security:     3
```

Every finding above is deliberate. The `mod x;` declarations in `src/main.rs`
produce no findings: a Rust module *declaration* cannot carry documentation
and is named in `snake_case`, so `ModuleDoc` and `ModuleNames` skip it. Structs,
enums, traits and `impl` blocks are still checked normally.
## Verifying the crate compiles

The crate is valid Rust — it builds cleanly. The 19 warnings `cargo` emits
come from the intentionally non-idiomatic names:

```sh
cd examples/rust && cargo build
```

## Troubleshooting

If `mix` aborts with:

```
cannot get bootfile .../start.boot
```

then `ERL_ROOTDIR` is pointing at an OTP *release* rather than a real Erlang
installation — typically because a release's `erts/bin` directory was
prepended to `PATH`. `run.sh` probes `mix` itself and repairs this
automatically, printing a `note: repairing ERL_ROOTDIR -> ...` line when it
does. To override the detection, point `METACREDO_ERL` at a working `erl`
binary:

```sh
METACREDO_ERL=/usr/lib/erlang/bin/erl ./examples/rust/run.sh
```

## Exit code

A run that finds issues exits **60**, as `mix metacredo` does by design. That
is expected here — the crate is meant to produce findings. Use
`./run.sh > /dev/null; echo $?` to confirm, or `--format json` to inspect them
programmatically.