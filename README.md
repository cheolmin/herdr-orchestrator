# herdr-orchestrator

Claude Code plugin that decomposes complex dev tasks into parallel agents coordinated through dependency-aware waves with automated review. Agents run in visible [herdr](https://herdr.dev) panes.

- **Inside herdr**: each agent gets its own pane (`herdr pane split` + `herdr agent start`). An optional dashboard pane shows progress.
- **Outside herdr**: falls back to native Claude Code subagents.

## Install

```bash
claude plugin marketplace add cheolmin/herdr-orchestrator
claude plugin install herdr-orchestrator@herdr-orchestrator
```

Optional dashboard pane (herdr plugin). The orchestrator opens it at the bottom of your tab:

```bash
herdr plugin install cheolmin/herdr-orchestrator
```

## Usage

Start Claude Code **inside a herdr pane**, then:

```
/herdr-orchestrator:orchestrate <your task description>
```

## Requirements

- Claude Code CLI, Node.js, bash
- herdr (for visual multi-pane mode)

## Choosing the worker launcher

Say it in the request, the same way you would in wmux:

```
/herdr-orchestrator:orchestrate <task>. Use ccc-sonnet-skip for the workers.
```

The command is typed into each new pane's shell, so it must exist there (for example a PowerShell function). herdr detects the agent from the process, then the plugin names it.

Without it, workers start with `claude --dangerously-skip-permissions`. You can also set `HERDR_WORKER_CMD` as a default.

## License

MIT
