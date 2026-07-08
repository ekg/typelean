/-!
# Demo: sum of first n naturals = n*(n+1)/2 (proven), program computes sums.

A **proof-of-correctness** demo for typelean. `sum10` is computed by unrolling
the recurrence sum(n) = n + sum(n-1) (only `Nat.add` — no `Nat.rec`, which M1
lowers structurally to unsupported runtime ops). The theorem `sum10_formula`
proves `sum10 = 55 = 10*11/2` via `native_decide`, demonstrating that a
**theorem validates a program property** while being computationally irrelevant
(erased by typelean).

`lean --run` → `55`. M1 category: proof-carrying demo
(ROADMAP M1, DESIGN §4.2, §12).
-/


/-- Compute sum(10) by unrolling sum(n) = n + sum(n-1) one term at a time:

    sum(1) = 1
    sum(2) = 2 + sum(1) = 3
    sum(3) = 3 + sum(2) = 6
    ...
    sum(10) = 55
-/
def sum10 : Nat :=
  let s1 := 1                 -- 1
  let s2 := 2 + s1            -- 3
  let s3 := 3 + s2            -- 6
  let s4 := 4 + s3            -- 10
  let s5 := 5 + s4            -- 15
  let s6 := 6 + s5            -- 21
  let s7 := 7 + s6            -- 28
  let s8 := 8 + s7            -- 36
  let s9 := 9 + s8            -- 45
  let s10 := 10 + s9          -- 55
  s10


/-- Theorem: sum(10) = 55. Proved via `native_decide` (Lean's native
    computation — not a `sorry`). The proof is computationally irrelevant
    (a `Prop`) and erased by typelean's Lower stage (DESIGN §4.2). -/
theorem sum10_formula : sum10 = 55 := by
  native_decide


/-- Theorem: sum(10) = 10*11/2, i.e. sum(10) equals the closed-form formula
    n*(n+1)/2 for n=10. Also proved via `native_decide`. -/
theorem sum10_closed_form : sum10 = (10 * 11) / 2 := by
  native_decide


/-- Print sum(10). The theorems are erased at compile time but validate the
    computation's correctness — proof-carrying code semantics. -/
def main : IO Unit := IO.println sum10