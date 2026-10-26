---
name: herdr-detect
description: Detect if herdr terminal multiplexer is running. Used internally by orchestrate skill to decide between herdr multi-pane mode and degraded subagent mode.
---

# herdr Detection

First, resolve the plugin root (not available as env var in main session):

```bash
PLUGIN_ROOT=$(find "$HOME/.claude/plugins/cache/herdr-orchestrator" -name "plugin.json" -path "*/.claude-plugin/*" 2>/dev/null | sort -V | tail -1 | sed 's|/.claude-plugin/plugin.json||')
```

Run the detection script to check if herdr is available:

```bash
bash "$PLUGIN_ROOT/scripts/detect-herdr.sh"
```

**If output is "available":**
- herdr is running and this shell runs inside a herdr pane (`HERDR_ENV=1`) and the server answers
- The orchestrator can use `herdr pane split`, `herdr agent start`, `herdr agent prompt`, `herdr agent wait` etc.
- Full multi-pane visual experience is available

**If output is "unavailable":**
- herdr is not running or not installed
- Fall back to Claude Code's native `Agent` tool for parallel workers
- No visual dashboard — use text summaries in the terminal instead
- Log: "herdr not detected. Running in degraded mode — agents will use Claude Code's native subagent system. Install herdr for the full multi-pane experience: https://herdr.dev"

Store the detection result so other skills can check it without re-running:

```bash
export HERDR_AVAILABLE=$( bash "$PLUGIN_ROOT/scripts/detect-herdr.sh" 2>/dev/null && echo "true" || echo "false" )
```

**ENFORCEMENT:**
- When `HERDR_AVAILABLE=true`: ALL agents MUST be spawned via `herdr agent spawn`. Do NOT use Claude Code's `Agent` tool. The Agent tool creates invisible subagents — the user chose herdr specifically to SEE agents in panes.
- When `HERDR_AVAILABLE=false`: Use Claude Code's `Agent` tool with `subagent_type: "herdr-orchestrator:herdr-worker"`.
- Never mix modes within an orchestration.
