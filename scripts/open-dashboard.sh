#!/usr/bin/env bash
# open-dashboard.sh [orch-dir]
# Open the herdr dashboard pane at the bottom of the orchestrator's tab, once.
# Needs the herdr plugin installed: herdr plugin install cheolmin/herdr-orchestrator

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/orchestration-state.sh"   # defines herdr() when it is not on PATH

PLUGIN="cheolmin.herdr-orchestrator"
ORCH_DIR="$1"
[ -z "$ORCH_DIR" ] && ORCH_DIR=$(find_active_orch)

herdr plugin list 2>/dev/null | grep -q "$PLUGIN" || { echo "dashboard plugin not installed; skipping" >&2; exit 0; }

# Already open for this orchestration? The pane id is kept in state.json.
if [ -n "$ORCH_DIR" ]; then
  OLD=$(read_state "$ORCH_DIR" '.dashboardPaneId')
  if [ -n "$OLD" ] && [ "$OLD" != "null" ] && herdr pane get "$OLD" >/dev/null 2>&1; then
    echo "dashboard already open: $OLD"
    exit 0
  fi
fi

ARGS=(plugin pane open --plugin "$PLUGIN" --entrypoint dashboard --placement split --direction down)
[ -n "${HERDR_PANE_ID:-}" ] && ARGS+=(--target-pane "$HERDR_PANE_ID")
RESULT=$(herdr "${ARGS[@]}" --no-focus 2>&1)
PANE=$(printf '%s' "$RESULT" | grep -o '"pane_id":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ -z "$PANE" ]; then
  echo "dashboard open failed: $RESULT" >&2
  exit 0
fi
[ -n "$ORCH_DIR" ] && update_state "$ORCH_DIR" '.dashboardPaneId' "$PANE" >/dev/null 2>&1
echo "dashboard opened: $PANE"
