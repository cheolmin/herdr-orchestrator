#!/usr/bin/env node
// snapshot-tree.js <cwd> <out-file>
// Record the current content hash of every changed/untracked file in the git
// project, so verify-wave.sh can tell which files a wave changed.
const fs = require('fs');
const { execFileSync } = require('child_process');
const [, , cwd, outFile] = process.argv;
const norm = (p) => String(p).replace(/\\/g, '/').replace(/^\.\//, '');
function git(args) {
  try { return execFileSync('git', args, { cwd, encoding: 'utf8' }); } catch { return ''; }
}
const names = new Set(
  git(['diff', '--name-only', 'HEAD']).split('\n')
    .concat(git(['ls-files', '--others', '--exclude-standard']).split('\n'))
    .filter(Boolean).map(norm),
);
const map = {};
for (const n of names) {
  try { map[n] = execFileSync('git', ['hash-object', n], { cwd, encoding: 'utf8' }).trim(); }
  catch { map[n] = 'deleted'; }
}
fs.writeFileSync(outFile, JSON.stringify(map));
