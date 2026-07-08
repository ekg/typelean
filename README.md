# typelean

**typelean** is a compiler, written in **Lean 4**, that translates **Lean 4
source programs into TypeScript**. The north star is **perfect Lean 4
compatibility** and **complete translation**: every valid Lean 4 program is
accepted, and every construct is given defined TypeScript semantics so that the
translated program reproduces Lean's evaluation behavior.

```
   Lean 4 source ──Frontend──▶ Environment ──Lower──▶ IR ──Emit──▶ TypeScript
   (Lean.Elab)                  (Lean.Expr,      (erase types/   (against a
                                 type-checked)     proofs/u)        hand-written
                                                                   runtime)
```

## Why?

Lean is a proof assistant. If typelean faithfully compiles **verified Lean** to
TypeScript, the emitted TS **inherits the Lean proofs of correctness**. This
opens a path to building software where *proof-of-correctness* substitutes for
*painful testing* — especially on hard problems where exhaustive testing is
infeasible: astronomical input spaces, arithmetic/Unicode edge cases,
state-space explosion, invariant maintenance across millions of operations.

The proof is *erased* (`Prop`/`Sort`/universes carry no runtime content). What
survives is the verified computational core; its guarantee reaches the TS output
**only if** typelean + its runtime faithfully reproduce Lean's evaluation
semantics. That "only if" is the whole game — see
[`DESIGN.md`](DESIGN.md) and [`OPPORTUNITIES.md`](OPPORTUNITIES.md).

## Status

**M1 (in progress)** — the pipeline compiles end-to-end for a growing set of
programs. `def main := IO.println "hello"` is verified to produce identical
output from `lean` and `node`. See [`ROADMAP.md`](ROADMAP.md) for the milestone
plan and [`tests/fidelity/`](tests/fidelity/) for the parity harness.

| Stage | Module | Status |
|---|---|---|
| 1 — Frontend (`Lean.Elab` reuse) | [`Typelean/Frontend.lean`](Typelean/Frontend.lean) | ✅ |
| 2 — Lower (`Expr → IR`, erasure) | [`Typelean/Lower.lean`](Typelean/Lower.lean) | ✅ (M1 cut) |
| 3 — Emit (`IR → TypeScript`) | [`Typelean/Emit.lean`](Typelean/Emit.lean) | ✅ (M1 cut) |
| Runtime (Lean value model in TS) | [`runtime/typelean_rt.ts`](runtime/typelean_rt.ts) | ✅ (M1 cut) |

## How it works

1. **Frontend** runs Lean's own elaborator (`Lean.Elab`) on the source. typelean
   never re-implements parsing, macro expansion, type-class resolution, coercion
   insertion, universe inference, `do`-notation, or termination checking — it
   inherits all of it *verbatim* from Lean. This is the core of the
   compatibility strategy.
2. **Lower** takes the elaborated `Lean.Expr` and translates it to an untyped
   IR, *erasing* types, proofs, and universe levels. Type-class dispatch is
   dissolved with `Lean.Meta.reduce` (under `TransparencyMode.instances`); a
   binder is erased when its type is a `Sort` or a `Prop`.
3. **Emit** renders the IR as a self-contained TypeScript ES module, backed by
   a hand-written runtime that reproduces Lean's value model: tagged
   constructor objects, curried closures, arbitrary-precision `Nat`/`Int`
   (`BigInt`), Unicode-aware `String`/`Char` (codepoint semantics), and `IO`
   modeled as thunks.

## Build & run

Requirements: [Lean 4](https://leanprover.github.io/) (`elan`), `lake`, and
[`node`](https://nodejs.org/) (to run emitted TypeScript).

```bash
git clone https://github.com/ekg/typelean.git
cd typelean
lake build

# Compile a Lean program to TypeScript:
echo 'def main : IO Unit := IO.println "hello from typelean"' > hello.lean
lake exe typelean hello.lean        # writes TypeScript to stdout

# Run the emitted TypeScript:
lake exe typelean hello.lean > hello.mts
node hello.mts
# => hello from typelean
```

## Fidelity harness

typelean verifies "perfect compatibility" with a parity harness
([`tests/fidelity/run.sh`](tests/fidelity/run.sh)): for each test case it
captures Lean's `lean --run` output and the Node output of the emitted
TypeScript, and diffs them. A case `PASS`es only when they match exactly.

```bash
bash tests/fidelity/run.sh
```

## Project layout

```
Typelean/
  Frontend.lean   # stage 1 — Lean.Elab → Environment
  IR.lean         # the untyped IR (stable contract between Lower & Emit)
  Lower.lean      # stage 2 — Expr → IR with type/proof erasure
  Emit.lean       # stage 3 — IR → TypeScript text
  Pipeline.lean   # end-to-end driver
runtime/
  typelean_rt.ts  # the Lean value-model runtime in TypeScript
tests/fidelity/   # parity harness + cases
DESIGN.md         # architecture (living document)
ROADMAP.md        # milestones M0–M6
OPPORTUNITIES.md  # research catalog: proof-of-correctness over testing
SURVEY.md         # prior-art survey of Lean→X compilers & verified compilers
```

## Documentation

- **[`docs/USAGE.md`](docs/USAGE.md)** — usage guide (honest, grounded in current M1 state):
  install, first compile, pipeline diagram, what works / what doesn't, fidelity
  harness, and proof-carrying thesis.

## Autopoietic development

typelean is being built with an autopoietic task-graph agent system (`wg`): a
spark task fans out subtasks that fan out further until the objective is
complete. Agents work in isolated git worktrees against a frozen IR contract;
the fidelity harness is the ground-truth quality gate (a program either matches
Lean's output or it doesn't).

## License

See the repository. Contributions welcome — the fidelity corpus is the fastest
way to help: add a Lean program to `tests/fidelity/cases/` and the harness will
check whether typelean reproduces Lean's behavior.
