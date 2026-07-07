# typelean — Roadmap

Milestones toward the root objective: **a Lean 4 → TypeScript compiler, written
in Lean 4, with perfect Lean 4 compatibility and complete translation.** Each
milestone lists what is delivered and how it is verified (the *exit criteria*).
The objective is complete only when M6's parity suite passes across the targeted
Lean surface — until then the graph keeps fanning out (see `PROTOCOL.md`).

Status legend: ✅ done · 🚧 in progress · ⬜ not started.

---

## M0 — Repo + skeleton compile ✅

**Delivered**
- Lean 4 `lake` project named `typelean` (`lakefile.lean`, `lean-toolchain`
  pinned to `leanprover/lean4:v4.31.0`, `.gitignore` for `/.lake`).
- Pipeline module scaffold: `Typelean/{Basic,IR,Frontend,Lower,Emit,Pipeline}.lean`,
  root `Typelean.lean`, CLI `Main.lean`.
- `import Lean` builds inside the Lake project (the Frontend/Lower stages depend
  on it) — verified.
- `DESIGN.md`, `ROADMAP.md`, `PROTOCOL.md`.

**Exit criteria (met)**
- [x] `lake build` succeeds.
- [x] `./.lake/build/bin/typelean` runs and prints the version/usage banner.
- [x] Design docs present.

---

## M1 — Expression & definition translation 🚧

The first end-to-end slice: compile a *small* Lean program (non-dependent
functions over `Nat`/`Bool`, simple `let`/`λ`/application, a couple of
constructors) all the way to runnable TypeScript.

**Delivered**
- `Typelean.IR`: the IR datatype, fleshed out (vars, λ, app, let, ctor, lit,
  const; literal & projection forms). *(subtask `typelean-ir`)*
- `Typelean.Frontend.elaborateSource`: real elaboration via `Lean.Elab`
  (`runFrontend`), search path initialized; returns an `Environment` or a
  positioned `CompileError`. *(subtask `typelean-frontend`)*
- `Typelean.Lower`: `Expr → IR` for the core lambda calculus with type/proof
  erasure; constructor applications; `const` references; `Nat`/`String` literals.
  *(subtask `typelean-lower`)*
- `Typelean.Emit` + `runtime/typelean_rt.ts`: IR → TS text; name mangling;
  runtime with `Nat` (`bigint`), constructor objects, closures, `IO.println`.
  *(subtask `typelean-emit`)*
- `Typelean.Pipeline` + `Main`: wire Frontend → Lower → Emit; CLI compiles a
  file to TS. End-to-end test. *(subtask `typelean-integrate-m1`)*

**Exit criteria**
- [ ] `lake build` clean; per-stage unit tests pass (`lake test`).
- [ ] `typelean examples/hello.lean` emits TS that, run under Node, prints the
      same output as `lean --run examples/hello.lean` (e.g. `def main` printing a
      string; `#eval (2 + 3 : Nat)` parity = `5`).
- [ ] At least 5 fidelity cases pass (arithmetic, `let`/`λ`, a user inductive +
      `match`, a recursive `Nat` function, string concat).
- [ ] No silent drops: any unhandled `Expr` case yields a stage-tagged
      `CompileError`, and each is filed as a follow-up subtask.

---

## M2 — Inductives, structures, pattern matching ⬜

**Delivered**
- Full recursor/`casesOn`/`brecOn`/matcher translation (§4.3 of DESIGN).
- Structures, projections, nested & dependent pattern matches (as elaborated),
  `deriving` instances (`Repr`, `BEq`, `DecidableEq`, `Hashable`) as data.
- Mutual & nested inductives; well-founded recursion (`WellFounded.fix`).
- Specialized runtime reps for `List`, `Array`, `Option`, `Prod`, `Sum`, `Fin`.

**Exit criteria**
- [ ] Fidelity corpus covers: red-black tree ops, `List`/`Array` algorithms,
      mutual recursion, well-founded recursion (e.g. `gcd`), structure update.
- [ ] `#eval` parity for the above between Lean and emitted-TS-under-Node.

---

## M3 — Tactics & metaprogramming ⬜

Tactic *proofs* are erased (they build `Prop` terms). The work here is the
**runtime** side of metaprogramming and any tactic-produced **data**:

**Delivered**
- Confirm tactic-built terms (e.g. `decide`, `Decidable` instances, `simp`-normalized
  defs) lower correctly (they are ordinary `Expr` post-elaboration).
- `macro`/`elab`/`syntax`-defined surface translates (front-end handles it;
  verify produced terms compile).
- Handle reflection/`Quote`/`Expr`-as-data only insofar as user programs *run*
  them (rare; tracked as encountered).

**Exit criteria**
- [ ] Programs using `decide`, deriving handlers, and macro-heavy code compile
      and match `#eval`.

---

## M4 — Effects, IO, monads ⬜

**Delivered**
- `IO`/`EIO`/`ST` runtime bridge: `IO.println`, `IO.print`, `eprintln`, file IO
  (`IO.FS.*`), `IO.Ref`/`ST.Ref`, `IO.rand`, time, `IO.Process`, env vars.
- Exception/`throw`/`try`-`catch` in `IO` and `Except`.
- `do`-notation end-to-end (already desugared; verify), `for`/`while`/`mut`
  (elaborated to folds/`forIn`), `StateT`/`ReaderT`/`ExceptT` stacks.
- `Task`/`Thread` mapped to the runtime scheduler (cooperative or async).

**Exit criteria**
- [ ] An `IO` program doing console + file IO + refs matches `lean --run`
      behavior under Node (modulo unavoidable platform differences, documented).
- [ ] Monad-transformer-stack programs match `#eval`.

---

## M5 — Standard library coverage ⬜

**Delivered**
- Runtime primitive table (§9) populated for the targeted `Init`/`Std` surface:
  `Nat`/`Int`/`UInt*`/`Float` arithmetic, `String`/`Char` (codepoint/UTF-8
  semantics, §11), `Array`/`List`/`HashMap`/`HashSet`/`RBMap`, `Option`/`Except`.
- A coverage report: which stdlib constants have runtime primitives vs. compile
  from their Lean body vs. are still gaps (gaps ⇒ subtasks).
- `@[extern]` discovery automated (read `externAttr`) so unmapped externs are
  reported, never silently wrong.

**Exit criteria**
- [ ] Parity for a stdlib-exercising corpus (string processing, collections,
      numeric edge cases incl. truncating `Nat` subtraction, div/mod by zero).
- [ ] Zero unmapped `@[extern]` constants reachable from the corpus, or each
      remaining one filed as a tracked subtask.

---

## M6 — Fidelity test suite vs Lean (parity harness) ⬜

**Delivered**
- `tests/fidelity/` corpus + a harness that, per program, captures Lean's
  result (`lake env lean` / `#eval` / `lean --run`) and the Node result of the
  emitted TS, and diffs them (§12 of DESIGN).
- CI wiring (the generated `.github/workflows/lean_action_ci.yml`, extended) so
  parity runs on every change; the corpus is grow-only.
- A `make fidelity` / `lake test` target running the whole suite.

**Exit criteria**
- [ ] The full corpus passes (Lean ≟ Node) for the targeted Lean surface.
- [ ] Every previously-fixed bug has a regression case in the corpus.
- [ ] A documented compatibility report stating exactly which Lean surface is
      covered and what (if anything) remains — driving the next fan-out wave.

---

## Beyond M6 — toward *perfect* compatibility

M6 passing on the initial corpus is not the end: the objective is *perfect*
compatibility and *complete* translation. Ongoing waves:
- Broaden the corpus toward all of `Init`/`Std` and common `Mathlib`-free code.
- Migrate Lower's input from `Expr` to `Lean.Compiler.LCNF` for Lean-exact
  erasure (DESIGN §2 alternative), if fidelity gaps demand it.
- Performance: uncurrying, TCO/trampoline tuning, specialized reps, dead-code
  elimination, per-module ES output.
- Track each Lean release's changes (the toolchain is pinned; bumping it is a
  deliberate, tested subtask).

When a milestone completes, update this file and create the next wave's subtasks
(`PROTOCOL.md`).
