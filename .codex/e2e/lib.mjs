// Helpers for end-to-end checks against the server from start_server.sh.
// A scenario script (test/e2e/<feature>.mjs in the plugin repo) looks like:
//
//   import { e2e } from '../../.codex/e2e/lib.mjs';
//   const t = await e2e('my-feature');                 // screenshots go to <out>/my-feature-*.png
//   await t.login('manager');                          // admin, manager, reporter, outsider
//   await t.go('/projects/e2e-project/issues/1');
//   await t.page.click('text=Edit');                   // plain Playwright from here on
//   await t.shot('edit-form', 'The edit form shows the new field');
//   await t.login('reporter');
//   await t.go('/projects/e2e-project/my_plugin', { status: 403 });   // a failure path is evidence too
//   await t.shot('no-permission', 'Without the permission the page is refused');
//   await t.done();
//
// Every navigation records the HTTP status, JavaScript errors and failed asset or
// XHR requests; done() fails the run when any of them was not expected, and
// writes <out>/<name>.md with one line per screenshot (caption, user, URL).
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

function loadPlaywright() {
  const roots = [process.cwd() + '/'];
  try { roots.push(execSync('npm root -g', { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim() + '/'); } catch { /* no npm */ }
  roots.push('/opt/node-tools/node_modules/', '/usr/local/lib/node_modules/', '/usr/lib/node_modules/');
  for (const r of roots) {
    try { return createRequire(r)('playwright'); } catch { /* next */ }
  }
  throw new Error('Playwright not found. Install it with: npm install -g playwright && npx playwright install --with-deps chromium');
}

export const BASE = process.env.RMP_URL || 'http://127.0.0.1:3000';
const OUT = process.env.RMP_E2E_OUT || 'docs/e2e';
const PASSWORDS = {
  admin: process.env.RMP_ADMIN_PASSWORD || 'Redmine7Test!',
  default: process.env.RMP_USER_PASSWORD || process.env.RMP_ADMIN_PASSWORD || 'Redmine7Test!',
};

// 'networkidle' never arrives on a page that keeps a WebSocket open (redmine_zenedit
// 3.x and its /rup_cable), so wait for it a few seconds at most.
async function settle(page) {
  await page.waitForLoadState('load').catch(() => {});
  await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
}

export async function e2e(name, { width = 1366, height = 900 } = {}) {
  const { chromium } = loadPlaywright();
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await chromium.launch();
  let context, page, user = 'anonymous';
  const shots = [];
  const problems = [];
  let pending = { js: [], requests: [] };

  async function newContext() {
    if (context) await context.close();
    context = await browser.newContext({ viewport: { width, height } });
    page = await context.newPage();
    page.on('pageerror', e => pending.js.push(String(e.message || e).split('\n')[0]));
    page.on('console', m => {
      if (m.type() === 'error' && !/Failed to load resource/.test(m.text())) pending.js.push('console: ' + m.text().split('\n')[0]);
    });
    page.on('response', r => {
      const type = r.request().resourceType();
      if (r.status() >= 400 && type !== 'document') pending.requests.push(`${r.status()} ${type} ${r.url().replace(BASE, '')}`);
    });
    api.page = page;
  }

  function flush(where, allow = {}) {
    for (const j of pending.js) if (!(allow.js || []).some(p => j.includes(p))) problems.push(`${where}: JS ${j}`);
    for (const q of pending.requests) if (!(allow.requests || []).some(p => q.includes(p))) problems.push(`${where}: ${q}`);
    pending = { js: [], requests: [] };
  }

  const api = {
    page: null,
    BASE,
    // Logs in as one of the seeded users in a fresh browser context (fresh cookies).
    async login(login, password) {
      await newContext();
      await page.goto(`${BASE}/login`);
      await page.fill('#username', login);
      await page.fill('#password', password || PASSWORDS[login] || PASSWORDS.default);
      await page.click('#login-submit');
      await page.waitForURL(u => !u.pathname.startsWith('/login'), { timeout: 20000 }).catch(() => {});
      await settle(page);
      if (await page.locator('#username').count()) throw new Error(`login failed as ${login}`);
      user = login;
      flush(`login ${login}`);
      return page;
    },
    async anonymous() { await newContext(); user = 'anonymous'; return page; },
    // Navigates and checks the HTTP status (default 200). Pass { status: 403 } to prove a refusal.
    async go(urlPath, { status = 200, allow = {} } = {}) {
      if (!page) await newContext();
      const res = await page.goto(BASE + urlPath);
      await settle(page);
      const got = res ? res.status() : 0;
      if (got !== status) problems.push(`${urlPath} as ${user}: HTTP ${got}, expected ${status}`);
      flush(`${urlPath} as ${user}`, allow);
      return page;
    },
    // Redmine 7 asks for the password again before sensitive actions (sudo mode,
    // on by default). Call this after a click that may lead to that form.
    async sudo(password) {
      if (await page.locator('#sudo_password').count()) {
        await page.fill('#sudo_password', password || PASSWORDS[user] || PASSWORDS.default);
        await page.locator('#sudo_password').press('Enter');
        await settle(page);
      }
    },
    // Call after clicks or form submits to attribute their errors to a step.
    check(step, allow = {}) { flush(`${step} as ${user}`, allow); },
    async shot(shotName, caption, { full = true } = {}) {
      await settle(page);
      const file = path.join(OUT, `${name}-${shotName}.png`);
      await page.screenshot({ path: file, fullPage: full });
      shots.push({ file: path.basename(file), caption, user, url: page.url().replace(BASE, '') });
      flush(`shot ${shotName}`);
      return file;
    },
    // Mails written by Redmine (delivery_method :file) since the given time.
    mails(since = 0) {
      const dir = path.join(process.env.REDMINE_DIR || 'redmine', 'tmp', 'mails');
      if (!fs.existsSync(dir)) return [];
      return fs.readdirSync(dir).map(f => path.join(dir, f))
        .filter(f => fs.statSync(f).mtimeMs >= since)
        .map(f => ({ to: path.basename(f), body: fs.readFileSync(f, 'utf8') }));
    },
    settle: () => settle(page),
    problems,
    async done() {
      const lines = [`# ${name}`, '', `Run ${new Date().toISOString()} against ${BASE}.`, '',
        '| screenshot | user | URL | shows |', '|---|---|---|---|',
        ...shots.map(s => `| ![](${s.file}) | ${s.user} | \`${s.url}\` | ${s.caption} |`)];
      if (problems.length) lines.push('', '## Problems', '', ...problems.map(p => `- ${p}`));
      fs.writeFileSync(path.join(OUT, `${name}.md`), lines.join('\n') + '\n');
      await browser.close();
      console.log(`${name}: ${shots.length} screenshot(s), ${problems.length} problem(s)`);
      for (const p of problems) console.log(`  FAIL ${p}`);
      if (problems.length) process.exitCode = 1;
    },
  };
  return api;
}
