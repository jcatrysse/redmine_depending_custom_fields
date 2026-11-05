// Helpers for the admin/project scenarios. Args: <base-url> <out-dir>
const fs = require('fs');
const path = require('path');
const L = require('./lib');
const E2E = L.E2E;

function parseArgs() {
  const base = process.argv[2] || 'http://127.0.0.1:3151';
  const ver = /3070|3051/.test(base) ? (/3070/.test(base) ? '7.0' : '5.1') : (/3170/.test(base) ? '7.0' : '5.1');
  const outDir = process.argv[3] || path.join(E2E, 'out', ver);
  const checkout = { '3151': 'c51', '3170': 'c70', '3051': 'b51', '3070': 'b70' }[(base.match(/:(\d+)/) || [])[1]];
  return { base, ver, outDir, checkout };
}

async function start(key) {
  const a = parseArgs();
  const run = await L.start({ ver: a.ver, scenario: key, viewport: { width: 1366, height: 900 } });
  run.checkout = a.checkout; run.base = a.base; run.outDir = a.outDir; run.key = key; run.recs = []; run.ver = a.ver;
  run.logFile = path.join(E2E, a.checkout, 'log', 'development.log');
  try { run.logStart = fs.statSync(run.logFile).size; } catch (e) { run.logStart = 0; }
  fs.mkdirSync(path.join(a.outDir, key), { recursive: true });
  return run;
}

// check(run, name, expected, fn): fn returns observed (string/obj) or throws on mismatch. Screenshot after each step.
async function check(run, name, expected, fn) {
  const rec = { step: name, expected, observed: null, pass: true, screenshot: null };
  const t = Date.now();
  try { const o = await fn(); rec.observed = o === undefined ? 'ok' : o; }
  catch (e) { rec.pass = false; rec.observed = String(e && e.message || e).split('\n').slice(0, 6).join(' | '); }
  rec.ms = Date.now() - t;
  try { rec.screenshot = await L.screenshot(run, name); } catch (e) { rec.screenshot = null; }
  run.recs.push(rec);
  console.log(`${rec.pass ? 'PASS' : 'FAIL'} [${run.ver}] ${name} (${rec.ms}ms) ${rec.pass ? '' : ':: ' + rec.observed}`);
  return rec.pass;
}

async function finish(run) {
  let logExc = [];
  try {
    const buf = fs.readFileSync(run.logFile); const txt = buf.slice(run.logStart).toString('utf8');
    logExc = txt.split('\n').filter((l) => /Error|Exception|Completed 5\d\d|FATAL/.test(l) && !/ActionController::RoutingError.*favicon/.test(l)).slice(0, 30);
  } catch (e) {}
  const out = { scenario: run.key, ver: run.ver, base: run.base, steps: run.recs, consoleErrors: run.errors, responses5xx: run.responses5xx, logExceptions: logExc };
  fs.writeFileSync(path.join(run.outDir, run.key + '.json'), JSON.stringify(out, null, 2));
  await run.browser.close();
  console.log(`== ${run.key} [${run.ver}] pass ${run.recs.filter((r) => r.pass).length} fail ${run.recs.filter((r) => !r.pass).length} jserr ${run.errors.length} 5xx ${run.responses5xx.length} logexc ${logExc.length}`);
}

// Submit form helper
const exp = (a, b, w) => L.expectEqual(a, b, w);
const cp = require('child_process');
function rails(run, code) {
  const f = path.join(E2E, 'tmp-' + run.key + '-' + run.ver + '.rb');
  fs.writeFileSync(f, code);
  const co = path.join(E2E, run.checkout);
  const cmd = `cd ${co} && source ${path.join(__dirname, '..', 'lib', 'common.sh')} && dcf_select_ruby ${run.ver} >/dev/null 2>&1 && RAILS_ENV=development bundle exec rails runner ${f} 2>&1 | tail -20`;
  return cp.execSync(cmd, { shell: '/bin/bash', encoding: 'utf8', timeout: 180000 });
}
module.exports = { rails, L, start, check, finish, exp, parseArgs };
