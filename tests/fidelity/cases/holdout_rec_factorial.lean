/-! # Fidelity HOLDOUT case: recursive Nat function (unseen by impl agents).

`lean --run` → 720. A recursive `Nat` function NOT in the visible corpus —
prevents a compiler special-casing the known `fact`/`reverse` cases from
clearing the parity gate without genuine recursor lowering. -/
def countdown : Nat → Nat → Nat
  | 0, acc => acc
  | n + 1, acc => countdown n (acc * (n + 1))

def main : IO Unit := IO.println (countdown 6 1)
