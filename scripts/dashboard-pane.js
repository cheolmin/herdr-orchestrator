#!/usr/bin/env node
// Plugin pane: live dashboard for the newest running orchestration.
// Pure Node (no bash) so it works on Windows panes where `bash` may be WSL.
//
// No flicker: never clear the whole screen on a tick. Redraw only when the
// rendered text changed, and overwrite in place (cursor home, erase to end of
// each line, erase below). A full clear happens only on first draw and resize.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const base = process.env.TMPDIR || os.tmpdir();
const dashboard = path.join(__dirname, 'dashboard-text.js');
const out = process.stdout;

function activeOrch() {
  let best = null;
  let bestTime = 0;
  let entries = [];
  try { entries = fs.readdirSync(base); } catch { return null; }
  for (const name of entries) {
    if (!name.startsWith('herdr-orch-')) continue;
    const state = path.join(base, name, 'state.json');
    try {
      const st = fs.statSync(state);
      const data = JSON.parse(fs.readFileSync(state, 'utf8'));
      if (data.status === 'running' && Date.now() - st.mtimeMs < 6 * 3600 * 1000 && st.mtimeMs > bestTime) {
        best = path.join(base, name);
        bestTime = st.mtimeMs;
      }
    } catch { /* skip */ }
  }
  return best;
}

function render() {
  const dir = activeOrch();
  if (!dir) return 'No active orchestration.';
  const cols = out.columns || 0;
  const r = spawnSync(
    process.execPath,
    [dashboard, dir, cols ? '--width=' + cols : '--compact'],
    { encoding: 'utf8' },
  );
  return (r.stdout || r.stderr || '').replace(/\n+$/, '');
}

let last = null;
let forceClear = true;

function draw() {
  const text = render();
  const rows = out.rows || 0;
  let lines = text.split('\n');
  if (rows > 0 && lines.length > rows - 1) lines = lines.slice(0, rows - 1);
  const frame = lines.join('\n');
  if (frame === last && !forceClear) return;
  let buf = '';
  if (forceClear) buf += '\x1b[2J';
  buf += '\x1b[H' + lines.map((l) => l + '\x1b[K').join('\n') + '\x1b[J';
  out.write('\x1b[?2026h' + buf + '\x1b[?2026l'); // synchronized output where supported
  last = frame;
  forceClear = false;
}

out.write('\x1b[?25l'); // hide cursor
process.on('exit', () => out.write('\x1b[?25h'));
process.on('SIGINT', () => process.exit(0));
process.on('SIGTERM', () => process.exit(0));
out.on('resize', () => { forceClear = true; last = null; draw(); });

draw();
setInterval(draw, 1000);
