/-! # Fidelity case: a^m * a^n = a^(m+n) for Nat (proven), program exercises exponentiation.

`lean --run` → `15625`. M1 category: recursive def + theorem + IO
(ROADMAP M1, DESIGN §12). -/

/-- Exponentiation: `a ^ n` as a `Nat`. -/
def pow (a : Nat) : Nat → Nat
  | 0     => 1
  | n + 1 => pow a n * a

/-- Theorem: a^m * a^n = a^(m+n) for natural numbers `a`, `m`, `n`.
    The proof is by induction on `m` and uses `Nat.mul_assoc`, `Nat.mul_comm`,
    `Nat.succ_eq_add_one`, and `add_assoc`. -/
theorem pow_mul_add (a m n : Nat) : pow a m * pow a n = pow a (m + n) := by
  induction m with
  | zero =>
    simp [pow]
  | succ m ih =>
    calc
      pow a (Nat.succ m) * pow a n = (pow a m * a) * pow a n := rfl
      _ = pow a m * (a * pow a n) := by rw [Nat.mul_assoc]
      _ = pow a m * (pow a n * a) := by rw [Nat.mul_comm a (pow a n)]
      _ = (pow a m * pow a n) * a := by rw [← Nat.mul_assoc]
      _ = pow a (m + n) * a := by rw [ih]
      _ = pow a ((m + n) + 1) := rfl
      _ = pow a (Nat.succ m + n) := by
        have h : ((m + n) + 1) = (Nat.succ m + n) := by omega
        rw [h]

/-- Exercise exponentiation: prints `pow 5 6` = 15625. This is a concrete
    instance of `pow_mul_add` with `m = n = 3`. -/
def main : IO Unit :=
  IO.println (pow 5 6)