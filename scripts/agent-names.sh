#!/usr/bin/env bash
# agent-names.sh <orch-dir>
# Print "<agent-id> <herdr-name>" for every agent in every wave, using the same
# naming rule as spawn-agents.sh. Run it BEFORE writing prompt files so each
# prompt can list its teammates' herdr names.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/orchestration-state.sh"
ORCH_DIR="$1"
[ -z "$ORCH_DIR" ] && { echo "Usage: agent-names.sh <orch-dir>"; exit 1; }

ORCH_ID=$(read_state "$ORCH_DIR" '.id')
SHORT=$(printf '%s' "$ORCH_ID" | tr -c 'a-z0-9\n' '-' | tr 'A-Z' 'a-z' | cut -c1-8)

safe_name() {
  local n
  n=$(printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9_\n-' '-' | cut -c1-31)
  case "$n" in [a-z]*) ;; *) n="a$n" ;; esac
  printf '%s' "$n" | cut -c1-31
}

WAVES=$(node "$JSON_TOOL" query "$ORCH_DIR/state.json" wave-count)
for ((w = 0; w < WAVES; w++)); do
  node "$JSON_TOOL" query "$ORCH_DIR/state.json" wave-agent-ids "$w" | while IFS= read -r id; do
    [ -z "$id" ] && continue
    echo "$id $(safe_name "o${SHORT}-${id}")"
  done
done
