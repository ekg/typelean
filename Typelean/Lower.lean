import Lean
import Typelean.IR
import Typelean.Basic

/-! # Typelean.Lower

Pipeline **stage 2**: lower Lean's elaborated core terms (`Lean.Expr`, read out
of the `Environment`'s `ConstantInfo`s) into typelean `IR`. This is where type
information is *erased* and the runtime computational content is extracted.

Concerns for the `typelean-lower` subtask:
* de Bruijn `bvar`/`fvar` → IR variable names;
* `lam`/`app`/`letE` → IR equivalents; erase type-class/Prop arguments;
* `const` references, constructor applications, projections;
* recursors / `casesOn` / matcher auxiliaries → IR pattern dispatch;
* literals (`Nat`, `String`) → IR literals.

> **SKELETON.** The `typelean-lower` subtask owns this file. Depends on the IR
> shape defined by `typelean-ir`.
-/

namespace Typelean.Lower
open Lean

/-- Lower a single Lean `Expr` to an IR expression.
    TODO(typelean-lower): structural recursion over `Expr` with erasure. -/
def lowerExpr (_e : Expr) : Typelean.CompileM Typelean.IR.Expr :=
  .error (.at "lower" "Typelean.Lower.lowerExpr: not yet implemented")

/-- Lower selected `roots` (plus their dependencies) from `env` to an IR module.
    TODO(typelean-lower): walk `env.constants`, erase types, topo-order decls. -/
def lowerEnv (_env : Environment) (_roots : List Name) :
    Typelean.CompileM Typelean.IR.Module :=
  .error (.at "lower" "Typelean.Lower.lowerEnv: not yet implemented")

end Typelean.Lower
