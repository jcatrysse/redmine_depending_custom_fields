'use strict';
// Syntax gate: every shipped asset must parse as ES2017 (no ?., ??, object spread).
const fs = require('node:fs');
const path = require('node:path');
const acorn = require('acorn');
const dir = path.join(__dirname, '..', '..', '..', 'assets', 'javascripts');
let failed = 0;
for (const f of fs.readdirSync(dir).filter((n) => n.endsWith('.js')).sort()) {
  const file = path.join(dir, f);
  try {
    acorn.parse(fs.readFileSync(file, 'utf8'), { ecmaVersion: 2017, sourceType: 'script' });
    console.log('ok   ES2017 ' + f);
  } catch (e) {
    failed += 1;
    console.error('FAIL ES2017 ' + f + ': ' + e.message);
  }
}
process.exit(failed ? 1 : 0);
