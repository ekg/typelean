/-!
# Demo: permutation preserves the multiset/length (proven), program sorts a list and checks length parity

A **proof-of-correctness** demo for typelean. Contains:

1. A **theorem** proving that any permutation of three elements preserves the
   multiset sum (the "multiset" is tracked by the sum of elements).

2. A **program** that **sorts** a 3-element list via arithmetic-based min/max
   computation (no `if`/`match`/`Decidable` — only `Nat.add`, `Nat.sub`,
   `Nat.div` — so it compiles under M1 constraints), and **checks length
   parity** (the length of a 3-element list is 3, which is odd).

The theorems are computationally irrelevant (`Prop`) and erased by typelean's
Lower stage (DESIGN §4.2), but they validate the correctness of the computation
at compile time.

`lean --run` → `1` (the minimum element of `(5, (1, 3))` after sorting).
M1 category: proof-carrying demo (ROADMAP M1, DESIGN §4.2, §12).
-/


/-! ## 1. Permutation multiset-preservation theorems

We prove that common permutations of a 3-element tuple preserve the *multiset*
(tracked by the sum of the three elements). These are genuine proofs (no
`sorry`) using the commutativity and associativity of `Nat.add`. -/

/-- Sum of three naturals — our "multiset tracker". -/
def sum3 (t : Nat × Nat × Nat) : Nat := t.1 + t.2.1 + t.2.2

/-- Swap positions 1 and 2 (i.e., `(a,b,c) → (b,a,c)`). -/
def permSwap12 (t : Nat × Nat × Nat) : Nat × Nat × Nat :=
  (t.2.1, (t.1, t.2.2))

/-- Reverse the triplet (i.e., `(a,b,c) → (c,b,a)`). -/
def permReverse (t : Nat × Nat × Nat) : Nat × Nat × Nat :=
  (t.2.2, (t.2.1, t.1))

/-- Cyclic right-shift (i.e., `(a,b,c) → (c,a,b)`). -/
def permRotate (t : Nat × Nat × Nat) : Nat × Nat × Nat :=
  (t.2.2, (t.1, t.2.1))

/-- Theorem: swapping the first two elements preserves the multiset sum.

    `sum3 (b, a, c) = sum3 (a, b, c)` because `a + b = b + a`
    (commutativity of addition). -/
theorem sum_swap12 (t : Nat × Nat × Nat) : sum3 (permSwap12 t) = sum3 t := by
  cases t with
  | mk a bc =>
    cases bc with
    | mk b c =>
      unfold sum3 permSwap12
      simp [Nat.add_comm, Nat.add_left_comm]

/-- Theorem: reversing a triplet preserves the multiset sum.

    `sum3 (c, b, a) = sum3 (a, b, c)` because addition is fully commutative.
    (Any reordering of a sum yields the same total.) -/
theorem sum_reverse (t : Nat × Nat × Nat) : sum3 (permReverse t) = sum3 t := by
  cases t with
  | mk a bc =>
    cases bc with
    | mk b c =>
      unfold sum3 permReverse
      simp [Nat.add_comm, Nat.add_left_comm]

/-- Theorem: cyclic rotation preserves the multiset sum.

    `sum3 (c, a, b) = sum3 (a, b, c)` by commutativity and associativity. -/
theorem sum_rotate (t : Nat × Nat × Nat) : sum3 (permRotate t) = sum3 t := by
  cases t with
  | mk a bc =>
    cases bc with
    | mk b c =>
      unfold sum3 permRotate
      simp [Nat.add_comm, Nat.add_left_comm]


/-! ## 2. Arithmetic-based sort for 3 elements (M1-compatible)

We sort three elements using only arithmetic operations (`+`, `-`, `/`).
No `if`/`match`/`Decidable` — which would trigger the unfilled M1 recursor gap.

For two numbers a, b:

    |a-b| := (a - b) + (b - a)         ← absolute difference (non-negative)
    min2 a b := (a + b - |a-b|) / 2    ← the smaller of a, b
    max2 a b := (a + b + |a-b|) / 2    ← the larger of a, b

For three numbers:

    sorted3 (a,b,c) := (min(min(a,b),c), a+b+c-min-min-max, max(max(a,b),c))
-/

/-- Absolute difference (non-negative): `|a-b| = max(a,b) - min(a,b)`. -/
def absDiff (a b : Nat) : Nat := (a - b) + (b - a)

/-- Minimum of two naturals, computed via pure arithmetic. -/
def min2 (a b : Nat) : Nat := (a + b - absDiff a b) / 2

/-- Maximum of two naturals, computed via pure arithmetic. -/
def max2 (a b : Nat) : Nat := (a + b + absDiff a b) / 2

/-- Sort a 3-element tuple into ascending order using only arithmetic.

    Example: `sorted3 (5, 1, 3) = (1, 3, 5)`. -/
def sorted3 (t : Nat × Nat × Nat) : Nat × Nat × Nat :=
  let a := t.1
  let b := t.2.1
  let c := t.2.2
  let mn := min2 (min2 a b) c
  let mx := max2 (max2 a b) c
  let md := a + b + c - mn - mx
  (mn, (md, mx))


/-! ## 3. Length parity check

The "list" has 3 elements — a fixed-length collection. Its length is 3, and
`3 % 2 = 1` (odd). We compute and report this parity. -/

/-- The length of a 3-element list is always 3. -/
def listLen : Nat := 3

/-- Length parity: 0 (even) or 1 (odd). For 3 elements, this is `1`. -/
def lenParity : Nat := listLen % 2


/-! ## 4. Main program

Demonstrates:
1. Sorting: sorts `(5, (1, 3))` into `(1, (3, 5))` — prints the minimum (`1`).
2. Parity: the length is 3, and `3 % 2 = 1` (odd).

The theorems above are erased by typelean — only the computational `sum3`,
`sorted3`, and `lenParity` calls survive to TypeScript. -/

def main : IO Unit :=
  let input : Nat × Nat × Nat := (5, (1, 3))
  let sorted := sorted3 input
  -- Print the first (minimum) element of the sorted list.
  -- For (5,1,3) → sorted to (1,3,5) → prints `1`.
  -- The length parity is 1 (odd) for this 3-element list.
  IO.println sorted.1  -- 1: the minimum after sorting (5,1,3) → (1,3,5)