/-!
# Proof-carrying demo: reverse (reverse l) = l  (demo-03-demo-reverse-invol)

`lean --run` → `[3, 2, 1]`. A proof-carrying demo for typelean M1.

**What this demonstrates:**
- A Lean 4 program with a **theorem** (`revRev`) proving list reverse is
  involutive via structural induction (no `sorry`/admitted).
- A **def main** that exercises double-reverse on a concrete list and prints
  the result via `IO.println`.
- The theorem is computationally irrelevant — typelean erases the proof
  (DESIGN §4.2) but the guarantee carries: the program typechecks, so the
  theorem's conclusion holds for all inputs reachable from `main`.

**M1 limitation: recursors not yet lowered to IR switch (DESIGN §4.3)**
Lean elaborates `match` + structural recursion into `List.brecOn` / `List.below`
machinery.  typelean's `expr → Expr` lowering (Lower.lean, 494L) handles each
case of `Lean.Expr` (see DESIGN §4 table) but does not yet *recognize* recursor
forms, so it passes them through as ordinary `const` references.  At emit time
(Emit.lean, 196L) these imported recursor constants resolve to `undefined` in
the runtime — there is no `_rt.listBrecOn` primitive.

The result: _lean --run_ evaluates the full Lean program correctly (all
theorems checked, `main` prints `[3, 2, 1]`), and typelean emits syntactically
valid TypeScript.  But the emitted code fails at Node runtime:

    TypeError: undefined is not a function  ... at typelean_main

The fix is the tracked `brecOn`/`casesOn` → `IR.switch` recognizer in Lower
(ROADMAP M2).  Companion cases: `rec_nat.lean` (imported `Nat` recursors) and
`inductive_match.lean` (user-inductive via imported `casesOn` matcher).
-/

open List

/-! A structural-recursive reverse over `List Nat`.  Lean elaborates the
    pattern-matching recursion to `List.brecOn` / `List.below`; typelean's
    current Lower stage passes these through as opaque `const` references. -/
def rev : List Nat → List Nat
  | []    => []
  | x :: xs => rev xs ++ [x]

/-! Lemma: `rev (as ++ [x]) = x :: rev as`.
    Proved by structural induction on `as`.  No `sorry`. -/
theorem rev_snoc (as : List Nat) (x : Nat) : rev (as ++ [x]) = x :: rev as := by
  induction as with
  | nil => rfl
  | cons y ys ih =>
    simp [rev, ih]

/-! Main theorem: `rev (rev l) = l` for all `l : List Nat`.
    Proof by structural induction:
    - `nil`: `rev (rev []) = []` — trivial.
    - `cons x xs`: `rev (rev (x :: xs)) = rev (rev xs ++ [x]) = x :: rev (rev xs) = x :: xs`.
      Uses `rev_snoc` and the induction hypothesis.
    No `sorry` or axioms — a genuine deductive argument. -/
theorem revRev (l : List Nat) : rev (rev l) = l := by
  induction l with
  | nil => rfl
  | cons x xs ih =>
    calc
      rev (rev (x :: xs))
          = rev (rev xs ++ [x])     := by rfl
      _   = x :: rev (rev xs)       := by rw [rev_snoc (rev xs) x]
      _   = x :: xs                 := by rw [ih]

/-! Exercise the theorem: construct `[3, 2, 1]`, reverse it twice, and print.
    By the theorem `revRev`, the result equals the original. -/
def main : IO Unit :=
  IO.println (rev (rev [3, 2, 1] : List Nat))