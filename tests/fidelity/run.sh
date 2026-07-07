#!/usr/bin/env bash
# typelean fidelity harness (DESIGN §12; ROADMAP M1/M6).
#
# For each `cases/*.lean`, capture Lean's `lean --run` output and the Node
# output of the emitted TypeScript, and diff them. `BLOCKED` = `typelean`
# itself failed (a stage-tagged CompileError); reported with the stage + first
# error line, never silent (DESIGN §1.4). `BLOCKED` is non-pass: the suite is
# not green while cases are blocked (the expected pre-worker-landing state).
#
# Exit code: 0 iff every case PASSes (no FAIL, no BLOCKED); 1 otherwise.
set -u

# Self-locate the project root (this script is at tests/fidelity/run.sh).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CASES_DIR="$SCRIPT_DIR/cases"

LEAN="${LEAN:-lean}"
NODE="${NODE:-node}"
# Prefer the pre-built binary (lake test builds it); fall back to `lake exe`.
TYPELEAN="${TYPELEAN:-}"
if [ -z "$TYPELEAN" ]; then
  if [ -x "$ROOT/.lake/build/bin/typelean" ]; then
    TYPELEAN="$ROOT/.lake/build/bin/typelean"
  else
    TYPELEAN="lake exe typelean --"
  fi
fi

pass=0; fail=0; blocked=0
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# `lean --run` requires `lean` to be the Lean binary on PATH (elan provides it
# inside `lake env`; when run via `lake test`/`lake exe` the PATH is already set).
shopt -s nullglob
for c in "$CASES_DIR"/*.lean; do
  name="$(basename "$c" .lean)"

  # 1. Lean result.
  lean_out="$("$LEAN" --run "$c" 2>"$tmp/$name.lean.err")"; lean_rc=$?
  if [ "$lean_rc" -ne 0 ]; then
    echo "FAIL: $name — lean --run failed (rc=$lean_rc): $(head -1 "$tmp/$name.lean.err")"
    fail=$((fail + 1)); continue
  fi

  # 2. Compile with typelean → TypeScript.
  ts_out="$("$TYPELEAN" "$c" 2>"$tmp/$name.tcerr")"; ts_rc=$?
  if [ "$ts_rc" -ne 0 ]; then
    # typelean writes "typelean: <stage>: <msg>" to stderr (Main.lean).
    line="$(head -1 "$tmp/$name.tcerr")"
    echo "BLOCKED: $name — typelean failed (rc=$ts_rc): $line"
    blocked=$((blocked + 1)); continue
  fi

  # 3. Run the emitted TS under Node (`.mts` = ESM + Node type-stripping, so
  #    both typed and untyped output run; DESIGN §1.3, §5).
  ts_file="$tmp/$name.mts"
  printf '%s\n' "$ts_out" > "$ts_file"
  node_out="$("$NODE" "$ts_file" 2>"$tmp/$name.node.err")"; node_rc=$?
  if [ "$node_rc" -ne 0 ]; then
    echo "FAIL: $name — node failed (rc=$node_rc): $(head -1 "$tmp/$name.node.err")"
    fail=$((fail + 1)); continue
  fi

  # 4. Diff (command substitution already normalized trailing newlines on both).
  if [ "$lean_out" = "$node_out" ]; then
    echo "PASS: $name — '$lean_out'"
    pass=$((pass + 1))
  else
    echo "FAIL: $name — lean='$lean_out' != node='$node_out'"
    fail=$((fail + 1))
  fi
done

echo ""
echo "Fidelity summary: $pass passed, $fail failed, $blocked blocked"

if [ "$((fail + blocked))" -eq 0 ]; then
  exit 0
else
  exit 1
fi
