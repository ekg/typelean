# Smoketest Report — typelean (2026-06-25)

## System Overview
`typelean` is not an application source tree — it is a **WG (workgraph)
deployment workspace**. The repo root holds only `AGENTS.md`, `CLAUDE.md`,
`.gitignore`, and the live `.wg/` state directory (task graph, agency,
chat handlers, daemon socket/logs). The "system" under test is therefore the
**`wg` CLI itself** (`wg 0.1.0`, a Rust binary at `~/.cargo/bin/wg`) running a
**dispatcher daemon** that spawns agents through the **`claude` CLI executor**
(`claude` 2.1.191, `model=claude:opus`, `endpoint=none`).

## Build & Test Results
There is **no compilable source** in this workspace — no `Cargo.toml`,
`package.json`, `README`, or `tests/smoke/manifest.toml`. So there is no
`cargo build`/`cargo test` to run here, and **no smoke gate is attached to this
task** (`wg done` will run zero owned scenarios). For a deployment workspace the
canonical "build & test" is operational health, which I exercised directly:

| Command | Result |
|---|---|
| `wg --version` | PASS — `wg 0.1.0` |
| `wg status` | PASS — service running, 1 agent working |
| `wg service status` | PASS — daemon up, ticking every 5s (last tick #12) |
| `wg list` / `wg show` | PASS — graph readable, this task in-progress |
| `wg endpoints list` | PASS — "No endpoints configured" (expected) |
| `wg dev-check` | **WARN** — branch is `master` not `main`; couldn't read main HEAD |

No errors or panics from any `wg` invocation; the daemon dispatches cleanly.

## Health Assessment
**Verdict: HEALTHY** (two cosmetic warnings, no functional impact).
- Daemon running (PID 2388920), coordinator ticks succeeding, fs-watcher live.
- Dispatch path works end-to-end — proof: this agent (`agent-1`) was spawned via
  the `claude:opus → claude` CLI handler and is executing now.
- Graph state intact: `.wg/graph.jsonl` + `operations.jsonl` consistent; 1
  in-progress task, 0 blocked, 0 dead agents.
- Only non-INFO signals are the two flagged log lines (below) plus the benign
  `dev-check` git-branch-naming WARN.

## WG System Notes
- **Dispatcher:** running, `max_agents=10`, `executor=claude`,
  `model=claude:opus`, `poll=5s`; 1/10 agents alive. Healthy.
- **(a) `No API key found for provider 'openrouter'`** — **Cosmetic.** This is
  the background *model-registry refresh* (metadata only) probing a provider
  that has no key. `wg endpoints list` shows **no endpoints configured**, so
  openrouter is an *unused* provider — the active route `claude:opus` runs
  through the `claude` CLI (`endpoint=none`) and is unaffected. It does not gate
  dispatch; the refresh simply cooled down for 60 min. (Related, also benign:
  native lightweight calls — triage/evaluator `haiku` — lack `ANTHROPIC_API_KEY`
  and gracefully fall back to the `claude` CLI.)
- **(b) `Coordinator-0: nex subprocess exited signal: 15 (SIGTERM)`** —
  **Expected.** SIGTERM is a graceful stop, and the very next log line
  (`daemon.log:114`) explains it: chat task `.chat-0` was
  `archived/Done/Abandoned`, so the supervisor exited cleanly with no respawn. A
  normal lifecycle shutdown of a finished chat handler; the `[ERROR]` severity
  is just alarmist labeling, not a crash.

## Recommended Next Steps
- Downgrade both log lines to INFO/WARN — a metadata refresh for an unconfigured
  provider and a clean chat-handler SIGTERM should not log at `[ERROR]`.
- Add a key (`wg endpoints add` or `ANTHROPIC_API_KEY`) only if you want native
  lightweight calls / the model registry; otherwise the `claude` CLI fallback is
  fine and no action is needed.
- Optional: align git branch to `main` (or silence the `dev-check` WARN) to keep
  the dev-freshness check green.
