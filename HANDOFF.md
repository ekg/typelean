# HANDOFF — typelean (Lean4 → TypeScript compiler)

**Written:** 2026-07-07 · **For:** a fresh chat session resuming this project.
**TL;DR:** The spark ran, produced a real M0 skeleton + design docs, then the
provider went down. The spark never called `wg done`, so it's stuck in
`failed-pending-eval` and the FLIP/eval machinery has been **churning ~12 days
(5767 dead agents)**. Nothing is lost — the work is on disk, uncommitted. Fix
the provider, resolve the stuck spark, clean up, commit, then fan out.

---

## 1. Mission (unchanged, immutable)

Build **typelean**: a compiler **written in Lean 4** that translates **Lean 4
source → TypeScript**, targeting **perfect Lean 4 compatibility** and
**complete translation**. Lives in `/home/bot/typelean`. Built with `lake`
(Lean toolchain at `~/.elan`).

The design is **autopoietic**: a spark task establishes form + design and fans
out into subtasks; each subtask is empowered to fan out further; a recurring
monitor nudges the graph if it goes quiescent. Continues until the objective
is done (a `DONE.marker` sentinel stands the monitor down).

## 2. What actually got done (it's real, on disk, **uncommitted**)

The spark agent (`typelean-spark`) produced Phase 0 before exiting:

- **Lean project skeleton** — `lakefile.lean`, `lean-toolchain`
  (`leanprover/lean4:v4.31.0`), `Main.lean`, `Typelean.lean`, and
  `Typelean/{Basic,IR,Frontend,Lower,Emit,Pipeline}.lean`. Per the spark log:
  *"M0 skeleton: lake project 'typelean' initialized; pipeline module scaffold
  builds (18 jobs); 'import Lean' works in-project; CLI prints version
  banner."* So `lake build` was passing.
- **`DESIGN.md`** (23 KB, 13 sections) — real architecture: pipeline
  (Frontend via `Lean.Elab` → Lower `Expr→IR` with erasure → Emit `IR→TS`),
  typeclass/coercion, monads/do/effects, quotients/Decidable, FFI/`@[extern]`,
  universes, runtime strategy, fidelity testing, module map.
- **`ROADMAP.md`** (7.4 KB) — milestones **M0 ✅ / M1 🚧 / M2–M6 ⬜ / Beyond M6**.
- **`.github/workflows/lean_action_ci.yml`** — Lean Action CI on push/PR.
- **`scripts/watchdog.sh`** — the monitor's payload (see §5).
- `SMOKESTEST_REPORT.md` — the very first task (WG-workspace health check, done).

**Git has NO commits** — everything above is untracked in the working tree.

## 3. Current broken state (as of 2026-07-07 09:39 UTC)

- **`typelean-spark`** → status `failed-pending-eval` (assigned agent-8, opus).
  It exited with code 1 *without* `wg done` on 2026-06-24. Awaiting a rescue
  eval from `.evaluate-typelean-spark` (needs score ≥ 0.70).
- **Runaway FLIP/eval churn** — `.flip-typelean-spark` / `.evaluate-*` have
  been retrying for ~12 days → **5767 dead agents** (mostly `.flip-typelean-spark`
  claude agents). `wg agents` shows them aged 5–12 days, all dead.
- **Provider is broken right now.** Config was switched from `claude:opus`
  (original, went down) to `pi:lunaroute:glm-5.2-nvfp4`. That resolves via the
  pi-handler to `openrouter:z-ai/glm-5.2`, but the pi-plugin errors:
  `Provider wg, model z-ai/glm-5.2: no "api" specified.` So **nothing can
  dispatch successfully** until the model/provider is fixed.
  - Good news: `wg key list` shows **openrouter key is present**
    (`keyring:openrouter ✓`).
- **Two agents currently "alive"** (both will fail on the broken provider):
  `agent-5769` on `.flip-typelean-spark`, `agent-5768` on `typelean-monitor`.
- **Monitor** (`typelean-monitor`): recurring cron shell task
  (`0 */15 * * * *`, payload `scripts/watchdog.sh`). Status `done` + flagged
  **1 overdue** (it's a recurring cron). It has fired before but can't make
  progress while the provider is down.

## 4. Recommended recovery sequence (do this first)

```bash
cd /home/bot/typelean

# 4a. FIX THE PROVIDER (the root blocker). Pick a working one:
wg executors                 # what's installed/usable
wg key list                  # openrouter key is present
# Option 1 — back to Claude (if Anthropic is up again):
wg config -m claude:opus
# Option 2 — OpenRouter directly (key present), e.g.:
wg config -m openrouter:anthropic/claude-sonnet-4-5
# (then) wg endpoints add  if no default endpoint; verify with a tiny test task.

# 4b. STOP THE CHURN. Kill the stuck FLIP/eval agents + purge dead ones:
wg kill --all                # SIGTERM all agents (they're failing anyway)
wg dead-agents --purge       # clear the 5767 dead agents

# 4c. RESOLVE THE STUCK SPARK. Its Phase-0 work is essentially done — accept it:
wg done typelean-spark       # accept the real M0 deliverables (preferred)
#   (if you'd rather re-run cleanly: wg fail typelean-spark --reason "provider down, retry fresh" && wg retry typelean-spark)
wg gc                        # clean failed/abandoned scaffolding

# 4d. COMMIT THE WORK (it's all uncommitted!):
git add lakefile.lean lean-toolchain Main.lean Typelean.lean Typelean/ \
        DESIGN.md ROADMAP.md README.md .github/ .gitignore scripts/
git commit -m "M0: typelean skeleton + DESIGN + ROADMAP (from typelean-spark)"

# 4e. VERIFY BUILD + DISPATCHER:
lake build
wg service restart
wg status
```

## 5. Then: resume the autopoietic fan-out

The spark never created its subtasks (it exited before fanning out). After
recovery, the next job is to **create + publish the first implementation
wave** per `ROADMAP.md` (M1 🚧 is next). Each subtask:

- MUST include a `## Validation` section with concrete `lake build`/test criteria.
- MUST propagate the **Autopoiesis Protocol** (publish every `wg add`;
  `wg publish <id>` immediately — drafts are invisible to the dispatcher and
  stall the graph; fan out further as needed; respect guardrails **max 10
  children/agent, depth 8**; add an integrator task for parallel joins; check
  messages before/after).
- Use `--no-place` on `wg add` so tasks dispatch immediately (no draft/publish
  dance) — `--no-place` is what made `typelean-spark`/`typelean-monitor` open
  on creation.

The canonical subtask description template + protocol block is in the spark
task (`wg show typelean-spark`); mirror it into children.

## 6. Key artifacts / state pointers

| Thing | Where |
|---|---|
| Spark task (failed-pending-eval, has the design) | `typelean-spark` (`wg show typelean-spark`) |
| Monitor (recurring cron, payload is a script) | `typelean-monitor` (`wg show typelean-monitor`) |
| Monitor payload | `scripts/watchdog.sh` (releases drafts, retries failures, injects `mnudge-*` LLM tasks when quiescent; stands down on `DONE.marker`) |
| Design | `DESIGN.md` |
| Roadmap | `ROADMAP.md` (M0 ✅, M1 🚧 next) |
| Lake project | `lakefile.lean`, `Typelean/`, `Main.lean`, `lean-toolchain` (v4.31.0) |
| CI | `.github/workflows/lean_action_ci.yml` |
| WG config | `.wg/config.toml` (auto_assign + auto_evaluate ON; max_agents 10) |

## 7. Known gotchas

- `wg add` from the chat shell defaults to **draft (paused)**; **always pass
  `--no-place`** (immediate dispatch) or run `wg publish <id>` right after.
- The earlier `wg dev-check` WARN: branch is `master` (not `main`) — cosmetic.
- `auto_evaluate=true` scaffolds `.assign-*`/`.flip-*`/`.evaluate-*` around
  every LLM task — that's what churned for 12 days when the provider was down.
  If the provider is flaky, consider `wg config --auto-evaluate false`
  temporarily to stop the eval runaway, then re-enable.
- Self-loop cycles are **not** allowed (`wg edit X --add-after X` → "cannot
  block itself"). The monitor uses **cron** instead, which is the supported
  recurring mechanism.

## 8. The one-line status for the new chat

> Provider down → spark stuck in `failed-pending-eval` → ~12 days of dead-agent
> churn → work is on disk, uncommitted, and good. Fix provider (`wg config -m …`),
> `wg kill --all` + `wg dead-agents --purge`, `wg done typelean-spark`, commit,
> then fan out M1 subtasks per `ROADMAP.md` (each `--no-place`, with
> `## Validation` + the autopoiesis protocol).
