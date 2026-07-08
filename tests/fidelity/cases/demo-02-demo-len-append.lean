/-! # Fidelity case: List length distributes over append (proven), program
computes length using the guarantee.

`lean --run` → `5`. M1 category: proof-carrying demo (ROADMAP M1, DESIGN §4.2,
§12, §4.3).

We prove `(xs ++ ys).length = xs.length + ys.length` by structural induction
on `xs`.  The proof is computationally irrelevant (erased by typelean) but
validates the program's correctness.  The program then computes the combined
length of two concrete lists by adding their individual lengths — a
computation whose correctness is justified by the proven theorem. -/

theorem length_append (xs ys : List Nat) : (xs ++ ys).length = xs.length + ys.length := by
  induction xs with
  | nil => simp
  | cons x xs ih => simp [ih, Nat.succ_add]

/-- Compute the total length of two lists by summing their individual lengths.
    The `length_append` theorem guarantees this equals the length of the
    concatenated list `xs ++ ys`.  The proof is erased at runtime — only the
    computational content remains. -/
def combinedLength (lenA lenB : Nat) : Nat := lenA + lenB

/-- Demonstrate that `combinedLength` correctly computes the length of
    concatenated lists [1,2,3] and [4,5], relying on the proven theorem.

    [1,2,3].length = 3
    [4,5].length   = 2
    combinedLength 3 2 → 5  (which equals `([1,2,3] ++ [4,5]).length`). -/
def main : IO Unit :=
  IO.println (combinedLength ([1, 2, 3].length) ([4, 5].length))
