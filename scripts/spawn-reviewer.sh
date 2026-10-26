#!/usr/bin/env bash
# spawn-reviewer.sh <orch-dir>
# Start the reviewer as an independent agent in a new pane. It has no memory of
# the workers' sessions: it reads the results and the real project files.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/orchestration-state.sh"

ORCH_DIR="$1"
[ -z "$ORCH_DIR" ] && { echo "Usage: spawn-reviewer.sh <orch-dir>"; exit 1; }

STATUS=$(read_state "$ORCH_DIR" '.reviewer.status')
if [ "$STATUS" = "skipped" ]; then echo "review skipped by plan"; exit 0; fi

CWD=$(read_state "$ORCH_DIR" '.cwd')
[ -z "$CWD" ] || [ "$CWD" = "null" ] && CWD="$(pwd)"
ORCH_ID=$(read_state "$ORCH_DIR" '.id')
MAIN_NAME=$(read_state "$ORCH_DIR" '.mainAgent'); { [ -z "$MAIN_NAME" ] || [ "$MAIN_NAME" = "null" ]; } && MAIN_NAME=orch-main
SHORT=$(printf '%s' "$ORCH_ID" | tr -c 'a-z0-9\n' '-' | tr 'A-Z' 'a-z' | cut -c1-8)
NAME=$(printf 'o%s-reviewer' "$SHORT" | cut -c1-31)

WORKER_CMD=$(read_state "$ORCH_DIR" '.workerCmd')
{ [ -z "$WORKER_CMD" ] || [ "$WORKER_CMD" = "null" ]; } && WORKER_CMD="${HERDR_WORKER_CMD:-}"

# New pane next to the orchestrator.
SPLIT_ARGS=(pane split --direction right --cwd "$CWD" --no-focus)
if [ -n "${HERDR_PANE_ID:-}" ]; then SPLIT_ARGS+=(--pane "$HERDR_PANE_ID"); else SPLIT_ARGS+=(--current); fi
PANE_ID=$(parse_json "$(herdr "${SPLIT_ARGS[@]}" 2>&1)" '.result.pane.pane_id')
[ -z "$PANE_ID" ] || [ "$PANE_ID" = "null" ] && { echo "ERROR: could not open a pane for the reviewer" >&2; exit 1; }

START=""
if [ -n "$WORKER_CMD" ]; then
  sleep 3
  herdr pane run "$PANE_ID" "$WORKER_CMD" >/dev/null 2>&1
  for _ in $(seq 1 30); do
    sleep 2
    herdr pane get "$PANE_ID" 2>&1 | grep -q '"agent":"claude"' && { START=ok; break; }
  done
  [ -n "$START" ] && herdr agent rename "$PANE_ID" "$NAME" >/dev/null 2>&1
else
  for _ in 1 2 3 4 5 6 7 8; do
    R=$(herdr agent start "$NAME" --kind claude --pane "$PANE_ID" --timeout 60000 -- --dangerously-skip-permissions 2>&1)
    echo "$R" | grep -q 'agent_pane_busy' || break
    sleep 2
  done
  echo "$R" | grep -q '"error"' || START=ok
  if echo "$R" | grep -q 'agent_not_ready' && herdr agent read "$NAME" --source recent-unwrapped --lines 40 2>&1 | grep -qi "trust this folder"; then
    herdr agent send-keys "$NAME" down enter >/dev/null 2>&1
    for _ in $(seq 1 10); do sleep 2; herdr agent get "$NAME" 2>&1 | grep -q '"agent_status":"idle"' && { START=ok; break; }; done
  fi
fi
[ -z "$START" ] && { echo "ERROR: reviewer did not start" >&2; update_state "$ORCH_DIR" '.reviewer.status' failed; exit 1; }

# Reviewer brief = the reviewer skill's body + this orchestration's facts.
SKILL_FILE="$SCRIPT_DIR/../skills/reviewer/SKILL.md"
BRIEF="$ORCH_DIR/reviewer-prompt.md"
{
  echo "# Review this orchestration"
  echo
  echo "- Orchestration directory: $ORCH_DIR"
  echo "- Project directory: $CWD"
  echo "- Aggregated worker results: $ORCH_DIR/all-results.md (and the *-result.md files)"
  echo "- State: $ORCH_DIR/state.json"
  echo "- Write your report to: $ORCH_DIR/review-report.md"
  echo "- Orchestrator agent: $MAIN_NAME. When the report is written, send ONE line:"
  echo "  bash \"$SCRIPT_DIR/say.sh\" \"$ORCH_DIR\" reviewer $MAIN_NAME \"review done: <READY TO COMMIT | NEEDS USER REVIEW | SIGNIFICANT ISSUES FOUND>\""
  echo "- Do not message anyone else. Use only say.sh for messaging."
  echo
  echo "You are a fresh reviewer: you did not see the workers work. Judge only from the files and the results."
  echo "Ignore any step below that says to resolve PLUGIN_ROOT, update state, or present to the user: the orchestrator does that."
  echo
  sed '1,/^---$/{/^---$/!d}' "$SKILL_FILE" | sed '1,/^---$/d' 2>/dev/null
} > "$BRIEF"

update_state "$ORCH_DIR" '.reviewer.status' running
update_state "$ORCH_DIR" '.reviewer.agentName' "$NAME"
herdr agent prompt "$NAME" "Read the file $BRIEF and carry out the review it describes. Write the report where it says." >/dev/null 2>&1
echo "Reviewer started as '$NAME' in pane $PANE_ID"
