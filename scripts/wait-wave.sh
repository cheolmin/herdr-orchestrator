#!/usr/bin/env bash
# wait-wave.sh <orch-dir> <wave-index> [timeout-ms]
# Blocks until every agent in the wave is settled (idle/done/blocked), marks
# them exited in state.json, and prints a per-agent summary.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/orchestration-state.sh"
ORCH_DIR="$1"; WAVE_IDX="$2"; TIMEOUT="${3:-1800000}"
[ -z "$ORCH_DIR" ] || [ -z "$WAVE_IDX" ] && { echo "Usage: wait-wave.sh <orch-dir> <wave-index> [timeout-ms]"; exit 1; }

while IFS= read -r agent; do
  [ -z "$agent" ] && continue
  ID=$(parse_json "$agent" '.id')
  NAME=$(parse_json "$agent" '.agentName')
  [ -z "$NAME" ] || [ "$NAME" = "null" ] && continue
  # Give the agent a moment to leave its initial idle state, then wait for it to settle.
  sleep 3
  herdr agent wait "$NAME" --timeout "$TIMEOUT" >/dev/null 2>&1
  RAW=$(herdr agent get "$NAME" 2>&1)
  # Response shape is not pinned: take the first "agent_status" value anywhere.
  STATE=$(printf '%s' "$RAW" | grep -o '"agent_status"[[:space:]]*:[[:space:]]*"[a-z]*"' | head -1 | sed 's/.*"\([a-z]*\)"$/\1/')
  NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  if [ "$STATE" = "blocked" ]; then
    update_agent "$ORCH_DIR" "$ID" "status=blocked"
  else
    update_agent "$ORCH_DIR" "$ID" "status=exited" "exitCode=0" "finishedAt=$NOW"
  fi
  echo "$ID ($NAME): $STATE"
done < <(node "$JSON_TOOL" query "$ORCH_DIR/state.json" wave-agents-each "$WAVE_IDX")
