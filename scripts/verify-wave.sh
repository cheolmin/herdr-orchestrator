#!/usr/bin/env bash
# verify-wave.sh <orch-dir> <wave-index>
# After wait-wave.sh: check each agent of the wave with evidence, not just "idle".
#   1. its result file exists and is non-empty
#   2. its result file has the required sections
#   3. files changed in the project are inside SOME agent's allowed zone
#      (git projects only; compares against the snapshot taken by snapshot-tree.sh)
# Prints one line per check. Marks failing agents "failed" in state.json.
# Exit 0 = all verified, 1 = at least one problem.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/orchestration-state.sh"

ORCH_DIR="$1"
WAVE_IDX="$2"
[ -z "$ORCH_DIR" ] || [ -z "$WAVE_IDX" ] && { echo "Usage: verify-wave.sh <orch-dir> <wave-index>"; exit 1; }

BAD=0
while IFS= read -r agent; do
  [ -z "$agent" ] && continue
  ID=$(parse_json "$agent" '.id')
  RF=$(parse_json "$agent" '.resultFile')
  [ -z "$RF" ] || [ "$RF" = "null" ] && RF="$ORCH_DIR/${ID}-result.md"
  RF_UNIX="$(cygpath -u "$RF" 2>/dev/null || printf '%s' "$RF")"

  if [ ! -s "$RF_UNIX" ]; then
    echo "FAIL $ID: result file missing or empty ($RF)"
    update_agent "$ORCH_DIR" "$ID" "status=failed" "exitCode=1"
    BAD=1
    continue
  fi
  MISSING=""
  for sec in "Summary" "Files Modified"; do
    grep -qi "^#\+ *$sec" "$RF_UNIX" || MISSING="$MISSING $sec"
  done
  if [ -n "$MISSING" ]; then
    echo "WARN $ID: result file lacks section(s):$MISSING"
  else
    echo "OK   $ID: result file complete"
  fi
done < <(node "$JSON_TOOL" query "$ORCH_DIR/state.json" wave-agents-each "$WAVE_IDX")

# Zone check: any changed file not allowed for any agent of this wave?
CWD=$(read_state "$ORCH_DIR" '.cwd')
CWD_UNIX="$(cygpath -u "$CWD" 2>/dev/null || printf '%s' "$CWD")"
if [ -d "$CWD_UNIX/.git" ] && [ -f "$ORCH_DIR/tree-before-wave-$WAVE_IDX.txt" ]; then
  OUTSIDE=$(node "$SCRIPT_DIR/zone-check.js" "$ORCH_DIR/state.json" "$WAVE_IDX" \
    "$ORCH_DIR/tree-before-wave-$WAVE_IDX.txt" "$CWD_UNIX")
  if [ -n "$OUTSIDE" ]; then
    echo "WARN files changed outside every agent's zone:"
    printf '%s\n' "$OUTSIDE" | sed 's/^/       /'
    BAD=1
  else
    echo "OK   all changed files are inside agent zones"
  fi
else
  echo "SKIP zone check (not a git project or no snapshot)"
fi
exit $BAD
