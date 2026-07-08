/-! # Proof-carrying demo: gcd divides both arguments (proven), program computes
gcd via Euclid and prints results.

`lean --run` → `4`. M1 category: proof-carrying demo (ROADMAP M1, DESIGN §4.2,
§12).

We compute gcd(12, 8) = 4 via Euclidean algorithm (unrolled, no recursion), then
prove via a theorem that the result divides both input arguments. The theorem is
computationally irrelevant — erased by typelean (§4.2) — but validates the
program's correctness.

Euclid's algorithm for gcd(12, 8):
  (12, 8) → (8, 12%8=4) → (4, 8%4=0) → 4
-/

/-- Compute gcd(12, 8) using unrolled Euclidean algorithm.

    Euclid: gcd(a, b) = gcd(b, a % b) until b = 0, then return a.

    Iteration:
      (12, 8)  → r₁ = 12 % 8  = 4
      (8, 4)   → r₂ = 8 % 4   = 0  → terminating → answer = 4
-/
def gcd12_8 : Nat :=
  let r1 := 12 % 8           -- 4
  let _ := 8 % r1            -- 0 (terminating — Euclid's condition b=0 reached)
  r1                         -- gcd = last non-zero remainder

/-- Theorem: gcd(12, 8) = 4, proved by direct computation.

    `native_decide` decides the equality for concrete `Nat` expressions.
    This is a genuine proof (no `sorry`). It type-checks in Lean and is erased
    by typelean — it carries a correctness guarantee, not runtime code. -/
theorem gcd12_8_eq_4 : gcd12_8 = 4 := by
  native_decide

/-- Theorem: gcd(12, 8) divides 12. That is, 4 ∣ 12.

    This proves that the computed GCD actually satisfies the defining property
    of a greatest common divisor: it divides the first argument.
    The proof uses `native_decide` for concreteness. -/
theorem gcd_divides_first : gcd12_8 ∣ 12 := by
  -- gcd12_8 = 4, so we need 4 ∣ 12
  have h : gcd12_8 = 4 := gcd12_8_eq_4
  rw [h]
  -- 4 ∣ 12 because 12 = 4 * 3
  refine ⟨3, ?_⟩
  native_decide

/-- Theorem: gcd(12, 8) divides 8. That is, 4 ∣ 8.

    This proves the second defining property of a GCD: the result divides
    the second argument as well. Together with `gcd_divides_first`, we have
    proven that the computed value is a common divisor of both inputs. -/
theorem gcd_divides_second : gcd12_8 ∣ 8 := by
  have h : gcd12_8 = 4 := gcd12_8_eq_4
  rw [h]
  -- 4 ∣ 8 because 8 = 4 * 2
  refine ⟨2, ?_⟩
  native_decide

/-- Print gcd(12, 8) = 4. The theorems above are erased at compile time but
    validate the result's correctness — proof-carrying code semantics. -/
def main : IO Unit := IO.println gcd12_8
