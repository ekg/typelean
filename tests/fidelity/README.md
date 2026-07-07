# typelean fidelity suite (M1)

End-to-end parity testing: for each Lean program in `cases/`, capture Lean's
result (`lean --run`) and the result of the emitted TypeScript under `node`,
and diff them. A mismatch is a fidelity bug (DESIGN §12; ROADMAP M1/M6).

## Corpus

Each case is a standalone Lean file with `def main : IO Unit := IO.println <v>`
so that `lean --run case.lean` and the emitted TS (run under `node`) both print
exactly `<v>` — a uniform, single-line comparison. The M1 corpus (ROADMAP M1,
≥5 cases):

| file                  | category                       | expected output       |
|-----------------------|--------------------------------|-----------------------|
| `arith.lean`          | arithmetic over `Nat`          | `5`                   |
| `letlambda.lean`      | `let` / λ (curried application)| `42`                  |
| `inductive_match.lean`| user inductive + `match`      | `1`                   |
| `rec_nat.lean`        | recursive `Nat` function       | `120`                 |
| `string_concat.lean`  | string concatenation           | `hello, typelean!`    |

The corpus is **grow-only**: every fixed fidelity bug adds a regression case
here (ROADMAP M6).

## Harness

`run.sh` is the parity harness (DESIGN §12, steps 2–4):

1. **Lean result** — `lean --run cases/<case>.lean` (stdout captured).
2. **Compile** — `typelean cases/<case>.lean` emits TypeScript to stdout (the
   real product path, DESIGN §12 step 3: "Compile with typelean ⇒ prog.ts").
3. **Node result** — the emitted TS is written to a temp `.mts` (ESM + Node
   type-stripping, so both typed and untyped output run) and executed with
   `node`.
4. **Diff** — `lean_out` vs `node_out` (trailing newlines normalized by command
   substitution). `PASS` if equal, else `FAIL`.

A case is `BLOCKED` when `typelean` itself exits non-zero (a stage-tagged
`CompileError`: `frontend` / `lower` / `emit`). `BLOCKED` is reported with the
offending stage + first error line so the gap is visible, never silent (DESIGN
§1.4). `BLOCKED` counts as non-pass: the suite is not green while cases are
blocked, which is exactly the "reproducer fails before the worker stages land,
passes after integration" state the integrator task expects.

## Running

```bash
bash tests/fidelity/run.sh            # standalone
lake test                             # via the `test` driver (runs unit tests + this suite)
```

Override the tool locations with `LEAN=…`, `TYPELEAN=…`, `NODE=…` (defaults:
`lean`, `.lake/build/bin/typelean`, `node`).

## Current status (M1 bring-up)

Until the **Lower** (`Typelean.Lower.lowerEnv`) and **Emit**
(`Typelean.Emit.emitModule` + `runtime/typelean_rt.ts`) stages are implemented,
`typelean` returns a `lower`-stage `CompileError` for every case, so all cases
report `BLOCKED: … typelean failed … lower: …`. That is the expected pre-worker
state; once those stages land (follow-up subtasks `typelean-lower-impl` /
`typelean-emit-impl`), the same corpus goes green with no harness changes.
