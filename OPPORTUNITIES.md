# typelean — Opportunities: Proof-of-Correctness over Testing

**A research catalog of what we could build with typelean.**

> typelean is a compiler, written in Lean 4, that translates Lean 4 source →
> TypeScript, targeting perfect Lean 4 compatibility and complete translation.
> Architecture in one line (see `DESIGN.md`): reuse `Lean.Elab` so we compile the
> *same* core term Lean produces; erase types/proofs/universes; emit untyped TS
> backed by a hand-written runtime reproducing Lean's value/evaluation semantics
> exactly; verify "perfect compatibility" with a parity harness (`lean` ≟ `node`).

---

## 0. The thesis

Lean is a proof assistant. If typelean faithfully compiles **verified Lean** to
TypeScript, the emitted TS **inherits the Lean proofs of correctness**. We can
then build software where we substitute *proof-of-correctness* for *painful
testing*, and go faster on hard problems where exhaustive testing is infeasible:
astronomical input spaces, arithmetic/Unicode edge cases, state-space
explosion, invariant maintenance across millions of operations.

The pattern, repeated below:

```
   Lean spec  ──┐                         ┌──  TS that is correct-by-construction
   Lean impl   ──┼──  typelean (Lower+Emit) ──  (proof erased at runtime;
   Lean proof  ──┘   erases Prop/Sort/u      guarantee rides on faithful runtime)
```

The proof is *erased* (`DESIGN.md` §4.2, §8 — `Prop`/`Sort` carry no runtime
content). What survives is the verified computational core; its guarantee reaches
the TS output **only if** typelean + its runtime faithfully reproduce Lean's
evaluation semantics. That "only if" is the whole game.

## 1. The strategic crux — read this first

**A proof guarantees the *Lean* program. For that guarantee to reach the TS
output, typelean itself must be trusted to preserve semantics.** Every
opportunity below is licensed by that one condition. Frame each one against
this cost/benefit:

### 1a. What it takes to establish typelean's *own* correctness

Four routes, weakest → strongest, all cumulative:

1. **Empirical fidelity harness (today, M6).** The parity harness (`lean` ≟
   `node`, `DESIGN.md` §12) is *differential testing*, not proof. It catches
   bugs over a grow-only corpus and gives strong empirical confidence, but it
   cannot *prove* semantics preservation — it can only fail to find a
   counterexample. It is the floor every opportunity stands on, and the
   regression net for everything stronger.

2. **Prove Lower+Emit semantics-preserving for a subset, grow per milestone.**
   Layered: prove a simulation theorem for the M1 surface (pure `Nat`/`Bool`,
   `let`/`λ`/`app`, a couple of constructors) first; add the constructor/recursor
   cases at M2; add `Fin`/`UInt*` wrap-around at M5; etc. The *proven subset* is
   the guarantee; the *fidelity corpus* is the evidence for the rest. This is the
   pragmatic CompCert-style path: "prove the kernel of the compiler, test the
   rest."

3. **Lower from `Lean.Compiler.LCNF`** (`DESIGN.md` §2 alternative) to *inherit
   Lean's own erasure*. Erasure is subtle (relevance classification of every
   binder/argument) and is exactly where compatibility bugs hide; if LCNF
   performs it, the "Lower is correct" burden shrinks to "Emit (IR→TS) + runtime
   are correct." Combined with a verified Emit, this is the strongest practical
   route. Note Lean's own trust stack (`@[implemented_by]`, `@[extern]`, the
   kernel) is itself a boundary; **Lean4Lean** (arXiv 2403.14064) is working
   to *verify Lean's own kernel/typechecker* (the first complete Lean 4
   typechecker besides the C++ reference; it checks all of mathlib), which
   would close one more layer under us — though it targets the *typechecker*,
   not the codegen compiler, so it underwrites *checking* our inputs, not
   *compiling* them.

4. **Tier-1 runtime hazards as proof obligations.** The transfer *fundamentally
   depends* on the runtime faithfully implementing the observable primitives.
   `DESIGN.md` §11/§12 call these out explicitly and they are the load-bearing
   wall under every opportunity:

   | Runtime primitive | Hazard | Voids which proofs |
   |---|---|---|
   | `Nat` (`bigint`) | truncating subtraction `n - m = 0` when `m > n`; `x / 0 = 0`; `mod` toward zero | all arithmetic, crypto, money, CRC, oracles |
   | `Int` (`bigint`) | Lean's `Int.div`/`Int.mod` (T-division) conventions | money, signed arithmetic |
   | `UInt8…64`, `USize`, `Fin n` | explicit modular wrap-around at width | crypto, CRC, no-overflow kernels, fixed-size hashing |
   | `String`/`Char` | **codepoint** `length`; `String.Pos` = **byte offsets into UTF-8** (not UTF-16 units) | parsers, Unicode algorithms, oracles — *the showcase hazard* |
   | `Array`/`List`/constructors | Lean bounds/panic behavior, tag + field order | data structures, state machines |
   | recursion | TCO/trampoline (JS has no guaranteed TCO) | every recursive verified program (crypto, RB-trees, parsers) |

   An **unfaithful `Nat` or `String` runtime silently voids the proof transfer**
   for every downstream opportunity — the proof still describes the *Lean*
   program, but the TS output no longer matches it. This is precisely why the
   Tier-1 hazard cases are first-class, not an afterthought.

### 1b. How that one-time investment licenses many downstream wins

typelean's correctness is a **shared, one-time cost** amortized over *every*
verified Lean program compiled through it. Once `Lower + Emit + runtime` is
trusted (proof for the verified subset + fidelity corpus for the rest), each new
"skip the tests" win needs only **its own Lean proof** — the compiler transfer
comes free. So the cost is

```
total = (typelean-trust, paid ONCE)  +  Σ (per-program proof)
```

**not** `(per-program proof) + (per-program test suite) + (per-program
fuzz/corpus)`. The bigger the catalog N, the better the ROI — which is the
whole point of this document. And it is why the Tier-1 runtime investment is so
leveraged: it is the foundation under *every* transfer, so hardening
`Nat`/`String`/`UInt` once unlocks every opportunity below.

### 1c. Honest scope — where proof helps, where it doesn't

- **Proof covers the pure computational core.** Arithmetic, data-structure
  invariants, parsers/decoders, protocol state-transition cores, codec
  round-trips, optimizer transforms — all pure, all provable, all transferable.
- **Effects/IO are an external boundary that cannot be fully proven.** The
  network, the filesystem, the clock, other processes, hardware — these are
  outside the proof. The pattern, repeated in several opportunities below, is:

  > **Prove the core; keep IO a thin trusted shell** (`DESIGN.md` §7).

  typelean compiles the *pure* `step`/`decode`/`fold` to verified TS; the
  unverified glue (network driver, file reads, the `IO` bridge) is kept small,
  reviewable, and pinned by the fidelity harness. The proof narrows the attack
  surface to that shell; it does not eliminate it.

---

## 2. Milestone surface legend

Each opportunity lists the typelean milestone surface it depends on
(`ROADMAP.md`):

| Tag | Milestone | What lands |
|---|---|---|
| **M1** | Expression & definition translation 🚧 | pure `Nat`/`Bool`/`let`/`λ`/`app`, a couple constructors, `Nat`/`String` literals |
| **M2** | Inductives, structures, pattern matching ⬜ | recursors/`casesOn`/`brecOn`/match, mutual & well-founded recursion, `List`/`Array`/`Option`/`Prod`/`Sum`/`Fin` reps |
| **M3** | Tactics & metaprogramming ⬜ | tactic-produced data (`decide`, `deriving`, macros) lowered as ordinary `Expr` |
| **M4** | Effects, IO, monads ⬜ | `IO`/`EIO`/`ST` bridge, `do`, transformer stacks, `Task`/`Thread` |
| **M5** | Standard library coverage ⬜ | `Nat`/`Int`/`UInt*`/`Float`, `String`/`Char` codepoint+UTF-8, collections, `@[extern]` discovery |
| **M6** | Fidelity harness ⬜ | `lean` ≟ `node` parity corpus (grow-only); CI |

**Standing caveat (applies to every opportunity):** the proof transfer
*additionally* requires that **M6 has shown parity over the relevant surface**
— the runtime must have demonstrated `lean ≟ node` for the constructs the proof
relies on. A proof that depends on `String`, for instance, transfers only once
the Tier-1 `String` fidelity cases pass. Where an opportunity flags a "gap would
break the correctness story," that gap is precisely a Tier-1 hazard (§1a table).

---

## 3. The catalog

Nine opportunities, each with: the problem & why testing fails, the
proof-vs-testing payoff, a concrete Lean sketch (illustrative — need not compile
today), fidelity/milestone needs, a real precedent, and a verdict. A brief
"Further horizons" list follows.

---

### Opportunity 1 — Verified fixed-point money & exact decimal arithmetic

**The problem.** Financial code is haunted by floating-point and rounding
errors: `0.1 + 0.2 ≠ 0.3`, banker's-rounding vs. half-up drift, integer cents
that silently underflow on `a - b` when `b > a`, and tax/interest splits that
gain or lose a cent because `(a + b) * r ≠ a*r + b*r` under naive rounding. Test
suites are giant tables of hand-curated rounding edge cases that still miss the
combinatorial space of multi-step accumulations, and regress on every locale or
scale change.

**How proof changes the game.** Model money as fixed-point scaled integers
(`Money = { cents : Int, dec : Nat }`) and **prove the algebra laws once**:
distributivity of scaling over addition, monotonicity, and that operations stay
non-negative / within-bounds under a declared policy. The tests replaced are
exactly the rounding/accumulation tables that fuzzing can't exhaust. Speed gain:
you ship the money kernel with *no* rounding regression suite, and refactor it
freely knowing the laws are mechanically enforced.

**Concrete Lean sketch.**

```lean
-- Fixed-point money: cents in the smallest unit, with a decimal scale.
structure Money where
  cents : Int          -- raw value in the smallest unit (e.g. 1/100 of a dollar)
  dec   : Nat          -- number of decimal places (e.g. 2 for USD)
deriving Repr, DecidableEq

def Money.add (m n : Money) (h : m.dec = n.dec) : Money :=
  { cents := m.cents + n.cents, dec := m.dec }

def Money.scale (m : Money) (r : Int) : Money :=
  { cents := m.cents * r, dec := m.dec }

-- Law 1: scaling distributes over addition — a tax split can't create/lose a cent.
theorem Money.add_distributive (m n : Money) (h : m.dec = n.dec) (r : Int) :
    (Money.scale (Money.add m n h) r).cents =
      (Money.scale m r).cents + (Money.scale n r).cents := by
  simp [Money.add, Money.scale]; ring

-- Law 2: non-negativity is preserved under addition (no silent underflow).
theorem Money.nonneg_add (m n : Money) (hm : 0 ≤ m.cents) (hn : 0 ≤ n.cents) :
    0 ≤ (Money.add m n rfl).cents := by
  simp [Money.add]; omega
```

typelean lowers `Money` to a runtime constructor object `_rt.ctor(tag, [cents,
dec])`, `Money.add`/`Money.scale` to curried TS functions, and field access
(`m.cents`) to runtime projection (`DESIGN.md` §4.4, §5). The two `theorem`s are
`Prop`-valued and **erased** — they emit *no* TS. The guarantee rides on the
runtime faithfully implementing `Int` (`bigint`) `+` and `*` (§1a hazard table).

**Fidelity/milestone needs.** M1 (pure arithmetic, structures, field projection)
+ M5 (faithful `Int` div/mod conventions) + M6 parity over `Int` arithmetic.
**Gap that breaks the story:** an unfaithful `Int` runtime (wrong `div`/`mod`
convention, or `Int` masquerading as float) voids `add_distributive` transfer —
Tier-1 hazard.

**Precedent.** **Flocq** — the Coq formalization of IEEE-754 floating-point
(`Flocq.IEEE754.Binary`, used by CompCert's float layer) proves rounding
operators correct; the same "verified rounding arithmetic" pattern. **Dafny**
is used in production financial/verification contexts (see Opportunity 2's AWS
Encryption SDK precedent for verified-in-Dafny-→-multiple-targets). Relevance:
verified decimal/rounding arithmetic is an established, deployed genre.

**Verdict — HIGH.** Pure M1 surface, ships early, immediately demo-able
("compare a verified money lib against a buggy float one on `0.1+0.2` and a
tax-split"), and the pain is universally understood. Strongest "first flagship"
candidate.

---

### Opportunity 2 — Verified cryptographic primitives (modular arithmetic, HMAC/SHA, curve ops)

**The problem.** Crypto correctness is hard (huge field-arithmetic input spaces)
and *constant-time* resistance is **untestable** — you cannot test "leaks no
timing information"; you must prove the control flow is data-independent.
Fuzzing finds crashes and overflow but cannot establish absence of side-channel
branches or the absence of a single wrong bit over 2^256 inputs. Bugs ship
silently and are catastrophic.

**How proof changes the game.** Prove (a) **arithmetic correctness** — `modpow a
n p = a^n mod p` for all `a n p` — and (b) a **control-flow independence**
property: the recursion/match structure depends only on *public* parameters
(e.g. the exponent length), not on secret bytes, which is the kernel of a
constant-time argument. The tests replaced are the giant Known-Answer-Test (KAT)
vectors and the manual constant-time audits. Speed gain: refactor the inner loop
knowing correctness is enforced; the constant-time proof gives assurance
testing fundamentally cannot.

**Concrete Lean sketch.**

```lean
-- Modular exponentiation by squaring, proven correct mod p.
def modpow (a n p : Nat) : Nat :=
  match n with
  | 0     => 1 % p
  | k + 1 => (modpow a k p * a) % p

theorem modpow_spec (a n p : Nat) (hp : 0 < p) :
    modpow a n p = a^n % p := by
  induction n with
  | zero     => simp [modpow, Nat.pow_zero]
  | succ k ih => simp [modpow, Nat.pow_succ, Nat.mul_mod, ih]

-- Control-flow independence: the match is on `n` only, so the branch shape
-- (hence, modulo a side-channel model, the timing) is independent of `a`/`p`.
-- Honest limit: full constant-time needs a separate side-channel model; this
-- is the value-semantics kernel of that argument.
theorem modpow_shape_indep (a b n p : Nat) (hp : 0 < p) :
    sameControlFlow (modpow a n p) (modpow b n p) := by
  sorry  -- by the match-on-`n`-only structure
```

typelean lowers `modpow` (structural recursion via `brecOn`) to a self-recursive
TS function; Emit marks it TCO/trampolined (`DESIGN.md` §11) so deep `n` doesn't
stack-overflow. The `theorem`s are erased. The guarantee rides on faithful `Nat`
(`bigint`) `*`, `%`, `Nat.pow`, and the trampoline (Tier-1 hazards).

**Fidelity/milestone needs.** M1 (Nat arithmetic, recursion) + M5 (Nat bitwise
ops, `UInt*` for fixed-width limbs, `@[extern]` for `Nat.mul`/`pow` if used) +
M6 parity. **Gap that breaks the story:** wrong `Nat`/`UInt*` modular
wrap-around, or a trampoline that changes the recursion shape, voids both the
correctness and the control-flow-independence transfer.

**Precedent.** **HACL\*/EverCrypt** (Project Everest, F\*) — verified C/assembly
crypto via the (partially-verified) **KreMLin** F\*→C compiler, deployed in
Firefox NSS. **Fiat Crypto** — Coq, correct-by-construction elliptic-curve
field arithmetic, used in Chrome/Firefox. **AWS s2n-tls + Galois** — verified
HMAC/DRBG components with Cryptol/SAW (component-level, not the full state
machine). Relevance: "verified crypto, compiled to a deployable target" is the
most established genre here — typelean's twist is Lean-as-source and
TS-as-target.

**Verdict — HIGH.** Flagship proof-of-correctness story, universally cited.
Caveat: pure *correctness* is M1; *constant-time* is a harder, secondary
property needing a side-channel model Lean's value semantics don't fully
capture — be honest that this is a "prove correctness, audit constant-time
separately" win unless we invest in the side-channel model. Still the most
resonant demo.

---

### Opportunity 3 — Verified parsers & protocol decoders (TLS framing, CBOR, JSON, binary formats)

**The problem.** Parsers are where memory-safety and logic bugs become
exploits: length-field confusion, integer overflow in size computations,
out-of-bounds reads on malformed input. The input space is combinatorial (every
byte sequence is a potential input); fuzzing finds bugs up to a depth/size bound
but **cannot prove absence**. Maintaining "this never panics on any byte
sequence" by testing is exactly the infeasible case.

**How proof changes the game.** Prove two properties over **all** byte inputs:
(1) **round-trip** — `decode (encode x) = some x` (and ideally `encode ∘ decode`),
so the format is faithful; and (2) **totality / no-panic** — `decode bs` returns
`Option` and never crashes for any `bs : ByteArray`. The fuzz corpus is replaced
by a proof that *no malformed input exists that breaks the decoder*. Speed gain:
ship a parser you can refactor freely, knowing the totality and round-trip
guarantees are enforced.

**Concrete Lean sketch.**

```lean
inductive CBOR where
  | uint (n : Nat)
  | str  (s : String)
  | arr  (xs : List CBOR)
  deriving Repr

def encode : CBOR → ByteArray := ...   -- total, pure
def decode : ByteArray → Option CBOR := ... -- total, never panics

-- Guarantee 1: round-trip — the format is faithful.
theorem decode_encode_roundtrip (x : CBOR) :
    decode (encode x) = some x := by
  induction x <;> simp [decode, encode, ByteArray.append, List.mapM]

-- Guarantee 2: totality — no byte sequence can panic the decoder.
theorem decode_total (bs : ByteArray) :
    decode bs = none ∨ ∃ x, decode bs = some x := by
  ...
```

typelean lowers `inductive CBOR` to runtime constructors, `match`/recursion to
`switch`+recursion (M2), `ByteArray`/`String` to runtime reps. The proofs are
erased. The guarantee rides on faithful `String` (codepoint/UTF-8) and
`Array`/byte-array runtime (Tier-1 hazards).

**Fidelity/milestone needs.** M2 (inductives, match, recursion) + M5
(`String`/`ByteArray`, `@[extern]` byte ops) + M6 parity over string/byte ops.
**Gap that breaks the story:** an unfaithful `String` codepoint/UTF-8 runtime
(§1a hazard) voids `decode_encode_roundtrip` for any text-bearing format — the
same Tier-1 wall as Opportunity 4.

**Precedent.** **miTLS / Project Everest** (F\*) — verified TLS message parsing.
**Isabelle AFP "LL(1) Parser Generator"** — verified JSON parser. **TRX** — a
formally verified parser interpreter in Coq. Relevance: verified parsers/decoders
are an established sub-genre; typelean lets you write them in Lean and ship them
in a TS process.

**Verdict — HIGH.** Security-critical, M2 surface (so enabled soon after M1),
and one of the most demo-able ("here is a CBOR/JSON decoder that is provably
total and round-trips; fuzz it forever, it won't panic"). Strong second flagship.

---

### Opportunity 4 — Verified Unicode / string algorithms (NFC/NFD, grapheme clustering, UTF-8 validation)

**The problem.** Unicode is combinatorial evil: combining marks, surrogates,
canonical/compatibility equivalence, normalization edge cases, grapheme-cluster
boundaries. "Test every string" is infeasible; ICU and platform libraries ship
normalization bugs for years. The space is precisely the one where exhaustive
testing is impossible and a single missed combining sequence is a real-world
data-corruption or security bug (e.g. IDN homograph attacks, normalization
bypasses in security checks).

**How proof changes the game.** Prove the Unicode *laws*: normalization is
**idempotent** (`nfc (nfc s) = nfc s`), the validator accepts **exactly** the
valid byte sequences (`validUTF8 bs = true ↔ ∃ s, toUTF8 s = bs`), and
grapheme-boundary counting is stable under re-chunking. These laws are exactly
the ones fuzzing can't exhaust. **Uniquely Lean-flavored:** Lean's *own* stdlib
already proves UTF-8 encode/decode inversion (`Init.Data.String.Decode`) — part
of the proof is *already done in Lean*, and typelean's job is to faithfully
lower it.

**Concrete Lean sketch.**

```lean
-- A UTF-8 validator: accepts exactly the valid byte sequences.
def validUTF8 (bs : ByteArray) : Bool := ...

-- Soundness + completeness — every String round-trips validly, and only those.
theorem validUTF8_complete (s : String) :
    validUTF8 (String.toUTF8 s) = true := by
  -- re-uses Lean's Init.Data.String.Decode: encode ∘ decode = id
  ...

theorem validUTF8_sound (bs : ByteArray) :
    validUTF8 bs = true → ∃ s, String.toUTF8 s = bs := by
  ...

-- Normalization idempotence — the core Unicode law fuzzing can't exhaust.
def nfc (s : String) : String := ...
theorem nfc_idempotent (s : String) : nfc (nfc s) = nfc s := by ...
```

typelean lowers `String` ops to the runtime's codepoint/UTF-8 implementation.
The proofs are erased. The guarantee rides **entirely** on the `String` runtime
faithfully implementing codepoint length and UTF-8-byte-offset `String.Pos`
(`DESIGN.md` §11).

**Fidelity/milestone needs.** M5 (faithful `String`/`Char`, `String.Pos` byte
offsets, UTF-8 round-trip) + M6 parity over the Tier-1 `String` cases. **Gap
that breaks the story — and this is THE showcase:** `DESIGN.md` §11 explicitly
flags Lean `String` (codepoint length, UTF-8 byte-offset positions) as a
fidelity hazard. An unfaithful `String` runtime voids every text-opportunity
transfer. This opportunity exists *to make that hazard concrete and motivate
hardening it first*.

**Precedent.** **Lean `Init.Data.String.Decode`** — Lean's stdlib already proves
UTF-8 encode/decode are inverse (the proof partially exists in Lean today).
**`smoothutf8`** — a mechanically verified Rust UTF-8 *validator*. Relevance: a
verified UTF-8/normalization layer in Lean, shipped to TS via typelean, is a
direct lift of an established pattern into a new ecosystem.

**Verdict — HIGH.** Highest *strategic* value relative to its surface: it is the
single best showcase for why the Tier-1 `String` hazard is first-class (it
motivates the foundation under Opportunities 1, 3, and 7), and part of the proof
is already in Lean. Demo-able ("a TS NFC that is provably idempotent"). Strong
"Top 3" contender.

---

### Opportunity 5 — Verified data structures with proven invariants (RB/B-trees, persistent maps, heaps)

**The problem.** Self-balancing structures maintain invariants across
delete/rebalance that interact subtly; tests can't cover every rotation
sequence and ordering of operations. A missed rotation in a red-black delete
can silently break the balance invariant and degrade to O(n) or, worse, lose a
key in a map used for correctness elsewhere. The invariant is global and the
operation space is unbounded.

**How proof changes the game.** Prove the invariants are **maintained by every
operation**: BST-ness + red-black color/balance after `insert` and `delete`;
heap-property after `push`/`pop`; log-height bounds. The proof replaces the
"test every rotation sequence" suite. Speed gain: refactor the rebalance freely
knowing the invariant is enforced, and drop the property-based-testing harness
you'd otherwise need to * probabilistically* check invariants.

**Concrete Lean sketch.**

```lean
inductive Color where | red | black
inductive Tree (α : Type) where
  | leaf
  | node (c : Color) (l : Tree α) (k : α) (r : Tree α)

def Tree.insert [Ord α] (k : α) : Tree α → Tree α := ...

-- The two proofs that replace "test every rotation sequence":
theorem insert_isBst [Ord α] (t : Tree α) (h : IsBst t) :
    IsBst (t.insert k) := by ...

theorem insert_balanced [Ord α] (t : Tree α) (h : Balanced t) :
    Balanced (t.insert k) := by
  -- the textbook case analysis, once, by hand
  ...
```

typelean lowers the `inductive` + `match` to constructors + `switch` (M2),
recursion to TCO/trampolined TS (§11). The proofs are erased. The guarantee
rides on faithful constructor evaluation and the trampoline (Tier-1 hazards —
especially TCO, since rebalance is recursive).

**Fidelity/milestone needs.** M2 (inductives, match, structural recursion,
`Ord` typeclass dictionaries lowered as data per §6) + M6 parity. **Gap that
breaks the story:** a trampoline/runtime that silently truncates deep rebalance
recursion (no TCO) would let a "balanced" proof describe a stack-overflowing
reality.

**Precedent.** **seL4** (Isabelle/HOL) — verified kernel object invariants
(CNodes, capability tables) maintained across every operation; the canonical
"global invariant maintained by all ops" proof at scale. Verified red-black
trees are a textbook benchmark in Coq/Isabelle/CFML. Relevance: invariant
maintenance under all operations is exactly seL4's pattern at data-structure
granularity.

**Verdict — MEDIUM-HIGH.** Solid M2 building block and a clean demo, but more
"textbook" than the security/crypto/Unicode wins; its real value is as a
*dependency* for Opportunities 3, 6, and 8 (verified maps underlie verified
parsers and state machines). High leverage as infrastructure, medium as a
standalone story.

---

### Opportunity 6 — Verified state machines & distributed-protocol pieces (Raft, Paxos, leader election)

**The problem.** Distributed protocols have enormous state spaces; model
checking catches bugs up to a bound but cannot prove safety/liveness for all
executions, and testing on a real network is nondeterministic and slow. The
bugs are subtle (split-brain, log divergence, stale-leader writes) and only
surface under rare interleavings that testing rarely hits.

**How proof changes the game.** Prove the **safety invariants** for all
executions: "at most one leader per term," "log monotonicity," "agreement — no
two committed entries differ," "Election Safety." These are exactly the
properties that are infeasible to test exhaustively over interleavings. Pattern:
**prove the pure state-transition core in Lean; keep the network/IO a thin
trusted shell** (`DESIGN.md` §7) — the proof narrows the trusted surface to the
driver, exactly the §1c scoping.

**Concrete Lean sketch.**

```lean
inductive Role where | follower | candidate | leader
structure RaftState where
  currentTerm : Nat
  log         : List LogEntry
  votedFor    : Option Nat
  role        : Role

-- A PURE step of the protocol. The network driver (unverified TS) feeds `m`.
def step (s : RaftState) (m : Message) : RaftState := ...

-- Safety invariant: the core Raft guarantee.
def atMostOneLeader (s : RaftState) : Prop := ...

-- The proof that replaces "model-check every interleaving."
theorem step_preserves_safety (s : RaftState) (m : Message)
    (h : atMostOneLeader s) : atMostOneLeader (step s m) := by
  induction m <;> simp [step, atMostOneLeader] <;> ...
```

typelean lowers the pure `step` to TS (M2). The unverified network driver is
small TS glue over the M4 `IO` bridge. The proof is erased. The guarantee rides
on faithful `List`/constructor evaluation and the trusted shell being small and
reviewable.

**Fidelity/milestone needs.** M2 (inductives, match, recursion) + **M4** (the
`IO` bridge the trusted shell uses) + M6. **Gap that breaks the story:** this is
the exemplar of §1c — the proof covers `step`, *not* the network; if the
trusted shell is large or does protocol logic itself, the proof no longer
describes the deployed system. The discipline "thin shell" is part of the
requirement.

**Precedent.** **Verdi** (Coq) — verified distributed systems (Raft, Paxos,
sharded KV) with verified message handling and a verified actor runtime.
**IronFleet** (Dafny + IronLambda, MSR) — verified distributed protocols via
refinement (replicated state machine, sharded KV). **Disel** (Coq) — verified
distributed protocols with typed endpoints. Relevance: verified
distributed-protocol cores are an established, high-profile genre — typelean's
value is shipping the proven core into a TS service.

**Verdict — HIGH.** Flagship distributed-systems value and a great illustration
of "prove the core, trust the shell." Drag: needs M2 *and* M4, and is harder to
demo convincingly (network nondeterminism is the untrusted part). Highest
*depth* payoff, slightly later on the roadmap.

---

### Opportunity 7 — Proof-generated test oracles (spec → executable reference → test real impls against it)

**The problem.** Often you **can't** prove your production implementation (legacy
code, a hot hand-optimized path, a third-party lib). But you still need
confidence. Expected-output tables are painful, brittle, and don't cover the
input space; writing them by hand is the painful-testing the thesis wants to
avoid. Property-based testing helps but needs a trustworthy oracle to check
against, and a hand-written oracle is itself an unverified test artifact.

**How proof changes the game.** This is the **pragmatic bridge** between "all
proven" and "all tested": prove a *reference* implementation equals an abstract
spec for all inputs, then **typelean compiles the verified reference to TS as an
oracle**. Run property tests (and fuzzers) comparing the *production* (possibly
unverified) implementation against the verified oracle. The tests "come for
free" from the spec — no hand-curated expected-output tables. You get
proof-grade confidence in the oracle and test-grade coverage of the production
impl, with the oracle provably correct.

**Concrete Lean sketch.**

```lean
-- The SPEC: declarative (sorted + permutation).
def sortSpec [Ord α] (xs : List α) : List α := ...   -- "the math"

-- The FAST impl (mergesort) we suspect is buggy.
def sortFast [Ord α] (xs : List α) : List α := ...

-- Prove fast == spec FOR ALL inputs (full), OR for a restricted slice (partial).
theorem sortFast_eq_spec [Ord α] (xs : List α) :
    sortFast xs = sortSpec xs := by
  induction xs <;> simp [sortSpec, sortFast, List.merge] <;> ...

-- typelean compiles sortSpec to TS: a verified oracle. Test an arbitrary
-- production sorter `prodSort` against it: prodSort(input) ?= oracle(input).
```

typelean compiles `sortSpec` (and optionally `sortFast`) to TS; the proof is
erased. The oracle runs in JS and is consumed by any JS test/fuzz harness.
Guarantee rides on faithful `List`/`Ord` runtime (Tier-1 hazards).

**Fidelity/milestone needs.** M1 (if the spec is pure arithmetic) or M2
(inductives/`Ord`), + M5 (collections, `Ord`/`BEq` dictionaries as data per §6),
+ M6. **Gap that breaks the story:** if the oracle's runtime differs from Lean
(e.g. `Ord`/`BEq` semantics drift), the oracle is no longer trustworthy — same
Tier-1 wall, lower stakes (it's an oracle, not the deployed code).

**Precedent.** **Verdi** uses verified reference implementations as oracles for
testing deployed systems; **EverParse / F\*** verified parsers serve as
reference implementations against which production parsers are tested. The
pattern (verified reference as test oracle) is standard in the verification
community. Relevance: this is the *least* radical opportunity — it doesn't ask
production to be proven, only the oracle, and it works *today* against
unverified JS.

**Verdict — HIGH.** The most immediately useful and least demanding: enabled as
soon as M1/M2 land, works against arbitrary existing TS code (no rewrite
required), and is trivially demo-able ("here's a verified `sortSpec` oracle in
TS; watch it catch a bug in this naive `prodSort`"). The pragmatic on-ramp to the
whole thesis.

---

### Opportunity 8 — Verified compiler passes / optimizer transforms shipped to JS (meta: typelean enables verified sub-compilers)

**The problem.** Optimizer passes (constant folding, common-subexpression
elimination, inlining, loop-invariant code motion, minifier transforms) are
themselves buggy and can silently change program semantics — and they run on
*all* code, so a bug is a universal miscompilation. Testing a pass requires
golden-output snapshots that can't cover all AST shapes, and "this transform
preserves semantics for all programs" is exactly a property you want to *prove*.

**How proof changes the game.** This opportunity is **meta and uniquely
typelean**: write and *prove* a compiler pass in Lean (semantics preservation:
`eval (pass e) = eval e`), then typelean compiles the **verified Lean pass
itself** to TS, shipping a proven optimizer transform into a JS/TS toolchain.
typelean becomes a vehicle for embedding verified sub-compilers in the JS
ecosystem — the same trick applied *to* compiler construction. The tests
replaced are the snapshot suites that can't cover all AST shapes.

**Concrete Lean sketch.**

```lean
inductive Expr where
  | num (n : Nat) | add (a b : Expr) | mul (a b : Expr)

def eval : Expr → Nat
  | .num n   => n
  | .add a b => eval a + eval b
  | .mul a b => eval a * eval b

-- A verified constant-folding pass.
def fold : Expr → Expr
  | .add (.num a) (.num b) => .num (a + b)
  | .mul (.num a) (.num b) => .num (a * b)
  | .add a b => .add (fold a) (fold b)
  | .mul a b => .mul (fold a) (fold b)
  | .num n   => .num n

-- Semantics preservation — the pass never changes the value, for ALL Expr.
theorem fold_correct (e : Expr) : eval (fold e) = eval e := by
  induction e <;> simp [eval, fold] <;> first | rfl | omega
```

typelean lowers the `inductive Expr`, `eval`, and `fold` to TS constructors and
functions (M2). The `theorem` is erased. The deployed TS `fold` is a verified
optimizer pass. Guarantee rides on faithful `Nat` `+`/`*` and constructor
evaluation (Tier-1 hazards).

**Fidelity/milestone needs.** M1 (Nat, recursion) + M2 (inductives, match) +
M6. **Gap that breaks the story:** if `Nat` `+`/`*` runtime drifts, `fold`
changes the value — Tier-1 `Nat` hazard, here applying to *typelean's own
verified sub-compiler output*.

**Precedent.** **CompCert** — verified C compiler whose optimizer passes
(constant propagation, common-subexpression elimination, register allocation)
are each proven semantics-preserving in Coq; the canonical "verified compiler
pass" precedent. Relevance: this opportunity is CompCert's pattern, retargeted
through typelean so the verified pass *runs in JS*.

**Verdict — HIGH (meta).** The most "typelean-native" opportunity — it uses
typelean to ship *typelean-shaped* artifacts (verified transforms) into the JS
world, demonstrating the tool as a platform, not just a compiler. Excellent
narrative/demo ("a JS minifier pass that is provably semantics-preserving").
Slightly niche audience but extremely high strategic signaling.

---

### Opportunity 9 — Verified no-overflow / wrap-around numeric kernels (CRC, bit-twiddling, fixed-size hashing, DSP filters)

**The problem.** Integer overflow, signed-overflow UB, and wrap-around bugs are
notorious (the classic security/launch-failure class). Testing cannot cover all
2^32/2^64 states, so "this loop never overflows" and "this CRC wraps exactly
mod 2^32" are infeasible to test and silent when wrong.

**How proof changes the game.** Prove (a) **absence of overflow** — the
computation stays within its `Fin n` ring for all inputs in range — and (b)
**wrap-around spec match** — e.g. `crc32 bs = polyMod (polyOf bs) crc32Poly`.
These are exactly the all-inputs properties testing can't reach. Speed gain:
drop the saturation/bounds-check scaffolding and the overflow fuzzing harness,
knowing bounds are proven.

**Concrete Lean sketch.**

```lean
-- CRC32 over a byte array, staying in the Fin 32 ring (provable no-overflow).
def crc32 (bs : ByteArray) : UInt32 :=
  bs.foldl (init := 0xFFFFFFFF) fun acc b =>
    ((acc >>> 8) ^^^ crcTable (acc ^.lo 8 ^^^ b))

-- Provable absence of overflow: the computation never leaves the 32-bit ring.
theorem crc32_in_bounds (bs : ByteArray) :
    ∃ r : UInt32, crc32 bs = r := by
  -- foldl over Fin 32 stays in Fin 32
  ...

-- Spec match: CRC equals the polynomial-mod of the message.
theorem crc32_spec (bs : ByteArray) :
    crc32 bs = polyMod (polyOf bs) crc32Poly := by ...
```

typelean lowers `UInt32`/`Fin 32` to the runtime's modular-wrap-around numeric
rep (`DESIGN.md` §11), `foldl` to a loop. The proofs are erased. The guarantee
rides **entirely** on the `UInt*`/`Fin` runtime implementing exact modular
wrap-around at the type's width (Tier-1 hazard).

**Fidelity/milestone needs.** M1 (arithmetic, `foldl`) + M5 (`UInt*`/`Fin`
wrap-around, `ByteArray`, bitwise `@[extern]`) + M6 parity over `UInt*` edge
cases. **Gap that breaks the story:** an unfaithful `UInt*`/`Fin` runtime (e.g.
JS `number` double-rounding, or wrong wrap-around width) voids both the
no-overflow and the spec-match transfer — Tier-1 hazard, the numeric analog of
the `String` showcase.

**Precedent.** **Fiat Crypto** — proves field-arithmetic bounds (no-overflow)
for all inputs. **CompCert** — its verified `int` semantics give a proven
machine-integer model. **Frama-C/WP** — proves absence of runtime integer
overflow in C for industrial code. Relevance: "prove no-overflow for all inputs"
is an established industrial verification target; typelean brings it to TS with
a clean `Fin n` story.

**Verdict — MEDIUM-HIGH.** Real, common pain (overflow/UB), enabled early on
M1+M5, demo-able ("a CRC32 that is provably in-bounds and spec-correct"). Less
resonant than crypto/Unicode but a strong, concrete, early-roadmap win and a
clean `Fin n` illustration.

---

### Further horizons (brief — proposed beyond the seed list)

These are credible but either more niche or further out; each would expand into a
full opportunity on demand:

- **Certified SAT/SMT-style solvers & verified decision procedures** — prove
  soundness/completeness of a verified `DPLL`/unit-propagation core or a verified
  LRAT/DRAT *unsat-certificate checker*; ship a "never-wrong-UNSAT" checker to
  TS. Precedent: **Fleury's verified CDCL SAT solver (Isabelle)**, **coq-lrat**.
  Verdict: MEDIUM — high intellectual value, niche audience.
- **Verified security checkers / sanitizers** — a verified taint/escape analyzer
  or a verified regex-based input validator (proven: accepts exactly the policy
  language). Precedent: verified regex matching in Isabelle; **EverParse**
  verified format checkers. Verdict: MEDIUM-HIGH.
- **Verified lock-free / concurrent data structures** — prove linearizability
  and the ABA-freedom of a queue/stack. Caveat: concurrency is an
  effects/IO-adjacent boundary (§1c), so this leans on the runtime's `Task`/
  scheduler (M4) and a memory model. Verdict: MEDIUM.
- **Verified game/invariant engines & ML-quant safety** — prove invariants of a
  game-state machine or prove a quant-numerics kernel stays within bounds (no
  NaN/Inf/overflow in a trading model). Precedent: verified numeric kernels
  (Fiat). Verdict: MEDIUM.
- **Verified regex / DSL engines** — prove a regex compiler from spec → NFA →
  DFA is semantics-preserving and the matcher is total. Precedent: verified
  regex in Isabelle/Coq. Verdict: MEDIUM-HIGH (great M2/M5 demo).

---

## 4. Top 3 bets

Ranked by (a) proof-vs-testing payoff, (b) how soon the roadmap enables it,
(c) demo-ability.

### 🥇 #1 — Proof-generated test oracles (Opportunity 7)

- **(a) Proof-vs-testing payoff:** uniquely *doesn't* require the production code
  to be proven — only the oracle — so it converts the thesis into immediate
  value against *existing, unverified* TS. It is the on-ramp: every other
  opportunity is a harder sell until people see this one work.
- **(b) Roadmap timing:** earliest. Enabled at **M1** (pure specs) and fully at
  **M2** (inductives/`Ord`). No M4/M5 dependency for the core demo.
- **(c) Demo-ability:** trivially compelling — "watch a verified Lean oracle,
  compiled to TS, catch a real bug in a naive TS sorter." No proof-assistant
  literacy required from the audience.
- **Why #1:** it is the *lowest-friction* proof-of-correctness story and it
  makes the case for the whole thesis. It also de-risks the catalog: even where
  full proof is infeasible, the oracle pattern pays off.

### 🥈 #2 — Verified parsers & protocol decoders (Opportunity 3)

- **(a) Proof-vs-testing payoff:** security-critical; "provably total and
  round-trips over *all* byte inputs" is precisely what fuzzing cannot
  establish. Replaces a fuzz corpus that never finishes with a proof that
  finishes.
- **(b) Roadmap timing:** **M2** (inductives, match, recursion) + M5
  (`String`/`ByteArray`). Lands right after M1; does not need M4.
- **(c) Demo-ability:** very high — a CBOR/JSON/UTF-8 decoder you can fuzz
  forever without a panic is a vivid, hands-on demo.
- **Why #2:** the clearest "skip the painful tests" win on a soon-enabled,
  security-relevant surface. Pairs with Opportunity 4 (shares the `String`
  Tier-1 hazard).

### 🥉 #3 — Verified Unicode / string algorithms (Opportunity 4)

- **(a) Proof-vs-testing payoff:** combinatorial Unicode is the canonical
  "exhaustive testing is infeasible" domain; idempotent normalization and exact
  UTF-8 validity are exactly the laws you want proven, not tested. And *part of
  the proof already exists in Lean* (`Init.Data.String.Decode`).
- **(b) Roadmap timing:** **M5** (faithful `String`/`Char`/`String.Pos`) — later
  than #1/#2, but M5 is the milestone that *unlocks* Opportunities 3, 7, and 8's
  text cases too, so the investment compounds.
- **(c) Demo-ability:** high and intuitive — "a TS NFC that is provably
  idempotent" and "a UTF-8 validator that accepts exactly the valid sequences"
  are crisp and universally legible.
- **Why #3:** highest *strategic* leverage: it is the showcase for the Tier-1
  `String` hazard — the foundation under every text-bearing opportunity — and
  motivates hardening that foundation first. The ROI is not just the Unicode
  library itself but the unlocked value across the catalog.

---

## 5. Trust in the transfer

The single sentence that governs everything above:

> **A Lean proof licenses a Lean program. For that license to cover the TS that
> typelean emits, typelean + its runtime must faithfully preserve Lean's
> evaluation semantics. The proof is erased; the guarantee is not — it now
> rests on the runtime.**

Concretely, the transfer has three links, each of which can break:

1. **Lower (Lean `Expr` → IR, with erasure).** Erasure must match Lean's notion
   of relevance; recursors/`casesOn`/`brecOn` must lower to faithfully-equivalent
   switch+recursion; `Nat`/`String` literals must reach their specialized
   runtime reps. *Strongest fix:* lower from **`Lean.Compiler.LCNF`** to inherit
   Lean's own erasure (`DESIGN.md` §2), shrinking this link to "Lean is correct."
2. **Emit (IR → TS).** Name mangling must be injective; currying/saturation must
   match Lean's application; TCO/trampolining must preserve termination behavior
   (JS has no guaranteed TCO).
3. **Runtime (`typelean_rt.ts`).** `Nat`/`Int` (`bigint`, truncating `-`, `div`/
   `mod`-by-zero), `UInt*`/`Fin` (exact wrap-around), `String`/`Char`
   (**codepoint length, UTF-8 byte-offset `String.Pos`**), constructors, `Array`,
   panics. **This is the load-bearing wall.** An unfaithful `Nat` or `String`
   runtime silently voids every downstream proof transfer — the proof still
   describes the Lean program, but the TS no longer matches it. This is exactly
   why the Tier-1 hazard cases (§1a table) are first-class.

**The investment is one-time and shared.** Establish the transfer once — by (i)
the M6 fidelity harness as the empirical floor over the whole targeted surface,
(ii) a proven Lower+Emit subset grown per milestone as the *guarantee*, and (iii)
lowering from LCNF to inherit Lean's erasure where the proof burden is greatest
— and **every** downstream "skip the tests" win costs only its own Lean proof.
The catalog's ROI is `(typelean-trust, once) + Σ (per-program proof)`, not a
per-program test suite plus a per-program fuzz corpus. The bigger the catalog,
the better the bet — which is the point of this document.

**And the honest limit, repeated:** proofs cover the **pure computational
core**. Effects and IO — the network, the filesystem, the clock, other processes
— are an external boundary no proof can fully close. The discipline across every
opportunity is **"prove the core, keep IO a thin trusted shell"** (`DESIGN.md`
§7): typelean ships the verified core; the unverified shell is kept small,
reviewable, and pinned by the fidelity harness. The proof narrows the attack
surface to that shell. It does not, and cannot, eliminate it.

---

*Precedents cited by name: CompCert (verified C compiler, Coq) · seL4 (verified
microkernel, Isabelle/HOL) · AWS s2n-tls + Galois (verified HMAC/DRBG,
Cryptol/SAW) · HACL\*/EverCrypt + KreMLin (verified crypto → C, F\*, Firefox
NSS) · Fiat Crypto (verified ECC arithmetic, Coq) · Verus (verified Rust, MSR)
· IronFleet (verified distributed protocols, Dafny) · Verdi (verified
distributed systems, Coq) · Disel (verified distributed protocols, Coq) ·
Flocq (verified IEEE-754/rounding, Coq; used by CompCert) · AWS Encryption SDK
(Dafny → .NET, GA May 2022; the canonical "verified-in-Dafny, compiled to a
deployable target, shipped in production" showcase) · Coq extraction (verified
→ OCaml/Haskell)
· Lean `Init.Data.String.Decode` (UTF-8 encode/decode inversion, already proven
in Lean) · `smoothutf8` (mechanically verified Rust UTF-8 validator) · Isabelle
AFP "LL(1) Parser Generator" (verified JSON parser) · TRX (verified parser
interpreter, Coq) · EverParse (verified format checkers, F\*) · Frama-C/WP
(proves absence of integer overflow in C) · Fleury verified CDCL / coq-lrat
(verified SAT, Isabelle/Coq) · Lean4Lean (verifying Lean's own
kernel/typechecker, arXiv 2403.14064; first complete Lean 4 typechecker besides
the C++ reference, checks all of mathlib) · Lean `@[implemented_by]` (Lean's own
trust boundary).*

*Companion to `DESIGN.md` (§2 LCNF alternative, §4 erasure, §7 IO bridge, §11
runtime, §12 fidelity) and `ROADMAP.md` (M1–M6). Propagates
`PROTOCOL.md`.*
