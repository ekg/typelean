/-! # Fidelity case: `let` + λ (curried application).

`lean --run` → `42`. M1 category: `let`/`λ` (ROADMAP M1, DESIGN §12). -/
def main : IO Unit :=
  IO.println (let f : Nat → Nat := fun x => x + 1; f 41)
