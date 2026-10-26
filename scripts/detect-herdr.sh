#!/usr/bin/env bash
# Detect if running inside a herdr-managed pane with a reachable server.
# Exit 0 + "available" or exit 1 + "unavailable".

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/orchestration-state.sh"

if [ "${HERDR_ENV:-}" = "1" ] && herdr pane current --current &>/dev/null; then
  echo "available"
  exit 0
fi

echo "unavailable"
exit 1
