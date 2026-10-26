#!/usr/bin/env bash
# wait-reviewer.sh <orch-dir> [timeout-ms]
# Wait until the reviewer agent settles, then print the report.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/orchestration-state.sh"

ORCH_DIR="$1"; TIMEOUT="${2:-900000}"
[ -z "$ORCH_DIR" ] && { echo "Usage: wait-reviewer.sh <orch-dir> [timeout-ms]"; exit 1; }

NAME=$(read_state "$ORCH_DIR" '.reviewer.agentName')
if [ -z "$NAME" ] || [ "$NAME" = "null" ]; then echo "no reviewer was started"; exit 1; fi

REPORT=$(read_state "$ORCH_DIR" '.reviewer.reportFile')
REPORT_UNIX="$(cygpath -u "$REPORT" 2>/dev/null || printf '%s' "$REPORT")"

# Wait for working first (a fresh prompt leaves the agent idle briefly), then settle.
for _ in $(seq 1 20); do
  herdr agent get "$NAME" 2>&1 | grep -q '"agent_status":"working"' && break
  [ -s "$REPORT_UNIX" ] && break
  sleep 1
done
herdr agent wait "$NAME" --timeout "$TIMEOUT" >/dev/null 2>&1

if [ -s "$REPORT_UNIX" ]; then
  update_state "$ORCH_DIR" '.reviewer.status' complete
  echo "=== review report ==="
  cat "$REPORT_UNIX"
else
  update_state "$ORCH_DIR" '.reviewer.status' failed
  echo "reviewer settled but wrote no report at $REPORT"
  exit 1
fi
