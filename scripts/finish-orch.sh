#!/usr/bin/env bash
# finish-orch.sh <orch-dir>
# Close an orchestration: mark it complete so it no longer counts as "active"
# (dashboard, SessionStart and Stop hooks ignore it), and print a short summary.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/orchestration-state.sh"

ORCH_DIR="$1"
[ -z "$ORCH_DIR" ] && { echo "Usage: finish-orch.sh <orch-dir>"; exit 1; }

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
update_state "$ORCH_DIR" '.status' complete
update_state "$ORCH_DIR" '.finishedAt' "$NOW"

echo "orchestration $(read_state "$ORCH_DIR" '.id'): complete"
echo "reviewer: $(read_state "$ORCH_DIR" '.reviewer.status')"
[ -f "$ORCH_DIR/messages.log" ] && echo "messages: $(wc -l < "$ORCH_DIR/messages.log") (see $ORCH_DIR/messages.log)"
