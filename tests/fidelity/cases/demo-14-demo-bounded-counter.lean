/-!
# Proof-carrying demo: a counter staying within [0, max] bounds (proven invariant)

`lean --run` → `5`. M1 category: proof-carrying demo (ROADMAP M1, DESIGN §4.2, §12).

We define a function `boundedInc` that increments a counter up to a given maximum
bound. A theorem proves that the result never exceeds the maximum. The theorem is
computationally irrelevant — erased by typelean (§4.2) — but validates the
function's correctness at the specification level.

The program runs 10 increments starting from 0 with max=5. The counter saturates
at 5 and stays there.
-/

/-- Increment `c` by `inc` but never exceed `max`. Uses only `Nat.sub` which maps
    to the runtime `natSub` primitive (DESIGN §9). The increment `inc` is a
    parameter (not a literal) so `reduce` does not unfold `Nat.sub` into
    constructor-based recursion — preserving the `_rt.natSub` mapping.

    The identity: `max - (max - c - inc)` equals `c + inc` when `c + inc ≤ max`,
    and `max` otherwise, because `Nat` subtraction saturates at zero. -/
def boundedInc (c max inc : Nat) : Nat := max - (max - c - inc)

/-- Theorem: the bounded increment never exceeds the upper bound.

    Since `a - b ≤ a` for any `Nat` a, b, we have
    `max - (max - c - inc) ≤ max`.
    This is a genuine proof (no `sorry`). It type-checks in Lean and is erased
    by typelean — it carries a correctness guarantee, not runtime code. -/
theorem boundedInc_le_max (c max inc : Nat) : boundedInc c max inc ≤ max := by
  unfold boundedInc
  exact Nat.sub_le max (max - c - inc)

/-- Run 10 increments starting from 0 with max=5, report the final value.
    The counter saturates at 5 and stays there, as the theorem guarantees. -/
def main : IO Unit :=
  let c0 := 0
  let max := 5
  let inc := 1
  let c1 := boundedInc c0 max inc
  let c2 := boundedInc c1 max inc
  let c3 := boundedInc c2 max inc
  let c4 := boundedInc c3 max inc
  let c5 := boundedInc c4 max inc
  let c6 := boundedInc c5 max inc
  let c7 := boundedInc c6 max inc
  let c8 := boundedInc c7 max inc
  let c9 := boundedInc c8 max inc
  let c10 := boundedInc c9 max inc
  IO.println c10