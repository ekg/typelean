import Typelean.Basic
import Typelean.Frontend
import Typelean.Lower
import Typelean.Emit
import Lean

/-! # Typelean.Pipeline

End-to-end driver wiring the three stages:

```
Lean source ──Frontend──▶ Environment ──Lower──▶ IR ──Emit──▶ TypeScript
```

`compile` elaborates the source with `Typelean.Frontend.elaborateSource` (Lean's
own `Lean.Elab`), chooses the root declarations (default: `main`, or every
top-level user `def` when there is no `main`), lowers them and their reachable
dependencies to `Typelean.IR` via `Typelean.Lower.lowerEnv`, and emits a
TypeScript module via `Typelean.Emit.emitModule`. Any stage failure is returned
as a stage-tagged `Typelean.CompileError` (no silent drops — DESIGN §1.4).

> The `typelean-integrate-m1` subtask owns this file and the end-to-end wiring. -/

namespace Typelean.Pipeline
open Typelean

/-- Is `n` a top-level user `def`n declared in the *input* module (not imported
    from the Lean/`Init`/`Std` environment)?

    We discriminate via `Lean.Environment.isImportedConst`: a constant is from
    the current (main) module iff it is not in any imported module's constant
    table. Restricting to atomic names (no module/namespace prefix) selects the
    user's own top-level definitions and excludes the equation-compiler's
    auto-generated auxiliaries (`Color.casesOn`, `fact._unreachable._eqdef_1`,
    `_private.…`, …), which are reached transitively from the real roots by
    `Lower.lowerEnv`. -/
def isUserTopDefn (env : Lean.Environment) (n : Lean.Name) : Bool :=
  match env.find? n with
  | some (.defnInfo _) => (¬ env.isImportedConst n) && n.isAtomic
  | _ => false

/-- Choose the root declarations to compile from an elaborated environment
    (DESIGN §2; M1 closed-world).

    * If the program defines `main`, compile from `main` — `Lower.lowerEnv`
      walks `main`'s reachable dependencies (helpers, constructors, recursors).
    * Otherwise compile every top-level user `def`n in the input module. -/
def chooseRoots (env : Lean.Environment) : List Lean.Name :=
  if env.contains `main then [`main]
  else env.constants.toList.filterMap fun (n, _) => if isUserTopDefn env n then some n else none

/-- Compile Lean 4 source text to a TypeScript module string.

    Wires `Frontend.elaborateSource` → `chooseRoots` → `Lower.lowerEnv` →
    `Emit.emitModule`. Returns the emitted TypeScript, or the first stage-tagged
    `CompileError` (`frontend` or `lower`). (`Emit.emitModule` is currently total;
    unhandled IR cases are tracked by the emit stage as follow-up subtasks —
    DESIGN §1.4.) -/
def compile (source : String) (fileName : String := "<input>") :
    IO (Except CompileError String) := do
  match ← Frontend.elaborateSource source fileName with
  | .error e => return .error e
  | .ok env =>
    let roots := chooseRoots env
    match Lower.lowerEnv env roots with
    | .error e => return .error e
    | .ok irModule =>
      return .ok (Emit.emitModule irModule)

end Typelean.Pipeline
