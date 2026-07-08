# FFI — the external-library problem: proven inside, monitored at the edge

> **How typelean handles code that leaves the verified boundary.**
>
> This is the hardest limit of the "verified Lean → TypeScript" dream and
> where typelean can be genuinely novel rather than "another compiler."
>
> Companion documents: [`DESIGN.md`](../DESIGN.md) (architecture — §1 trust,
> §9 runtime primitives), [`OPPORTUNITIES.md`](../OPPORTUNITIES.md) (the
> proof-transfer thesis — §0 thesis, §1 strategic crux),
> [`ROADMAP.md`](../ROADMAP.md) (milestones), [`USAGE.md`](USAGE.md)
> (user guide — this doc is the external-library story).

---

## 1. The problem

Lean is a proof assistant. A `theorem` in Lean gives a mathematical guarantee
about the behaviour of a Lean program — but only about the *Lean* program. The
moment that program calls a function implemented outside Lean — a JavaScript
`fetch`, Node's `fs.readFile`, a third-party npm parser, a database driver, the
DOM — the proof says *nothing* about that call's behaviour.

**Concrete example.** Consider a Lean program that downloads a JSON blob, decodes
it, and processes the result:

```lean
def downloadJson (url : String) : IO Json := do
  let raw ← IO.FS.readFile url    -- calls Node fs under the hood
  return Json.parse raw            -- calls a JS JSON parser
```

The Lean proof might guarantee that the *processing* step is correct (no
overflow, no out-of-bounds access), and it might even prove that `Json.parse`
returns a well-formed tree for any valid JSON input. But it cannot prove:

- That `IO.FS.readFile` returns the bytes the server sent (the network is
  outside the proof).
- That the JSON parser correctly implements RFC 8259 (it is a JS library
  the proof cannot reach).
- That `fetch` (if we used it instead) resolves the URL, follows redirects, or
  respects timeouts — all of these are outside Lean's semantics.

**The honest statement is:** the Lean proof covers the *core* — the pure
computational kernel. Every external library, platform API, and effect source
is an unverified seam. Pretending otherwise would be dishonest and would destroy
the thesis's credibility.

> **Proven inside, monitored at the edge, never silently wrong.**
>
> typelean does NOT claim to *prove* external libraries. It claims to *make the
> boundary explicit, typed, and runtime-checkable* — so that the program either
> satisfies its declared contract or throws. It cannot silently misbehave.

---

## 2. The boundary model

```
┌──────────────────────────────────────────────────┐
│  VERIFIED CORE  (proven in Lean)                  │
│                                                   │
│  ┌─────────┐   ┌──────────┐   ┌──────────────┐   │
│  │ Lean    │   │ Lean     │   │ Verified     │   │
│  │ theorms │   │ pure     │   │ pure         │   │
│  │ (erased)│   │ functions│   │ state        │   │
│  └─────────┘   └──────────┘   │ transitions  │   │
│                               └──────────────┘   │
└──────────────────┬───────────────────────────────┘
                   │  @[extern] / @[spec extern]
                   │  THE SEAM — explicit boundary
                   ▼
┌──────────────────────────────────────────────────┐
│  UNVERIFIED PERIPHERY  (TS/JS ecosystem)          │
│                                                   │
│  ┌──────────────┐  ┌──────────┐  ┌───────────┐   │
│  │ npm packages │  │ platform │  │ databases │   │
│  │              │  │ APIs     │  │           │   │
│  │ (lodash,     │  │ (fetch,  │  │ (SQLite,  │   │
│  │  zod, etc.)  │  │  fs,     │  │  PG, etc.)│   │
│  │              │  │  DOM)    │  │           │   │
│  └──────────────┘  └──────────┘  └───────────┘   │
└──────────────────────────────────────────────────┘
```

Every `@[extern]` binding in Lean is a **seam** — a point where the Lean
program leaves the proof system and enters the unverified runtime. The Lean-side
type signature is the *contract* (what types cross the boundary), but Lean's
type system cannot constrain the *observable behaviour* of the external call.

### 2.1 What is on the verified side

- Pure Lean functions with proofs about their behaviour.
- `IO` computations whose effect specifications are in Lean (e.g. `IO.println`
  is a runtime primitive, but its specification is part of the typelean contract
  — see `DESIGN.md` §9).
- Data structures, algorithms, protocol cores — anything that can be expressed
  and verified entirely in Lean.

### 2.2 What is on the unverified side

- **Platform APIs**: `fetch`, DOM, `fs.readFile`, `crypto`, `process.env`.
- **npm packages**: any third-party library (lodash, zod, express, React, etc.).
- **Databases**: SQLite, PostgreSQL, Redis — the network protocol and the
  database's own logic are outside the proof.
- **Native bindings**: any `@[extern "lean_…"]` that maps to C code in Lean's
  own runtime (Lean's `Nat.add` is compiled to C; for typelean, this is a
  hand-written TS primitive — see `DESIGN.md` §9).

### 2.3 The honesty constraint

typelean must **never** silently pass a bad value from the periphery into the
verified core. If the unverified call returns something that violates the
contract, the system must detect it — not silently produce a wrong answer that
the proof says is impossible.

This is the core constraint that the rest of this document addresses.

---

## 3. Three mechanisms, increasing ambition

typelean provides three mechanisms for handling the boundary, each with
different cost, strength, and ambition. They are cumulative — a project can
use Specified FFI for cheap calls, Runtime Monitoring for critical calls,
and Shadow Testing for the highest-stakes calls.

### 3.1 Mechanism 1: Specified FFI (design-by-contract)

**What it is.** Every `@[extern]` binding carries a Lean *spec* — a theorem
about the required behaviour of the external call. The spec is **admitted**
(we cannot prove an npm package correct), but it is **stated and
type-checked** by Lean's kernel. This means:

- The spec lives in the same term language as any Lean proof.
- It is type-checked by Lean's elaborator (no syntactic loopholes).
- It serves as *documentation* of the assumed behaviour.
- It creates a **type-level obligation** for any code that depends on the
  external call's behaviour.

**What it does not do.** It does not *verify* the external call. The spec is an
assumption — if the external library violates it, the proof is unsound. This is
the honest, minimal layer.

**When to use it.** For every external call as a matter of discipline — even if
you are not running monitors, the spec documents what you assume.

**Cost.** Essentially zero at runtime (no checks). The cost is the spec-writing
effort in Lean.

**Analogy.** This is "design by contract" for the FFI boundary — the spec is
the contract, and anyone reading the code knows exactly what assumptions are
being made.

### 3.2 Mechanism 2: Runtime monitoring (satisfy-or-throw)

**What it is.** The emitted TypeScript wraps every monitored `@[extern]` call
with a runtime assertion that the result satisfies the Lean spec. If the
assertion passes, the value enters the verified core. If it fails, the program
throws (or returns `none`, depending on the monitoring mode).

**The soundness claim.** "Proof + runtime verification" is a known sound
combination in the programming-languages literature. Concretely:

> If the Lean core is correct and the runtime monitor catches all
> spec-violating results from external calls, then the combined system
> either produces a correct result or throws — it never silently produces an
> incorrect result.

This is **strictly stronger** than Mechanism 1: the spec is now an enforced
runtime barrier, not just documentation.

**When to use it.** For any external call where:

- The spec can be expressed as a cheap predicate (e.g. "status code < 600,"
  "result length == input length," "parsed value is valid JSON").
- The call is on a critical path where a wrong answer would be catastrophic.
- The overhead of the runtime check is acceptable.

**What kinds of specs are monitorable.** The monitor is extracted from the
Lean `theorem`'s conclusion — specifically, from the *right-hand side* of the
statement. The most practical specs are:

- **Range predicates**: `result.status < 600`, `|result| ≤ maxLen`.
- **Structural invariants**: `isValidUTF8 result`, `isSorted result`.
- **Round-trip properties**: `decode (encode x) = some x` (monitor the
  encoding then decoding of the result).
- **Type-class based**: `BEq`/`Hashable` consistency checks on the result.
- **Length/count invariants**: `List.length result = n` (a known input length).

**Cost.** The runtime check adds overhead proportional to the predicate's
complexity. A range check is free; a round-trip check doubles the work.

**Analogy.** This is "satisfy-or-throw" — the program either satisfies the
contract the Lean spec describes, or it terminates with an error. It is the
most honest guarantee deliverable for unverified code.

### 3.3 Mechanism 3: Differential / shadow testing

**What it is.** For the highest-stakes external calls, run a reference Lean
implementation *alongside* the TypeScript library and diff the results. The
Lean reference is verified (or at least well-tested in Lean); the TypeScript
call is the production path. On mismatch, the system logs, alerts, or throws.

**The evidence claim.** This provides the strongest evidence short of proving
the library. If the Lean reference and the TS library agree on a
representative input distribution, the probability of the library being wrong
for the actual workload is acceptably low. This is the same idea as
*differential testing* (aka "fuzzing with an oracle"), but with the oracle
being a verified Lean implementation.

**When to use it.** For calls where:

- The spec is too expensive or too imprecise to monitor at runtime.
- The library is a black box and you cannot inspect it.
- The correctness requirement is high but runtime overhead is tolerable
  (shadow mode runs in parallel and can be sampled, not per-call).
- You are in the process of replacing the library with a verified Lean
  implementation and want regression safety during the transition.

**Concrete pattern:**

```
                    ┌──────────────────┐
                    │  TS library      │──→ result_ts
  input ────────────┤                  │
                    │  Lean reference  │──→ result_lean
                    │  (compiled to TS)│
                    └──────────────────┘
                              │
                              ▼
                    diff(result_ts, result_lean)
                              │
                    ┌─────────┴─────────┐
                    ✓                  ✗
                 silent           alert / throw
```

**Cost.** High — 2× computation for the shadow path. Practical only for
critical, lower-throughput calls. Sampling (shadow 1 in N calls) is a
practical middle ground.

**Analogy.** This is "prove the oracle, test the implementation against it."
It is the same pattern described in [`OPPORTUNITIES.md` §0–§1](../OPPORTUNITIES.md)
(proof-generated test oracles), but deployed as a runtime safeguard rather than
a CI-time check.

---

## 4. Syntax proposal (Lean-side)

### 4.1 Declaring a monitored extern

```lean
/--
  `fetch` retrieves the content at `url` and returns it as a string
  together with the HTTP status code.

  Spec: the status code must be < 600 (a valid HTTP status).
  Status codes ≥ 600 are invalid per RFC and indicate a monitor failure.
-/
@[extern typelean_fetch, spec fetch_spec]
def fetch (url : String) : IO (String × Nat) :=
  -- The Lean body is a placeholder; the TS runtime provides the real impl.
  pure ("", 0)

/-- The spec theorem.
    `admit` because we cannot prove npm correct — this is a boundary assumption.
    But it IS type-checked by Lean's kernel: types must match. -/
theorem fetch_spec (url : String) (result : String × Nat) :
    result.2 < 600 := by
  admit  -- boundary assumption, typed
```

What this means:

- `@[extern typelean_fetch]` tells typelean to emit a call to the runtime
  function `typelean_fetch` rather than compiling the Lean body.
- `spec fetch_spec` tells typelean that `fetch_spec` is the contract theorem.
- `fetch_spec` takes the same parameters as `fetch` and a `result` parameter,
  and returns a proposition that must hold.
- `admit` is honest: we are *stating* the assumption, not proving it. But
  Lean's kernel type-checks the whole statement — if `result` is a `Nat` and
  the theorem expects a `String`, the error is caught at elaboration time.
- The `@[extern]` symbol `typelean_fetch` is registered in the runtime
  primitive table (see `DESIGN.md` §9).

### 4.2 What the emitted TypeScript looks like (Mechanism 2 — monitoring)

```typescript
// Runtime monitoring wrapper — typelean_rt.ts
function typelean_fetch(url: string): [string, bigint] {
  // The real implementation — e.g. Node https.get
  const response = ... ;
  return [response.body, BigInt(response.statusCode)];
}

// Emitted TS for a MONITORED call
function fetch_spec_check(url: string, result: [string, bigint]): boolean {
  // The spec predicate: result.2 < 600
  return result[1] < 600n;
}

// Emitted TS for a call-site with monitoring
export function use_fetch(url: string): [string, bigint] {
  const result = typelean_fetch(url);
  if (!fetch_spec_check(url, result)) {
    throw new Error(
      `typelean runtime spec violation: fetch_spec failed for url=${url}, ` +
      `status=${result[1]}`
    );
  }
  return result;
}
```

If the user opts for **Mechanism 1** (no monitoring), the call is direct:

```typescript
export function use_fetch(url: string): [string, bigint] {
  return typelean_fetch(url);  // no spec check — trust the library
}
```

### 4.3 Monitoring modes

The emitted TS supports several monitoring modes, controllable per-extern or
globally:

| Mode | Behaviour | Use case |
|---|---|---|
| `trust` | No check — call the extern directly | Cheap, frequently called, low-stakes |
| `monitor` | Check the spec predicate; throw on violation | Critical calls with cheap specs |
| `monitor_option` | Return `Option`; `none` on violation | When the caller wants to handle failure, not crash |
| `monitor_sample(n)` | Check 1 in `n` calls statistically | When overhead matters but you want probabilistic coverage |
| `shadow` | Run Lean reference + TS lib; diff results | Highest-stakes, lower-throughput calls |
| `shadow_sample(n)` | Shadow 1 in `n` calls | Practical for production |

### 4.4 Declaring a shadow-tested extern

```lean
@[extern typelean_json_parse, spec json_parse_spec, shadow json_parse_ref]
def jsonParse (s : String) : IO (Option Json) := ...

/-- A verified reference implementation of JSON parsing.
    This IS compiled to TS (not erased) and run alongside the extern. -/
def jsonParseRef (s : String) : Option Json := ...

/-- Proving the reference is correct for all inputs.
    This proof is erased — only `jsonParseRef` survives to TS. -/
theorem jsonParseRef_total (s : String) :
    (jsonParseRef s).isSome ∨ (jsonParseRef s).isNone := by
  ...
```

The emitted TS runs both paths and diffs:

```typescript
function use_jsonParse(s: string): Option<Json> | never {
  const result = typelean_json_parse(s);  // from npm/JS
  const reference = jsonParseRef(s);       // verified Lean ref, compiled to TS
  if (!deepEqual(result, reference)) {
    console.error("SHADOW MISMATCH:", {input: s, result, reference});
    // Alert or throw depending on policy
  }
  return result;
}
```

---

## 5. What is NOT solved

It is critical to be honest about the limits of this approach. typelean does
not — and cannot — *prove* external libraries.

### 5.1 This does not prove external libraries

The Lean spec is an *assumption*, not a proof. If the external library violates
the spec, and monitoring is off (Mechanism 1), the program silently produces
wrong results. Even with monitoring on (Mechanism 2):

- The monitor can only check the spec, not the *full semantic equivalence*
  between the Lean semantics and the TS implementation.
- If the spec is wrong (under-specified), monitoring passes but the program
  is still wrong at the semantic level — the monitor enforces the *stated* spec, but the stated spec may not capture the *real* requirement.

### 5.2 Monitoring has overhead

Runtime monitors execute a predicate on every external-call result. For cheap
predicates (range check, length check, type check) the overhead is negligible.
For expensive predicates (round-trip encoding, structural deep-equal) the
overhead can exceed the cost of the external call itself. The monitoring modes
(`trust`, `monitor`, `monitor_sample`, `shadow_sample`) are designed to let
users balance coverage and cost, but the overhead is real and must be accounted
for in production budgeting.

### 5.3 Specs can be wrong

Writing a correct spec is a *specification problem*, not a verification problem.
A mis-specified extern — one whose theorem statement is true but
under-constrained — will pass monitoring and still produce wrong results. The
typical case:

```lean
-- This spec is too weak: it ensures the result is non-negative, but says
-- nothing about correctness of the computed value.
theorem fetch_spec_weak (url : String) (result : String × Nat) :
    0 ≤ result.2 := by
  admit
```

The monitor passes, the program gets a status code of 999 (not a valid HTTP
status), and the verified core proceeds to process invalid data. The monitor
did not *lie* — it enforced the spec — but the spec was insufficient.

**Mitigation:** spec review. The spec theorem is just a Lean theorem — it can
be audited, discussed in code review, and tightened over time. This is the sane
analogue of "write a type annotation for your function" — you can get it wrong,
but you are better off with it than without it.

### 5.4 The monitoring predicate itself is unverified

The runtime monitor is a TS function derived from the Lean spec theorem. It is
*not* verified to faithfully implement the Lean spec — it is hand-written or
auto-extracted. If the monitor is buggy, it can:

- **False positive** — throw on a valid result (reduces availability).
- **False negative** — pass on an invalid result (the guarantee is void).

**Mitigation:** for the highest-stakes calls, the monitor can be *itself*
derived from the Lean spec by a code generator that maps Lean propositions to
TS predicates. This is the same pattern as proof extraction, but for predicates
rather than programs. This is future work (see §7).

### 5.5 The LCNF/trust-the-compiler hole

The verified core is only as verified as the compiler that processes it.
typelean's Lower and Emit stages are *trusted* — they are not verified
(`DESIGN.md` §1, §4.2). A bug in Lower or Emit can silently change the
semantics of the verified core, making the proof irrelevant. This is the same
hole every verified compiler faces (CompCert is verified, but its OCaml runtime
is not; Lean's own kernel is verified by Lean4Lean, but the elaborator is not).

**Honest framing:** the FFI boundary is not the *only* unverified seam. The
compiler itself is one. The FFI story is honest about the external-call
boundary; the compiler trust story is told in `DESIGN.md` §1 and
`OPPORTUNITIES.md` §1a — they are separate concerns.

---

## 6. Relationship to the dream

typelean's value proposition is: **a verified Lean core, running in a TypeScript
process, with an explicit and honest boundary to the unverified world.** This
splits the vision into two tiers:

### Tier A: Embed verified cores in larger TS (near-term)

In this tier, the Lean code is a *component* embedded in a larger TypeScript
application. The external-library boundary is pervasive — the Lean core calls
fetch, reads files, uses npm libraries. The Specified FFI mechanism (§3.1) is
the primary tool: every external call is declared with a spec, documented in
Lean, and optionally monitored. The verified core is a *trusted island* in a
sea of unverified TS.

This is the near-term, pragmatic tier. It is enabled as soon as M1/M2 land
(basic Lean-to-TS compilation) plus the `@[extern]` primitive table (`DESIGN.md`
§9). The FFI doc describes exactly how the boundary works, and users get a
honest, typed seam rather than pretending the whole program is verified.

### Tier B: Full Lean app → TS (needs the full monitoring + stdlib FFI coverage)

In this tier, the *entire* application is written in Lean and compiled to TS.
There is no separate TS codebase — the TS is an artifact of compilation. The
external-library boundary is the *stdlib coverage boundary*: every function in
Lean's `IO` module, `Std` library, and common ecosystem packages needs an
`@[extern]` binding with a spec. The Runtime Monitoring mechanism (§3.2)
becomes the default — every stdlib FFI call is monitor-checked in production.

This tier is the full dream. It requires:

1. **Complete stdlib FFI coverage** (M5 of the roadmap — `DESIGN.md` §9
   runtime primitive table). Every `@[extern]` constant in `Init`/`Std` must
   have a spec and a TS primitive.
2. **Automatic `@[extern]` discovery** — the compiler must detect unmapped
   externs and report them as errors, not silently emit wrong code.
3. **Spec extraction for monitors** — the compiler must derive the runtime
   monitor from the Lean spec theorem automatically for a useful subset of
   spec patterns.
4. **Performance tuning** — monitoring overhead must be acceptable for the
   targeted workloads, and the `trust`/`monitor_sample`/`shadow_sample` modes
   give production escape hatches.

### How this doc bridges them

The three mechanisms (§3) form a spectrum:

```
Mechanism 1     Mechanism 2       Mechanism 3
  (spec only)     (runtime check)    (shadow testing)
     │                │                   │
     └────────────────┴───────────────────┘
          │                            │
     Tier A works                Tier B full
     with this                    dream needs
     (document the                (runtime check
      boundary)                   as default)
```

- **Tier A** uses §3.1 for most calls, §3.2 for critical ones.
- **Tier B** uses §3.2 for all calls, §3.3 for the highest-stakes ones.

The doc is the bridge: it shows both what is possible today (Tier A, the near
term) and what the full vision requires (Tier B, the long term).

---

## 7. Open questions

These are open design questions for future work. Each is a research direction
that the project can invest in over time.

### 7.1 Spec language expressiveness

What subset of Lean propositions can be automatically extracted to a TS
runtime monitor? The most practical subset:

- Equality (`=` on decidable types)
- Inequality (`<`, `≤`, `>`, `≥` on `Nat`, `Int`, `Float`)
- Boolean predicates (`isSome`, `isNone`, `isEmpty`)
- Structural predicates (isSorted, isValidUTF8, isWellFormed)
- Negation (`¬`), conjunction (`∧`), disjunction (`∨`) of the above

Beyond this, the spec monitor must be hand-written. How far can automatic
extraction go? This is analogous to the problem of extracting executable
code from `Prop` — it is the same general area as proof mining.

### 7.2 Can the monitor be extracted automatically?

If the Lean spec is a simple predicate (e.g., the right-hand side of an
equality, or a decidable proposition), the compiler can generate the monitor
from the spec's *conclusion* directly — no hand-written TS needed. The
difficulty is that `theorem` bodies can be arbitrarily complex `Prop` terms
that are not computationally relevant. But many useful specs are simple enough.

A concrete research sub-question: for a decidable proposition `p` (one with
an instance of `Decidable p`), can we lower `p`'s *decision procedure* (not
its proof) to TS and use that as the monitor? This would give automatically-
extracted monitors from decidable specs.

### 7.3 Performance of monitoring

How much overhead does runtime monitoring add to a real application? This
depends entirely on:

1. How many external calls cross the boundary (the call frequency).
2. How expensive their spec predicates are (cheap vs. round-trip vs. deep-equal).
3. What monitoring mode is used (`monitor` vs. `monitor_sample`).

Benchmarking this on real-world workloads (a web server with verified request
handling, a CLI tool that reads files, a JSON API gateway) is needed to
establish realistic overhead numbers. The expectation is that most calls
(>99%) use cheap, constant-time predicates (range checks, length checks, type
tests) and add <1% overhead.

### 7.4 When to trust vs. monitor

What policy governs whether an external call is `trust` (no check) or
`monitor` (checked)?

Possible heuristics:

- **Trust by default for performance, monitor on critical path.**
- **Monitor everything in debug/dev mode; accept monitoring overhead.
  Production uses a whitelist: monitor only the documented-critical externs.**
- **Monitor everything; use sampling for cost control.**
- **Differential: monitor only if the spec is decidable and cheap.**

This is a user-facing configuration concern. The answer likely depends on the
deployment context (embedded in a web browser vs. server-side CLI tool vs.
financial backend).

### 7.5 Spec evolution and regression

When an external library changes (npm update, browser API version bump), the
Lean spec may become stale. How is this detected?

- **Monitoring at runtime** detects violations immediately (if the monitor is
  on).
- **Shadow testing** detects behavioural differences between the old and new
  library version.
- **A CI step** could run the new library against the Lean reference
  implementation and diff.

None of these are automatic — they require the library consumer to notice the
change. This is the same problem as any external-dependency evolution.

### 7.6 Lean4Lean implications

`Lean4Lean` (verified Lean kernel) verifies Lean's *typechecker*. If Lean4Lean
is extended to also verify Lean's *elaborator*, then the compiler pipeline
becomes more trusted. But the FFI boundary is outside even the kernel —
typechecking a `theorem … := by admit` is valid even under a fully verified
kernel. **The FFI spec is a stated assumption, not a proved fact, and no
amount of kernel verification makes it a proof.** This is an important nuance:
the FFI seam is fundamentally different from the kernel-trust seam, and the
honest framing in §5 is not undermined by kernel verification.

### 7.7 Effect specs and purity

Monitored externs currently cover *pure* specs (predicates on the return
value). For `IO` externs like `fetch`, the interesting spec often involves
*effects* (e.g., "the HTTP request must be sent with TLS 1.3"). Effect specs
are harder to monitor because the effect happens *before* the result — the
monitor sees only the return value, not the side effect.

Possible approaches:

- **Trust-but-verify hidden:** log the effect and correlate with external
  observability (e.g., check the TLS version against a server-side log).
- **Semantic monitoring:** for `IO` actions, the monitor can run the action
  and check its return value *and* capture its effect trace (if the runtime
  supports effect introspection). This is deep future work.
- **Restrict the spec:** write only return-value specs for `IO` externs; trust
  the side-effect behaviour based on the library's own testing. Honest but
  limited.

### 7.8 Cross-boundary type fidelity

When Lean `String` (codepoint-length, UTF-8 byte offsets) crosses the
boundary to a JS `string` (UTF-16 code-unit length, `String.length`), how
is the mismatch handled? The runtime bridge (`DESIGN.md` §11, the Tier-1
hazard table in `OPPORTUNITIES.md` §1a) implements the translation — but
monitoring the translation itself is a separate concern.

A cross-boundary monitor could verify that the runtime's translation of a
Lean `String` to a JS `string` is faithful (e.g., roundtrip-encode the result
and check it matches the original). This is one of the most valuable
applications of Mechanism 2.

---

## References

Link references to companion documents:

- [`DESIGN.md`](../DESIGN.md) — architecture: §1 (guiding principles — trust),
  §2 (pipeline), §4 (erasure), §7 (IO/monads), §9 (runtime primitives — the
  `@[extern]` table), §11 (runtime strategy — Tier-1 hazards).
- [`OPPORTUNITIES.md`](../OPPORTUNITIES.md) — the proof-transfer thesis: §0
  (the thesis — proven Lean → TS guarantee), §1 (the strategic crux — what it
  takes to establish typelean's own correctness; §1a Tier-1 runtime hazard
  table; §1c honest scope — effects as external boundary). See also
  Opportunity 7 (proof-generated test oracles) for the shadow-testing pattern.
- [`ROADMAP.md`](../ROADMAP.md) — milestones: M0 (skeleton), M1 (expression
  translation), M4 (IO bridge), M5 (stdlib coverage including `@[extern]`
  discovery).
- [`USAGE.md`](USAGE.md) — user guide: the external-library story links here
  for the full explanation of `@[spec extern]` and monitoring modes.
- `runtime/typelean_rt.ts` — the runtime primitive table and monitoring
  infrastructure.
