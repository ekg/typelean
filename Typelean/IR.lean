/-! # Typelean.IR

The typelean **intermediate representation**: an untyped, computational
lambda calculus that sits between Lean's elaborated `Lean.Expr` and the emitted
TypeScript. Types and proofs are erased here; what remains is the runtime
computational content (à la Lean's own `Lean.Compiler.LCNF`).

> **SKELETON.** The `typelean-ir` subtask owns this file and is expected to
> expand it (precise literals, projections, recursor/`casesOn` dispatch,
> join points, erased-argument handling, etc.). Keep the public type names
> (`Expr`, `Decl`, `Module`) stable so downstream stages keep building.
-/

namespace Typelean.IR

/-- IR expressions: untyped core terms produced by lowering and consumed by emit. -/
inductive Expr where
  /-- Local variable, referenced by name (lowering chooses a naming scheme). -/
  | var (name : String)
  /-- Lambda abstraction over a single parameter. -/
  | lam (param : String) (body : Expr)
  /-- Application of a function to a single argument (curried). -/
  | app (fn arg : Expr)
  /-- `let name := value; body`. -/
  | letE (name : String) (value body : Expr)
  /-- Saturated constructor application: constructor `name` with numeric `tag`. -/
  | ctor (name : String) (tag : Nat) (args : List Expr)
  /-- Literal value (nat / string / …); refined by the IR subtask. -/
  | lit (raw : String)
  /-- Reference to a top-level declaration. -/
  | const (name : String)
  deriving Repr, Inhabited

/-- A top-level IR declaration: `name params* := body`. -/
structure Decl where
  name : String
  params : List String := []
  body : Expr
  deriving Repr, Inhabited

/-- A whole IR module: an ordered list of declarations (topologically ordered). -/
structure Module where
  decls : List Decl := []
  deriving Repr, Inhabited

end Typelean.IR
