import Typelean.Lower

/-! # Typelean.Lower.Test — unit tests for the lowering helpers

This module exercises the *pure* (non-`partial`, non-`Meta`) helpers of
`Typelean.Lower` with compile-time `#guard`s, so a drift in name hygiene or the
binder-stack lookup is caught at elaboration time. The lowering *logic* itself
(`lowerGo`/`lowerEnvM`, `constsIn`, `topoOrder`, `reachesSelf`) is `partial` and
`Meta`-effectful and so cannot be reduced by the kernel at compile time; it is
exercised end-to-end by the fidelity suite (`tests/fidelity/run.sh`), where each
case now passes the `lower` stage (no `lower`-stage `CompileError`) and proceeds
to the (stubbed) `emit` stage.

Run directly:

    lake env lean Typelean/Lower/Test.lean
-/

open Typelean.Lower Lean

/-! ## Name hygiene (`binderBase`, `varName`) -/

-- `binderBase` extracts the last `Name.str` component.
#guard binderBase (.str .anonymous "x") == "x"
#guard binderBase (.str (.str .anonymous "A") "y") == "y"
-- Non-`.str` names fall back to `"x"`.
#guard binderBase .anonymous == "x"
#guard binderBase (.num .anonymous 5) == "x"

-- `varName` suffixes the base by the binding depth for hygienic uniqueness.
#guard varName 0 (.str .anonymous "n") == "n_0"
#guard varName 2 (.str .anonymous "x") == "x_2"
#guard varName 0 .anonymous == "x_0"
-- Shadowing (`fun x => fun x => x`) yields distinct IR names.
#guard varName 0 (.str .anonymous "x") != varName 1 (.str .anonymous "x")

/-! ## Binder-stack lookup (`Ctx.lookup`) -/

def fidA : FVarId := { name := `a }
def fidB : FVarId := { name := `b }
def fidC : FVarId := { name := `c }
-- Innermost binder first.
def ctx0 : Ctx := [(fidA, "a_0", false), (fidB, "b_1", true)]

#guard Ctx.lookup ctx0 fidA == some ("a_0", false)
#guard Ctx.lookup ctx0 fidB == some ("b_1", true)   -- erased flag preserved
#guard Ctx.lookup ctx0 fidC == none                 -- unknown free variable
#guard Ctx.lookup [] fidA == none                   -- empty context
