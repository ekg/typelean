import Lake
open Lake DSL

package "typelean" where
  version := v!"0.1.0"

lean_lib «Typelean» where
  -- add library configuration options here

@[default_target]
lean_exe "typelean" where
  root := `Main
  -- REQUIRED by `Typelean.Frontend.elaborateSource`: it calls
  -- `Lean.importModules (loadExts := true)`, which runs imported modules'
  -- `initialize` blocks via Lean's IR interpreter. Without the interpreter
  -- linked into the exe, even a bare `def x := 2` (which auto-imports `Init`)
  -- fails at the frontend stage with "Could not find native implementation of
  -- external declaration 'IO.getRandomBytes' …". The `typelean` CLI therefore
  -- cannot compile anything without this flag — it is a one-line,
  -- correctness-required edit delegated by `typelean-frontend` and needed for
  -- the M1 validation ("`typelean examples/hello.lean` emits TS"). See
  -- `Typelean/Frontend.lean` for the full note.
  supportInterpreter := true

/-- The `lake test` driver (ROADMAP M1). Roots at `Typelean.Test`, which runs
    the per-stage unit tests (`Typelean.Frontend.Test.run`; the IR `#guard`s
    run at build time via `import Typelean.IR.Test`) and the end-to-end
    fidelity suite (`tests/fidelity/run.sh`, DESIGN §12). Like the `typelean`
    CLI it must set `supportInterpreter := true` because it runs
    `elaborateSource` (Frontend tests) and, transitively, the full pipeline. -/
@[test_driver]
lean_exe "test" where
  root := `Typelean.Test
  supportInterpreter := true
