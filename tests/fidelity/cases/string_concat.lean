/-! # Fidelity case: string concatenation.

`lean --run` → `hello, typelean!`. M1 category: string concat
(ROADMAP M1, DESIGN §12). -/
def main : IO Unit := IO.println ("hello, " ++ "typelean!")
