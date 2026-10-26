#!/usr/bin/env bash
# say.sh <orch-dir> <from> <to-agent-name> <message...>
# Send a one-line message to another herdr agent AND append it to messages.log.
# Workers use this instead of calling `herdr agent prompt` directly, so the whole
# conversation of an orchestration lives in one file.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/orchestration-state.sh"

ORCH_DIR="$1"; FROM="$2"; TO="$3"; shift 3
MSG="$*"
[ -z "$ORCH_DIR" ] || [ -z "$FROM" ] || [ -z "$TO" ] || [ -z "$MSG" ] && {
  echo "Usage: say.sh <orch-dir> <from> <to-agent-name> <message...>" >&2; exit 1; }

# One line only.
MSG=$(printf '%s' "$MSG" | tr '\r\n' '  ' | cut -c1-500)
TS=$(date -u +%H:%M:%S)
printf '%s %s -> %s: %s\n' "$TS" "$FROM" "$TO" "$MSG" >> "$ORCH_DIR/messages.log"

# The receiver sees who it is from.
herdr agent prompt "$TO" "$FROM: $MSG" >/dev/null 2>&1 \
  && echo "sent to $TO" \
  || { echo "FAILED to send to $TO" >&2; printf '%s   (delivery failed)\n' "$TS" >> "$ORCH_DIR/messages.log"; exit 1; }
