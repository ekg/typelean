import Lean
import Typelean.Basic

/-! # Typelean.Frontend

Pipeline **stage 1**: load Lean 4 source text and run it through Lean's own
frontend (parser + elaborator) to obtain a fully type-checked
`Lean.Environment`. Reusing `Lean.Elab` is the core of typelean's
compatibility strategy — we never re-implement elaboration.

Implementation route (for the `typelean-frontend` subtask):
* `Lean.Elab.runFrontend` / `Lean.Elab.IO.processCommands` drive the elaborator
  over a parsed command stream;
* `Lean.Parser.parseHeader` + `Lean.importModules` set up the environment;
* the resulting `Environment` exposes every elaborated `ConstantInfo`.

> **SKELETON.** The `typelean-frontend` subtask owns this file. Keep the
> public signature of `elaborateSource` stable; the integrator depends on it.
-/

namespace Typelean.Frontend
open Lean Elab

/-- Elaborate Lean 4 source text into a checked `Environment`.

    `fileName` is used for diagnostics. Returns the elaborated environment or a
    `CompileError` carrying the first elaboration failure.

    TODO(typelean-frontend): drive the real elaborator via `runFrontend`. -/
def elaborateSource (_source : String) (_fileName : String := "<input>") :
    IO (Except Typelean.CompileError Environment) := do
  return .error (.at "frontend" "Typelean.Frontend.elaborateSource: not yet implemented")

end Typelean.Frontend
