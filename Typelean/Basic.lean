/-! # Typelean.Basic

Common definitions shared across the typelean compiler pipeline
(Lean 4 source → elaborated `Environment` → IR → TypeScript).
-/

namespace Typelean

/-- Compiler version string. -/
def version : String := "0.1.0"

/-- A compilation error with a human-readable message and optional stage tag. -/
structure CompileError where
  /-- Pipeline stage that produced the error (`frontend`, `lower`, `emit`, …). -/
  stage : String := "typelean"
  /-- Human-readable message. -/
  msg : String
  deriving Repr, Inhabited

/-- Convenience: build a stage-tagged error. -/
def CompileError.at (stage msg : String) : CompileError := { stage, msg }

/-- Result of a pure pipeline stage. -/
abbrev CompileM (α : Type) := Except CompileError α

end Typelean
