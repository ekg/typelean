#!/usr/bin/env bash
# typelean graph watchdog.
# Keeps the autopoietic task set from going quiescent/stuck. Runs ~every 15 min
# via a WG cron shell task. Safe + idempotent: re-running is harmless.
# Stands down once DONE.marker exists (objective complete).
set -u
REPO=/home/bot/typelean
cd "$REPO" 2>/dev/null || exit 0

WG_DIR="$REPO/.wg"
LOG="$WG_DIR/watchdog.log"
NUDGE_COUNT="$WG_DIR/watchdog.nudge"
SENTINEL="$REPO/DONE.marker"
GRAPH="$WG_DIR/graph.jsonl"
PROTOCOL="$REPO/PROTOCOL.md"

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "[$(ts)] $*" >> "$LOG"; }

log "tick"

# 0. Objective complete → stand down.
if [[ -f "$SENTINEL" ]]; then
  log "OBJECTIVE COMPLETE (DONE.marker present) — standing down"
  exit 0
fi

# 1. Dispatcher must be alive or nothing dispatches.
if ! wg service status >/dev/null 2>&1; then
  log "dispatcher DOWN — starting"
  wg service start >>"$LOG" 2>&1 || log "ERROR: could not start service"
fi

# 2. Tally graph state across ALL tasks (incl. agency .assign/.evaluate).
active=$(jq -r 'select(.kind=="task" and (.status=="ready" or .status=="in-progress")) | .id' "$GRAPH" 2>/dev/null | wc -l)
# user tasks only (id not starting with '.')
drafts=$(jq -r 'select(.kind=="task" and (.id|startswith(".")|not) and (.status=="paused" or .status=="waiting")) | .id' "$GRAPH" 2>/dev/null)
failed=$(jq -r 'select(.kind=="task" and (.id|startswith(".")|not) and .status=="failed") | .id' "$GRAPH" 2>/dev/null)
blocked=$(jq -r 'select(.kind=="task" and (.id|startswith(".")|not) and .status=="blocked") | .id' "$GRAPH" 2>/dev/null)

log "active(ready+in-progress)=$active drafts=$(echo "$drafts"|wc -l) failed=$(echo "$failed"|wc -l) blocked=$(echo "$blocked"|wc -l)"

# 3. Release unpublished drafts first — that's trapped work.
if [[ -n "$drafts" ]]; then
  log "releasing drafts: $(echo "$drafts" | tr '\n' ' ')"
  echo "$drafts" | while read -r pid; do
    [[ -n "$pid" ]] && { wg publish "$pid" --wcc >>"$LOG" 2>&1 && log "published $pid (--wcc)"; }
  done
  exit 0
fi

# 4. Active work exists → healthy, do nothing.
if (( active > 0 )); then
  log "active work present — healthy"
  exit 0
fi

# 5. Quiescent. Retry a failed user task if one exists.
frst=$(echo "$failed" | head -1)
if [[ -n "$frst" ]]; then
  log "quiescent + failed task $frst — retrying"
  wg retry "$frst" >>"$LOG" 2>&1 && log "retried $frst"
  exit 0
fi

# 6. Don't stack nudges — skip if a non-terminal nudge already exists.
existing=$(jq -r 'select(.kind=="task" and (.id|startswith("mnudge-")) and (.status!="done" and .status!="failed" and .status!="abandoned")) | .id' "$GRAPH" 2>/dev/null | head -1)
if [[ -n "$existing" ]]; then
  log "nudge already pending ($existing) — skipping"
  exit 0
  : "${existing:-}" # no-op to satisfy set -u branch
fi

# 7. Fully quiescent / stuck — inject an LLM nudge to drive the objective forward.
n=$(($(cat "$NUDGE_COUNT" 2>/dev/null || echo 0)+1))
echo "$n" > "$NUDGE_COUNT"
nid="mnudge-$(date +%s)"
proto=""
[[ -f "$PROTOCOL" ]] && proto=$(cat "$PROTOCOL")

title="Monitor nudge #$n: graph quiescent — drive typelean forward"
desc="## Context
The typelean graph watchdog found the task graph quiescent (0 ready, 0 in-progress, no unpublished drafts, no retryable failures) but the objective is NOT complete (no DONE.marker).

## Objective (unchanged, root goal)
Build **typelean** — a compiler, written in Lean 4, that translates Lean 4 source into TypeScript with **perfect Lean 4 compatibility** and complete translation. See DESIGN.md and ROADMAP.md (create them on the first nudge if they don't exist yet, per the root spark task).

## Your job
1. \`wg list\`, \`wg status\`, \`wg viz\` to assess current state.
2. Read DESIGN.md / ROADMAP.md to find the next unstarted/incomplete milestone.
3. Either resume stuck work (\`wg retry\`/\`wg resume\`) or create + **publish** the next wave of subtasks.
4. \`wg publish <id>\` EVERY subtask you create — drafts are invisible to the dispatcher.
5. Keep going until the graph is producing again.

## Autopoiesis Protocol (propagate verbatim into every subtask)
${proto:-See PROTOCOL.md at repo root. Publish every wg add. Create more subtasks as needed. Each subtask must include a ## Validation section and this protocol section. Respect guardrails: max 10 children/agent, depth 8. Integrate parallel work with an integrator task.}

## Validation
- [ ] Graph is no longer quiescent after your run (>=1 ready/in-progress user task)
- [ ] Any new subtasks are published (not drafts)
- [ ] Progress made toward a milestone in ROADMAP.md"

log "quiescent — injecting nudge $nid (nudge #$n)"
out=$(wg add "$title" --id "$nid" -d "$desc" --model sonnet --no-place 2>&1)
log "wg add: $out"
if echo "$out" | grep -qiE 'paused|draft'; then
  wg publish "$nid" >>"$LOG" 2>&1 && log "published nudge $nid"
fi
exit 0
