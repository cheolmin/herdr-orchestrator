#!/usr/bin/env bash
# update-dashboard.sh <orch-dir>
# Regenerates dashboard.md; the herdr dashboard pane re-reads it every second.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/orchestration-state.sh"

ORCH_DIR="$1"
[ -z "$ORCH_DIR" ] && ORCH_DIR=$(find_active_orch)
[ -z "$ORCH_DIR" ] && exit 0

node "$SCRIPT_DIR/dashboard-text.js" "$ORCH_DIR" > "$ORCH_DIR/dashboard.txt" 2>/dev/null || true
