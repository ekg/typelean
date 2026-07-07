/- Root of the `Typelean` library — the typelean Lean 4 → TypeScript compiler.

Pipeline modules, in dependency order:
* `Typelean.Basic`    — shared types (`CompileError`, `CompileM`).
* `Typelean.IR`       — the intermediate representation.
* `Typelean.Frontend` — Lean source → elaborated `Environment` (via `Lean.Elab`).
* `Typelean.Lower`    — `Lean.Expr` → `Typelean.IR`.
* `Typelean.Emit`     — `Typelean.IR` → TypeScript text.
* `Typelean.Pipeline` — end-to-end driver.
-/
import Typelean.Basic
import Typelean.IR
import Typelean.Frontend
import Typelean.Lower
import Typelean.Emit
import Typelean.Pipeline
