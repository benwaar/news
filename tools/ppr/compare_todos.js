#!/usr/bin/env node
const { execSync } = require('child_process');

function pickBase() {
  const candidates = ['origin/dev', 'origin/develop', 'origin/main', 'origin/master'];
  for (const cand of candidates) {
    try {
      execSync(`git show-ref --verify --quiet refs/remotes/${cand}`, { stdio: 'ignore' });
      return cand;
    } catch (_) {}
  }
  throw new Error('No dev-like base branch found (origin/dev, origin/develop, origin/main, origin/master).');
}

function parseArgs(argv) {
  const args = { base: null, pattern: 'TODO' };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--base') args.base = argv[++i];
    else if (a === '--pattern') args.pattern = argv[++i];
  }
  return args;
}

function main() {
  try {
    // Keep remotes fresh
    try { execSync('git fetch origin --prune', { stdio: 'ignore' }); } catch (_) {}

    const { base: cliBase, pattern } = parseArgs(process.argv);
    const base = cliBase || pickBase();
    const re = new RegExp(pattern, 'i');

    const diff = execSync(`git diff --unified=0 --no-color ${base}...HEAD`, { encoding: 'utf8' });
    const lines = diff.split(/\r?\n/);

    let file = null;
    let oldln = 0, newln = 0;
    const added = [];
    const removed = [];

    for (const raw of lines) {
      if (raw.startsWith('+++ b/')) { file = raw.slice(6).trim(); continue; }
      if (raw.startsWith('@@ ')) {
        const m = raw.match(/-([0-9]+)(?:,([0-9]+))? \+([0-9]+)(?:,([0-9]+))?/);
        if (m) { oldln = Number(m[1]); newln = Number(m[3]); }
        continue;
      }
      if (!file) continue;
      if (raw.startsWith('+') && !raw.startsWith('+++')) {
        const content = raw.slice(1);
        if (re.test(content)) added.push({ file, line: newln, text: content.trim() });
        newln++;
        continue;
      }
      if (raw.startsWith('-') && !raw.startsWith('---')) {
        const content = raw.slice(1);
        if (re.test(content)) removed.push({ file, line: oldln, text: content.trim() });
        oldln++;
        continue;
      }
      // For context lines (rare with -U0), advance both if present
      if (raw.startsWith(' ')) { oldln++; newln++; }
    }

    console.log(`Base: ${base}`);
    console.log(`Pattern: ${pattern}`);
    console.log('TODO changes (HEAD vs base):');

    if (!added.length && !removed.length) {
      console.log('No TODO changes found in the diff.');
      process.exit(0);
    }

    if (added.length) {
      console.log(`\nADDED (${added.length}):`);
      for (const a of added) {
        console.log(`  - ${a.file}:${a.line} -> ${a.text}`);
      }
    }
    if (removed.length) {
      console.log(`\nREMOVED (${removed.length}):`);
      for (const r of removed) {
        console.log(`  - ${r.file}:${r.line} -> ${r.text}`);
      }
    }
  } catch (e) {
    console.error('Failed to scan TODOs:', e && e.message ? e.message : e);
    process.exit(1);
  }
}

main();
