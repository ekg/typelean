/-! # Fidelity case: String.length properties (proven), program computes lengths/codepoints

`lean --run` → verified string length computations demonstrating proof-carrying
code: theorems validate String.length semantics, while the program computes
lengths of various strings at runtime.

M1 category: proof-carrying demo (ROADMAP M1, DESIGN §4.2 erasure, §11 String).

We prove three properties of `String.length`:
  1. `String.length "" = 0` — empty string has zero length.
  2. `String.length "abc" = 3` — ASCII string length equals character count.
  3. `String.length "世界" = 2` — CJK characters count as one codepoint each
     (Lean `String.length` counts Unicode scalar values, not UTF-16 code units).

Each theorem is proved via `native_decide` (Lean's native computation — not
a `sorry`). The proofs are computationally irrelevant (`Prop`) and erased by
typelean's Lower stage (DESIGN §4.2), but they validate the correctness of the
computation at compile time. -/

/-- The empty string has length 0. -/
theorem len_empty : String.length "" = 0 := by
  native_decide

/-- An ASCII string's length equals its character count. -/
theorem len_ascii : String.length "abc" = 3 := by
  native_decide

/-- CJK characters are single Unicode scalar values — they count as one
    codepoint each, unlike UTF-16 surrogate pairs. -/
theorem len_cjk : String.length "世界" = 2 := by
  native_decide

/-- Compute a multi-line report of string lengths, exercising `String.length`
    and `toString` for different categories of input. -/
def demo : String :=
  "String.length proofs (erased at runtime, verified at compile time):\n"
  ++ "  len_empty : \"\" = " ++ toString (String.length "") ++ "\n"
  ++ "  len_ascii : \"abc\" = " ++ toString (String.length "abc") ++ "\n"
  ++ "  len_cjk   : \"世界\" = " ++ toString (String.length "世界")

/-- Print the demo report. The theorems above are erased by typelean — only the
    computational `length` calls survive to TypeScript. -/
def main : IO Unit := IO.println demo