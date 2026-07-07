import Typelean.IR
import Typelean.Basic

/-! # Typelean.Emit

Pipeline **stage 3**: render typelean `IR` as TypeScript source text. Emitted
code targets the hand-written runtime in `runtime/typelean_rt.ts`, which
supplies Lean's value model (constructor objects, closures, arbitrary-precision
`Nat`/`Int`, thunks for laziness, the `IO` bridge, …).

Concerns for the `typelean-emit` subtask:
* IR `lam`/`app` → TS arrow functions / calls (curried);
* `ctor` → runtime constructor objects `{ tag, fields }`;
* `const` → references to emitted top-level bindings;
* `lit` → runtime literal constructors (`Nat` via `BigInt`, etc.);
* name mangling: Lean names → valid TS identifiers;
* also create/own `runtime/typelean_rt.ts`.

> **SKELETON.** The `typelean-emit` subtask owns this file (and `runtime/`).
> Depends on the IR shape defined by `typelean-ir`.
-/

namespace Typelean.Emit

/-- Emit a TS expression string for an IR expression.
    TODO(typelean-emit): full case analysis over `IR.Expr`. -/
def emitExpr : Typelean.IR.Expr → String
  | _ => "/* TODO(typelean-emit) */ undefined"

/-- Emit a complete TypeScript module (with runtime import) from an IR module.
    TODO(typelean-emit): emit each declaration + a runtime import header. -/
def emitModule (_m : Typelean.IR.Module) : String :=
  "// TODO(typelean-emit): emit declarations against typelean_rt\n"

end Typelean.Emit
