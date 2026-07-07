# typelean — Autopoiesis Protocol

**Root objective (immutable — never lose sight of this):** build **typelean** —
a compiler, written in **Lean 4**, that translates **Lean 4 source programs
into TypeScript**, with the goal of **perfect Lean 4 compatibility** and
**complete translation**. The compiler is named `typelean` and lives in this
repo (`/home/bot/typelean`). The objective is complete only when typelean
achieves perfect Lean 4 compatibility and complete translation — until then,
the work continues and fans out.

This file is the constitution of the typelean workgraph. It is referenced by
the monitor (`scripts/watchdog.sh`) and propagated (verbatim or by pointer) into
every subtask so the protocol is **viral**. See `DESIGN.md` for the architecture
and `ROADMAP.md` for milestones.

---

## Autopoiesis Protocol

- Root objective is fixed: build typelean (Lean 4 → TypeScript compiler, written
  in Lean 4, perfect compatibility, complete translation).
- Use `wg add` to create subtasks. ALWAYS run `wg publish <id>` after `wg add` —
  drafts are invisible to the dispatcher and stall the graph.
- Every code task MUST include a `## Validation` section with concrete
  build/test criteria (`lake build`, `lake test`, behavior tests, fidelity
  checks).
- Include this Protocol section (or a pointer to `PROTOCOL.md`) in every
  subtask so the protocol is viral.
- Guardrails: max 10 child tasks per agent, max task depth 8. If you need more
  breadth, create subtasks that themselves fan out.
- Parallel work on different files is encouraged; ALWAYS add an integrator task
  (`wg add "Integrate X" --after part-a,part-b`) to merge parallel work. Never
  parallelize tasks that modify the same files.
- Worker hygiene: check messages (`wg msg read <task>` before AND after), reply
  to unread ones, log progress (`wg log <task> "..."`), record artifacts
  (`wg artifact <task> <path>`), stage surgically (never `git add -A`), push if
  a remote exists.
- When a milestone completes, update `ROADMAP.md` and create the next milestone's
  subtasks.
- The objective is complete only when typelean achieves perfect Lean 4
  compatibility and complete translation. Until then, keep fanning out. A
  monitor nudges the graph if it goes quiet.
- If you discover a gap, a bug, or missing design — create a subtask for it;
  don't wait for permission.

---

## Graph shape & conventions

- **Pipeline stages map to subtasks** (see `DESIGN.md` §13 for the module map):
  Frontend (`Typelean.Frontend`) → Lower (`Typelean.Lower`) → Emit
  (`Typelean.Emit`), joined by `Typelean.Pipeline`. Each stage is owned by a
  distinct subtask and a distinct file; the integrator (`typelean-integrate-m1`)
  wires the end-to-end pipeline and the fidelity test.
- **File ownership is exclusive.** No two parallel subtasks may modify the same
  file. When in doubt, serialize with `--after`.
- **Integrator at every join.** Parallel work always converges on an
  `Integrate …` task (`--after` all parallel parts). Never leave parallel work
  unmerged.
- **Validation is concrete.** A task is done when its `## Validation` checklist
  passes (`lake build` clean, `lake test` / fidelity cases green, no
  regressions). No silent drops: any unhandled construct yields a stage-tagged
  `CompileError` and is filed as a follow-up subtask.
- **The graph is alive.** Any agent may `wg add` follow-ups, bug fixes, or
  design-gap subtasks; the coordinator dispatches them without permission.

## Milestone cadence

When a milestone in `ROADMAP.md` completes, the completing agent:

1. updates `ROADMAP.md` (mark ✅, record what was verified), and
2. creates + `wg publish`es the next milestone's subtasks (each with a
   `## Validation` section and a pointer to this protocol).

The objective is complete only when M6's parity suite passes across the
targeted Lean surface AND the compatibility report in `ROADMAP.md` shows no
remaining gaps. Until then — keep fanning out.
