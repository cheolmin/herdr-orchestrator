#!/usr/bin/env bash
# Open the herdr dashboard pane at the bottom of the orchestrator's tab (once).
# Needs the herdr plugin linked: herdr plugin link <repo>  (or installed from GitHub).

PLUGIN="cheolmin.herdr-orchestrator"
herdr plugin list 2>/dev/null | grep -q "$PLUGIN" || { echo "dashboard plugin not installed; skipping" >&2; exit 0; }

# Already open? (a pane whose terminal runs dashboard-pane.js)
if herdr pane list 2>/dev/null | grep -q 'dashboard-pane'; then exit 0; fi

ARGS=(plugin pane open --plugin "$PLUGIN" --entrypoint dashboard --placement split --direction down)
[ -n "${HERDR_PANE_ID:-}" ] && ARGS+=(--target-pane "$HERDR_PANE_ID")
herdr "${ARGS[@]}" --no-focus >/dev/null 2>&1 || herdr "${ARGS[@]}" >/dev/null 2>&1
exit 0
