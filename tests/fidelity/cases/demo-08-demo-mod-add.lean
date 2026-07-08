/-! # Demo: (a + b) mod n properties (proven), program computes modular sums.

`lean --run` → `1`. Proof-carrying code demo (M1).

Contains a `theorem` proving commutativity of modular addition — the proof is
computationally irrelevant, erased by typelean, but validates correctness.

Category: demo (proof-carrying), (ROADMAP M1, DESIGN §4.2, §12). -/

/-- Compute `(a + b) % n` — modular addition. -/
def modAdd (a b n : Nat) : Nat := (a + b) % n

/-- Modular addition is commutative: `(a + b) % n = (b + a) % n`.

This theorem is genuine (no `sorry`). It type-checks in Lean and is erased by
typelean — it carries a guarantee, not runtime code. -/
theorem modAdd_comm (a b n : Nat) : modAdd a b n = modAdd b a n := by
  unfold modAdd
  rw [Nat.add_comm a b]

def main : IO Unit := IO.println (modAdd 10 3 6)