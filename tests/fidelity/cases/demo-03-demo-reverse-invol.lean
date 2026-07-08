/-! # Fidelity case: reverse (reverse l) = l (proven), program exercises double-reverse.

`lean --run` → `1`. M1 category: proof-carrying demo (ROADMAP M1, DESIGN §4.2).

A proof-of-correctness demo for typelean. The theorem is computationally
irrelevant (erased by typelean) but validates the function's correctness.

We use a fixed-length (3-element) list encoded as nested pairs.
`reverse` swaps the outer elements so the middle element stays in place.
For three elements `(a, (b, c))`, reverse is `(c, (b, a))`.
Double-reverse yields the original: `reverse (reverse (a, (b, c))) = (a, (b, c))`.

We prove `reverse_invol` — reverse is an involution — by `rfl`
(symbolic evaluation, no induction needed for this concrete encoding).

The theorem is erased by typelean (compilation erases Prop-valued declarations
and type arguments), and the guarantee (involution) carries into the emitted
TypeScript.
-/

/-- A fixed-length list of exactly three naturals, encoded as nested pairs. -/
def ThreeList (a b c : Nat) : Nat × Nat × Nat :=
  (a, (b, c))

/-- Reverse: swap the first and third elements. -/
def reverse (t : Nat × Nat × Nat) : Nat × Nat × Nat :=
  (t.2.2, (t.2.1, t.1))

/-- Theorem: reverse is an involution (applying it twice yields the original).

    reverse (reverse (a, b, c)) = (a, b, c)

    Proved by destructuring the nested pair and evaluating: for `(a,(b,c))`,
    `reverse` swaps outer elements, and double-reverse restores them.
    -/
theorem reverse_invol (t : Nat × Nat × Nat) : reverse (reverse t) = t := by
  cases t with
  | mk a bc =>
    cases bc with
    | mk b c =>
      rfl

/-- Extract the first element after reverse∘reverse (confirming identity). -/
def main : IO Unit :=
  IO.println ((reverse (reverse (1, (2, 3)))).1)
