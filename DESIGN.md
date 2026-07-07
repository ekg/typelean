# typelean — Design

**typelean** is a compiler, written in **Lean 4**, that translates **Lean 4
source programs into TypeScript**. The north star is **perfect Lean 4
compatibility** and **complete translation**: every valid Lean 4 program is
accepted, and every construct is given defined TypeScript semantics (or a
faithful runtime emulation) so that the translated program reproduces Lean's
evaluation behavior, modulo effects / IO bridging.

This document describes the architecture. It is a living document: as
milestones land, update it (and `ROADMAP.md`).

---

## 1. Guiding principles

1. **Reuse Lean's own front-end; never re-implement elaboration.** Parsing,
   macro expansion, elaboration, type-class resolution, coercion insertion,
   universe inference, `do`-notation desugaring, pattern-match compilation, and
   termination checking are all *enormous* and are exactly where compatibility
   bugs hide. typelean `import Lean` and drives `Lean.Elab` so that the input we
   compile is the *same* core term Lean itself produces. This is the single most
   important decision for "perfect compatibility".

2. **Compile from erased computational core, not surface syntax.** After
   elaboration, a declaration is a `Lean.Expr` (and a type, also an `Expr`).
   Types, proofs, and universe levels are *computationally irrelevant* and are
   erased. What remains is an untyped, call-by-value lambda calculus with
   constructors, recursors, and literals — which is what TypeScript must
   reproduce.

3. **Faithful value model over clever types.** TypeScript's structural type
   system cannot express Lean's dependent types, and it does not need to: at
   runtime Lean values are tagged constructor objects, closures, and a handful
   of primitive types. We emit *untyped* (or loosely-typed) TS backed by a
   hand-written runtime (`runtime/typelean_rt.ts`) that implements Lean's value
   semantics exactly. Optional `.d.ts`-style annotations can be emitted for
   documentation but never affect semantics.

4. **No silent drops.** "Complete translation" means there is no `unsupported`
   escape hatch in the final product. During bring-up a stage may emit a
   `CompileError` (stage-tagged, see `Typelean.Basic`), but every such gap is a
   tracked subtask, never a silent `undefined`.

---

## 2. Pipeline overview

```
                    ┌───────────────────────────────────────────────┐
  input.lean  ───▶  │  Stage 1: Frontend   (Typelean.Frontend)      │
                    │  parse + elaborate via Lean.Elab               │
                    │  ⇒ Lean.Environment (all ConstantInfo)         │
                    └───────────────────────────────────────────────┘
                                        │  Lean.Expr (core terms)
                                        ▼
                    ┌───────────────────────────────────────────────┐
                    │  Stage 2: Lower      (Typelean.Lower)          │
                    │  erase types/proofs/universes; Expr ⇒ IR       │
                    │  resolve recursors / casesOn / matchers        │
                    │  ⇒ Typelean.IR.Module                          │
                    └───────────────────────────────────────────────┘
                                        │  Typelean.IR
                                        ▼
                    ┌───────────────────────────────────────────────┐
                    │  Stage 3: Emit       (Typelean.Emit)           │
                    │  IR ⇒ TypeScript text; name mangling           │
                    │  against runtime/typelean_rt.ts                │
                    └───────────────────────────────────────────────┘
                                        │
                                        ▼
                              output.ts  +  typelean_rt.ts
                                        │
                                        ▼  (fidelity harness)
                              node output.ts   ≟   lean #eval
```

The driver lives in `Typelean.Pipeline` (`compile : String → IO (Except
CompileError String)`); the CLI is `Main.lean`.

### Why an explicit IR instead of `Expr → TS` directly?

* `Lean.Expr` carries type information, metadata (`mdata`), universe levels, and
  binder info that are noise for code generation. The IR is the *erased* form:
  untyped lambda calculus + constructors + literals + (eventually) join points.
* The IR is a stable contract between Lower and Emit, letting them be developed
  and tested in parallel (different files, different subtasks).
* It is the natural place for backend-agnostic optimizations (inlining of
  trivial wrappers, dead-binding elimination, constant folding) before we commit
  to TS syntax.

> **Alternative considered — lower from Lean's `Lean.Compiler.LCNF`** (Lean
> Compiler Normal Form: the IR Lean's *own* native/`Expr`-to-C compiler uses).
> LCNF already performs erasure, eta-expansion, let-normalization, and
> specialization. Long-term, hooking the LCNF pipeline (`Lean.Compiler.LCNF.*`,
> the `@[cpass]` phases) gives us Lean's exact erasure decisions for free and is
> the most direct route to fidelity. Short-term (M1) we lower from `Expr` with
> our own erasure because it has a smaller surface and no dependency on
> internal LCNF APIs that shift between Lean releases. The IR is designed to be
> a valid target for *either* source, so switching Lower's input later does not
> disturb Emit. This is an explicit, revisitable decision (see ROADMAP M5/M6).

---

## 3. Stage 1 — Frontend (leveraging `Lean.Elab`)

Goal: turn source text into a checked `Lean.Environment` using Lean's real
front-end, so typelean inherits Lean's parsing/elaboration semantics verbatim.

Relevant Lean internals:

* **`Lean.Elab.Frontend`** — `Frontend.runFrontend` (a.k.a. the machinery behind
  `lean --run`) takes source text, an `Options`, a file name, and a main module
  name, and returns the resulting `Environment` plus a `MessageLog`. This is the
  highest-level entry point and the recommended one.
* **`Lean.Elab.Frontend.processCommands` / `Command.CommandElabM`** — the
  command-by-command loop, if we need finer control (e.g. to intercept each
  command's elaboration, capture `#eval` results, or stream diagnostics).
* **`Lean.Parser.parseHeader`** + **`Lean.importModules`** — set up the initial
  environment from the `import` header before command elaboration. typelean must
  initialize the search path (`Lean.initSearchPath`, `Lake`-provided
  `LEAN_PATH`) so that imported modules (e.g. `Init`, `Std`) resolve.
* **`Lean.Environment`** — the output. `env.constants : ConstMap` maps `Name ⇒
  ConstantInfo`. `ConstantInfo` variants we care about:
  * `defnInfo`/`thmInfo`/`opaqueInfo` — `value : Expr` is the body to compile
    (proofs/`thmInfo` are erased — Prop-valued — but the constructor is the same).
  * `ctorInfo` — a constructor (tag = `cidx`, arity, number of params/fields).
  * `recInfo` — a recursor (its reduction rules define elimination).
  * `inductInfo` — an inductive type's metadata (constructors, params, indices).
  * `quotInfo`, `axiomInfo` — quotients and axioms (need runtime treatment; see
    §8 on `Quot` and §9 on opaque/`@[extern]` constants).

Frontend's public contract (kept stable for the integrator):

```lean
Typelean.Frontend.elaborateSource
  (source : String) (fileName : String := "<input>")
  : IO (Except CompileError Environment)
```

Error handling: elaboration errors are collected from the `MessageLog`; the
first error (with position) becomes a stage-tagged `CompileError`. A clean
compile yields the environment.

Capturing `#eval` for the fidelity harness: the harness can either re-run `lean`
externally and diff against Node, or hook `Command.CommandElabM` to record each
`#eval`'s pretty-printed result. The external route is simpler and is what M6
starts with.

---

## 4. Stage 2 — Lower (`Expr → IR`, with erasure)

Input: the elaborated `Environment` and a set of *root* declarations to compile
(by default everything reachable from `main` / `#eval` targets — closed-world).
Output: a `Typelean.IR.Module` (topologically ordered decls).

### 4.1 The `Lean.Expr` cases and their IR images

| `Lean.Expr` | meaning | IR / treatment |
|---|---|---|
| `bvar` / `fvar` | de Bruijn / local | `IR.Expr.var name` (fresh, hygienic names) |
| `lam` | λ | `IR.Expr.lam` (curried; erase binders whose domain is a type/Prop) |
| `app` | application | `IR.Expr.app`; **erase irrelevant args** (see §4.2) |
| `letE` | let | `IR.Expr.letE` |
| `const` | global ref | `IR.Expr.const` (or a constructor/recursor — dispatched specially) |
| `lit` | `Nat`/`String` literal | `IR.Expr.lit` (`Nat` ⇒ runtime `Nat` via `bigint`) |
| `proj` | structure projection | constructor-field access on the runtime object |
| `mdata` | metadata wrapper | transparent — recurse into the inner expr |
| `sort` | `Sort u` | **erased** (computationally irrelevant; if it survives to a value position it becomes a runtime "type token" — rarely needed) |
| `forallE` | Π / `→` | **erased** (a type) |
| `mvar` | metavariable | must not survive elaboration; an error if seen |

### 4.2 Erasure

A function argument (and a `lam` binder) is *computationally irrelevant* and is
erased when its type is a proposition (`Prop`) or a type/sort (`Sort`). Two
implementation routes:

* **Type-directed (M1):** use `Lean.Meta` (`Meta.inferType`, `Meta.whnf`,
  `Meta.isProp`) to classify each binder/argument. This matches the kernel's
  notion of relevance.
* **LCNF-directed (later):** let `Lean.Compiler.LCNF` decide; it already marks
  erased values as `lcErased`/`lcUnreachable`. (See §2 alternative.)

Erasure of *whole declarations*: `thmInfo` and any decl whose type is a `Prop`
produce no runtime code (or a runtime `Unit`/`undefined` placeholder if referenced
in an erased position). Universe-polymorphic decls are monomorphized by erasure:
levels are simply dropped (universes have no runtime content — see §10).

### 4.3 Recursion, recursors, and pattern matching

Lean compiles surface `match`, structural recursion, and well-founded recursion
*during elaboration* into core terms built from **recursors** and
**auxiliary matcher/`brecOn` definitions**. Because we compile post-elaboration,
we receive these already-compiled forms and only need to translate them:

* **`casesOn` / `T.rec`** (recursors) — for an inductive `T`, `T.rec` /
  `T.casesOn` is elimination. We translate an application of `casesOn` into a
  `switch` on the scrutinee's constructor tag, binding fields to the minor
  premises' parameters. For the *recursor* `T.rec` (with motives/IH), we emit a
  recursive helper (the IH is supplied by recursing on sub-values).
* **`brecOn` / below** — structural recursion is elaborated via `T.brecOn` and
  the `T.below` "course-of-values" table. We recognize this pattern and emit
  ordinary recursive functions (optionally memoizing `below` where Lean does).
* **`WellFounded.fix` / `WellFounded.fixF`** — well-founded recursion. The
  accessibility proof argument is erased; the fixpoint becomes a plain recursive
  function. Termination is Lean's concern, not the runtime's.
* **Matcher auxiliaries** (`Foo.match_1`, …) — generated splitter functions; we
  compile them like any other `def` (they bottom out in `casesOn`).

A dedicated *recognizer* in Lower detects these idioms (by head constant and the
recursor metadata in `recInfo`) and emits efficient JS (switch + recursion)
rather than literally modelling recursor reduction.

### 4.4 Inductives & structures

* **Inductive type** `T` ⇒ no runtime type object is needed for computation; its
  *constructors* become runtime constructor builders. Each constructor `c` has a
  numeric tag (`ConstructorVal.cidx`) and an arity; an application
  `c a₁ … aₙ` (with type/Prop args erased) ⇒ `IR.Expr.ctor "T.c" tag [args]`.
* **Structures** are single-constructor inductives. Field projections (`proj` or
  `T.field` projection functions) ⇒ field access by index. We may emit named
  fields for readability when `getStructureFields` is available.
* **Special-cased representations** (for fidelity *and* performance) decided in
  Lower/Emit:
  * `Nat`, `Int` ⇒ `bigint` (not unary `succ`/`zero` constructor objects).
  * `String`, `Char` ⇒ runtime string/codepoint (see §11).
  * `Array` ⇒ JS array (Lean `Array` is a dynamic array).
  * `Fin`, `UInt8…64`, `Float` ⇒ runtime numeric wrappers with wrap-around.
  * `Bool`, `Decidable` ⇒ JS boolean where sound (`Decidable p` erases its
    proof and is a tagged `isTrue/isFalse`).
  These mirror Lean's own `@[extern]` / runtime specializations so behavior
  matches `#eval`.

---

## 5. Stage 3 — Emit (`IR → TypeScript`)

Emit renders the IR as TypeScript and is the only stage that knows TS syntax.

* `IR.Expr.lam` ⇒ arrow function `(x) => …` (curried; a later pass may
  uncurry/saturate for performance).
* `IR.Expr.app` ⇒ `f(x)`.
* `IR.Expr.letE` ⇒ `(() => { const x = v; return body })()` or a statement-level
  `const` when in a block context (Emit maintains expression vs. statement
  context to avoid IIFE bloat).
* `IR.Expr.ctor` ⇒ runtime constructor object, e.g. `_rt.ctor(tag, [a, b])`
  (or a specialized literal for `Nat`/`String`).
* `IR.Expr.const` ⇒ reference to the mangled top-level binding.
* `IR.Expr.lit` ⇒ runtime literal (`_rt.nat(123n)`, `_rt.str("…")`).
* `IR.Decl` ⇒ `export const <mangled> = <params curried> => <body>;` (or
  `function` for self-recursion / TCO).

**Name mangling.** Lean `Name`s are hierarchical and may contain macro scopes,
numeric components, and characters illegal in JS identifiers (`.`, `«»`, `✝`,
unicode). Emit uses an *injective* mangling (e.g. escape each component, join
with `_`, prefix to avoid collisions/keywords) with a reverse map kept for
debugging/source-mapping. Injectivity is required for correctness; readability is
secondary.

**Module shape.** M1: whole-program single-file output that `import`s the
runtime. Later: per-Lean-module TS modules with ES imports mirroring Lean's
import graph (better for incremental builds and stdlib reuse).

---

## 6. Type classes & coercions (free, post-elaboration)

* **Type classes** are resolved by the elaborator into ordinary terms: an
  instance is a structure value (a "dictionary"), and a method call is a
  projection/application against the resolved instance. By the time we see
  `Expr`, there are *no* classes left — only data and functions. typelean
  therefore needs *no* special class machinery; dictionaries lower as ordinary
  constructor objects and method dispatch as ordinary application. (This is the
  payoff of compiling post-elaboration.)
* **Coercions** are likewise inserted by elaboration as explicit applications of
  `coe`/`↑`/`CoeT.coe` etc. They are ordinary function calls in `Expr` and need
  no special handling.

---

## 7. Monads, `do`-notation, and effects

* **`do`-notation** is desugared by the elaborator into core `bind`/`pure`/
  `seq`/`map` applications (and `Functor`/`Monad`/`Bind` dictionaries, see §6).
  We receive the desugared form and translate it as ordinary applications — no
  special `do` handling is required for correctness. (An optional Emit
  optimization can re-recognize state/IO monads and emit imperative JS for
  speed/readability, but it is not needed for fidelity.)
* **Pure monads** (`Option`, `Except`, `State`, `Reader`, `Id`, free monads,
  user monads) are just data + functions and translate structurally.
* **`IO` and effects** are the bridge point. In Lean, `IO α = EIO IO.Error α`
  and `EIO ε α = EStateM ε IO.RealWorld α`; an `IO` action is, operationally, a
  function of the (erased) world token that performs effects and returns a
  result-or-error. typelean represents an `IO` action at runtime as a **thunk**
  `() => α` (the world token is erased) that the top-level driver *runs*. The
  runtime supplies the effectful primitives (`IO.println`, file IO, `IO.Ref`,
  `ST`, randomness, time, `IO.Process`, …) as hand-written TS in
  `typelean_rt.ts`, keyed by the Lean constant name / `@[extern]` symbol. See §9.
* **`Task`/`Thread`/concurrency** map onto JS promises/async or a cooperative
  scheduler in the runtime (later milestone); pure code is unaffected.

---

## 8. Quotients, `Decidable`, propositions

* **`Prop` & proofs** are erased (§4.2). A term whose type is a `Prop` carries no
  runtime information; if forced into a value position it becomes a runtime unit.
* **`Decidable p`** erases its embedded proof; `isTrue`/`isFalse` become a tagged
  boolean. `decide`, `Decidable.decide`, and `if h : p then …` translate to the
  runtime boolean test.
* **Quotients (`Quot`)** — `Quot.mk` is the identity on the underlying value at
  runtime; `Quot.lift f h` is `f` (the soundness proof `h` is erased). The
  runtime represents `Quot α r` values as the underlying `α` value. (`Quot.ind`
  is a proposition.)

---

## 9. Opaque / `@[extern]` / FFI primitives

Lean's library is full of constants implemented natively in C and marked
`@[extern "lean_…"]` (e.g. `Nat.add`, `String.append`, `Array.push`,
`IO.println`). These have a Lean reference definition *and* a native impl; `#eval`
uses the native one. typelean maintains a **runtime primitive table**: a mapping
from Lean constant name (and/or `@[extern]` symbol, read via
`Lean.getExternConst?` / the `externAttr`) to a TS implementation in
`typelean_rt.ts`. When Lower sees a call to such a constant, Emit references the
runtime primitive instead of the (possibly slow or proof-laden) Lean definition.
Constants *without* a runtime primitive fall back to compiling their Lean body.
The set of required primitives grows per stdlib milestone (M5) and any unmapped
extern is a tracked gap, never a silent failure.

---

## 10. Universes

Universe levels (`Sort u`, `Type u`, `Prop = Sort 0`) are purely static: they
exist to keep the type theory consistent and have **zero runtime content**.
Universe-polymorphic definitions are not specialized per level for execution;
typelean simply **erases all level information** during Lower. Two universe
instantiations of the same polymorphic constant share one runtime binding.

---

## 11. Runtime strategy (`runtime/typelean_rt.ts`)

A single hand-written TypeScript module implementing Lean's value model and
primitive operations. Emitted code imports it. Fidelity to `#eval` is defined by
this file.

* **`Nat`** ⇒ `bigint` (unbounded). All `Nat` ops via runtime helpers with
  Lean's truncating subtraction (`n - m = 0` when `m > n`), `Nat.div`/`mod`
  rounding toward zero with `x / 0 = 0`, etc.
* **`Int`** ⇒ `bigint`; ops follow Lean's `Int.div`/`Int.mod` conventions
  (T-division semantics as Lean defines them).
* **`UInt8/16/32/64`, `USize`** ⇒ `bigint`/`number` with explicit modular
  wrap-around at the type's width.
* **`Float`** ⇒ JS `number` (IEEE-754 double), matching Lean's `Float`.
* **`Char`** ⇒ Unicode scalar value (a `number` code point), with validity
  invariants.
* **`String`** ⇒ a wrapper over a JS string but with **codepoint semantics**:
  Lean `String` is a sequence of `Char` (Unicode scalar values); `String.length`
  counts code points (not UTF-16 units), and positions (`String.Pos`) are
  **byte offsets into UTF-8**. The runtime must reproduce these (length, `get`,
  `next`, `Substring`) exactly, since they are observable via `#eval`. This is a
  known fidelity hazard and gets dedicated tests.
* **Constructors** ⇒ `{ tag: number, fields: any[] }` (or specialized classes
  for hot types). Helper `_rt.ctor(tag, fields)`.
* **Projection / `casesOn`** ⇒ field access + `switch (v.tag)`.
* **Closures** ⇒ JS functions; partial application via currying or an arity-aware
  `_rt.app`/`_rt.curry` to match Lean's saturation.
* **`Thunk α`** ⇒ memoizing closure (Lean `Thunk` is explicit, lazy, cached).
  Lean evaluation is otherwise **strict / call-by-value**, matching JS.
* **`Array α`** ⇒ JS array; ops (`push`, `get!`, `set!`, `mapM`) via runtime
  helpers with Lean's bounds/panic behavior.
* **`IO`** ⇒ thunk `() => α` run by the driver; `IO.Error` ⇒ thrown runtime
  error / `Except`-tagged value; `IO.Ref`/`ST.Ref` ⇒ mutable cell objects.
* **Panics / partial functions** (`panic!`, `get!` out of bounds,
  `Nat.toUInt`…overflow) ⇒ runtime behavior mirroring Lean (`panic` prints to
  stderr and returns the `Inhabited` default, as Lean's runtime does).
* **Equality / hashing** ⇒ structural `_rt.beq`/`_rt.hash` for `BEq`/`Hashable`
  default derivations where needed (most are user `deriving` and lower as data).
* **Deep recursion / TCO** ⇒ JS engines do not guarantee tail-call elimination.
  The runtime provides a trampoline and Lower/Emit mark self-tail-recursive
  functions to use a loop, avoiding stack overflow on programs Lean runs fine.

The runtime is **owned by the `typelean-emit` subtask initially** and grows with
each stdlib milestone; new primitives are added alongside the emit changes that
need them.

---

## 12. Compatibility & fidelity testing

"Perfect compatibility" is verified empirically by a **parity harness** (M6):

1. A corpus of Lean programs (from trivial `#eval (1+1)` up to stdlib-heavy
   code) under `tests/fidelity/`.
2. For each, capture Lean's result: `lake env lean prog.lean` / `#eval` output.
3. Compile with typelean ⇒ `prog.ts`, run under Node: `node prog.ts`.
4. Diff the two; any mismatch is a fidelity bug ⇒ a tracked subtask.
5. The corpus is grow-only; every fixed bug adds a regression case.

Per-stage unit tests live next to each module (Lower term-by-term, Emit
golden-output snapshots, Frontend "elaborates and counts constants").

---

## 13. Module map (current)

| File | Stage | Owner subtask |
|---|---|---|
| `Typelean/Basic.lean` | shared types (`CompileError`, `CompileM`) | spark |
| `Typelean/IR.lean` | the IR datatype | `typelean-ir` |
| `Typelean/Frontend.lean` | source → `Environment` via `Lean.Elab` | `typelean-frontend` |
| `Typelean/Lower.lean` | `Expr` → IR (erasure, recursors) | `typelean-lower` |
| `Typelean/Emit.lean` + `runtime/typelean_rt.ts` | IR → TS + runtime | `typelean-emit` |
| `Typelean/Pipeline.lean`, `Main.lean` | end-to-end wiring + CLI | `typelean-integrate-m1` |

See `ROADMAP.md` for milestones and `PROTOCOL.md` for the autopoiesis protocol
that governs how this graph fans out.
