#!/usr/bin/env node
// plan-tool.js — build and validate orchestration state from a plan file.
//
//   node plan-tool.js init <plan.json> <base-dir>
//       Validates the plan, creates <base-dir>/herdr-orch-<id>/, writes state.json,
//       prints {"orchDir": "...", "id": "..."} (forward slashes).
//   node plan-tool.js check <plan.json>
//       Validates only; prints problems, exit 1 if any.
//
// Plan file (written by the orchestrator with the Write tool):
//   { "task": "...", "cwd": "C:/proj", "workerCmd": "ccc-sonnet-skip" | null,
//     "review": false, "dashboard": false,
//     "waves": [ { "agents": [ { "id":"agent-a", "label":"...", "subtask":"...",
//                                "files":["src/a.js"], "excludeFiles":["*"] } ] } ] }
//
// Why a tool: the model used to write state.json and prompt files with shell
// heredocs, and shell variable mistakes created stray directories.

const fs = require('fs');
const path = require('path');

function fail(msg) { process.stderr.write(msg + '\n'); process.exit(1); }
function readJson(f) {
  try { return JSON.parse(fs.readFileSync(f, 'utf8')); } catch (e) { fail(`cannot read ${f}: ${e.message}`); }
}
const norm = (p) => String(p).replace(/\\/g, '/').replace(/^\.\//, '');

// Does glob-ish pattern `a` overlap pattern `b`? Conservative: treat a trailing
// "/**", "/*" or "*" as a directory prefix; otherwise exact match.
function prefixOf(p) {
  const n = norm(p);
  if (n === '*' || n === '**') return '';
  const m = n.match(/^(.*?)\/?\*{1,2}$/);
  return m ? m[1] + '/' : null;
}
function overlaps(a, b) {
  const na = norm(a);
  const nb = norm(b);
  if (na === nb) return true;
  const pa = prefixOf(na);
  const pb = prefixOf(nb);
  if (pa !== null && (nb + '/').startsWith(pa)) return true;
  if (pb !== null && (na + '/').startsWith(pb)) return true;
  if (pa !== null && pb !== null && (pa.startsWith(pb) || pb.startsWith(pa))) return true;
  return false;
}

function validate(plan) {
  const problems = [];
  if (!plan.task) problems.push('missing "task"');
  if (!Array.isArray(plan.waves) || plan.waves.length === 0) problems.push('"waves" must be a non-empty array');
  const ids = new Set();
  (plan.waves || []).forEach((wave, wi) => {
    const agents = wave.agents || [];
    if (agents.length === 0) problems.push(`wave ${wi + 1} has no agents`);
    if (agents.length > 5) problems.push(`wave ${wi + 1} has ${agents.length} agents (max 5)`);
    agents.forEach((a) => {
      if (!a.id || !/^[a-z][a-z0-9-]*$/.test(a.id)) problems.push(`agent id "${a.id}" must match [a-z][a-z0-9-]*`);
      if (ids.has(a.id)) problems.push(`duplicate agent id "${a.id}"`);
      ids.add(a.id);
      if (!a.label) problems.push(`agent ${a.id} has no label`);
      if (!a.subtask) problems.push(`agent ${a.id} has no subtask`);
      if (!Array.isArray(a.files) || a.files.length === 0) problems.push(`agent ${a.id} has no "files" (allowed write zone)`);
    });
    // Two agents in the SAME wave must not write the same file.
    for (let i = 0; i < agents.length; i++) {
      for (let j = i + 1; j < agents.length; j++) {
        for (const fa of agents[i].files || []) {
          for (const fb of agents[j].files || []) {
            if (overlaps(fa, fb)) {
              problems.push(`wave ${wi + 1}: ${agents[i].id} and ${agents[j].id} both write "${fa}" / "${fb}" - merge them or move one to another wave`);
            }
          }
        }
      }
    }
  });
  return problems;
}

const [, , cmd, planFile, baseDir] = process.argv;
if (!cmd || !planFile) fail('Usage: plan-tool.js init <plan.json> <base-dir> | check <plan.json>');

const plan = readJson(planFile);
const problems = validate(plan);
if (problems.length) {
  process.stderr.write('PLAN PROBLEMS:\n' + problems.map((p) => '  - ' + p).join('\n') + '\n');
  process.exit(1);
}
if (cmd === 'check') { process.stdout.write('plan ok\n'); process.exit(0); }
if (cmd !== 'init') fail(`unknown command ${cmd}`);
if (!baseDir) fail('init needs <base-dir>');

const id = 'orch-' + String(Date.now()).slice(-6);
const dir = path.join(baseDir, 'herdr-orch-' + id);
fs.mkdirSync(dir, { recursive: true });

const now = new Date().toISOString().replace(/\.\d+Z$/, 'Z');
const state = {
  id,
  task: plan.task,
  status: 'running',
  startedAt: now,
  cwd: plan.cwd ? norm(plan.cwd) : null,
  workspaceId: null,
  dashboard: !!plan.dashboard,
  dashboardPaneId: null,
  workerCmd: plan.workerCmd || null,
  mainAgent: null,
  waves: plan.waves.map((w, wi) => ({
    index: wi,
    status: wi === 0 ? 'running' : 'pending',
    blockedBy: wi === 0 ? [] : [wi - 1],
    agents: w.agents.map((a) => ({
      id: a.id,
      label: a.label,
      subtask: a.subtask,
      files: (a.files || []).map(norm),
      excludeFiles: (a.excludeFiles || []).map(norm),
      paneId: null,
      agentName: null,
      status: 'pending',
      exitCode: null,
      toolUses: 0,
      resultFile: norm(path.join(dir, `${a.id}-result.md`)),
      startedAt: null,
      finishedAt: null,
    })),
  })),
  reviewer: {
    status: plan.review === true ? 'pending' : 'skipped',
    agentName: null,
    reportFile: norm(path.join(dir, 'review-report.md')),
  },
};
fs.writeFileSync(path.join(dir, 'state.json'), JSON.stringify(state, null, 2));
process.stdout.write(JSON.stringify({ orchDir: norm(dir), id }) + '\n');
