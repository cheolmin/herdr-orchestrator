# herdr-orchestrator

Claude Code plugin that decomposes complex dev tasks into parallel agents coordinated through dependency-aware waves with automated review. Agents run in visible [herdr](https://herdr.dev) panes.

- **Inside herdr**: each agent gets its own pane (`herdr pane split` + `herdr agent start`). An optional dashboard pane shows progress.
- **Outside herdr**: falls back to native Claude Code subagents.

## Install

```bash
claude plugin marketplace add cheolmin/herdr-orchestrator
claude plugin install herdr-orchestrator@herdr-orchestrator
```

Optional dashboard pane (herdr plugin):

```bash
herdr plugin link <path-to-this-repo>
herdr plugin pane open --plugin cheolmin.herdr-orchestrator --entrypoint dashboard --placement split
```

## Usage

Start Claude Code **inside a herdr pane**, then:

```
/herdr-orchestrator:orchestrate <your task description>
```

## Requirements

- Claude Code CLI, Node.js, bash
- herdr (for visual multi-pane mode)

## License

MIT

## Custom worker command

By default workers start with `claude --dangerously-skip-permissions`. To use your own launcher (for example a PowerShell function such as `ccc-sonnet-skip`), set `HERDR_WORKER_CMD` before starting Claude Code:

```powershell
$env:HERDR_WORKER_CMD = "ccc-sonnet-skip"
```

The command is typed into each new pane's shell, so it must exist in that shell. herdr detects the agent from the process and the plugin then names it.
