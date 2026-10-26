---
name: orchestrate
description: Orchestrate a complex dev task as parallel Claude Code agents in herdr panes, in dependency-ordered waves with automated review. Use when the user runs /herdr-orchestrator:orchestrate or asks to split work across multiple herdr worker agents. The text after the command is the task; a named worker launcher (e.g. ccc-sonnet-skip) goes into workerCmd.
argument-hint: <task description>
---

# herdr Orchestration Skill

The user's task is the skill argument (`$ARGUMENTS`). Follow every phase below in order. Run the plugin scripts with bash; do not look for `herdr` or the worker launcher yourself — `detect-herdr.sh` and `spawn-agents.sh` find herdr, and the worker launcher is typed into a pane's own shell.

You are the orchestrator. Your job is to decompose the user's task into parallel subtasks, create a wave-based execution plan, and launch Claude Code agents to execute it.

## Phase 0: Resolve Plugin Root

`CLAUDE_PLUGIN_ROOT` is set by Claude Code only inside hook execution, NOT in the main session's shell environment. You MUST resolve the plugin root path before running any scripts.

Run this to find and export the plugin root:

```bash
PLUGIN_ROOT=$(find "$HOME/.claude/plugins/cache/herdr-orchestrator" -name "plugin.json" -path "*/.claude-plugin/*" 2>/dev/null | sort -V | tail -1 | sed 's|/.claude-plugin/plugin.json||')
echo "PLUGIN_ROOT=$PLUGIN_ROOT"
ls "$PLUGIN_ROOT/scripts/" | head -5
```

If the `find` returns empty, the plugin is not installed. Tell the user:
> "herdr-orchestrator plugin not found. Install it with: `claude plugins install herdr-orchestrator@herdr-orchestrator`"

**Store `PLUGIN_ROOT` and use it for ALL subsequent `bash` commands in this orchestration.** Every script reference below uses `$PLUGIN_ROOT` — you must prefix every bash command that references plugin scripts with the same export or pass the resolved path directly.

## Phase 1: Detect herdr

Run the detection script:

```bash
bash "$PLUGIN_ROOT/scripts/detect-herdr.sh"
```

Store the result as `HERDR_MODE`:
- If output is `"available"` → `HERDR_MODE=herdr` — agents spawn in visible terminal panes via `herdr agent start`
- If output is `"unavailable"` → `HERDR_MODE=degraded` — agents spawn as invisible Claude Code subagents via the Agent tool

**This decision is binding for the entire orchestration.** Do not switch modes mid-orchestration.

If degraded, log to the user:
> "herdr not detected. Running in degraded mode — agents will use Claude Code's native subagent system. Install herdr for the full multi-pane experience: https://herdr.dev"

If herdr mode, log to the user:
> "herdr detected. Agents will spawn in visible terminal panes."

### Worker launcher (herdr mode)

If the user's request names a launcher for the workers (for example "use ccc-sonnet-skip for the workers", "워커는 ccc-sonnet-skip으로"), put that exact command in state.json as `"workerCmd"`. spawn-agents.sh types it into each new pane's shell. Do not add flags and do not rewrite it. If the user names none, leave `workerCmd` as null (workers start with `claude --dangerously-skip-permissions`, or `$HERDR_WORKER_CMD` if set).

## Phase 2: Analyze the Codebase

Before decomposing, understand what the task involves:

1. **Map relevant files**: Use Glob and Grep to find all files related to the task
2. **Trace dependencies**: For each relevant file, check its imports and exports to understand coupling
3. **Identify conflict zones**: Files that would need to be touched by multiple subtasks — these MUST be assigned to a single agent or sequenced across waves
4. **Check git context**: Read recent commits for relevant context

Be thorough but efficient. You need enough understanding to make good decomposition decisions, not a complete codebase map.

## Phase 3: Decompose into Subtasks

Based on your analysis, break the task into subtasks. Each subtask must have:
- A clear, bounded scope described in 2-3 sentences
- An explicit list of files it may modify (allowed files)
- An explicit list of files it must NOT modify (other agents' zones)
- No circular dependencies with other subtasks

**Rules for decomposition:**
- Files that are tightly coupled (heavy imports between them) belong in the same subtask
- Shared types/interfaces should be in the earliest wave (other agents depend on them)
- Tests should generally be in the last wave (they depend on implementation)
- Prefer fewer, larger subtasks over many tiny ones — agent startup has overhead
- A single-line fix does NOT need an orchestration. If the task is trivial, just do it directly.

Reference the decomposition guide for patterns:
```bash
cat "$PLUGIN_ROOT/skills/orchestrate/references/decomposition-guide.md"
```

## Phase 4: Build the Wave Plan

Organize subtasks into sequential waves based on dependencies:

- **Wave 1**: Foundation work — types, models, shared interfaces. No dependencies on other subtasks.
- **Wave 2+**: Work that depends on previous wave output. Agents within a wave run in parallel.
- **Final wave**: Tests, documentation, or anything that depends on all previous work.

Determine agent count per wave based on:
- Number of truly independent subtasks in that wave
- If herdr is available, check layout capacity: `herdr pane list --workspace "$HERDR_WORKSPACE_ID"` (keep waves to about 4 panes; more makes panes too small)
- Maximum practical limit: 5 agents per wave (more causes diminishing returns from context overhead)
- If only 1 subtask exists, skip orchestration and do it directly

## Phase 4.5: Detect Coupling & Generate Contracts

Before presenting the plan, audit each wave for **coupling**: cases where multiple parallel agents must agree on names, types, shapes, or IDs for the final output to work. Coupling that isn't explicitly coordinated causes drift — agents independently invent different names for the same concept and the integration breaks. (This actually happened on a past run: two parallel agents building HTML and CSS invented different class names like `.hero__grid` vs `.hero__inner` for the same element, and 510 lines of alias CSS were needed to reconcile after the fact.)

### Coupling triggers

A wave has coupled agents when any of these apply:
- Two or more agents touch files of the same domain that reference each other by name:
  - HTML + CSS of the same component (class names must match)
  - HTML + JS of the same component (mount-point IDs and selectors must match)
  - Frontend client + backend server for the same feature (endpoint paths, request/response shapes must match)
  - Schema producer + schema consumer (exported type signatures must match)
  - Multiple agents adding methods/fields to the same exported module
- Two or more agents fill slots in a shared top-level structure (e.g., one writes the HTML skeleton, others write the component markup that plugs into it)
- Two or more agents read from or write to a common config/constants file

### Resolution paths

For each coupled group, choose ONE resolution:

1. **Merge into a single agent.** Use when the coupled work is small enough for one agent (roughly < 800 lines of final output) AND the work is naturally cohesive. Prefer this when possible — fewest moving parts.

2. **Sequence across waves.** Move one agent to an earlier wave; the later wave's prompt includes the earlier wave's result file so the dependent agent reads real names from real files. Use when the coupling is directional (types → consumers, schema → migrations, API → clients) and large enough that merging would make one agent unwieldy.

3. **Generate a shared contract file.** Write a single source-of-truth document that BOTH agents read before writing any code. Use when the work MUST run in parallel AND the coupling is naming-only, not logic-level.

### Generating the contract file (path 3)

When you choose path 3, write `{orch-dir}/wave-{N}-contract.md` BEFORE spawning the wave. Every shared name must appear in it. If an agent needs a name not in the contract, that's a bug — the agent must stop and flag disagreement (see injection below), not silently invent.

Template (omit sections that don't apply — don't include placeholder text, only real names):

````markdown
# Wave {N} Contract — [short description]

> This is the single source of truth for names shared by parallel agents in wave {N}.
> All agents listed below MUST read this file before writing any code and use these
> names verbatim. Do not invent alternatives.

## Agents bound by this contract
- agent-a ([role])
- agent-b ([role])

## Shared HTML class names
_(fill this section when at least one agent writes HTML and another writes CSS)_
- Site header: `.site-header`, `.site-header__brand`, `.site-header__nav`, `.site-header__link`
- Hero: `.hero`, `.hero__grid`, `.hero__title`, `.hero__title__line`, `.hero__cta`

## Shared DOM IDs and mount points
_(fill when one agent writes HTML scaffolding that another agent fills via JS)_
- `#wave-sim-root` — empty div in hero; agent-c mounts the simulator into it
- `aside.activity-rail` — empty aside in hero; agent-e appends log lines to it

## Shared CSS custom properties
_(fill when CSS declares variables that JS reads/writes)_
- `--scroll` — 0..1 fractional page scroll, written by motion agent, read by CSS
- `--mouse-x`, `--mouse-y` — **pixel** values (not normalized), written by ambient agent, read by CSS `top`/`left`

## Shared TypeScript/JavaScript exports
_(fill when one agent declares types/functions used by another in the same wave)_
- `export type User = { id: string; email: string; role: 'admin' | 'user' }` in `src/shared/types.ts`
- `export function formatDate(d: Date): string` in `src/shared/format.ts`

## Shared API endpoints
_(fill when frontend and backend are coupled)_
- `POST /api/auth/login` — request `{ email, password }`, response `{ token, user: User }`
- `GET /api/users/:id` — response `User`

## Shared file structure
_(fill when multiple agents place files in a coordinated layout)_
- `src/components/Hero/Hero.tsx` — structure (agent-a)
- `src/components/Hero/hero.module.css` — styles (agent-b)
````

### Injecting the contract into agent prompts

For EVERY coupled agent in the wave, add this block to their prompt file (in Phase 6c), placed right after the `## Orchestration Context` section and before `## Your Zone of Work`:

````markdown
## Shared Contract — READ BEFORE WRITING ANY CODE

You share this wave with other agents who depend on the same names. To prevent naming drift, a shared contract has been written at:

`{orch-dir}/wave-{N}-contract.md`

**Before writing any code, use the Read tool to read that file in full.** It defines every class name, mount point, type, and API shape that you and the other agents must use identically. Use these names verbatim — do not invent alternatives, do not translate them, do not simplify them.

If a name in the contract seems wrong or missing:
1. Stop implementation.
2. Write to your result file with status `contract_disagreement`.
3. Describe the specific name at issue and your proposed alternative.
4. Do NOT silently invent a different name and proceed.

The reviewer will pick up any `contract_disagreement` result and reconcile before the next wave.
````

Agents NOT in a coupled group skip this block — their work is independent and doesn't need the extra read.

## Phase 5: Present the Plan

Show the user a structured plan. Format it clearly:

```
Orchestration Plan: [task description]
Agents: [total] in [N] waves
Estimated complexity: [low/medium/high]

Wave 1 — [description]
  Agent A: "[subtask label]"
    Allowed files: [list]
    Excluded files: [list]

Wave 2 (after Wave 1) — [description]
  Agent B: "[subtask label]"
    Allowed files: [list]
    Excluded files: [list]
  Agent C: "[subtask label]"
    Allowed files: [list]
    Excluded files: [list]

Wave 3 (after Wave 2) — [description]
  Agent D: "[subtask label]"
    Allowed files: [list]
    Excluded files: [list]

Options:
  --worktree: Isolate each agent in a git worktree (default: no)
  --no-review: Skip the automated reviewer (default: review enabled)
```

Ask the user: **"Validate this plan? (yes / adjust / cancel)"**

Wait for user approval. If they want adjustments, modify the plan and re-present. Do NOT proceed without explicit approval.

## Phase 6: Initialize Orchestration

Once the user validates:

### 6a. Generate orchestration ID

```bash
ORCH_ID="orch-$(date +%s | tail -c 7)"
echo $ORCH_ID
```

### 6b. Create orchestration directory and state file

Create the directory:
```bash
mkdir -p "${TMPDIR:-/tmp}/herdr-orch-$ORCH_ID"
```

Write `state.json` using the Write tool. Schema:
```json
{
  "id": "orch-XXXXXX",
  "task": "the user's task description",
  "status": "running",
  "startedAt": "ISO-8601 UTC timestamp",
  "cwd": "project working directory",
  "workspaceId": null,
  "dashboardPaneId": null,
  "workerCmd": null,
  "mainAgent": null,
  "useWorktrees": false,
  "waves": [
    {
      "index": 0,
      "status": "running",
      "blockedBy": [],
      "agents": [
        {
          "id": "agent-a",
          "label": "Subtask label",
          "subtask": "Full subtask description",
          "files": ["allowed/file/paths"],
          "excludeFiles": ["excluded/patterns/*"],
          "paneId": null,
          "agentName": null,
          "status": "pending",
          "exitCode": null,
          "toolUses": 0,
          "resultFile": "/tmp/herdr-orch-XXXXXX/agent-a-result.md",
          "startedAt": null,
          "finishedAt": null
        }
      ]
    }
  ],
  "reviewer": {
    "status": "pending",
    "agentId": null,
    "reportFile": "/tmp/herdr-orch-XXXXXX/review-report.md"
  }
}
```

Use short agent IDs like "agent-a", "agent-b", etc. Set the first wave's status to "running", all others to "pending".

### 6c. Generate agent prompt files

First get the herdr name of every agent (needed for the Messaging section of each prompt):

```bash
bash "$PLUGIN_ROOT/scripts/agent-names.sh" "[orch-dir]"
```

It prints `<agent-id> <herdr-name>` lines. Use them verbatim.

For EACH agent, create a prompt file at `{orch-dir}/{id}-prompt.md` with:

```markdown
# Mission: [subtask label]

## Orchestration Context
You are [Agent ID] in orchestration [ORCH_ID].
[N] other agents are working on the same project in parallel.
You are in Wave [N] of [total waves].

[If this agent is in a coupled group per Phase 4.5, inject the Shared Contract block here — see Phase 4.5 template. Skip for non-coupled agents.]

[If wave 2+:]
## Previous Wave Results
The following agents completed before you. Their results:
[Paste contents of previous agents' result files here]

## Your Zone of Work
Allowed files (you MAY modify these):
- [list each file]

Excluded files (you MUST NOT modify these):
- [list patterns]

## Your Mission
[Detailed subtask description with specific steps]

## Messaging (herdr)
Your orchestrator is the herdr agent `orch-main`. Your teammates in this orchestration and their herdr names:
[One line per OTHER agent, from agent-names.sh: `- [id] ([role]) = [herdr-name]`]

Send a short message from bash:

```bash
"$HERDR_BIN_PATH" agent prompt <name> "<one short line>"
```

If `$HERDR_BIN_PATH` is empty, use `herdr`. Rules:
- Message `orch-main` for: a blocker, a question, an out-of-zone file you need, or "done".
- Message a teammate directly only for names/formats you share (see the Shared Contract). Say who you are: `"agent-a: ..."`.
- A message you receive arrives as a normal user message in your input. If it asks something, answer it the same way; if it is only information, use it and continue. Do not reply to a pure FYI.
- Keep every message to one line. Put long content in a file and send its path.
- Use herdr for messaging; do not use any other coordinator or messaging tool. Your result file is still the main report.

## When You Finish
Create your result file at: [orch-dir]/[id]-result.md

Use this format:
### Summary
[2-3 sentences]
### Files Modified
- `path` — [description]
### Interfaces/Types Changed
[Any exported types that changed signature]
### Tests
[Test results or "Out of scope"]
### Risks
[Points of attention for other agents or reviewer]
```

### 6d. Create herdr layout (if available)

**IMPORTANT: Work in the CURRENT workspace. Do NOT create or close workspaces — that hides agent panes from the user.**

The spawn script (`spawn-agents.sh`) automatically creates panes via `herdr pane split`.

### 6e. Spawn Wave 1 agents

**CRITICAL RULE: When herdr is available, you MUST use `herdr agent start` to create agents in visible terminal panes. Do NOT use Claude Code's `Agent` tool when herdr is available — the Agent tool creates invisible subagents that the user cannot see. The `Agent` tool is ONLY for degraded mode (no herdr).**

**If herdr IS available:**

Spawn agents using the spawn script:
```bash
bash "$PLUGIN_ROOT/scripts/spawn-agents.sh" "[orch-dir]" 0
```

This script:
1. Opens the live dashboard pane at the bottom (once), while the orchestrator pane still spans the full width
2. Names this (orchestrator) agent `orch-main` so workers can message it
3. Creates a pane per worker via `herdr pane split`, alternating right/down
4. Starts the worker in each pane: the user's `workerCmd` typed into the pane shell, or `herdr agent start --kind claude` by default
5. Sends each worker a short pointer prompt; the full mission is in `{orch-dir}/{id}-prompt.md`
6. Users can watch every pane and type into any worker to intervene

Do not open the dashboard by hand. Then verify agents are running:
```bash
herdr agent list
```

You should see the workers with `"agent_status": "working"`.

**If herdr is NOT available (degraded mode only):**

Spawn each agent using Claude Code's native Agent tool:
- For each agent in Wave 1, use the Agent tool with `subagent_type: "herdr-orchestrator:herdr-worker"`
- Pass the prompt file content as the prompt
- Use `description: "[agent label]"` for tracking
- Wait for all agents to complete before proceeding to next wave

## Phase 7: Monitor and Transition (Orchestrator Loop)

**You are the orchestrator.** Your job is to monitor agent progress and coordinate wave transitions. This is where the real orchestration happens.

### Live dashboard visibility

Before entering the loop, note how the user sees progress:

- **In herdr mode**: spawn-agents.sh already opened the live dashboard pane at the bottom. It re-reads state.json every 2 seconds. Do NOT call the text dashboard manually in herdr mode.

- **In degraded mode (no herdr)**: you must print the text dashboard into Claude Code's conversation at each wave transition so the user can see progress. Run:
  ```bash
  node "$PLUGIN_ROOT/scripts/dashboard-text.js" "[orch-dir]"
  ```
  Call it ONCE after spawning each wave, and ONCE after each wave completes. Do not call it inside the monitoring loop (that would spam the session). If the user asks "how's it going", you can also call it then.

### Messages from workers

Workers send a short note with `herdr agent prompt orch-main "..."`. It arrives as a normal user message. Each message starts with the sender (for example `agent-b: ...`). Handle it by type:

- **Done / FYI**: note it. Do not reply and do not start new work.
- **Question or blocker**: answer the worker with `herdr agent prompt <worker-name> "<one line>"` (names are in state.json under `agentName`). If it needs a file outside the worker's zone, decide: grant it in your reply, or give the file to another worker.
- **Worker-to-worker**: workers may message each other. You do not need to relay.
- A worker is "working" again after you message it. Wait for it with `wait-wave.sh` again before moving on.

You can also look at a worker yourself: `herdr agent read <name> --source recent-unwrapped --lines 60`.

When you call herdr yourself, use the plugin's resolver, because `herdr` may not be on PATH:

```bash
source "$PLUGIN_ROOT/scripts/orchestration-state.sh"   # defines herdr() from HERDR_BIN_PATH
herdr agent list
```

### With herdr (wait-based monitoring):

After spawning Wave N agents, block until the whole wave settles:

```bash
bash "$PLUGIN_ROOT/scripts/wait-wave.sh" "[orch-dir]" N
```

This runs `herdr agent wait <name>` per agent (settled = `idle`, `done` or `blocked`), updates state.json, and prints one line per agent. herdr has no exit codes for interactive agents, so "settled" means the agent stopped working. Judge success by its result file.

- `blocked` → agent waits on an approval/question. Inspect with `herdr agent read <name> --source recent-unwrapped --lines 80` and ask the user before sending input.
- For a progress peek at any time: `herdr agent list` and `herdr agent read <name>`.

**When ALL agents in the current wave are settled:**

1. Read each agent's result file: `[orch-dir]/[id]-result.md`
2. Report results to the user: which agents succeeded, which failed, what they produced
3. If there are more waves:
   a. Generate prompt files for Wave N+1 (inject previous wave results)
   b. Spawn: `bash "$PLUGIN_ROOT/scripts/spawn-agents.sh" "[orch-dir]" [N+1]`
   c. Verify with `herdr agent list`
   d. Wait again with wait-wave.sh
4. If all waves are done, proceed to Phase 8

### Without herdr (degraded mode — Agent tool returns):
1. Wait for all Wave N agents to complete (their Agent tool calls return)
2. Read their result files
3. Generate Wave N+1 agent prompts (inject previous wave results)
4. Spawn Wave N+1 agents using Agent tool
5. Repeat until all waves complete

## Phase 8: Launch Reviewer

When all waves are complete:

1. Aggregate results:
```bash
bash "$PLUGIN_ROOT/scripts/collect-results.sh" "[orch-dir]"
```

2. Invoke the reviewer skill to analyze all changes and produce a final report.

## Phase 9: Finalize

After the reviewer completes, present a summary:
- Total time elapsed
- Agents used, waves completed
- Files modified (from `git diff --stat`)
- Test results (if reviewer ran tests)
- Reviewer findings and corrections
- Offer actions: **commit** / **view full diff** / **abort all changes**
