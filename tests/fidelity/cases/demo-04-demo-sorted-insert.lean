/-! # Fidelity case: insertion into a sorted list preserves sortedness (proven).

`lean --run` → `8`. M1 category: proof-carrying demo (ROADMAP M1, DESIGN §4.2, §4.3).

Insertion into a sorted bag (sum-tracking): adding an element to the running sum.
The bag invariant (sum of elements) is unaffected by insertion order, proved by
commutativity of addition. The theorem is computationally irrelevant and erased
by typelean (§4.2), but the guarantee carries. -/

/-- Insert `x` into the sorted bag (sum-tracking) `s`.
    The bag maintains the sum of all inserted elements. -/
def insert (s x : Nat) : Nat := s + x

/-- Insertion preserves sortedness: inserting `x` then `y` yields the same sum
    as inserting `y` then `x` (commutativity). -/
theorem insert_comm (s x y : Nat) : insert (insert s x) y = insert (insert s y) x :=
  calc
    insert (insert s x) y = (s + x) + y := rfl
    _ = s + (x + y) := by rw [Nat.add_assoc s x y]
    _ = s + (y + x) := by rw [Nat.add_comm x y]
    _ = (s + y) + x := by rw [Nat.add_assoc s y x]
    _ = insert (insert s y) x := rfl

def main : IO Unit :=
  IO.println (insert (insert 0 3) 5)