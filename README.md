# herdr-orchestrator

A Claude Code plugin that splits a big dev task into parallel workers, runs them in **visible [herdr](https://herdr.dev) panes**, checks their work, and has an independent reviewer look at the result.

You give one request. The plugin:

1. reads your code and splits the task into **waves** of workers (workers in the same wave run in parallel, later waves wait for earlier ones),
2. shows you the plan and waits for your OK,
3. opens one herdr pane per worker and starts a Claude Code agent in each,
4. waits for each wave, **verifies** it, and starts the next wave,
5. optionally starts a **separate reviewer agent** (only if you ask), then closes the run.

> Based on [amirlehmam/wmux-orchestrator](https://github.com/amirlehmam/wmux-orchestrator) (MIT), ported from wmux to the herdr CLI.

---

## Install

```bash
claude plugin marketplace add cheolmin/herdr-orchestrator
claude plugin install herdr-orchestrator@herdr-orchestrator
```

Optional: the live dashboard pane is a herdr plugin from the same repository.

```bash
herdr plugin install cheolmin/herdr-orchestrator
```

Update later with `claude plugin update herdr-orchestrator@herdr-orchestrator` and `herdr plugin update`.

**Requirements**

| Need | Why |
|---|---|
| Claude Code | runs the orchestrator and the workers |
| herdr 0.9+ | panes, agent control, messaging |
| Node.js, bash | the helper scripts (on Windows, Git Bash is enough) |
| a git project | optional; enables the "changed outside its zone" check |

## Use

Start Claude Code **inside a herdr pane**, then:

```
/herdr-orchestrator:orchestrate <what you want built or changed>
```

Plugin skills are always called as `/<plugin>:<skill>`, so the name is fixed. You can also just describe the job in words and ask for the orchestrator.

Add options in plain words, in the same sentence:

| Say this | Effect |
|---|---|
| `Use ccc-sonnet-skip for the workers.` | Workers are started with that launcher (see below) |
| `Turn on the dashboard.` | Opens the live dashboard pane at the bottom |
| `Review it.` (or "리뷰도 해줘") | Starts an independent reviewer after the last wave (**off by default**) |
| `Go ahead without asking.` (or "확인 없이 진행") | Prints the plan but skips the "Validate this plan?" question |

Example:

```
/herdr-orchestrator:orchestrate Build a calculator module. Two workers in wave 1
(calc.js and format.js), one worker in wave 2 writes test.js. Use ccc-sonnet-skip
for the workers. Go ahead without asking.
```

The orchestrator answers in the language of your request (a Korean request gets Korean plans, progress lines and a Korean summary). Code, file names, commands and agent names stay as they are. What workers and scripts read (prompt files, `say.sh` messages) stays in English.

If you are **not** inside herdr, the plugin says so and falls back to Claude Code's built-in subagents (invisible, no panes, no messaging between workers).

---

## How it works

### 1. Plan

The orchestrator reads the project, then writes a **plan file** (JSON): the task, the working directory, the waves, and for every worker an `id`, a `label`, a `subtask`, and its **write zone** (`files`).

`plan-tool.js check` validates the plan **before anything starts**:

- every worker has an id, label, subtask and a write zone,
- at most 5 workers per wave,
- **two workers in the same wave must not write the same file** (`src/*` overlaps `src/app.js`; the plan is rejected and must be fixed, merged or split across waves).

`plan-tool.js init` then creates the run directory and `state.json`. The model never writes these by hand, which removed a class of shell-quoting mistakes.

### 2. Coupling and contracts

Workers in one wave can each be correct alone and still not fit together (an HTML id that JS does not know, a function name that differs). For such waves the orchestrator picks one of:

- merge the coupled work into one worker,
- put one worker in an earlier wave so the later one reads real names from a real file,
- write a **shared contract file** (`wave-N-contract.md`) that every worker reads first.

### 3. Spawn

`spawn-agents.sh` creates the panes and starts the workers:

- panes are split alternately **right / down** so none becomes too narrow,
- the orchestrator's own agent is named **`orch-main`** so workers can reach it,
- each worker gets a deterministic name: `o<orch-id>-<agent-id>` (for example `oorch-882-agent-a`; `agent-names.sh` prints them),
- a worker is started either with your launcher (`ccc-sonnet-skip`, typed into the pane's shell) or with `herdr agent start --kind claude`,
- the "trust this folder" dialog is answered automatically **only** for that exact dialog; any other blocked dialog is left for you,
- each worker gets a short pointer prompt; the full mission is in `<run-dir>/<agent-id>-prompt.md`.

A snapshot of the project's changed files is taken before each wave (used by the zone check).

### 4. Wait and verify

`wait-wave.sh` waits for every worker of the wave with `herdr agent wait`. It first waits to see the worker **start working**, because a prompt that was just sent leaves an agent briefly `idle`; without that, the wait would end too early.

`verify-wave.sh` then checks evidence, not just "idle":

| Check | Result |
|---|---|
| result file exists and is not empty | `FAIL` marks the worker `failed` |
| result file has `Summary` and `Files Modified` | `WARN` if missing |
| no file changed outside **every** worker's zone | `WARN` with the file list |

### 5. Review (optional, off by default)

Only if you asked for a review, `spawn-reviewer.sh` starts the reviewer as **its own agent in its own pane**. It did not see the workers work, so it judges only from the files and the result files. It checks cross-worker consistency, runs the tests, may fix small problems (missing import, typo), and writes `review-report.md` with a recommendation: `LOOKS GOOD`, `NEEDS USER REVIEW` or `SIGNIFICANT ISSUES FOUND`.

`finish-orch.sh` then marks the run `complete`.

### Messages between agents

Everyone talks through `say.sh`:

```
bash say.sh <run-dir> <from-id> <target-agent-name> "<one line>"
```

- It sends the line with `herdr agent prompt` (the receiver sees `agent-b: ...`) **and** appends it to `<run-dir>/messages.log`.
- Workers message `orch-main` for a blocker, a question, a file they need outside their zone, or "done".
- Workers may message each other directly about shared names. The orchestrator does not relay.
- The orchestrator answers questions and never starts new work because of an FYI.
- A failed delivery is logged as `(delivery failed)` and `say.sh` exits 1.

### Dashboard (optional)

Off by default. When on, a herdr pane at the bottom shows the task, elapsed time, a progress bar per wave, one line per worker (`✓` done, `●` working, `·` waiting, `✗` failed, tool-use count, time) and the **last 3 messages**.

- It redraws in place and only when something changed (no flicker).
- It fits the pane width and counts Korean/CJK characters as two columns.
- Turn it on with "turn on the dashboard", or later with `bash scripts/open-dashboard.sh <run-dir>`.
- The text version works anywhere: `node scripts/dashboard-text.js <run-dir>`.

### Hooks

| Hook | What it does |
|---|---|
| `PostToolUse` | counts tool uses per worker for the dashboard (matches the worker by `HERDR_PANE_ID`) |
| `SubagentStop` | updates state for built-in subagents (degraded mode only) |
| `Stop` | warns if you exit while workers are still running |
| `SessionStart` | tells you about an unfinished orchestration |

---

## Choosing the worker launcher

Say it in the request:

```
/herdr-orchestrator:orchestrate <task>. Use ccc-sonnet-skip for the workers.
```

The command is typed into each new pane's shell, so it must exist **there** (for example a PowerShell function from your profile). herdr detects the agent from the running process and the plugin then names it. Without a launcher, workers start as `claude --dangerously-skip-permissions`.

You can also set a default: `HERDR_WORKER_CMD` (environment variable). The request wins over the variable.

## Files of one run

Each run lives in `<TMPDIR>/herdr-orch-<id>/`:

| File | Content |
|---|---|
| `state.json` | the single source of truth: waves, workers, status, pane ids, reviewer |
| `<agent-id>-prompt.md` / `-result.md` | a worker's mission and its report |
| `wave-N-contract.md` | shared names (only if the wave is coupled) |
| `tree-before-wave-N.txt` | snapshot for the zone check |
| `messages.log` | every message between agents |
| `reviewer-prompt.md`, `review-report.md` | the review |

A run that has not changed for 6 hours is treated as abandoned and is no longer "active".

## Scripts

| Script | Purpose |
|---|---|
| `plan-tool.js` | validate a plan, create the run (`check`, `init`) |
| `detect-herdr.sh` | is this shell inside herdr and is the server reachable |
| `agent-names.sh` | herdr names of all workers (before writing prompts) |
| `spawn-agents.sh` | open panes, start workers, send pointer prompts |
| `wait-wave.sh` | wait for a wave, mark workers and the wave |
| `verify-wave.sh`, `zone-check.js`, `snapshot-tree.js` | evidence checks |
| `say.sh` | send a message and log it |
| `collect-results.sh` | join all result files into one document |
| `spawn-reviewer.sh`, `wait-reviewer.sh` | independent review |
| `finish-orch.sh` | close the run |
| `open-dashboard.sh`, `dashboard-pane.js`, `dashboard-text.js` | dashboard |
| `orchestration-state.sh`, `json-tool.js` | shared helpers |

`herdr` is found through `HERDR_BIN_PATH` when it is not on `PATH` (herdr sets that variable in every pane it manages).

## Limits and known gaps

- Not tested for more than 2 waves or 5 workers.
- Worker panes are small when many are open; use fewer workers or a bigger window.
- herdr gives no exit code for an interactive agent. "Done" means the worker stopped working and, when verified, left its result file.
- No git-worktree isolation. All workers share one working tree and rely on write zones.
- Workers run with `--dangerously-skip-permissions` unless your launcher says otherwise.
- The orchestrator skips an Orca/other-coordinator workflow on purpose: all messaging goes through herdr.

## License

MIT. Original work © amirlehmam; herdr port © cheolmin.
