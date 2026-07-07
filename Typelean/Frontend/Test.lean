import Lean
import Typelean.Basic
import Typelean.Frontend

/-! # Typelean.Frontend.Test

IO test driver for `Typelean.Frontend.elaborateSource`. Exercises the three
acceptance criteria from the `typelean-frontend` task:

1. a clean `def` elaborates to `.ok env` with the constant present in
   `env.constants`;
2. a syntax error yields `.error` with `stage = "frontend"` and a non-empty
   `msg`;
3. a source beginning `import Init` elaborates to `.ok` (search path
   initialized — no missing-module error);
4. a source importing a *missing* module yields `.error` with `stage =
   "frontend"` and a non-empty `msg` naming the module — this guards the
   `importMsgs` re-merge in `elaborateSource` (without it, the import error is
   dropped by `IO.processCommands` and a misleading downstream
   "unknown constant" error is reported instead).

The driver is a plain `IO` action (`run : IO UInt32`, exit `0` on success,
`1` on failure). Because `elaborateSource` drives Lean's frontend
(`Lean.importModules (loadExts := true)`, which runs the IR interpreter over
imported initializers), the test **must** run inside a native `lean_exe` that
declares `supportInterpreter := true` in its `lakefile.lean` — running it via
`lean --run` is not viable: it triggers an IR-interpreter assertion violation
(`ir_interpreter.cpp`: “'unreachable' code was reached”) when `elaborateSource`
re-imports modules with `loadExts := true` inside a process that has already
imported them. Concretely, a consuming test exe is:

```lean
-- Main.lean
import Typelean.Frontend.Test
def main : IO UInt32 := Typelean.Frontend.Test.run
```
```lean
-- lakefile.lean (excerpt)
lean_exe "frontendtest" where
  root := `Main
  supportInterpreter := true   -- required by Typelean.Frontend.elaborateSource
```

Then `lake build && .lake/build/bin/frontendtest`. The integrator
(`typelean-integrate-m1`) wires this into `lake test`. It does not depend on
any test framework.
-/

namespace Typelean.Frontend.Test
open Typelean

/-- Mutable test counters. -/
structure TestState where
  passed : Nat := 0
  failed : Nat := 0

/-- Record a named assertion, printing PASS/FAIL and updating counters. -/
def check (st : IO.Ref TestState) (name : String) (cond : Bool) : IO Unit := do
  if cond then
    IO.println s!"PASS: {name}"
    st.modify fun s => { s with passed := s.passed + 1 }
  else
    IO.eprintln s!"FAIL: {name}"
    st.modify fun s => { s with failed := s.failed + 1 }

/-- Run all frontend tests; returns a process exit code (`0` = all pass). -/
def run : IO UInt32 := do
  let st ← IO.mkRef ({} : TestState)

  -- 1. A clean `def` elaborates and the constant is present in the env.
  match ← Frontend.elaborateSource "def x := 2\n" with
  | .ok env =>
    check st "clean def elaborates to .ok" true
    check st "constant `x present in env.constants" (env.contains `x)
  | .error e =>
    check st "clean def elaborates to .ok" false
    IO.eprintln s!"  (unexpected error — {e.stage}: {e.msg})"

  -- 2. A syntax error yields `.error` with stage "frontend" and a non-empty msg.
  match ← Frontend.elaborateSource "def bad := )(" with
  | .error e =>
    check st "syntax error yields .error" true
    check st "error.stage = \"frontend\"" (e.stage == "frontend")
    check st "error.msg non-empty" (!e.msg.isEmpty)
    IO.eprintln s!"  (reported: {e.msg})"
  | .ok _ =>
    check st "syntax error yields .error" false

  -- 3. A source beginning `import Init` elaborates to `.ok` (search path works).
  match ← Frontend.elaborateSource "import Init\n\ndef y := 1 + 1\n" with
  | .ok env =>
    check st "import Init elaborates to .ok" true
    check st "constant `y present after import Init" (env.contains `y)
  | .error e =>
    check st "import Init elaborates to .ok" false
    IO.eprintln s!"  (unexpected error — {e.stage}: {e.msg})"

  -- 4. A *missing* module yields `.error` with stage "frontend" and a message
  --    naming the module. Guards the `importMsgs` re-merge: without it the import
  --    error is dropped by `IO.processCommands` and a misleading downstream
  --    "unknown constant" error is reported instead.
  match ← Frontend.elaborateSource "import Definitely.Not.A.Module\n\ndef z := 1\n" with
  | .error e =>
    check st "missing module yields .error" true
    check st "missing-module error.stage = \"frontend\"" (e.stage == "frontend")
    check st "missing-module error.msg non-empty" (!e.msg.isEmpty)
    check st "missing-module error.msg mentions the module" (e.msg.contains "Definitely")
    IO.eprintln s!"  (reported: {e.msg})"
  | .ok _ =>
    check st "missing module yields .error" false

  let s ← st.get
  IO.println s!"\nSummary: {s.passed} passed, {s.failed} failed"
  return if s.failed == 0 then 0 else 1

end Typelean.Frontend.Test
