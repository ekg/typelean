# typelean — Completion Scope

> **What "done" means, concretely. The honest current state, the keystone gap,
> the remaining work decomposed, and the one blocker that's stopping us.**

## The completion milestone (realistic near-term: "embed verified cores")

**A curated corpus of ~30 real Lean 4 programs compiles to TypeScript and
matches Lean's `lean --run` output, character-for-character, under `node` —
covering recursive functions, inductives + pattern match, basic `List`/`Array`/
`String`, `do`-notation, `IO` (println/print/file), and proof-carrying demos —
plus the FFI/monitored-edge design for the external-library boundary, and docs
that let a stranger use it.**

This is dream (A): *verified Lean cores, embedded in larger TS apps.* The deep
dream (B) — full Lean app → TS — is the same path plus more stdlib (M5 full) and
the FFI monitor made concrete; it is *beyond* this scope, deliberately.

## Honest current state (ground truth = `scripts/check-parity.sh`)

- **Pipeline runs end-to-end.** `def main := IO.println "hello"` compiles to TS
  and matches Lean. Frontend (Lean.Elab reuse) ✅, IR ✅ (256L, frozen contract),
  Lower ✅ (494L, type-directed erasure), Emit ✅ (214L), runtime ✅ (55L).
- **Fidelity: 17 pass / 5 fail.** All 5 failures are **recursor-related**
  (`rec_nat`, `inductive_match`, `reverse-invol`, `pow-mult`, `holdout`). The
  passes are straight-line / fully-reducible-by-`Meta.reduce`.
- **The keystone gap is M2: recursor / `casesOn` / matcher lowering.** Lean
  elaborates every recursive function and every pattern match into `Nat.rec` /
  `T.casesOn` / matcher auxiliaries. Lower's M1 cut passes these through
  *structurally* → emitted TS has `undefined` holes → crash. The IR already has
  `Expr.switch` (with a `self` recursive helper) — Lower just doesn't *populate*
  it. This is the single thing between "toy" and "real functions compile."

## The blocker that's stopping us (must be named, not papered)

The autopoietic loop **cannot currently land M2**, and the reason is mechanical,
not the model being merely weak:

1. The agent (minimax-m2.7, a capable model) engages genuinely — streams show
   40–100× `Nat.rec`/`switch`/`casesOn` references — but **bails in 2–7 min**
   without committing (writes analysis, not code).
2. When the agent process exits, the **wrapper auto-marks the task `done`** —
   *without* calling `wg done`, so the smoke gate (which only fires on an
   explicit `wg done`) never runs.
3. The fail-open eval (now disabled, but the wrapper path doesn't need it) is
   moot; the **wrapper's exit→done** is the real fail-open.
4. The **worktree sweep then eats the uncommitted work** because, with no
   commit, the branch tip == main tip → `is_branch_merged` returns true →
   "safe to reap." (The source fix for this — dirty-worktree check — has not
   landed; bug report at `/home/bot/wg/BUG-worktree-sweep-destroys-uncommitted-work.md`.)

So: **agents bail → wrapper marks done → sweep destroys evidence → false-done,
gate still red.** Every M2 attempt (6042/43/44/45/46) died this way. Switching
models (flash→minimax) and toggling eval did not break the cycle because the
cycle is the wrapper + sweep, not the eval.

## Two fixes required before scoping is actionable

**F1 — stop the wrapper from auto-marking-done on agent exit** (or gate the
exit path with the smoke gate). The smoke gate exists and is correct; it's at
the wrong choke point. Either:
- the wrapper must call the smoke gate before marking done on exit (same
  `run_smoke_gate` the `wg done` path uses), refusing to mark done while a
  owned scenario is red; **or**
- the wrapper must NOT mark done on exit at all — leave the task in-progress
  and require an explicit `wg done` (which is gated).

**F2 — make commit a mechanical precondition for marking done.** The sweep
can only destroy work that is uncommitted. If `wg done` (and the wrapper's
exit-done) require a clean, committed-ahead worktree (a `git status --porcelain`
check + `git rev-list --count main..<branch> >= 1`), the sweep can never eat
real work. This is the same fix as the sweep bug, applied as a *done*
precondition.

Until F1+F2 land, **no impl task can be reliably driven through the autopoietic
loop** — the system will keep false-passing and eating work. This is the first
thing to fix in `~/wg`.

## The remaining work, scoped (post-F1/F2)

### M2 — recursor / casesOn / matcher lowering [THE keystone]
- Recognize `Nat.rec`/`T.rec`/`T.casesOn`/`T.brecOn`/matcher auxiliaries in
  `lowerApp`/`lowerGo`; rewrite to `IR.Expr.switch` (zero/succ branches, IH via
  `self`); verify Emit's `switch`→IIFE; `WellFounded.fix` as ordinary recursion.
- **Gate:** `scripts/check-parity.sh` green (the 5 recursor fails → pass).
- **Decomposition for tractability** (so a capable model succeeds at each piece,
  since the whole is where it bails):
  - M2a: `Nat.rec` only (zero + succ, IH) → makes `rec_nat`/`holdout` pass.
  - M2b: `T.casesOn` over user inductives → makes `inductive_match` pass.
  - M2c: matcher auxiliaries (`Foo.match_1`) + `below`/`brecOn` → `reverse`/`pow`.

### M4-cut — effects/IO runtime (focused, not full M4)
- `IO.print`, `IO.FS.*` (read/write file), `IO.Ref`/`ST.Ref`.
- Verify `do`/`for`/`mut` (already elaborated to folds/`forIn`) lower correctly.
- **Gate:** fidelity cases for a `do`-block program + file IO match Lean.

### M5-cut — stdlib primitives (focused)
- Runtime primitive table for `List` (map/fold/filter/append/length/reverse),
  `Array` (same), `String` (length/codepoints/append/get), `Option`/`Except`.
- `@[extern]` discovery (read `externAttr`) so unmapped externs are reported.
- **Gate:** fidelity cases exercising each, incl. truncating `Nat.sub`, div-by-zero.

### FFI — monitored-edge (the novel contribution; doc in flight → concrete)
- Take `docs/FFI.md` (the proven-inside/monitored-edge design) from design to a
  real mechanism: `@[extern]` spec declarations + emitted runtime monitors that
  assert the spec at the boundary (satisfy-or-throw).
- **Gate:** one demo where a verified core calls an external TS fn with a spec +
  monitor, and a spec-violation throws (not silently wrong).

### Corpus + synthesis
- Grow `tests/fidelity/cases/` to ~30 covering the above.
- `synthesize-demos`: `demos/` catalog + `PARITY_REPORT.md` (PASS/FAIL/BLOCKED
  counts + unsupported constructs) + README link.

## Model recommendation for the impl core

minimax-m2.7 (current) engages but bails on the hard M2 whole. Two options:
- **Decompose** M2 into M2a/b/c (above) so each piece is tractable for minimax.
- **Escalate the impl model** for M2 only to a stronger reasoning model
  (e.g. an opus/sonnet-class or gpt-5-class model via openrouter/codex), keeping
  minimax for demos/docs/eval. The M2 task is genuinely hard Lean metaprogramming.

## Sequencing

1. **F1 + F2** (in `~/wg`) — unblock the loop. Until then, nothing else is
   drivable.
2. **M2a** (Nat.rec) → M2b (casesOn) → M2c (matchers/below). Each gated.
3. **M5-cut** (stdlib primitives) — in parallel with M2 once M2a lands (they're
   independent: stdlib prims are runtime, not lowering).
4. **M4-cut** (IO) — after M2 (so recursive IO programs work).
5. **FFI monitor** — after M4-cut (needs IO).
6. **Corpus → ~30 + synthesis** — grow-through; the PARITY_REPORT drives each
   next wave.
