// Shared Playwright helpers for the DCF walkthrough.
// Usage: const L = require('../lib'); const run = await L.start({ver:'5.1', scenario:'name'});
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const E2E = process.env.E2E_DIR || path.join(process.env.DCF_WORK_DIR || '.', 'e2e'); // checkouts and output (out/)
const PORTS = { '5.1': 3051, '7.0': 3070 };
const PASSWORDS = { admin: 'admin123!', manager: 'Passw0rd!x', developer: 'Passw0rd!x', reporter: 'Passw0rd!x' };

function baseUrl(ver) { return process.env.BASE_URL || `http://127.0.0.1:${PORTS[ver]}`; }

// start({ver, scenario}) -> run object with browser, context, page, helpers.
async function start({ ver, scenario, viewport = { width: 1400, height: 1000 } }) {
  const outDir = path.join(E2E, 'out', ver);
  fs.mkdirSync(outDir, { recursive: true });
  const browser = await chromium.launch();
  const run = {
    ver, scenario, outDir, browser, base: baseUrl(ver), viewport,
    steps: [], errors: [], consoleMessages: [], responses5xx: [], ids: loadIds(ver), seq: 0,
    user: null,
  };
  await newContext(run);
  return run;
}

function loadIds(ver) {
  // b* databases are the ones used by the scenarios; ids are identical per version.
  const f = path.join(E2E, 'out', ver === '5.1' ? 'ids-dcf_e2e_b51.json' : 'ids-dcf_e2e_b70.json');
  try { return JSON.parse(fs.readFileSync(f, 'utf8')); } catch (e) { return null; }
}

async function newContext(run) {
  if (run.context) await run.context.close().catch(() => {});
  run.context = await run.browser.newContext({ viewport: run.viewport });
  run.page = await run.context.newPage();
  attachCapture(run, run.page);
  run.context.on('page', (p) => attachCapture(run, p));
}

function attachCapture(run, page) {
  page.on('console', (m) => {
    run.consoleMessages.push({ type: m.type(), text: m.text(), url: page.url() });
    if (m.type() === 'error') run.errors.push({ kind: 'console', text: m.text(), url: page.url() });
  });
  page.on('pageerror', (e) => run.errors.push({ kind: 'pageerror', text: String(e && e.message || e), url: page.url() }));
  page.on('response', (r) => {
    if (r.status() >= 500) run.responses5xx.push({ status: r.status(), url: r.url() });
  });
}

// login(run, user[, password]) -> logs out any session first (fresh context).
async function login(run, user, password) {
  await newContext(run);
  const pw = password || PASSWORDS[user];
  const page = run.page;
  await page.goto(run.base + '/login');
  await page.fill('#username', user);
  await page.fill('#password', pw);
  await Promise.all([page.waitForLoadState('load'), page.click('#login-submit')]);
  const loggedIn = !/\/login(\?|$)/.test(page.url()) && (await page.locator('#login-form').count()) === 0;
  run.user = loggedIn ? user : null;
  if (!loggedIn) throw new Error(`login failed for ${user} at ${page.url()}`);
  return page;
}

async function goto(run, p, opts = {}) {
  const url = p.startsWith('http') ? p : run.base + p;
  const resp = await run.page.goto(url, { waitUntil: 'load', ...opts });
  return resp;
}

function slug(s) { return String(s).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 60); }

// screenshot(run, name) -> path under out/<ver>/<scenario>/NN-name.png
async function screenshot(run, name, opts = {}) {
  const dir = path.join(run.outDir, run.scenario || 'misc');
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, `${String(++run.seq).padStart(2, '0')}-${slug(name)}.png`);
  await run.page.screenshot({ path: file, fullPage: opts.fullPage !== false });
  return file;
}

// step(run, name, fn): runs fn, records pass/fail, screenshot on failure.
// fn may return a string or object as detail. Never throws unless opts.fatal.
async function step(run, name, fn, opts = {}) {
  const t = Date.now();
  const rec = { n: run.steps.length + 1, name, ok: true, detail: null, ms: 0, screenshot: null };
  try {
    const d = await fn();
    if (d !== undefined) rec.detail = d;
  } catch (e) {
    rec.ok = false;
    rec.detail = String(e && e.message || e).split('\n').slice(0, 6).join(' | ');
    try { rec.screenshot = path.relative(E2E, await screenshot(run, 'FAIL-' + name)); } catch (_) { /* page gone */ }
  }
  rec.ms = Date.now() - t;
  run.steps.push(rec);
  console.log(`${rec.ok ? 'PASS' : 'FAIL'} [${run.ver}] ${name}${rec.ok ? '' : ' :: ' + rec.detail}`);
  if (!rec.ok && opts.fatal) throw new Error(`fatal step failed: ${name}`);
  return rec.ok;
}

// assertNotInHtml(run, strings, {url}) -> throws listing strings found in the
// current (or fetched) page HTML, scripts, data attributes and inline JSON included.
async function assertNotInHtml(run, strings, opts = {}) {
  let html;
  if (opts.url) html = await (await run.context.request.get(opts.url.startsWith('http') ? opts.url : run.base + opts.url)).text();
  else html = await run.page.content();
  const found = strings.filter((s) => html.includes(s));
  if (found.length) throw new Error(`forbidden strings present in HTML: ${JSON.stringify(found)}`);
  return `none of ${strings.length} strings in HTML (${html.length} bytes)`;
}

// Same for a JSON/HTML endpoint fetched with the logged-in session.
async function assertNotInResponse(run, url, strings) {
  return assertNotInHtml(run, strings, { url });
}

function expectEqual(actual, expected, what) {
  const a = JSON.stringify(actual); const b = JSON.stringify(expected);
  if (a !== b) throw new Error(`${what || 'value'}: expected ${b}, got ${a}`);
}

// Option labels of a <select> (non-hidden, non-disabled unless all=true).
async function selectOptions(run, selector, all = false) {
  return run.page.$$eval(`${selector} option`, (opts, all) => opts
    .filter((o) => all || (!o.hidden && !o.disabled && o.style.display !== 'none'))
    .map((o) => o.textContent.trim()), all);
}

// Custom field select selector on issue forms.
function cfSel(id) { return `#issue_custom_field_values_${id}`; }

// finish(run) -> writes out/<ver>/<scenario>.json, closes the browser, returns summary.
async function finish(run) {
  const summary = {
    scenario: run.scenario, ver: run.ver, base: run.base, finished: new Date().toISOString(),
    passed: run.steps.filter((s) => s.ok).length, failed: run.steps.filter((s) => !s.ok).length,
    steps: run.steps, errors: run.errors, responses5xx: run.responses5xx,
    consoleWarnings: run.consoleMessages.filter((m) => m.type === 'warning').length,
  };
  fs.mkdirSync(run.outDir, { recursive: true });
  fs.writeFileSync(path.join(run.outDir, `${run.scenario}.json`), JSON.stringify(summary, null, 2));
  await run.browser.close();
  console.log(`== ${run.scenario} [${run.ver}] pass ${summary.passed} fail ${summary.failed} js-errors ${run.errors.length} 5xx ${run.responses5xx.length}`);
  return summary;
}

module.exports = { E2E, PORTS, PASSWORDS, start, login, goto, screenshot, step, assertNotInHtml, assertNotInResponse,
  expectEqual, selectOptions, cfSel, finish, newContext, baseUrl };
