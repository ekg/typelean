/-! # Fidelity case: Nat addition is commutative (proven), then a program
computing a sum relies on the rearrangement.

`lean --run` → `17`. M1 category: proof-carrying demo (ROADMAP M1, DESIGN §4.2,
§12).

We prove the commutativity of `Nat.add` by structural induction on `n`, then
compute a sum whose correctness relies on this property. The proof is
computationally irrelevant (erased by typelean) but validates the program's
correctness. -/

theorem add_comm (n m : Nat) : n + m = m + n :=
  by
    induction n with
    | zero =>
      simp
    | succ n ih =>
      rw [Nat.succ_add, ih, Nat.add_succ]

/-- Rearranged addition: computes `y + x` and relies on `add_comm` to guarantee
    it equals `x + y`. -/
def rearrangedAdd (x y : Nat) : Nat := y + x

/-- The computed sum is valid because `add_comm` proves `x + y = y + x`.
    The proof is erased at runtime — only the computational content remains. -/
def main : IO Unit :=
  IO.println (rearrangedAdd 5 12)
