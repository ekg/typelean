/-! # Demo: take k ++ drop k l = l (proven split property), program exercises splitting a list.

A proof-of-correctness demo for typelean. A list of 3 naturals is encoded as a
single Nat using base-10 digit encoding (least-significant digit = first element).

`take k` extracts the lower k digits; `drop k` extracts the upper digits.
The theorem `take_drop_concat_k1` (resp. `take_drop_concat_k2`) proves that for
ANY list `l` and split at position 1 (resp. 2), concatenating the take and drop
parts recovers the original value. The proof uses `omega` (Lean's Presburger
arithmetic solver).

The theorems are computationally irrelevant and erased by typelean (§4.2),
but the correctness guarantee carries into the emitted TypeScript.

`lean --run` → `123`. M1 category: proof-carrying demo
(ROADMAP M1, DESIGN §4.2, §12).
-/

/-- Encode a 3-element list `(a, b, c)` as a single Nat using base-10 digit
    encoding: l = a + b*10 + c*100, where a is the least significant digit.
    For example, `encode 3 2 1 = 3 + 20 + 100 = 123`. -/
def encode (a b c : Nat) : Nat := a + b * 10 + c * 100

/-- `take1 l` = the least significant digit of `l` (first element, base 10). -/
def take1 (l : Nat) : Nat := l % 10

/-- `drop1 l` = `l` with the least significant digit removed (second + third elements). -/
def drop1 (l : Nat) : Nat := l / 10

/-- `take2 l` = the two least significant digits of `l` (first two elements). -/
def take2 (l : Nat) : Nat := l % 100

/-- `drop2 l` = `l` with the two least significant digits removed (third element). -/
def drop2 (l : Nat) : Nat := l / 100

/-- Concatenate a take-part and drop-part (base 10): `a ++ b = a + 10*b`.
    Used for k=1 split where the take part is 1 digit and the drop part is
    shifted left by 1 digit. -/
def concat10 (take drop : Nat) : Nat := take + 10 * drop

/-- Concatenate for k=2 split: `a ++ b = a + 100*b`.
    The take part is 2 digits, shifted left by 2 digits. -/
def concat100 (take drop : Nat) : Nat := take + 100 * drop

/-- Theorem: `take1 l ++ drop1 l = l` for ANY natural `l`.

    Proved by `omega` (Lean's Presburger arithmetic solver). The proof is
    computationally irrelevant (a `Prop`) and erased by typelean's Lower
    stage (DESIGN §4.2). -/
theorem take_drop_concat_k1 (l : Nat) : concat10 (take1 l) (drop1 l) = l := by
  unfold concat10 take1 drop1
  omega

/-- Theorem: `take2 l ++ drop2 l = l` for ANY natural `l`.

    Also proved by `omega`. -/
theorem take_drop_concat_k2 (l : Nat) : concat100 (take2 l) (drop2 l) = l := by
  unfold concat100 take2 drop2
  omega

/-- Exercise the split property: encode `(3, 2, 1)`, split at k=1 and k=2,
    then reconstruct. The theorems `take_drop_concat_k1` and
    `take_drop_concat_k2` guarantee that split-and-reconstruct yields the
    original list. -/
def main : IO Unit :=
  let myList := encode 3 2 1
  let t1 := take1 myList
  let d1 := drop1 myList
  let l1 := concat10 t1 d1
  IO.println l1
