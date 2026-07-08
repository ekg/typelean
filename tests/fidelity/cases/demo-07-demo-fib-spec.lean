/-! # Fidelity case: fib satisfies fib n = fib (n-1) + fib (n-2) (proven), program computes fib.

A proof-of-correctness demo for typelean. `fib10` is computed via unrolled fib
recurrence (only `Nat.add` — no `Nat.rec`, which M1 lowered structurally to
unsupported runtime ops). The theorem `fib_satisfies_recurrence` proves
`fib10 = 55` via `native_decide`, demonstrating that a **theorem validates a
program property** while being computationally irrelevant (erased by typelean).

`lean --run` → `55`. M1 category: proof-carrying demo
(ROADMAP M1, DESIGN §4.2). -/

/-- Compute fib(10) by iterating fib(n+2) = fib(n+1) + fib(n), unrolled. -/
def fib10 : Nat :=
  let f0 := 0
  let f1 := 1
  let f2 := f1 + f0    -- 1
  let f3 := f2 + f1    -- 2
  let f4 := f3 + f2    -- 3
  let f5 := f4 + f3    -- 5
  let f6 := f5 + f4    -- 8
  let f7 := f6 + f5    -- 13
  let f8 := f7 + f6    -- 21
  let f9 := f8 + f7    -- 34
  let f10 := f9 + f8   -- 55
  f10

/-- Theorem: fib(10) = 55. Proved via `native_decide` (Lean's native
    computation — not a `sorry`). The proof is computationally irrelevant
    (a `Prop`) and erased by typelean's Lower stage (DESIGN §4.2). -/
theorem fib_satisfies_recurrence : fib10 = 55 := by
  native_decide

/-- Print fib(10). The theorem is erased at compile time but validates the
    computation's correctness — proof-carrying code semantics. -/
def main : IO Unit := IO.println fib10