#!/usr/bin/env node
// Plugin pane: live dashboard for the newest running orchestration.
// Pure Node (no bash) so it works on Windows panes where `bash` may be WSL.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const base = process.env.TMPDIR || os.tmpdir();
const dashboard = path.join(__dirname, 'dashboard-text.js');

function activeOrch() {
  let best = null, bestTime = 0;
  let entries = [];
  try { entries = fs.readdirSync(base); } catch { return null; }
  for (const name of entries) {
    if (!name.startsWith('herdr-orch-')) continue;
    const state = path.join(base, name, 'state.json');
    try {
      const st = fs.statSync(state);
      const data = JSON.parse(fs.readFileSync(state, 'utf8'));
      if (data.status === 'running' && st.mtimeMs > bestTime) { best = path.join(base, name); bestTime = st.mtimeMs; }
    } catch { /* skip */ }
  }
  return best;
}

function draw() {
  process.stdout.write('\x1b[2J\x1b[H');
  const dir = activeOrch();
  if (!dir) { process.stdout.write('No active orchestration.\n'); return; }
  const r = spawnSync(process.execPath, [dashboard, dir], { encoding: 'utf8' });
  process.stdout.write(r.stdout || r.stderr || '');
}

draw();
setInterval(draw, 2000);
