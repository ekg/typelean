/-! # Fidelity case: a user inductive + `match`.

`lean --run` → `1`. M1 category: a user inductive + `match`
(ROADMAP M1, DESIGN §12). -/
inductive Color where
  | red
  | green
  | blue

def toNum : Color → Nat
  | .red   => 0
  | .green => 1
  | .blue  => 2

def main : IO Unit := IO.println (toNum Color.green)
