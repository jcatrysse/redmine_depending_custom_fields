// Baseline browser check, run by e2e.sh before the plugin's own scenarios:
// as admin, every GET page the plugin adds (routes.rb) with its parameters
// filled from the seed, the plugin's settings page, and the core pages a plugin
// most often hooks into. One screenshot per page; fails on HTTP >= 500, a
// JavaScript error or a missing asset. It proves pages render, not that the
// features work: that is what test/e2e/*.mjs is for.
import fs from 'node:fs';
import { e2e } from './lib.mjs';

const P = 'e2e-project';
const id = process.env.PLUGIN_NAME;
const routes = (process.env.RMP_ROUTES_FILE && fs.existsSync(process.env.RMP_ROUTES_FILE))
  ? fs.readFileSync(process.env.RMP_ROUTES_FILE, 'utf8').split('\n').filter(Boolean) : [];

const pages = new Set([
  '/', `/projects/${P}`, `/projects/${P}/issues`, '/issues/1', `/projects/${P}/issues/new`,
  `/projects/${P}/settings`, '/my/page', '/my/account', '/admin', '/admin/plugins',
]);
if (fs.existsSync(`${process.env.REDMINE_DIR}/plugins/${id}/app/views/settings`)) pages.add(`/settings/plugin/${id}`);
for (const spec of routes) {
  if (/\*|logout|\/login/.test(spec)) continue;
  let uri = spec.replace(/\(\.:format\)/g, '').replace(/\([^)]*\)/g, '');
  uri = uri.replace(/:project_id|:project\b/g, P).replace(/:(issue_id|user_id|version_id|id)\b/g, '1')
           .replace(/:[a-z_]+/g, '1');
  pages.add(uri);
}

const t = await e2e('smoke');
await t.login('admin');
let n = 0;
for (const uri of pages) {
  n += 1;
  const res = await t.page.goto(t.BASE + uri).catch(e => ({ status: () => 0, err: e }));
  await t.settle();
  const status = res.status();
  // 404/403/422 are expected for some guessed parameters; a 5xx never is.
  if (status === 0 || status >= 500) t.problems.push(`${uri}: HTTP ${status}`);
  t.check(uri);
  await t.shot(String(n).padStart(2, '0'), `${uri} (HTTP ${status})`, { full: false });
}
await t.done();
