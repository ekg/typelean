import Typelean.Basic
import Typelean.IR.Test        -- compile-time IR `#guard`/`native_decide` checks
import Typelean.Frontend.Test  -- `Frontend.Test.run : IO UInt32`

/-! # Typelean.Test — `lake test` driver (ROADMAP M1)

The `@[test_driver]` `lean_exe "test"` (see `lakefile.lean`) roots here. `main`
runs the per-stage unit tests and the end-to-end fidelity suite, aggregating
their exit codes:

1. **IR unit tests** — `import Typelean.IR.Test` makes `lake build` / `lake test`
   elaborate that module, running its `#guard` / `native_decide` checks at
   build time. (`Typelean.IR.Test` is not imported by `Typelean.lean`, so
   `lake build` alone does not compile it; importing it here — per the
   `typelean-ir` hand-off — runs the IR unit tests in CI.)
2. **Frontend unit tests** — `Typelean.Frontend.Test.run` exercises
   `elaborateSource` (clean def, syntax error, `import Init`, missing module).
3. **Fidelity suite** — `tests/fidelity/run.sh` (DESIGN §12): for each
   `cases/*.lean`, capture `lean --run` output and the Node output of the
   emitted TypeScript and diff them. A `BLOCKED` (a stage-tagged `CompileError`
   from `typelean`) is reported with the stage + first error line, never
   silently dropped (DESIGN §1.4).

`supportInterpreter := true` (on this exe, set in `lakefile.lean`) is mandatory:
`Frontend.Test.run` calls `elaborateSource` → `Lean.importModules (loadExts :=
true)`, which runs the IR interpreter over imported initializers (see
`Typelean/Frontend.lean`). Running this driver via `lean --run` is not viable
(an IR-interpreter assertion violation); it must be a built `lean_exe`. -/

/-- Run the fidelity suite by shelling out to `tests/fidelity/run.sh`. The
    script inherits stdout/stderr so its per-case `PASS`/`FAIL`/`BLOCKED` lines
    and summary appear inline. -/
def runFidelity : IO UInt32 := do
  let child ← IO.Process.spawn
    { cmd := "bash", args := #["tests/fidelity/run.sh"]
      stdin := .inherit, stdout := .inherit, stderr := .inherit }
  child.wait

/-- `lake test` entry point: run unit tests + fidelity, aggregate exit codes.
    Exit `0` iff both the frontend unit tests and the fidelity suite pass. -/
def main : IO UInt32 := do
  IO.println "=== typelean test suite (M1) ==="
  IO.println "--- frontend unit tests ---"
  let fe ← Typelean.Frontend.Test.run
  IO.println ""
  IO.println "--- fidelity suite ---"
  let fid ← runFidelity
  IO.println ""
  let feOk := fe == 0
  let fidOk := fid == 0
  IO.println
    s!"SUMMARY: frontend={if feOk then "PASS" else "FAIL"}, fidelity={if fidOk then "PASS" else "FAIL"}"
  return if feOk && fidOk then 0 else 1
