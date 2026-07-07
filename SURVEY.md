# Survey: similar projects — Lean 4 compilers/translators to other targets, and adjacent verified-compiler work

> Research deliverable for **typelean** — a Lean 4 → TypeScript compiler written
> in Lean 4 that targets *perfect* Lean 4 compatibility by reusing `Lean.Elab`
> and emitting untyped code against a hand-written runtime reproducing Lean's
> value semantics (erasing types/proofs/universes). See `DESIGN.md` (§2 LCNF
> alternative, §4 erasure, §4.4 runtime value model, §11 runtime, §12 fidelity)
> and `OPPORTUNITIES.md` (§0 thesis, §1 strategic crux) for the internal framing.
> This document is **external prior art**, not internal design. Read-only
> research; no `Typelean/*.lean`, `DESIGN.md`, or `ROADMAP.md` were modified.

---

## 0. Executive summary

The table below lists every relevant project/work found. "Source→Target"
gives the compilation direction; "Status" is the project's maturity;
"Key technique" is what is transferable to typelean; "Relevance" is the
specific lesson for typelean. Permalinks are GitHub commit/tree URLs or arXiv
IDs where available.

| # | Project | Source→Target | Status | Key technique | Relevance to typelean | Permalink |
|---|---|---|---|---|---|---|
| 1 | **Lean 4 native compiler (official)** | Lean `Expr`→LCNF→IR→C/LLVM | Production | LCNF erasure (`lcErased`), 2-phase (base/mono) passes, `@[extern]`, `shouldGenerateCode` skips Prop/Sort | The reference backend; typelean's §2 "lower from LCNF" alt. inherits Lean's exact erasure for free | https://github.com/leanprover/lean4/blob/4c5e3d73/src/Lean/Compiler/LCNF/Passes.lean |
| 2 | **jroesch/lean.js** | Lean IR→JavaScript | Prototype ("rough", unmerged branch) | Reuses Lean's `backend` API; ships a JS runtime replacing the C++ VM | Closest direct precedent: Lean IR→JS + hand-written runtime = almost typelean's thesis, but target is JS (untyped) and never productized | https://github.com/jroesch/lean.js |
| 3 | **T-Brick/lean2wasm** | Lean→C→emcc→WASM | Prototype | Toolchain wrapper: reuses Lean's C codegen + Emscripten | Shows the "no new backend, just retarget C" route; **not** a native WASM backend — a shortcut typelean deliberately does *not* take | https://github.com/T-Brick/lean2wasm/blob/main/Lean2Wasm.lean |
| 4 | **sdiehl/lean4 (Rust backend fork)** | Lean→Rust | Experimental fork | Fork adding a `backend := .rust` codegen | Another "new backend on Lean's IR" experiment; evidence the IR is the natural hook point | https://github.com/sdiehl/lean4 |
| 5 | **Lean 4 LLVM backend (PR #1837)** | Lean IR→LLVM | WIP/PR | LLVM bindings from Lean; `compiler.target`/`compiler.runtime` cross-compile options (also in `dennj/solana-lean`) | Confirms Lean exposes a pluggable-backend story; typelean is a new backend in the same spirit, target TS | https://github.com/leanprover/lean4/pull/1837 |
| 6 | **Lean Emscripten/WASM build** | Lean (the compiler)→JS/WASM | Production (web editor, `lean4game`) | Emscripten of the *whole* Lean binary | Not a compiler of Lean *programs* — it runs Lean in the browser. Baseline for "Lean in JS" infra typelean does *not* need | https://github.com/leanprover/lean4/pull/505 |
| 7 | **Zulip "JS backend" design thread** | Lean→JS (proposed `EmitJs.lean`) | Design only | `EmitJs.lean` ≅ `IR.EmitC`; `lean.mjs` ≅ `lean.h` for `@[extern]` | Independent articulation of typelean's exact architecture (EmitC→EmitJs + runtime) by the community — strong validation the design is the obvious one | https://leanprover-community.github.io/archive/stream/270676-lean4/topic/Ideas.20about.20a.20JS.20backend.html |
| 8 | **kiranandcode/lean.py (LeanPy)** | Lean↔Python | Prototype | `@[python "name"]` + `derive_python`; CPython via `dlopen`; kernel facade | Lean→Python *interop* via annotated extraction — adjacent; marshalling + inductive-as-foreign-constructors is a typelean-relevant technique | https://github.com/kiranandcode/lean.py |
| 9 | **lp2 (LP²)** | Lean↔Python (bidirectional) | Prototype (PyPI) | Source-level transpiler both directions | Surface-level bidirectional transpiler; lacks erasure/runtime-fidelity story — counterexample of "translate syntax not semantics" | https://pypi.org/project/lp2/ |
| 10 | **Coq extraction (Letouzey)** | Coq→OCaml/Haskell/Scheme | Production | `CIC_box` untyped IR; proof/type erasure; the canonical "erase & extract" | The historical template for typelean's erasure; extraction is in the TCB (unverified) | https://rocq-prover.org/doc/v8.10/refman/addendum/extraction.html |
| 11 | **MetaCoq certified erasure (λ☐)** | PCUIC→untyped λ☐ | Verified (Coq) | Machine-checked correctness of erasure to untyped CBV λ-calculus | The *verified* version of #10; exactly typelean's §4.2 erasure, with a proof. typelean's "prove Lower semantics-preserving" route (OPP §1a.2) is this idea | https://github.com/MetaCoq/metacoq/blob/coq-8.17/erasure/theories/ErasureCorrectness.v |
| 12 | **CertiCoq / CertiRocq** | Coq (Gallina)→C/WASM | Partially verified | ANF pipeline; verified λANF→λANF^C; WasmCert-Coq backend | Verified end-to-end compiler with erasure+ANF — the closest "verified sibling" of typelean's long-term ambition | https://github.com/CertiRocq/certirocq |
| 13 | **CakeML** | Standard ML→bytecode→ASM (6 archs) | Verified (HOL4) | Incremental ILs; currying/closure-conv/data-rep proofs; self-bootstrap | "Verified compiler for a strict functional lang to realistic targets" — typelean's faithful-runtime burden is CakeML's whole thesis | https://cakeml.org/jfp19.pdf |
| 14 | **F\* / KaRaMeL (KreMLin)** | Low\* F\*→C | Partially verified (paper proof) | Proof erasure at compile time; Low\* subset → C\* → C AST; HACL\*/EverCrypt | Deployed verified crypto→C; "prove high-level, erase proofs, emit low-level" = typelean's pattern at runtime-tier scale | https://github.com/FStarLang/karamel |
| 15 | **Isabelle/HOL code generator** | HOL→SML/OCaml/Haskell/Scala | Production | Equational theorems→code; dictionary-elimination for type classes; Mini-Haskell IR | "Turn specs into executable code" with a correctness argument; dictionary-passing erasure is directly relevant to typelean §6 | https://isabelle.in.tum.de/dist/Isabelle2025-2/doc/codegen.pdf |
| 16 | **Agda compilers (GHC + JS)** | Agda→Haskell; Agda→JS | Production | `@0`/`@erased` runtime-irrelevance; JS backend with its own RTS, "intentionally `Undefined`" erased primitives | Erasure annotations + a JS RTS with explicit erased-primitive table — typelean's `@[extern]` runtime table is the same shape | https://agda.readthedocs.io/en/latest/tools/compilers.html |
| 17 | **Idris 2 codegens** | Idris 2→Scheme/C/JS/RefC/Racket/Gambit | Production | Pluggable `Codegen` via `Idris.Driver.mainWithCodegens`; JS uses BigInt | The clearest "pluggable multi-backend from a dependently-typed lang" model; typelean is one such backend for Lean | https://idris2.readthedocs.io/en/latest/backends/ |
| 18 | **CompCert** | Clight→PowerPC/ARM/RISC-V/x86 ASM | Verified (Coq) | Per-pass forward-simulation; "observable behavior improves on" theorem | The canonical verified-compiler template (OPP §1a.2, Opportunity 8); typelean's "prove a subset, grow per milestone" is CompCert-style | https://github.com/AbsInt/CompCert/blob/master/driver/Compiler.v |
| 19 | **Lean4Lean** | (verifies Lean's own typechecker) | Research, runs on all mathlib | Reimplementation of Lean 4 kernel in Lean; first complete checker besides C++ ref | Closes one layer *under* typelean (verifies the *inputs* we compile), not the codegen — OPP §1a.3 is explicit about this limit | https://arxiv.org/abs/2403.14064 |
| 20 | **VerifiedJS (BasisResearch)** | JS (ECMA-2020)→WebAssembly | In-progress, verified-in-Lean | CompCert-style pass-wise semantic preservation in Lean 4; per-IL Syntax/Semantics/Interp/Print | A *verified compiler written in Lean 4* — typelean's nearest "neighbor" on the method axis (Lean-4-implemented, CompCert-style), though opposite source/target | https://github.com/BasisResearch/VerifiedJS |
| 21 | **Proof-carrying code (Necula)** | untrusted code + safety proof | Foundational | Code producer ships a proof the receiver checks | The intellectual ancestor of "verified Lean → deployable target"; frames *why* the runtime fidelity wall (OPP §1a.4) is the load-bearing condition | https://dl.acm.org/doi/10.1145/263699.263712 |

Adjacent / opposite-direction (compile *into* Lean, or Lean-as-data) noted but
not primary: `jessealama/thales` (TypeScript→Lean 4, https://github.com/jessealama/thales),
`lidangzzz/Lean4-ts` (a Lean-4 lexer/parser/evaluator *in* TypeScript, https://github.com/lidangzzz/Lean4-ts),
`spolu/jscore` (annotated TS→Lean proofs, https://github.com/spolu/jscore),
`brettkoonce/lean4-mlir` (Lean→StableHLO MLIR, niche, https://github.com/brettkoonce/lean4-mlir).

---

## 1. Research questions answered

### RQ1 — Lean 4 (and Lean 3) → &lt;target&gt; compilers/translators

**Lean has *one* official codegen path** — the native compiler: elaborated
`Expr` → **LCNF** (Lean Compiler Normal Form, an A-normal-form IR) → a `base`
phase (type-preserving: `simp`, `cse`, `specialize`, `findJoinPoints`) → a
`mono` phase (monomorphization via `toMono`, `lambdaLifting`, `elimDeadBranches`)
→ `IR.Decl` (closure conversion, boxing, RC) → **C** (or experimental **LLVM**).
Erasure is built into LCNF: proofs become `lcErased`, type-formers in
computational positions become `◾`, universes dropped in `mono`, and
`shouldGenerateCode` simply skips declarations whose type is a proposition or a
type former. `@[extern "lean_…"]` symbols are emitted as C calls into the Lean
runtime (`lean.h`). Lean does **not** ship a Coq/Isabelle-style "extraction to
OCaml/Haskell" command (the canonical route to runnable non-C code is the C
backend; community discussion confirms no built-in equivalent —
https://stackoverflow.com/q/74301506).

Every **third-party Lean→X** project hooks this same pipeline at one of three
points:

- **Hook the IR / backend API (closest to typelean).** `jroesch/lean.js`
  (Jared Roesch, a Lean team member) implements a compiler "from Lean's internal
  IR to JavaScript" using Lean's `backend` API, paired with an npm `runtime/`
  package that "replaces the VM implemented in C++." This is *almost exactly*
  typelean's thesis — IR→JS + hand-written runtime — but it is an early
  prototype ("I just started to put this together in the last couple days; rough
  state"), target is plain JS (not TS), it requires an *unmerged* Lean branch
  (`jroesch/lean/tree/direct-calls`), and it was never productized. The
  community design thread on Zulip independently proposes the same shape:
  implement `EmitJs.lean` "counterpart to `Lean.Compiler.IR.EmitC`" plus
  `lean.mjs` "(`~lean.h`) for all those `@[extern] opaque` definitions," compiling
  each `*.lean` to `*.mjs`. typelean's architecture is the converged design the
  community already identified as obvious — but typelean's distinguishing
  decisions are (a) **target TypeScript**, (b) **reuse `Lean.Elab` from source
  text** (not just IR), and (c) make **perfect-fidelity runtime** the
  first-class goal with a parity harness.

- **Retarget the C output (shortcut).** `T-Brick/lean2wasm` does *not* implement
  a WASM backend; it downloads a `wasm32` Lean toolchain, collects the `.c` files
  Lean already emitted (via the import graph), and feeds them to `emcc` with
  `-lInit -lLean -lleancpp -lleanrt`. This is the "Lean itself in WASM via
  Emscripten" route (also `leanprover/lean4#505`, `#2855`), which produces a
  *whole Lean runtime* blob, not Lean-program-as-first-class-WASM. typelean
  deliberately rejects this: it wants *Lean programs* to become ordinary TS, not
  to ship a C runtime in the browser.

- **Add a new native backend (fork).** `sdiehl/lean4` is an "experimental fork
  of the Lean 4 compiler to add a Rust backend" (`backend := .rust`); the
  official `leanprover/lean4#1837` "LLVM Backend" PR and `dennj/solana-lean`
  (cross-compilation LLVM backend with `compiler.target`/`compiler.runtime`)
  extend the same backend API. These confirm Lean is *designed* to accept new
  backends — typelean is best understood as a new backend whose "machine" is the
  TS/JS runtime, except typelean compiles from post-elaboration `Expr` (M1) with
  the option to switch to LCNF later (`DESIGN.md` §2).

- **Source-level transpilation / interop (weaker).** `kiranandcode/lean.py`
  (LeanPy) annotates a Lean definition with `@[python "name"]` and marshals to
  CPython via `dlopen`, with `derive_python` exposing inductives/structures as
  Python constructors; `lp2` is a bidirectional Lean↔Python *source*
  transpiler. Both treat Lean as a surface language and hand marshalling; they
  do **not** address erasure or runtime fidelity — the precise gap typelean
  fills. (A Medium post claiming a "Lean 4 → OCaml extraction pipeline" by
  Pablo Nogueira Grossi was found but is not backed by a verifiable repo/release
  and is treated as unreliable.)

**Lean 3** had a different (C++-VM, less pluggable) compilation story and a
separate `lean.js` Emscripten port (`leanprover/lean.js`); the modern,
backend-API-extensible story is Lean 4 only.

### RQ2 — How third-party projects relate to Lean's official backend

Three relationships, in order of fidelity to typelean's "perfect compatibility":

1. **Lower from `Lean.Expr` post-elaboration (typelean M1 choice).** Reuse
   `Lean.Elab` (`Frontend.runFrontend`) so the compiled input is the *same*
   core term Lean produces; do erasure yourself (type-directed via
   `Meta.isProp`, `Meta.whnf`). This is the smallest surface and the M1 plan
   (`DESIGN.md` §2, §4.2). Risk: erasure must match Lean's notion of relevance
   exactly — the Tier-1 hazard (`OPPORTUNITIES.md` §1a).
2. **Lower from `Lean.Compiler.LCNF`** (typelean long-term alt). Hook the
   `@[cpass]` phases / `Lean.Compiler.compile` and consume LCNF `Decl`s after
   `toLCNF` has already erased proofs to `lcErased`, eta-expanded, and (after
   `toMono`) monomorphized. This *inherits Lean's exact erasure decisions for
   free* and shrinks the trusted Lower to "Lean is correct" — the strongest
   practical route per OPP §1a.3. `jroesch/lean.js` sits here (it consumes the
   IR, one stage past LCNF); typelean's IR is *designed to be a valid target for
   either* source.
3. **Reuse only the C output** (lean2wasm, Emscripten). Inherits *everything*
   including the C runtime — maximum fidelity to `#eval` but at the cost of
   shipping a C/Lean runtime blob. typelean explicitly trades this away to get
   first-class TS.

### RQ3 — Adjacent verified/proof-carrying compilers that erase types/proofs and emit to an untyped target with a faithful runtime

This is typelean's exact thesis (erasure + faithful runtime, `DESIGN.md` §4.2
erasure, §4.4 value model, §11 runtime):

- **Coq extraction (Letouzey, production).** Coq → OCaml/Haskell/Scheme via the
  untyped intermediate `CIC_box`: proofs and types are erased, only the
  computational core remains. This is the *historical template* for typelean's
  erasure. Crucially, **the extraction process is itself in the TCB**
  (unverified) — which is precisely the gap MetaCoq and typelean's "prove a
  subset" route (OPP §1a.2) try to close.

- **MetaCoq certified erasure (λ☐, verified in Coq).** A complete, machine-checked
  specification of Coq's extraction: PCUIC → untyped call-by-value λ-calculus
  `λ☐` (with a `tBox` for erased terms), with an `ErasureCorrectness` theorem
  relating erased evaluation back to source evaluation. This is *exactly*
  typelean's §4.2 erasure, *with the proof typelean plans to grow per milestone*
  (OPP §1a.2). It is the single most directly relevant prior-art result.

- **CertiCoq / CertiRocq (partially verified, Coq).** A compiler for Gallina →
  Clight (→ CompCert) and, newly, → WebAssembly (CertiCoq-Wasm, CPP 2025,
  mechanized against WasmCert-Coq). It uses an ANF λ-calculus pipeline with
  verified closure-conversion optimizations. This is the closest *verified
  end-to-end sibling* of typelean's long-term ambition — same shape (dependently
  typed source → erasure → untyped functional IR → low-level target), just
  Coq→C/WASM instead of Lean→TS, and with a heavier proof burden.

- **CakeML (verified in HOL4).** "The most realistic verified compiler for a
  functional programming language to date" — Standard ML → bytecode → machine
  code for 6 architectures, with incremental ILs and per-pass correctness
  proofs, including verified currying, closure conversion, configurable data
  representations, exceptions, GC, and a self-bootstrap. CakeML's *entire*
  contribution — a verified compiler whose correctness rests on a faithful
  runtime/semantics model — is typelean's runtime-fidelity wall (OPP §1a.4,
  §5) at full scale. typelean's runtime hazards (`Nat` truncating `-`,
  `String` codepoint/UTF-8 `Pos`, TCO/trampoline) are CakeML-style "the runtime
  *is* the load-bearing proof obligation" problems.

- **F\* / KaRaMeL (KreMLin), partially verified.** Low\* F\* → readable C.
  Proofs are erased at compile time, leaving low-level code; the compilation is
  argued correct on paper (not fully mechanized) and *deployed* (HACL\*/EverCrypt
  in Firefox NSS, miTLS). This is the "prove high-level, erase proofs, emit
  low-level, ship to production" pattern at runtime-tier scale — the strongest
  real-world evidence that the erasure-and-ship model works (and that the
  *compiler/runtime*, not the per-program proof, is the trust bottleneck).

- **Isabelle/HOL code generator (production).** HOL specifications → SML/OCaml/
  Haskell/Scala, with correctness established by giving the intermediate
  "Mini-Haskell" an equational semantics and relating it back to the logic,
  plus a *dictionary-based translation eliminating type classes* (proved
  correct). The dictionary-elimination is directly relevant to typelean §6:
  typelean gets dictionaries "for free" post-elaboration, but Isabelle shows
  the *correctness* of treating class dictionaries as ordinary data.

- **Agda (GHC + JS backends, production).** Agda → Haskell (GHC) and → JS. From
  v2.6.1 Agda has `@0`/`@erased` *runtime-irrelevance* annotations enforced by
  the typechecker, and the JS backend ships its own RTS with primitives
  "intentionally compiled to `Undefined` … because they are erased, type-level
  only, or implemented in Agda." This is structurally identical to typelean's
  `@[extern]`→runtime-primitive table (`DESIGN.md` §9, §11): an explicit map of
  which constants are erased vs. runtime-implemented. The Agda JS backend even
  hit the exact bug class typelean fears — "mapping a function that returns `Set`
  fails" (issue #3545, erasure of a type-returning function) — a concrete
  gotcha to learn from.

- **Idris 2 (5+ codegens, production).** Idris 2 → Scheme (default), C, JS/node,
  RefC (C with refcounting), Racket, Gambit, via `Idris.Driver.mainWithCodegens`.
  The JS codegen uses BigInt (matching typelean's `Nat` ⇒ `bigint`). Idris 2 is
  the clearest existence proof that a dependently-typed language can have many
  pluggable, faithful backends including JS — typelean is "one such backend for
  Lean," with the added fidelity-harness discipline.

- **CompCert (verified in Coq).** Clight → assembly, each pass proved by
  forward simulation; "the observable behavior of C improves on one of the
  allowed behaviors of S." This is the canonical verified-compiler template
  typelean's roadmap explicitly adopts (OPP §1a.2 "CompCert-style: prove the
  kernel, test the rest"; Opportunity 8 "CompCert's pattern retargeted through
  typelean"). typelean's "prove a simulation theorem for the M1 surface, grow
  per milestone" is CompCert's strategy applied to *erasure + Emit + runtime*
  rather than to C optimization passes.

- **Lean4Lean (research, arXiv 2403.14064).** A reimplementation of the Lean 4
  typechecker *in Lean*, the first complete checker besides the C++ reference,
  competitive (20–50% slower) and able to check all of mathlib. It closes the
  layer *under* typelean: it verifies the *inputs* (that the `Expr` we lower is
  well-typed), not the *codegen*. OPP §1a.3 is explicit that Lean4Lean
  "underwrites checking our inputs, not compiling them" — a useful foundation,
  not a substitute for typelean's own Lower/Emit/runtime correctness.

### RQ4 — "Verified Lean → JS/TS" precedents and evidence for/against the proof-over-testing thesis

**No prior project markets "verified Lean → JS/TS."** The closest things:

- **jroesch/lean.js + the Zulip JS-backend thread** establish the *architecture*
  (IR→JS + runtime) as the obvious one, but neither is verified nor claims
  proof-over-testing.
- **VerifiedJS** is the strongest *method* precedent: a **verified compiler
  written in Lean 4** with CompCert-style per-pass semantic-preservation proofs,
  `Syntax`/`Semantics`/`Interp`/`Print` per IL, and an end-to-end theorem — but
  it compiles *JS→WASM*, the opposite direction. Its existence is evidence
  that (a) Lean 4 is a viable host for verified-compiler development at scale,
  (b) the CompCert pass-prove-compose methodology ports to Lean, and (c) the
  "Linux-kernel moment" ambition (VerifiedJS targets compiling `tsc` itself)
  is culturally live. typelean and VerifiedJS are dual neighbors: same host
  (Lean 4), same method (CompCert-style verified passes), opposite
  source/target (Lean→TS vs JS→WASM).
- **F\*/KaRaMeL (EverCrypt, miTLS)** and **CompCert** are the deployed evidence
  *for* the thesis that verified-source + verified/audited-compiler substitutes
  for testing at scale. **AWS Encryption SDK (Dafny→.NET)** (cited in OPP) is the
  cleanest "verified-in-Dafny, compiled to a deployable target, shipped in
  production" showcase.
- The **against** evidence is the recurring *trust-transfer* gap, echoed in
  every prior art: Coq extraction is unverified (MetaCoq's whole motivation);
  KaRaMeL's compilation is only paper-proven; and CakeML's scale shows the
  runtime/semantics model *is* the cost. typelean's OPP §1 strategic crux —
  "a proof guarantees the *Lean* program; for that guarantee to reach the TS,
  typelean itself must be trusted to preserve semantics" — is exactly the gap
  these projects live at. There is **no precedent that refutes** the thesis;
  there is strong precedent that the *compiler/runtime*, not the per-program
  proof, is the bottleneck.

### RQ5 — Technical techniques shared with typelean, and gotchas

| Technique | Who does it | typelean lesson |
|---|---|---|
| **Reuse the host elaborator** | typelean (`Lean.Elab`); Coq (Gallina is native); Isabelle (HOL is the logic); Agda/Idris (own elaborator) | typelean is unusual in reusing *Lean's* elaborator to compile *Lean*; CakeML does *not* reuse an elaborator (separate typechecker). The payoff (§6: classes/coercions gone post-elab) is real but the elaborator API shifts between Lean releases — `jroesch/lean.js` needed an unmerged branch. |
| **de Bruijn / fvar handling** | Lean LCNF (`FVarId`, `binderRenaming`, `LCtx`); Coq/MetaCoq (de Bruijn lift/subst); CakeML | Use fresh hygienic names in the IR (typelean §4.1 `IR.Expr.var`); Lean LCNF's `CompilerM` substitution machinery is the model. |
| **Type-class / coercion erasure** | Isabelle (dictionary translation, *proved correct*); typelean (free post-elab, §6); Agda (`@erased`) | typelean gets this for free; Isabelle is the reference for *why* it's correct (dictionaries = ordinary data). |
| **Recursor / `casesOn` / `brecOn` lowering** | Lean LCNF special-cases `casesOn`, `Quot.lift`, `Eq.rec` (ToLCNF L557–747); `toMono` rewrites `cases` on `Nat`/`Int`/`UInt`/`Array`/`String` | typelean §4.3 must mirror LCNF's special-casing; **the `toMono` rewrite of `cases (s:String)` to `cases (String.toList s)` is a concrete fidelity gotcha** — if typelean's `String` runtime isn't faithful, pattern-match-on-`String` silently diverges. |
| **Arbitrary-precision `Nat`** | Idris 2 JS (BigInt); Lean (GMP, then C); typelean (`bigint`) | `bigint` is the consensus; Lean's *truncating* `Nat.sub` and `x/0=0` are the hazard (OPP §1a) — Idris/JS's BigInt gives exact arithmetic but typelean must add the Lean-specific truncation on top. |
| **Unicode `String`/`Char` codepoint + UTF-8 `Pos`** | Lean (its own stdlib proves UTF-8 inversion, `Init.Data.String.Decode`); Agda JS (its own RTS strings); `smoothutf8` (verified Rust) | This is typelean's *showcase* hazard (OPP Opportunity 4). No prior Lean→JS backend documents solving it — typelean would be first. Learn from Agda's JS-RTS string handling and Lean's own `toMono` `String`→`List Char` lowering. |
| **TCO / trampoline** | Lean LCNF `findJoinPoints` (tail `fun`→`jp`→direct jump in C); CakeML (verified tail-call handling); typelean (trampoline, §11) | JS has no guaranteed TCO; Lean's join-point pass is the model for *recognizing* tail recursion, and a trampoline is the model for *implementing* it. CakeML verifies this; typelean must at least pin it with the fidelity harness. |
| **IO as thunks / trusted shell** | Lean (`IO` = world-token function); F\* (effects as a monadic boundary); Verdi (prove core, trust driver); typelean (§7 thunk `() => α`) | The "prove the core, keep IO a thin trusted shell" discipline (OPP §1c) is the universal pattern in verified-systems work (Verdi, IronFleet, Everest). |
| **Erasure-correctness proof** | MetaCoq `ErasureCorrectness.v`; CakeML (per-pass); CompCert (per-pass) | typelean's OPP §1a.2 route — grow a proven subset per milestone — is MetaCoq's `λ☐` correctness theorem applied incrementally. |

---

## 2. Synthesis — where typelean sits

**typelean's position in the landscape.** typelean is a *new backend for the
Lean 4 compiler* whose "machine" is a hand-written TypeScript runtime, compiling
from post-elaboration `Lean.Expr` (with an LCNF-lowering option for fidelity),
erasing types/proofs/universes, and proving/per-testing that the runtime
reproduces Lean's `#eval` semantics. Concretely it combines:

- the **architecture** the Lean community already identified as obvious
  (`jroesch/lean.js`, the Zulip `EmitJs.lean` thread) — IR/backend → JS + a
  runtime replacing the C++ VM;
- the **erasure model** of Coq extraction / MetaCoq `λ☐` (erase proofs &
  types, keep the untyped computational core), with typelean's novelty of doing
  it for *Lean* and targeting *TS*;
- the **runtime-as-proof-obligation** discipline of CakeML and the
  trust-transfer framing of OPP §1a.4; and
- the **CompCert-style "prove the kernel, test the rest"** roadmap (OPP §1a.2,
  Opportunity 8), with VerifiedJS as the existence proof that Lean 4 hosts
  such verified-compiler work well.

**What is genuinely novel vs. known.**

- *Novel:* (a) a **Lean 4 → TypeScript** compiler with **perfect-compatibility**
  intent and a **parity harness** (`lean ≟ node`) as the empirical floor — no
  prior project targets TS or makes fidelity a first-class measured property;
  (b) the explicit **proof-over-testing** catalog (OPPORTUNITIES.md) tying
  verified Lean programs to deployable TS — no Lean→JS project frames this;
  (c) lowering **from `Lean.Elab` source text** (not just IR) so tactics,
  `deriving`, and macros are "lowered as ordinary `Expr`" (M3) — `jroesch/lean.js`
  hooks the IR, one stage later.
- *Known / heavily precedented:* erasure of proofs & types (Coq/MetaCoq/Agda);
  a JS backend with an explicit erased-primitive table (Agda, Idris 2); a
  pluggable backend for a dependently-typed language (Idris 2, Lean's own
  backend API); CompCert-style grow-the-proven-subset verification; the
  "prove core, trust IO shell" discipline (Verdi/Everest/IronFleet).

**Strongest prior-art "neighbors" to cite** in future typelean docs/papers:

1. **MetaCoq certified erasure (λ☐)** — cite for *verified erasure correctness*;
   typelean's planned Lower-correctness theorem is `λ☐` for Lean.
2. **CertiCoq/CertiRocq** — cite as the *verified end-to-end sibling*
   (Coq→C/WASM with ANF + erasure) and the closest comparable scope.
3. **CakeML** — cite for *the runtime-as-proof-obligation* thesis at scale.
4. **Coq extraction (Letouzey)** — cite as the *historical erasure template*
   and the caution that extraction is in the TCB.
5. **jroesch/lean.js + the Zulip JS-backend thread** — cite as the
   *direct architectural precedent* (Lean IR→JS + runtime), establishing the
   design is the obvious one and that typelean's contributions are the *target
   (TS), the fidelity harness, and the proof-over-testing framing* — not the
   architecture itself.
6. **F\*/KaRaMeL + CompCert** — cite as *deployed* evidence for the
   proof-over-testing thesis and the CompCert roadmap pattern.
7. **Agda JS backend + Idris 2 codegens** — cite for the
   *erased-primitive-table / pluggable-backend* engineering reality and the
   `String`-erasure gotcha to avoid.
8. **Lean4Lean** — cite as the *foundational under-layer* (verifies Lean's
   inputs), with the honest limit that it does not verify codegen.
9. **VerifiedJS** — cite as the *method neighbor*: a verified compiler
   *written in Lean 4*, CompCert-style, proving Lean 4 is a viable host for
   this kind of work.

**Honest gaps this survey exposes for typelean.** (i) No prior Lean→JS/TS
backend has *solved* the Tier-1 `String`/UTF-8 `Pos` fidelity hazard — typelean
would be first; treat it as the flagship risk. (ii) `jroesch/lean.js`'s need
for an unmerged Lean branch is a warning that the backend API shifts — typelean's
M1 choice to lower from `Expr` (smaller, more stable surface) is well-motivated,
and the LCNF route should be revisited per release. (iii) The trust-transfer
gap (OPP §1) is the *lived experience* of every adjacent project; typelean's
differentiator must be the runtime + harness + (eventually) the proven subset,
not the architecture.

---

## 3. References (perma/arXiv links)

- Lean 4 compiler (LCNF/IR/C): https://github.com/leanprover/lean4/blob/4c5e3d73/src/Lean/Compiler/LCNF/Passes.lean · `Main.lean` https://github.com/leanprover/lean4/blob/4c5e3d73/src/Lean/Compiler/LCNF/Main.lean · `IR/EmitC.lean` https://github.com/leanprover/lean4/blob/f6b6b36f47909fe8a089c16efdb87372154e7efa/src/Lean/Compiler/IR/EmitC.lean · backend overview https://deepwiki.com/leanprover/lean4/6-compiler-backend · Lean 4 paper https://lean-lang.org/papers/lean4.pdf
- jroesch/lean.js: https://github.com/jroesch/lean.js
- T-Brick/lean2wasm: https://github.com/T-Brick/lean2wasm · source https://github.com/T-Brick/lean2wasm/blob/main/Lean2Wasm.lean
- sdiehl/lean4 (Rust backend): https://github.com/sdiehl/lean4
- Lean LLVM backend PR: https://github.com/leanprover/lean4/pull/1837 · LLVM bindings https://github.com/leanprover/lean4/blob/3dc1a088b6d2d8eafe25a7cd7ec7b58d731bd7cc/src/Lean/Compiler/IR/LLVMBindings.lean · `dennj/solana-lean` https://github.com/dennj/solana-lean
- Lean Emscripten/WASM: https://github.com/leanprover/lean4/pull/505 · release wasm https://github.com/leanprover/lean4/pull/2855 · `leanprover/lean.js` https://github.com/leanprover/lean.js · `lean-client-js` https://github.com/leanprover/lean-client-js
- Zulip "JS backend" design thread: https://leanprover-community.github.io/archive/stream/270676-lean4/topic/Ideas.20about.20a.20JS.20backend.html · codegen state https://leanprover-community.github.io/archive/stream/270676-lean4/topic/The.20state.20of.20the.20code.20generator.html
- kiranandcode/lean.py (LeanPy): https://github.com/kiranandcode/lean.py
- lp2 (LP²): https://pypi.org/project/lp2/
- jessealama/thales (TS→Lean): https://github.com/jessealama/thales
- lidangzzz/Lean4-ts: https://github.com/lidangzzz/Lean4-ts
- spolu/jscore: https://github.com/spolu/jscore
- brettkoonce/lean4-mlir: https://github.com/brettkoonce/lean4-mlir
- Coq extraction: manual https://rocq-prover.org/doc/v8.10/refman/addendum/extraction.html · wiki https://github.com/coq/coq/wiki/Extraction
- MetaCoq certified erasure: `ErasureCorrectness.v` https://github.com/MetaCoq/metacoq/blob/coq-8.17/erasure/theories/ErasureCorrectness.v · erasure README https://github.com/MetaCoq/metacoq/blob/coq-8.16/erasure/theories/README.md · plugin https://rocq-prover.org/p/coq-metacoq-erasure-plugin/latest · JFLA 2024 https://sozeau.gitlabpages.inria.fr/www/research/publications/MetaCoq_and_Certified_Extraction-JFLA24-310124.pdf · "Extracting functional programs from Coq, in Coq" https://doi.org/10.1017/s0956796822000077 · Verified extraction from Coq to OCaml https://doi.org/10.1145/3656379 · λ☐ intermediate lang https://types22.inria.fr/files/2022/06/TYPES_2022_paper_67.pdf
- CertiCoq/CertiRocq: https://certicoq.org/ · repo https://github.com/CertiRocq/certirocq · pipeline wiki https://github.com/certirocq/certirocq/wiki/The-CertiRocq-pipeline · CertiCoq-Wasm (CPP 2025) https://doi.org/10.1145/3703595.3705879 · paper https://womeier.de/files/certicoqwasm-cpp25-paper.pdf · coqpl https://www.cs.princeton.edu/~appel/papers/certicoq-coqpl.pdf · compositional optimizations https://johnm.li/compositional-optimizations-for-certicoq.pdf
- CakeML: backend (JFP) https://cakeml.org/jfp19.pdf · multi-target (CPP'17) https://cakeml.org/cpp17.pdf · new backend (ICFP'16) https://cakeml.org/icfp16.pdf · verified impl (POPL'14) https://cakeml.org/popl14.pdf · repo https://github.com/CakeML/cakeml · backend README https://github.com/CakeML/cakeml/blob/master/compiler/backend/README.md · efficient function calls https://dl.acm.org/doi/10.1145/3110262
- F\*/KaRaMeL (KreMLin): repo https://github.com/FStarLang/karamel · intro https://fstarlang.github.io/general/2016/09/30/introducing-kremlin.html · Low\* manual https://fstarlang.github.io/lowstar/html/Introduction.html · DESIGN https://github.com/FStarLang/karamel/blob/master/DESIGN.md · F\*→C progress https://people.csail.mit.edu/wangpeng/fstar-to-c.pdf · https://jonathan.protzenko.fr/papers/ml16.pdf · erasure tips https://github.com/FStarLang/FStar/wiki/Tips-for-extraction-with-polymorphism-and-erasure
- Isabelle/HOL code generator: tutorial https://isabelle.in.tum.de/dist/Isabelle2025-2/doc/codegen.pdf · HOL↔Haskell https://isabelle.in.tum.de/~haftmann/pdf/from_hol_to_haskell_haftmann.pdf · framework (TPHOLs'07) https://es.cs.rptu.de/events/TPHOLs-2007/proceedings/B-128.pdf · HRS codegen https://isabelle.in.tum.de/~haftmann/pdf/code_generation_haftmann_nipkow.pdf
- Agda compilers: docs https://agda.readthedocs.io/en/latest/tools/compilers.html · runtime irrelevance https://agda.readthedocs.io/en/stable/language/runtime-irrelevance.html · JS backend module https://agda.github.io/agda/Agda-Compiler-JS-Compiler.html · `String`-erasure bug https://github.com/agda/agda/issues/3545 · GHC ctor-erasure bug https://github.com/agda/agda/issues/3732
- Idris 2 codegens: overview https://idris2.readthedocs.io/en/latest/backends/ · JS/node https://idris2.readthedocs.io/en/latest/backends/javascript.html · RefC https://idris2.readthedocs.io/en/latest/backends/refc.html · custom backend cookbook https://idris2.readthedocs.io/en/latest/backends/backend-cookbook.html
- CompCert: manual https://compcert.org/man/manual.pdf · docs https://compcert.org/doc/ · CACM https://cacm.acm.org/research/formal-verification-of-a-realistic-compiler/ · realistic compiler https://xavierleroy.org/publi/compcert-CACM.pdf · back-end https://xavierleroy.org/publi/compcert-backend.pdf · `driver/Compiler.v` https://github.com/AbsInt/CompCert/blob/master/driver/Compiler.v
- Lean4Lean: arXiv 2403.14064 https://arxiv.org/abs/2403.14064 · HTML https://arxiv.org/html/2403.14064v3 · repo `digama0/lean4lean` https://github.com/digama0/lean4lean · slides https://cs.ru.nl/~freek/courses/mfocs-2024/slides/rutger.pdf · Lean Kernel Arena https://arena.lean-lang.org/checker/official/
- VerifiedJS: https://github.com/BasisResearch/VerifiedJS
- Proof-carrying code (Necula): https://dl.acm.org/doi/10.1145/263699.263712 · dissertation https://apps.dtic.mil/sti/tr/pdf/ADA363676.pdf
- Verified compilation of a purely functional language (CakeML-related, Kent): https://doi.org/10.22024/unikent/01.02.105396
- Type Theory with Erasure (Agda, presheaf model → untyped λ): https://cthe.me/erasure-sogat.pdf
- 2025 Coq extraction report (Lean/Coq comparison context): https://www.normalesup.org/~sdima/2025_extraction_report.pdf

---

## 4. Search queries used (evidence of GitHub/web survey)

Per the validation requirement, the queries that produced this survey:

1. `Lean 4 compiler to JavaScript TypeScript transpiler project`
2. `lean4js compile Lean 4 to JavaScript runtime`
3. `Lean to JavaScript transpiler github`
4. `lean4 typescript compiler code generator`
5. `Coq extraction to OCaml Haskell Scheme erasure mechanism proof erasure`
6. `CakeML verified compiler proof correctness ML to bytecode assembly`
7. `Fstar KreMLin extraction erasure F* to C compiler verified`
8. `Isabelle code generator code extraction to Haskell OCaml SML verified`
9. `Agda compiler backend JavaScript Haskell GHC compilation erasure of proofs`
10. `Idris 2 codegen scheme C JavaScript refC backend`
11. `CompCert verified C compiler Coq proof semantics preservation`
12. `Lean4Lean verified Lean typechecker kernel mathlib arXiv 2403.14064`
13. `Lean 4 compiler LCNF IR C codegen pipeline passes erasure implemented_by extern`
14. `CertiCoq verified compiler Coq to C WASM extraction pipeline`
15. `Lean 4 codegen backend LLVM custom target list community projects`
16. `Proof carrying code verified compiler erasure untyped runtime faithful semantics`
17. `Lean 4 codegen python backend compile Lean to python`
18. `Lean 4 does not have extraction like Coq compile to OCaml Haskell`
19. `Lean 3 to javascript compilation js_of_lean lean2js`

Additional repo/README fetches (via `fetch_content`): `jroesch/lean.js`,
`T-Brick/lean2wasm` (incl. `Lean2Wasm.lean` source confirming the emcc route),
`BasisResearch/VerifiedJS`, and the DeepWiki "Compiler Backend" page for Lean 4.
