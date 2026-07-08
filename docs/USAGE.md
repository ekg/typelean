# typelean usage guide

**typelean** is a research compiler that translates **Lean 4 source programs
into TypeScript**. This guide describes what the compiler actually does today
(M1, in progress) — not what it aspires to do. Honesty about limits is the
value here.

---

## 1. Install

You need three things on your `PATH`:

| Tool | Install | Why |
|------|---------|-----|
| **Lean 4** + **elan** | [`elan`](https://github.com/leanprover/elan) | `lean` (the Lean 4 interpreter) and `lake` (the build system) |
| **lake** | (comes with `elan`) | Builds typelean and its Lean dependencies |
| **node** | [`nodejs.org`](https://nodejs.org/) | Runs the emitted TypeScript |

Clone and build:

```bash
git clone https://github.com/ekg/typelean.git
cd typelean
lake build
```

This compiles typelean itself — a Lean 4 program that takes Lean source files
as input and produces TypeScript. The binary lives at
`.lake/build/bin/typelean`.

---

## 2. Your first compile

Write a minimal "hello" program:

```bash
echo 'def main : IO Unit := IO.println "hello from typelean"' > hi.lean
```

Compile it to TypeScript (redirect stderr to hide lake's replay warnings):

```bash
lake exe typelean hi.lean 2>/dev/null > hi.mts
```

Run the emitted TypeScript:

```bash
node hi.mts
# => hello from typelean
```

### What was emitted?

The output (`hi.mts`) is a **self-contained ES module** with two parts:

1. **An inlined runtime** (`_rt` object) — about 20 lines of TypeScript that
   reproduces Lean's value model: `bigint`-backed `Nat`, constructor objects,
   `IO.println` as a curried thunk, and basic helpers like `natRepr`,
   `strAppend`, etc. The emitted code never imports external files — it's one
   blob you can copy anywhere Node runs.

2. **The compiled program** — a few `const` declarations and a call to
   `typelean_main()`. Every Lean declaration becomes a mangled top-level
   binding; `IO.println` is wired through the runtime's `_rt.println` helper.

Open `hi.mts` and look around. You should see:

```typescript
const typelean_main = (((_rt.println)(undefined))(_rt.ctor(0, [((s_0) => s_0)])))("hello from typelean");
typelean_main();
```

The `IO.println` argument chain (`print` typeclass → `ToString String` instance
→ `$` value → captured thunk) is fully inlined as curried application.

---

## 3. The pipeline

```
input.lean  ──Frontend──▶ Environment ──Lower──▶ IR ──Emit──▶ TypeScript
              (Lean.Elab)       (Lean.Expr,     (erase types/   (against inlined
                                type-checked)    proofs/u)      runtime)
```

| Stage | What it does | More |
|-------|-------------|------|
| **Frontend** | Runs Lean's own elaborator (`Lean.Elab`) on your source. No re-implementation of parsing, macro expansion, type-class resolution, or `do`-notation — typelean inherits all of it verbatim from Lean 4. | [`DESIGN.md §3`](../DESIGN.md#3-stage-1--frontend-leveraging-leanelab) |
| **Lower** | Takes the elaborated `Lean.Expr` and translates it to an untyped IR, erasing types, proofs, and universe levels. Binders over `Prop`/`Sort` are dropped; constructors and literals pass through. | [`DESIGN.md §4`](../DESIGN.md#4-stage-2--lower-expr--ir-with-erasure) |
| **Emit** | Renders the IR as self-contained TypeScript, backed by the inlined runtime (`_rt`) that reproduces Lean's value model. An injective name mangling maps Lean hierarchical names to JS identifiers. | [`DESIGN.md §5`](../DESIGN.md#5-stage-3--emit-ir--typescript) |

The full architecture is in [`DESIGN.md`](../DESIGN.md).

---

## 4. What works today (M1)

The **fidelity harness** (`tests/fidelity/run.sh`) is the ground truth. As of
this writing, **17 of 21 cases PASS**. Here is what they demonstrate:

### Straight-line arithmetic
```lean
def main : IO Unit := IO.println (2 + 3 : Nat)
```
Emitted TS uses `_rt.natAdd(2n)(3n) = 5n`. → [`arith`](../tests/fidelity/cases/arith.lean)

### `let` and lambda (curried application)
```lean
def main : IO Unit :=
  IO.println (let f : Nat → Nat := fun x => x + 1; f 41)
```
Lambdas become arrow functions; `let` becomes a local `const`. → [`letlambda`](../tests/fidelity/cases/letlambda.lean)

### `IO.println` with String
```lean
def main : IO Unit := IO.println ("hello, " ++ "typelean!")
```
`++` is wired through `_rt.strAppend`. → [`string_concat`](../tests/fidelity/cases/string_concat.lean)

### Basic `ToString` dispatch
`IO.println` automatically calls `toString` on its argument — for `Nat` via
`_rt.natRepr`, for `String` via identity (the `ToString String` instance).

### Inductives as constructor objects
```lean
inductive Color where | red | green | blue

def toNum : Color → Nat
  | .red   => 0
  | .green => 1
  | .blue  => 2
```
A zero-argument constructor like `Color.green` becomes
`_rt.ctor(1, [])` (tag 1 = second constructor). BUT — note the existential
caveat below: to actually **match** on `Color` via `casesOn`, you need M2.
→ [`inductive_match`](../tests/fidelity/cases/inductive_match.lean) (currently FAILs)

### Proof-carrying demos
Several demo cases prove theorems and then exercise them in `main`:
`demo-09-demo-string-len` (proof about `String.length`), `demo-16-demo-gcd-correct`
(correctness of Euclid's algorithm), `demo-12-demo-lookup-correct` (map lookup),
and many more. All 13 non-broken demos pass.

Full list of passing cases:

```
PASS: arith
PASS: demo-01-demo-add-comm
PASS: demo-02-demo-len-append
PASS: demo-04-demo-sorted-insert
PASS: demo-05-demo-sum-formula
PASS: demo-07-demo-fib-spec
PASS: demo-08-demo-mod-add
PASS: demo-09-demo-string-len
PASS: demo-10-demo-all-equal
PASS: demo-11-demo-abs-pos
PASS: demo-12-demo-lookup-correct
PASS: demo-13-demo-take-drop
PASS: demo-14-demo-bounded-counter
PASS: demo-15-demo-perm-same
PASS: demo-16-demo-gcd-correct
PASS: letlambda
PASS: string_concat
```

---

## 5. What does NOT work yet (honest limits)

**4 of 21 fidelity cases currently FAIL.** Every failure is a tracked gap
with a known root cause — no silent drops.

### Recursion via `Nat.rec` / `Nat.brecOn` (M2 blocker)

Lean elaborates structural recursion over `Nat` into recursors like
`Nat.rec` / `Nat.brecOn`. For example:

```lean
def fact : Nat → Nat
  | 0     => 1
  | n + 1 => (n + 1) * fact n
```

...becomes core `Expr` referring to `Nat.rec` (or `Nat.brecOn`). typelean's
Lower stage does not yet **recognize** recursor forms — it passes them through
as opaque `const` references, which emit as `undefined` calls at runtime.

Failing cases:

- [`rec_nat`](../tests/fidelity/cases/rec_nat.lean) — `fact 5` via structural recursion
- [`demo-06-demo-pow-mult`](../tests/fidelity/cases/demo-06-demo-pow-mult.lean) — `pow a n` via structural recursion
- [`demo-03-demo-reverse-invol`](../tests/fidelity/cases/demo-03-demo-reverse-invol.lean) — `List.brecOn` for structural recursion over lists

The error looks like:

```
TypeError: undefined is not a function  ... at typelean_main
```

This is the **next big blocker** — tracked as ROADMAP M2.

### Pattern matching on inductives (M2, same root cause)

`match` on a user inductive is elaborated by Lean into `casesOn` applications.
The same recognizer gap applies:

- [`inductive_match`](../tests/fidelity/cases/inductive_match.lean) — `toNum Color.green` via `casesOn`

### What else does not work

Beyond the fidelity corpus, many things are simply untested or known gaps:

| Feature | Status | Reason |
|---------|--------|--------|
| `do` notation | Desugared by Lean but `do`-style programs often use recursion | Compiles but fails if body uses recursion |
| `for` / `while` / `mut` | Not tested | Elaborated to `forIn` / folds; unknown fidelity |
| `List` / `Array` / `String` functions | Partial — only `++` works | `List.map`, `List.filter`, `Array.push` etc. need runtime primitives (M5) |
| Effects beyond `IO.println` | Not implemented | `IO.print`, `IO.FS.*`, `IO.Ref`, `ST.Ref` all missing |
| Stdlib (`Init`, `Std`) | Not targeted until M5 | Runtime primitive table (DESIGN §9) is M1-sized |
| Tactic-produced data | Untested | Should work post-elaboration (M3) |

**Plainly: this is M1-partial.** The compiler handles straight-line `Nat`
arithmetic, `let`, lambda, `IO.println`, `String` concat, and constructor
building. It cannot handle recursion, pattern matching, recursion-via-`match`,
most of the standard library, or effects beyond `println`. The next milestone
(M2) targets exactly this blocker.

---

## 6. The fidelity harness

The fidelity harness at [`tests/fidelity/run.sh`](../tests/fidelity/run.sh) is
the project's **ground-truth quality gate**:

```bash
bash tests/fidelity/run.sh
```

For each `.lean` file in `tests/fidelity/cases/`:

1. **Lean result** — runs `lean --run` to get the reference output.
2. **Compile** — runs typelean to produce TypeScript.
3. **Run** — runs the emitted TS under `node`.
4. **Diff** — compares the two; a PASS requires exact match.

### Semantics

| Status | Meaning |
|--------|---------|
| **PASS** | Lean output matches Node output (exact diff = 0). |
| **FAIL** | Compilation succeeded but Node output differs from Lean, or Node crashed. |
| **BLOCKED** | typelean itself failed with a stage-tagged `CompileError` (frontend/lower/emit). |

Exit code: **0** iff every case passes; **1** otherwise.

### How to add a case

1. Write a Lean program and save it as `tests/fidelity/cases/my-thing.lean`.
2. The program should use `def main : IO Unit := IO.println <expr>` or `#eval`.
3. Run `bash tests/fidelity/run.sh` to see if it passes.
4. If it passes, great — the corpus is grow-only, so future regressions are caught.
5. If it fails, the gap is tracked for a future milestone.

The harness does NOT permit silent drops (DESIGN §1.4): any unhandled construct
produces a stage-tagged error on stderr, never a silently wrong output.

---

## 7. The proof-carrying thesis

Lean is a proof assistant. If typelean faithfully compiles **verified Lean** to
TypeScript, the emitted TS **inherits the Lean proofs of correctness**. The
proof is erased (`Prop`/`Sort` carry no runtime content) — what survives is the
verified computational core; its guarantee reaches the TS output **only if**
typelean and its runtime faithfully reproduce Lean's evaluation semantics.

This "only if" is the whole game. Today:

- **Proof → Lean → typelean → TS**: the Lean proof guarantees the Lean program.
  If typelean preserves semantics (verified by the fidelity corpus), the TS
  inherits the guarantee.
- **Trust boundary**: the compiler itself is *not yet verified* (it is tested
  empirically via the harness). External code (FFI, `@[extern]` primitives, the
  runtime) is outside the formal guarantee. Future milestones could shrink this
  gap with interface specifications + runtime monitoring or a verified compile
  correctness proof for the M1 subset.

See [`OPPORTUNITIES.md`](../OPPORTUNITIES.md) for the full research catalog on
proof-of-correctness over testing.

---

## 8. Where to go next

### Roadmap

| Milestone | What | Status |
|-----------|------|--------|
| M0 | Repo + skeleton compile | ✅ Done |
| M1 | Expression & definition translation | 🚧 In progress (you are here) |
| M2 | Inductives, structures, pattern matching | ⬜ Next blocker |
| M3 | Tactics & metaprogramming | ⬜ |
| M4 | Effects, IO, monads | ⬜ |
| M5 | Standard library coverage | ⬜ |
| M6 | Fidelity test suite vs Lean (parity harness) | ⬜ |

See [`ROADMAP.md`](../ROADMAP.md) for milestone details.

### How to contribute

**The fastest way to help is the fidelity corpus.** Add a Lean program to
`tests/fidelity/cases/` and run `bash tests/fidelity/run.sh`:

- If it **PASSes**, you've expanded the regression net and confirmed typelean
  handles that construct.
- If it **FAILs** or is **BLOCKED**, you've identified a tracked gap that the
  next milestone addresses — file it as a subtask if one doesn't exist.

Every fidelity case is a step toward the M6 parity harness, and every case that
passes is a data point that typelean's proof-carrying thesis holds for that
program.