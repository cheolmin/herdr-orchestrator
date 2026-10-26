#!/usr/bin/env node
// zone-check.js <state.json> <wave-index> <tree-before.txt> <cwd>
// Print project files that changed since the snapshot and that no agent of the
// wave may write. Orchestration temp files are ignored.
const fs = require('fs');
const { execFileSync } = require('child_process');

const [, , stateFile, waveArg, beforeFile, cwd] = process.argv;
const state = JSON.parse(fs.readFileSync(stateFile, 'utf8'));
const wave = state.waves[parseInt(waveArg, 10)] || { agents: [] };
const norm = (p) => String(p).replace(/\\/g, '/').replace(/^\.\//, '');

function git(args) {
  try { return execFileSync('git', args, { cwd, encoding: 'utf8' }); } catch { return ''; }
}

// Current content hash per changed/untracked file.
function snapshot() {
  const map = {};
  const names = new Set(
    git(['diff', '--name-only', 'HEAD']).split('\n')
      .concat(git(['ls-files', '--others', '--exclude-standard']).split('\n'))
      .filter(Boolean).map(norm),
  );
  for (const n of names) {
    try {
      const out = execFileSync('git', ['hash-object', n], { cwd, encoding: 'utf8' }).trim();
      map[n] = out;
    } catch { map[n] = 'deleted'; }
  }
  return map;
}

let before = {};
try { before = JSON.parse(fs.readFileSync(beforeFile, 'utf8')); } catch { /* none */ }
const after = snapshot();
const changed = Object.keys(after).filter((f) => before[f] !== after[f])
  .concat(Object.keys(before).filter((f) => !(f in after)));

function allowed(file, pattern) {
  const p = norm(pattern);
  if (p === '*' || p === '**') return true;
  const m = p.match(/^(.*?)\/?\*{1,2}$/);
  if (m) return file === m[1] || file.startsWith(m[1] + '/');
  return file === p;
}
const zones = [];
for (const a of wave.agents) for (const f of a.files || []) zones.push(f);

const outside = [...new Set(changed)].filter((f) => !zones.some((z) => allowed(f, z)));
process.stdout.write(outside.join('\n') + (outside.length ? '\n' : ''));
