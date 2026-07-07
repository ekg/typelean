/-! # Fidelity case: a recursive `Nat` function.

`lean --run` → `120`. M1 category: a recursive `Nat` function
(ROADMAP M1, DESIGN §12). -/
def fact : Nat → Nat
  | 0     => 1
  | n + 1 => (n + 1) * fact n

def main : IO Unit := IO.println (fact 5)
