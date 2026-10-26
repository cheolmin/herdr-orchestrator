#!/usr/bin/env bash
# spawn-agents.sh <orch-dir> <wave-index>
# Splits herdr panes (alternating right/down) and starts one Claude Code agent
# per pane via `herdr agent start`, then submits the mission prompt.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/orchestration-state.sh"

ORCH_DIR="$1"
WAVE_IDX="$2"
[ -z "$ORCH_DIR" ] || [ -z "$WAVE_IDX" ] && { echo "Usage: spawn-agents.sh <orch-dir> <wave-index>"; exit 1; }

if ! bash "$SCRIPT_DIR/detect-herdr.sh" >/dev/null; then
  echo "herdr unavailable — writing pending spawn file for degraded mode" >&2
  node "$JSON_TOOL" query "$ORCH_DIR/state.json" wave-agents "$WAVE_IDX" > "$ORCH_DIR/wave-${WAVE_IDX}-pending-spawn.json"
  exit 0
fi

CWD=$(read_state "$ORCH_DIR" '.cwd')
[ -z "$CWD" ] || [ "$CWD" = "null" ] && CWD="$(pwd)"
ORCH_ID=$(read_state "$ORCH_DIR" '.id')
# Worker launcher: state.json .workerCmd (set from the user's request) wins,
# then the HERDR_WORKER_CMD environment variable, else plain claude.
WORKER_CMD=$(read_state "$ORCH_DIR" '.workerCmd')
{ [ -z "$WORKER_CMD" ] || [ "$WORKER_CMD" = "null" ]; } && WORKER_CMD="${HERDR_WORKER_CMD:-}"
SHORT=$(printf '%s' "$ORCH_ID" | tr -c 'a-z0-9\n' '-' | tr 'A-Z' 'a-z' | cut -c1-8)

# Agent names must match [a-z][a-z0-9_-]{0,31}
safe_name() {
  local n
  n=$(printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9_\n-' '-' | cut -c1-31)
  case "$n" in [a-z]*) ;; *) n="a$n" ;; esac
  printf '%s' "$n" | cut -c1-31
}

# Name the orchestrator's own agent so workers can message it.
MAIN_NAME="${HERDR_MAIN_NAME:-orch-main}"
if [ -n "${HERDR_PANE_ID:-}" ]; then
  herdr agent rename "$HERDR_PANE_ID" "$MAIN_NAME" >/dev/null 2>&1 || true
fi
update_state "$ORCH_DIR" '.mainAgent' "$MAIN_NAME" >/dev/null 2>&1 || true
HERDR_BIN_UNIX="$(cygpath -u "${HERDR_BIN_PATH:-herdr}" 2>/dev/null || printf '%s' "${HERDR_BIN_PATH:-herdr}")"

# Dashboard first: while the orchestrator pane still spans the full width, a
# bottom split gives a full-width dashboard. Workers then split the top area.
if [ "${HERDR_NO_DASHBOARD:-}" != 1 ]; then
  bash "$SCRIPT_DIR/open-dashboard.sh" "$ORCH_DIR" >/dev/null 2>&1 || true
fi

# Start from the orchestrator pane; split the most recent new pane each time,
# alternating direction so panes stay usable.
TARGET="${HERDR_PANE_ID:-}"
DIR=right
IDX=0
while IFS= read -r agent; do
  [ -z "$agent" ] && continue
  AGENT_ID=$(parse_json "$agent" '.id')
  AGENT_LABEL=$(parse_json "$agent" '.label')
  NAME=$(safe_name "o${SHORT}-${AGENT_ID}")
  # Agent ids already look like "agent-a"; the skill writes {id}-prompt.md.
  PROMPT_FILE="$ORCH_DIR/${AGENT_ID}-prompt.md"
  [ -f "$PROMPT_FILE" ] || PROMPT_FILE="$ORCH_DIR/agent-${AGENT_ID}-prompt.md"

  SPLIT_ARGS=(pane split --direction "$DIR" --cwd "$CWD" --no-focus)
  if [ -n "$TARGET" ]; then SPLIT_ARGS+=(--pane "$TARGET"); else SPLIT_ARGS+=(--current); fi
  SPLIT_RESULT=$(herdr "${SPLIT_ARGS[@]}" 2>&1)
  PANE_ID=$(parse_json "$SPLIT_RESULT" '.result.pane.pane_id')
  if [ -z "$PANE_ID" ] || [ "$PANE_ID" = "null" ]; then
    echo "ERROR: pane split failed for $AGENT_ID: $SPLIT_RESULT" >&2
    update_agent "$ORCH_DIR" "$AGENT_ID" "status=failed"
    continue
  fi

  START_RESULT=""
  if [ -n "$WORKER_CMD" ]; then
    # User-defined launcher (e.g. a PowerShell function like ccc-sonnet-skip).
    # herdr detects the agent from the running process; name it afterwards.
    for _try in 1 2 3 4 5 6 7 8; do
      herdr pane get "$PANE_ID" 2>&1 | grep -q '"terminal_title"' && break
      sleep 1
    done
    sleep 2
    herdr pane run "$PANE_ID" "$WORKER_CMD" >/dev/null 2>&1
    READY=""
    for _try in $(seq 1 30); do
      sleep 2
      if herdr pane get "$PANE_ID" 2>&1 | grep -q '"agent":"claude"'; then READY=1; break; fi
    done
    if [ -z "$READY" ]; then
      START_RESULT='{"error":{"code":"worker_cmd_not_detected"}}'
    else
      herdr agent rename "$PANE_ID" "$NAME" >/dev/null 2>&1
    fi
  else
    # A fresh pane may not show its shell prompt yet: retry while the pane is busy.
    for _try in 1 2 3 4 5 6 7 8; do
      START_RESULT=$(herdr agent start "$NAME" --kind claude --pane "$PANE_ID" --timeout 60000 -- --dangerously-skip-permissions 2>&1)
      echo "$START_RESULT" | grep -q 'agent_pane_busy' || break
      sleep 2
    done
  fi
  if echo "$START_RESULT" | grep -q 'agent_not_ready'; then
    # Only auto-answer the known "trust this folder" dialog. Anything else stays
    # blocked for the user.
    SCREEN=$(herdr agent read "$NAME" --source recent-unwrapped --lines 40 2>&1)
    if echo "$SCREEN" | grep -qi "trust this folder"; then
      herdr agent send-keys "$NAME" down enter >/dev/null 2>&1
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        sleep 2
        herdr agent get "$NAME" 2>&1 | grep -q '"agent_status":"idle"' && { START_RESULT=""; break; }
      done
    fi
  fi
  if echo "$START_RESULT" | grep -q '"error"'; then
    echo "ERROR: agent start failed for $AGENT_ID: $START_RESULT" >&2
    update_agent "$ORCH_DIR" "$AGENT_ID" "status=failed" "paneId=$PANE_ID"
    continue
  fi

  # Short pointer prompt: the full mission lives in the prompt file.
  # No --wait here: wait-wave.sh waits for the whole wave afterwards.
  PROMPT="Read the file $PROMPT_FILE and execute the mission described there exactly. Write your result file as instructed. Your orchestrator agent is named '$MAIN_NAME'. To message it, run in bash: \"$HERDR_BIN_UNIX\" agent prompt $MAIN_NAME \"<short message>\" . Use only herdr for messaging; do not use any other coordinator tool."
  herdr agent prompt "$NAME" "$PROMPT" >/dev/null 2>&1

  echo "Spawned $AGENT_ID ($AGENT_LABEL) as '$NAME' in pane $PANE_ID"
  NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  update_agent "$ORCH_DIR" "$AGENT_ID" \
    "paneId=$PANE_ID" "agentName=$NAME" "status=running" "startedAt=$NOW"

  TARGET="$PANE_ID"
  if [ "$DIR" = right ]; then DIR=down; else DIR=right; fi
  IDX=$((IDX + 1))
done < <(node "$JSON_TOOL" query "$ORCH_DIR/state.json" wave-agents-each "$WAVE_IDX")
