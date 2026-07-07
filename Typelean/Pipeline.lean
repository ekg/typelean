import Typelean.Basic
import Typelean.Frontend
import Typelean.Lower
import Typelean.Emit

/-! # Typelean.Pipeline

End-to-end driver wiring the three stages:

```
Lean source ──Frontend──▶ Environment ──Lower──▶ IR ──Emit──▶ TypeScript
```

> **SKELETON.** The `typelean-integrate-m1` subtask owns this file and replaces
> the stub body with the real wiring: elaborate the source, choose the root
> declarations, lower them to IR, and emit a TS module. It also adds an
> end-to-end fidelity test (compile a trivial Lean program, run the emitted TS
> under Node, compare against Lean `#eval`).
-/

namespace Typelean.Pipeline
open Typelean

/-- Compile Lean 4 source text to a TypeScript module string. -/
def compile (_source : String) (_fileName : String := "<input>") :
    IO (Except CompileError String) := do
  return .error (.at "pipeline"
    "Typelean.Pipeline.compile: stages not yet wired (see typelean-integrate-m1)")

end Typelean.Pipeline
