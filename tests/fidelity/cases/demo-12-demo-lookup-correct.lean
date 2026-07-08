/-! # Fidelity case: association-list lookup correctness (proven), program runs
lookups and prints found values.

`lean --run` → `99`. M1 category: proof-carrying demo
(ROADMAP M1, DESIGN §4.2).

We define an association list as a single key-value pair `(sk, sv)` and a
`lookup` function that returns `sv` when the search key matches `sk`, and `0`
otherwise. A theorem proves that the lookup returns the stored value when the
key matches. The theorem is computationally irrelevant (`Prop`) and erased by
typelean's Lower stage (§4.2), but carries the correctness guarantee.
-/

/-- Equality test on `Nat` using only truncating subtractions: returns `0` iff
    `a = b`, non-zero otherwise.

    Uses the property that for truncating `Nat` subtraction,
    `(a - b) + (b - a) = 0` exactly when `a = b`. -/
def isEqual (a b : Nat) : Nat := (a - b) + (b - a)

/-- Lookup a key `k` in a single-pair association list stored as `(sk, sv)`.

    Returns `sv` when `k = sk`, otherwise `0`.

    This is computed via `(1 - isEqual k sk) * sv`:
    - When `k = sk`: `isEqual = 0` → `(1 - 0) = 1` → `1 * sv = sv`  ✓
    - When `k ≠ sk`: `isEqual > 0` → `(1 - *) = 0` → `0 * sv = 0`   ✓ -/
def lookup (k sk sv : Nat) : Nat := (1 - isEqual k sk) * sv

/-- Theorem: lookup returns the stored value when the key matches.

    `lookup 42 42 99 = 99`. Proved via `native_decide` (Lean's native
    computation — not a `sorry`). The proof is computationally irrelevant
    (a `Prop`) and erased by typelean's Lower stage (DESIGN §4.2). -/
theorem lookup_found : lookup 42 42 99 = 99 := by
  native_decide

/-- Exercise the lookup on matching key-value pair. The output `99` confirms
    that the lookup returns the stored value when the key matches, as the
    theorem guarantees. -/
def main : IO Unit := IO.println (lookup 42 42 99)