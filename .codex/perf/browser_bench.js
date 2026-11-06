#!/usr/bin/env node
'use strict';
/*
 * Browser harness: Chromium (Playwright) against the production servers of main and branch, logged in (session cookie).
 *
 *   node browser_bench.js --version 51|61 [--reps 10] [--profile 3] [--only regex] [--variants main,branch] [--out results/raw]
 *
 * --variants (default main,branch): any of none, main, branch (none = Redmine without the plugin, checkout n<ver>). Interleaved, the
 * order rotates per repetition. For none the interaction only records the options shown (no filtering exists, ok is true) and
 * the context menu is timed without the wizard entry (there is none).
 *
 * Pages: issue_new_s1, issue_new_s2 (Feature form with the 25,000 value Part), issue_edit_s2, admin_part_editor (admin editor of
 * Part), context_menu_s1 and context_menu_s2 (10 issues selected in the list, right click).
 * Per load (fresh tab, warm HTTP cache, `reps` repetitions, main and branch interleaved, first variant alternates):
 *   dcl_ms, load_ms, ttfb_ms (navigation timing), js_heap_mb, script_ms, task_ms, layout_ms, style_ms, nodes (CDP
 *   Performance.getMetrics, difference between the start of the tab and the settled page), plugin_assets_kb and plugin_assets_ms
 *   (resource timing of the plugin files).
 * Plugin script cost (separable part): `profile` extra loads with the V8 CPU profiler, inclusive time of every stack that passes
 * through a plugin script file (plugin_script_ms). The profiler slows everything down, so these loads feed only that metric.
 * Interactions (on the loaded issue_new pages): interaction_s1_country, interaction_s2_assembly: time from changing the parent
 * select to the child select showing exactly the allowed options. sync_ms = the change event handlers returned, paint_ms = after the
 * next two animation frames. ok tells whether the child options equal the stored mapping of the new parent value.
 * Context menu pages: menu_ms (right click until the menu is shown) and wizard_ms (click on the wizard entry until its form is
 * shown), in the samples of context_menu_s1 / context_menu_s2.
 * A page that does not finish within BROWSER_TIMEOUT_S (default 30) is recorded as timeout and its server restarted.
 */
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');
const { Client } = require('./lib/client');
const S = require('./lib/servers');

const argv = process.argv.slice(2);
const arg = (k, d) => { const i = argv.indexOf(`--${k}`); return i >= 0 ? argv[i + 1] : d; };
const VER = arg('version', '51');
const REPS = parseInt(arg('reps', '10'), 10);
const PROFILE = parseInt(arg('profile', process.env.PROFILE_REPS || '2'), 10);
const ONLY = arg('only', null);
const OUT = path.resolve(arg('out', path.join(S.P, 'results', 'raw')));
const NAV_TIMEOUT_MS = parseFloat(process.env.BROWSER_TIMEOUT_S || '30') * 1000;
const log = (...a) => console.error(`[browser_bench ${VER} ${new Date().toISOString().slice(11, 19)}]`, ...a);

const ids = S.paths.ids(VER);
const F = ids.fields; const I = ids.issues; const V = ids.values;
const NAMES = { main: `m${VER}`, branch: `p${VER}`, none: `n${VER}` };
const VARIANTS = arg('variants', 'main,branch').split(',').filter(Boolean);
if (!VARIANTS.length || VARIANTS.some((v) => !NAMES[v])) { console.error('--variants: none, main, branch'); process.exit(1); }
const PLUGIN_URL = /redmine_depending_custom_fields|depending_custom_fields\.js|context_menu_wizard\.js|dcf_[a-z_]+\.js/;

const listUrl = (project, idList) => `/projects/${project}/issues?set_filter=1&f[]=issue_id&op[issue_id]==&v[issue_id][]=${idList.join(',')}&per_page=25`;
const PAGES = [
  { key: 'issue_new_s1', user: 'member', path: '/projects/perf-a/issues/new?issue[tracker_id]=1', interaction: { key: 'interaction_s1_country', parent: F.Country.id, child: F.City.id, value: 'France', allowed: V.cities.France } },
  { key: 'issue_new_s2', user: 'member', path: '/projects/perf-large/issues/new?issue[tracker_id]=2', interaction: { key: 'interaction_s2_assembly', parent: F.Assembly.id, child: F.Part.id, value: 'A020', allowed: Array.from({ length: 50 }, (_, k) => `A020-P${String(k + 1).padStart(2, '0')}`) } },
  { key: 'issue_edit_s2', user: 'member', path: `/issues/${I.s2_show}/edit` },
  { key: 'admin_part_editor', user: 'admin', path: `/custom_fields/${F.Part.id}/edit`, heavy: true },
  { key: 'context_menu_s1', user: 'member', path: listUrl('perf-a', I.s1_ctx_ids), menu: true },
  { key: 'context_menu_s2', user: 'member', path: listUrl('perf-large', I.s2_ctx_ids), menu: true, reps: 5 }
].filter((p) => !ONLY || new RegExp(ONLY).test(p.key));

const rot = (a, r) => { const k = r % a.length; return a.slice(k).concat(a.slice(0, k)); };
const metric = (list, name) => (list.find((m) => m.name === name) || { value: 0 }).value;

async function newCtx(browser, port, cookie) {
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  await ctx.addCookies([{ name: '_redmine_session', value: cookie, domain: '127.0.0.1', path: '/' }]);
  return ctx;
}

// In-page helpers: time stamps are taken inside the page (performance.now) so the harness round trips do not count.
async function interact(page, spec, record) {
  return page.evaluate(async ({ parent, child, value, allowed, record }) => {
    const p = document.querySelector(`#issue_custom_field_values_${parent}`);
    const c = document.querySelector(`#issue_custom_field_values_${child}`);
    const visible = () => Array.from(c.options).filter((o) => o.value && !o.hidden && !o.disabled && o.style.display !== 'none').map((o) => o.value);
    const t0 = performance.now();
    p.value = value;
    p.dispatchEvent(new Event('change', { bubbles: true }));
    const t1 = performance.now();
    await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
    const t2 = performance.now();
    const got = visible();
    const ok = record || (got.length === allowed.length && allowed.every((a) => got.includes(a)));
    return { sync_ms: t1 - t0, paint_ms: t2 - t0, ok, options: got.length };
  }, { ...spec, record: !!record });
}

async function contextMenu(page, noWizard) {
  await page.evaluate(() => {
    window.__cm = { t0: null, t1: null };
    window.addEventListener('contextmenu', (e) => { if (window.__cm.t0 === null) window.__cm.t0 = performance.now(); }, true);
    const check = () => {
      const m = document.querySelector('#context-menu');
      if (window.__cm.t0 !== null && window.__cm.t1 === null && m && m.style.display !== 'none' && m.querySelector('a')) window.__cm.t1 = performance.now();
    };
    new MutationObserver(check).observe(document.body, { subtree: true, childList: true, attributes: true, attributeFilter: ['style'] });
    window.__cm.check = check;
  });
  await page.click('#check_all');
  const box = await page.locator('tr.issue td.tracker').first().boundingBox();
  await page.mouse.click(box.x + 10, box.y + 5, { button: 'right' });
  await page.waitForFunction(() => window.__cm && window.__cm.t1 !== null, null, { timeout: 30000 });
  const menu = await page.evaluate(() => window.__cm.t1 - window.__cm.t0);
  if (noWizard) return { menu_ms: menu };
  // the wizard entry
  await page.evaluate(() => {
    window.__wz = { t0: null, t1: null };
    window.addEventListener('click', () => { if (window.__wz.t0 === null) window.__wz.t0 = performance.now(); }, true);
    const check = () => {
      const f = document.querySelector('form.cf-wizard-form');
      if (window.__wz.t0 !== null && window.__wz.t1 === null && f && f.offsetParent !== null) window.__wz.t1 = performance.now();
    };
    new MutationObserver(check).observe(document.body, { subtree: true, childList: true, attributes: true });
  });
  await page.click('#context-menu li.cf-parent a.submenu');
  await page.waitForFunction(() => window.__wz && window.__wz.t1 !== null, null, { timeout: 30000 });
  const wizard = await page.evaluate(() => window.__wz.t1 - window.__wz.t0);
  return { menu_ms: menu, wizard_ms: wizard };
}

async function load(ctx, base, spec, { profile = false, variant = '' } = {}) {
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e.message).slice(0, 200)));
  const cdp = await ctx.newCDPSession(page);
  try {
    await cdp.send('Performance.enable');
    const m0 = (await cdp.send('Performance.getMetrics')).metrics;
    if (profile) { await cdp.send('Profiler.enable'); await cdp.send('Profiler.setSamplingInterval', { interval: 200 }); await cdp.send('Profiler.start'); }
    await page.goto(base + spec.path, { waitUntil: 'load', timeout: NAV_TIMEOUT_MS });
    await page.waitForTimeout(150);
    if (profile) {
      const { profile: prof } = await cdp.send('Profiler.stop');
      return { plugin_script_ms: pluginTime(prof), errors };
    }
    const m1 = (await cdp.send('Performance.getMetrics')).metrics;
    const nav = await page.evaluate(() => {
      const n = performance.getEntriesByType('navigation')[0];
      const plugin = performance.getEntriesByType('resource').filter((r) => /redmine_depending_custom_fields|depending_custom_fields|context_menu_wizard|dcf_/.test(r.name));
      return { dcl: n.domContentLoadedEventEnd, load: n.loadEventEnd, ttfb: n.responseStart, kb: plugin.reduce((a, r) => a + r.decodedBodySize, 0) / 1024, ms: plugin.reduce((a, r) => a + r.duration, 0), count: plugin.length };
    });
    const sample = {
      dcl_ms: nav.dcl, load_ms: nav.load, ttfb_ms: nav.ttfb, js_heap_mb: metric(m1, 'JSHeapUsedSize') / 1048576,
      script_ms: (metric(m1, 'ScriptDuration') - metric(m0, 'ScriptDuration')) * 1000, task_ms: (metric(m1, 'TaskDuration') - metric(m0, 'TaskDuration')) * 1000,
      layout_ms: (metric(m1, 'LayoutDuration') - metric(m0, 'LayoutDuration')) * 1000, style_ms: (metric(m1, 'RecalcStyleDuration') - metric(m0, 'RecalcStyleDuration')) * 1000,
      nodes: metric(m1, 'Nodes'), plugin_assets_kb: nav.kb, plugin_assets_ms: nav.ms, plugin_asset_requests: nav.count, js_errors: errors.length
    };
    const extra = {};
    if (spec.interaction) extra.interaction = await interact(page, spec.interaction, variant === 'none');
    if (spec.menu) extra.menu = await contextMenu(page, variant === 'none');
    return { sample, ...extra };
  } finally {
    await page.close().catch(() => {});
  }
}

// Inclusive time (ms) of all samples whose stack contains a frame from a plugin script file.
function pluginTime(profile) {
  const byId = new Map(); const parent = new Map();
  profile.nodes.forEach((n) => { byId.set(n.id, n); (n.children || []).forEach((c) => parent.set(c, n.id)); });
  const memo = new Map();
  const inPlugin = (id) => {
    if (memo.has(id)) return memo.get(id);
    const n = byId.get(id);
    const r = PLUGIN_URL.test(n.callFrame.url || '') || (parent.has(id) && inPlugin(parent.get(id)));
    memo.set(id, r);
    return r;
  };
  let us = 0;
  profile.samples.forEach((id, i) => { if (inPlugin(id)) us += profile.timeDeltas[i] || 0; });
  return us / 1000;
}

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const t0 = Date.now();
  const meta = { kind: 'browser', version: VER, reps: REPS, profile_reps: PROFILE, variants: VARIANTS, started: new Date().toISOString(), load_at_start: S.loadavg1(), notes: {} };
  const up = {};
  for (const v of VARIANTS) {
    try { log(S.start(NAMES[v])); up[v] = true; } catch (e) { meta.notes[`boot_failed_${v}`] = String(e.stdout || e.message).slice(-800); }
  }
  if (VARIANTS.some((v) => !up[v])) { log('a variant did not boot'); VARIANTS.forEach((v) => S.stop(NAMES[v])); process.exit(2); }
  const browser = await chromium.launch();
  meta.chromium = browser.version();
  const base = {}; const ctxs = {};
  const cookies = {};
  const login = async (v) => {
    base[v] = `http://127.0.0.1:${S.PORTS[NAMES[v]]}`;
    cookies[v] = {};
    for (const u of ['admin', 'member']) {
      const c = await new Client(S.PORTS[NAMES[v]]).login(ids.users[u].login, ids.users[u].password);
      cookies[v][u] = c.cookies._redmine_session; c.close();
    }
    ctxs[v] = {};
    for (const u of ['admin', 'member']) { if (ctxs[v][u]) await ctxs[v][u].close().catch(() => {}); ctxs[v][u] = await newCtx(browser, S.PORTS[NAMES[v]], cookies[v][u]); }
  };
  const results = {}; // results[variant][key] = {mode, samples}
  const rec = (v, key) => ((results[v] ||= {})[key] ||= { mode: { mode: 'normal' }, samples: [] });
  try {
    for (const v of VARIANTS) if (up[v]) await login(v);
    const live = () => VARIANTS.filter((v) => up[v]);
    // one untimed load of every page per variant (cold HTTP cache, JIT) and the mapping check
    // heavy pages first: a timeout restarts a server, which must be warm again before the repetitions
    for (const p of [...PAGES].sort((a, b) => (b.heavy ? 1 : 0) - (a.heavy ? 1 : 0))) {
      for (const v of live()) {
        try { await load(ctxs[v][p.user], base[v], p, { variant: v }); } catch (e) {
          if (p.heavy) { rec(v, p.key).mode = { mode: 'timeout', timeout_s: NAV_TIMEOUT_MS / 1000, error: String(e.message).slice(0, 120) }; log(`${p.key} ${v}: ${String(e.message).slice(0, 80)}, restarting server`); S.start(NAMES[v]); await login(v); }
          else throw e;
        }
      }
    }
    for (let r = 0; r < REPS; r++) {
      for (const p of PAGES.filter((x) => r < (x.reps ? Math.min(x.reps, REPS) : REPS))) {
        for (const v of rot(live(), r)) {
          const entry = rec(v, p.key);
          if (entry.mode.mode === 'timeout') continue;
          try {
            const res = await load(ctxs[v][p.user], base[v], p, { variant: v });
            entry.samples.push({ phase: 'measured', ...res.sample, ...(res.menu || {}) });
            if (res.interaction) rec(v, p.interaction.key).samples.push({ phase: 'measured', ...res.interaction });
          } catch (e) {
            if (p.heavy) { entry.mode = { mode: 'timeout', timeout_s: NAV_TIMEOUT_MS / 1000, after_reps: r, error: String(e.message).slice(0, 120) }; log(`${p.key} ${v}: ${String(e.message).slice(0, 80)}`); S.start(NAMES[v]); await login(v); }
            else { entry.samples.push({ phase: 'measured', ok: false, error: String(e.message).slice(0, 200) }); log(`${p.key} ${v}: ${String(e.message).slice(0, 160)}`); }
          }
        }
      }
      log(`rep ${r + 1}/${REPS} (${((Date.now() - t0) / 60000).toFixed(1)} min)`);
    }
    // plugin script cost: profiled loads
    for (let r = 0; r < PROFILE; r++) {
      for (const p of PAGES.filter((x) => !x.menu && x.key !== 'issue_edit_s2')) {
        for (const v of rot(live(), r)) {
          const entry = rec(v, p.key);
          if (entry.mode.mode === 'timeout') continue;
          try {
            const res = await load(ctxs[v][p.user], base[v], p, { profile: true });
            (entry.profile ||= []).push(res.plugin_script_ms);
          } catch (e) { log(`profile ${p.key} ${v}: ${String(e.message).slice(0, 120)}`); }
        }
      }
    }
    // profiled values become samples of their own phase-free metric on the same page
    const stamp = new Date().toISOString();
    const keys = new Set(); VARIANTS.forEach((v) => Object.keys(results[v] || {}).forEach((k) => keys.add(k)));
    for (const k of keys) {
      for (const v of VARIANTS) {
        const e = (results[v] || {})[k] || { mode: { mode: up[v] ? 'not_run' : 'not_available', reason: up[v] ? '' : 'variant did not boot' }, samples: [] };
        const samples = e.samples.slice();
        (e.profile || []).forEach((x) => samples.push({ phase: 'profile', ok: true, plugin_script_ms: x }));
        fs.writeFileSync(path.join(OUT, `browser_${VER}_${v}_${k}.json`), JSON.stringify({ kind: 'browser', version: VER, variant: v, page: k, mode: e.mode, samples, time: stamp }));
      }
    }
    meta.finished = new Date().toISOString(); meta.minutes = (Date.now() - t0) / 60000; meta.load_at_end = S.loadavg1();
    fs.writeFileSync(path.join(OUT, `browser_${VER}_meta.json`), JSON.stringify(meta, null, 1));
    log(`done in ${meta.minutes.toFixed(1)} min`);
  } finally {
    await browser.close().catch(() => {});
    for (const v of VARIANTS) S.stop(NAMES[v]);
  }
})().catch((e) => { console.error(e); for (const v of VARIANTS) S.stop(NAMES[v]); process.exit(1); });
