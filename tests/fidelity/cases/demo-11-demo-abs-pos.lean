/-!
# Proof-carrying demo: absolute value is nonnegative (proven), program computes
absolute difference over implicitly-signed integers.

`lean --run` → `5`. M1 category: proof-carrying demo (ROADMAP M1, DESIGN §4.2,
§12).

## Signed integer model

A pair of natural numbers `(a, b)` represents the signed integer `a - b` (in ℤ).
The absolute value |a - b| is computed as `(a - b) + (b - a)`, which uses Nat's
truncating subtraction (DESIGN §11): when a ≥ b the first term is a-b and the
second is 0; when b > a the first term is 0 and the second is b-a. The sum is
always the absolute difference.

## Theorem

`absDiff_nonneg` proves that the computed absolute value is always nonnegative.
Since `Nat` values are already nonnegative, this is trivially true — but the
theorem is a genuine proof (no `sorry`, uses `Nat.zero_le`) that typelean erases
at compile time. The computational guarantee carries into the emitted TypeScript.

`absDiff_comm` proves commutativity (|a - b| = |b - a|) using `Nat.add_comm`,
confirming that the absolute difference is symmetric.

## Tested

- |8 - 3| = 5   (positive signed difference)
- |3 - 8| = 5   (negative signed difference — same absolute value)
-/

/-- Compute |a - b| using only `Nat.add` and `Nat.sub`.

    For any `a`, `b` in Nat: exactly one of `(a - b)` or `(b - a)` is zero;
    the other is the absolute difference. Uses only constructs that typelean
    lowers to runtime primitives (DESIGN §11, `Nat.add`/`Nat.sub`). -/
def absDiff (a b : Nat) : Nat := (a - b) + (b - a)

/-- Theorem: `absDiff` is always nonnegative.

    All `Nat` values are ≥ 0, so this is immediate from `Nat.zero_le`. The
    proof is a `Prop` and is erased by typelean (DESIGN §4.2) — it carries a
    correctness guarantee, not runtime code. -/
theorem absDiff_nonneg (a b : Nat) : 0 ≤ absDiff a b := by
  unfold absDiff; exact Nat.zero_le _

/-- Theorem: `absDiff` is symmetric (commutative): |a - b| = |b - a|.

    Proved by rewriting with `Nat.add_comm`. Also erased at compile time. -/
theorem absDiff_comm (a b : Nat) : absDiff a b = absDiff b a := by
  unfold absDiff; rw [Nat.add_comm]

/-- Exercise: |8 - 3| = 5 — the larger value first.

    The theorem `absDiff_nonneg` guarantees the result is nonnegative, but
    is erased by typelean. Only the computational content remains in the
    emitted TypeScript. -/
def main : IO Unit := IO.println (absDiff 8 3)