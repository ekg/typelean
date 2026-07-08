#!/usr/bin/env bash
# typelean deterministic parity gate (M2 acceptance).
#
# This is the GROUND-TRUTH gate for compiler-implementation tasks — not an LLM
# opinion. An agent's "done" is only accepted when this script exits 0.
#
# What it checks:
#   1. `lake build` is clean (the compiler compiles).
#   2. `bash tests/fidelity/run.sh` runs and every case reports PASS
#      (0 FAIL, 0 BLOCKED) — i.e. `lean --run` output == `node` output for the
#      whole corpus.
#
# Exit 0 iff the full corpus is green. Non-zero (with the failing cases listed)
# otherwise. Used as the blocking acceptance check for `typelean-m2-recursor`
# and any subsequent implementation task that changes lowering/emission.
#
# Usage: bash scripts/check-parity.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "▶ lake build"
if ! lake build 2>&1 | tail -3; then
  echo "✗ BUILD FAILED — parity gate cannot proceed."
  exit 2
fi

echo
echo "▶ tests/fidelity/run.sh"
# Capture full output; the harness exits 1 if any case is not PASS.
HARNESS_OUT="$(bash tests/fidelity/run.sh 2>&1)" || true
echo "$HARNESS_OUT" | grep -E "^(PASS|FAIL|BLOCKED):" || true

echo
SUMMARY="$(echo "$HARNESS_OUT" | grep -E "Fidelity summary:")"
echo "$SUMMARY"

# Require: 0 failed AND 0 blocked.
if echo "$SUMMARY" | grep -qE "0 failed, 0 blocked"; then
  echo
  echo "✓ PARITY GATE GREEN — full corpus passes (lean ≟ node)."
  exit 0
else
  echo
  echo "✗ PARITY GATE RED — failing cases:"
  echo "$HARNESS_OUT" | grep -E "^FAIL:|^BLOCKED:" || true
  echo
  echo "  'done' is NOT accepted while any case is FAIL or BLOCKED."
  exit 1
fi
