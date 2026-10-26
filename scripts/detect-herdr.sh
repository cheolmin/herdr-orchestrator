#!/usr/bin/env bash
# Detect if running inside a herdr-managed pane with a reachable server.
# Exit 0 + "available" or exit 1 + "unavailable".

if [ "${HERDR_ENV:-}" = "1" ] && command -v herdr &>/dev/null; then
  if herdr pane current --current &>/dev/null; then
    echo "available"
    exit 0
  fi
fi

echo "unavailable"
exit 1
