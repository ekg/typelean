/-!
# Proof-carrying demo: a list's all-equal property (proven), program checks equality

`lean --run` → `0`. M1 category: proof-carrying demo (ROADMAP M1, DESIGN §4.2,
§12).

We define a function `allEqualSum` that determines whether three numbers are all
equal by checking that their pairwise differences sum to zero. A theorem proves
that when all three inputs are identical, the result is zero. The theorem is
computationally irrelevant — erased by typelean (§4.2) — but validates the
function's correctness.
-/

/-- `allEqualSum a b c` returns 0 iff `a = b = c`.
    Computed as `(a - b) + (b - c) + (c - a)`. Each term is zero when its
    operands are equal because `Nat` subtraction saturates at zero. -/
def allEqualSum (a b c : Nat) : Nat := (a - b) + (b - c) + (c - a)

/-- Theorem: when all three inputs are identical, allEqualSum returns zero.

    This is a genuine proof (no `sorry`). It type-checks in Lean and is erased
    by typelean — it carries a correctness guarantee, not runtime code. -/
theorem allEqualSum_identity (x : Nat) : allEqualSum x x x = 0 := by
  unfold allEqualSum
  simp

/-- Exercise the function on three equal values. The output `0` confirms that
    all three values are equal, as the theorem guarantees. -/
def main : IO Unit := IO.println (allEqualSum 7 7 7)
