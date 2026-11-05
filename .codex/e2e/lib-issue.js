// Helpers for the issue side scenarios. Records {step, expected, observed, pass, screenshot}.
const fs = require('fs');
const path = require('path');
const L = require('./lib');
const E2E = L.E2E;
const NAMES = { '5.1': 'b51', '7.0': 'b70' };

function parseArgs() {
  const a = process.argv[2];
  let ver, base, outDir;
  if (a === '5.1' || a === '7.0') { ver = a; base = L.baseUrl(ver); outDir = path.join(E2E, 'out', ver); }
  else {
    base = a; outDir = process.argv[3] || path.join(E2E, 'out', 'misc');
    ver = /:3051/.test(a) || /:3151/.test(a) ? '5.1' : '7.0';
    if (process.argv[3]) outDir = path.resolve(process.argv[3]);
  }
  return { ver, base, outDir };
}

async function begin(key) {
  const { ver, base, outDir } = parseArgs();
  const run = await L.start({ ver, scenario: key, viewport: { width: 1366, height: 900 } });
  run.base = base; run.outDir = outDir; run.records = []; run.key = key;
  fs.mkdirSync(outDir, { recursive: true });
  run.logFile = path.join(E2E, NAMES[ver], 'log', 'development.log');
  try { run.logStart = fs.statSync(run.logFile).size; } catch (_) { run.logStart = 0; }
  run.uniq = Date.now().toString(36);
  return run;
}

// S(run, name, expected, fn): fn returns observed (string/object); throws on failed expectation.
async function S(run, name, expected, fn) {
  let observed, pass = true;
  try { observed = await fn(); if (observed === undefined) observed = 'as expected'; }
  catch (e) { pass = false; observed = String(e && e.message || e).split('\n').slice(0, 6).join(' | ').slice(0, 900); }
  let shot = null;
  try { shot = path.relative(E2E, await L.screenshot(run, name)); } catch (_) {}
  if (typeof observed !== 'string') observed = JSON.stringify(observed);
  run.records.push({ step: name, expected, observed, pass, screenshot: shot });
  console.log(`${pass ? 'PASS' : 'FAIL'} [${run.ver}] ${name}${pass ? '' : ' :: ' + observed}`);
  return pass;
}

function serverLogExceptions(run) {
  try {
    const fd = fs.openSync(run.logFile, 'r'); const st = fs.fstatSync(fd);
    const len = st.size - run.logStart; const buf = Buffer.alloc(len);
    fs.readSync(fd, buf, 0, len, run.logStart); fs.closeSync(fd);
    return buf.toString('utf8').split('\n').filter((l) => /Error \(|Exception|Completed 5\d\d|ActionView::Template::Error|NoMethodError|translation missing/i.test(l)).slice(0, 30);
  } catch (e) { return ['log read failed: ' + e.message]; }
}

async function end(run) {
  const out = {
    scenario: run.key, ver: run.ver, base: run.base, finished: new Date().toISOString(),
    pass: run.records.filter((r) => r.pass).length, fail: run.records.filter((r) => !r.pass).length,
    records: run.records, consoleErrors: run.errors, responses5xx: run.responses5xx, serverLogHits: serverLogExceptions(run),
  };
  fs.writeFileSync(path.join(run.outDir, `${run.key}.json`), JSON.stringify(out, null, 2));
  await run.browser.close();
  console.log(`== ${run.key} [${run.ver}] pass ${out.pass} fail ${out.fail} console-errors ${run.errors.length} 5xx ${run.responses5xx.length} log-hits ${out.serverLogHits.length}`);
  return out;
}

const sel = (id) => `#issue_custom_field_values_${id}`;
const F = (run, name) => run.ids.fields[name].id;

// Visible (not hidden/disabled) option labels of a select; '' for blank.
async function opts(run, selector) {
  return run.page.$$eval(`${selector} option`, (o) => o.filter((x) => !x.hidden && !x.disabled && x.style.display !== 'none').map((x) => x.textContent.trim()));
}
async function val(run, selector) {
  return run.page.$eval(selector, (e) => e.multiple ? [...e.selectedOptions].map((o) => o.textContent.trim()) : (e.selectedOptions[0] ? e.selectedOptions[0].textContent.trim() : ''));
}
async function pick(run, selector, label, wait = 500) {
  await run.page.selectOption(selector, { label });
  await run.page.waitForTimeout(wait);
}
async function pickMulti(run, selector, labels, wait = 500) {
  await run.page.selectOption(selector, labels.map((l) => ({ label: l })));
  await run.page.waitForTimeout(wait);
}
// Add a forced option (bypasses the JS filter) and select it.
async function force(run, selector, value) {
  await run.page.evaluate(([s, v]) => {
    const e = document.querySelector(s);
    let o = [...e.options].find((x) => x.value === v);
    if (!o) { o = new Option(v, v); e.add(o); }
    o.hidden = false; o.disabled = false;
    if (e.multiple) o.selected = true; else e.value = v;
  }, [selector, value]);
}
async function hintFor(run, selector) {
  return run.page.evaluate((s) => {
    const e = document.querySelector(s); if (!e) return null;
    const p = e.closest('p') || e.closest('.cf-wizard-field') || e.parentElement;
    return [...p.querySelectorAll('.dcf-hint')].filter((h) => !h.hidden && h.offsetParent !== null).map((h) => h.textContent.trim()).join(' / ');
  }, selector);
}
async function visible(run, selector) {
  return run.page.evaluate((s) => { const e = document.querySelector(s); return !!e && e.offsetParent !== null; }, selector);
}
async function submitIssue(run) {
  await Promise.all([run.page.waitForLoadState('load'), run.page.click('#issue-form input[type=submit][name=commit]')]);
  await run.page.waitForTimeout(300);
}
async function errorText(run) {
  const e = run.page.locator('#errorExplanation');
  return (await e.count()) ? (await e.innerText()).replace(/\s+/g, ' ').trim() : '';
}
async function flashText(run) {
  const e = run.page.locator('#flash_notice, #flash_error, .flash');
  return (await e.count()) ? (await e.first().innerText()).replace(/\s+/g, ' ').trim() : '';
}
function issueIdFromUrl(u) { const m = /\/issues\/(\d+)/.exec(u); return m ? +m[1] : null; }

// REST helper with basic auth (REST API is enabled in the seed).
async function api(run, method, p, body, user = 'manager') {
  const pw = L.PASSWORDS[user];
  const r = await fetch(run.base + p, {
    method, headers: { 'Content-Type': 'application/json', Authorization: 'Basic ' + Buffer.from(`${user}:${pw}`).toString('base64') },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await r.text(); let json = null; try { json = JSON.parse(text); } catch (_) {}
  return { status: r.status, json, text };
}
// Create an issue through REST. cf: {name: value}
async function createIssue(run, subject, cf, extra = {}, user = 'manager') {
  const custom_fields = Object.entries(cf).map(([n, v]) => ({ id: F(run, n), value: v }));
  const r = await api(run, 'POST', '/issues.json', { issue: { project_id: 1, tracker_id: 1, subject, custom_fields, ...extra } }, user);
  if (r.status !== 201) throw new Error(`createIssue ${subject}: ${r.status} ${r.text.slice(0, 200)}`);
  return r.json.issue.id;
}
async function issueCf(run, id, user = 'manager') {
  const r = await api(run, 'GET', `/issues/${id}.json`, null, user);
  const o = {}; for (const c of (r.json.issue.custom_fields || [])) o[c.name] = c.value; return o;
}
// Page text content of the main content area.
async function content(run) { return (await run.page.locator('#content').innerText()).replace(/\s+/g, ' '); }

module.exports = { L, E2E, begin, S, end, sel, F, opts, val, pick, pickMulti, force, hintFor, visible, submitIssue, errorText, flashText, issueIdFromUrl, api, createIssue, issueCf, content };
