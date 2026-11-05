#!/usr/bin/env node
'use strict';
/*
 * Writes the markdown tables of the performance report from results/summary.json, so no number is typed by hand.
 *   node report_tables.js [--summary results/summary.json] [--out report_tables.md]
 * Verdict rule (same for every time metric): slower when the branch median is more than 10 percent AND more than 5 ms above main,
 * faster when it is more than 10 percent AND more than 5 ms below, otherwise equal. Other units use the thresholds in RULES.
 */
const fs = require('fs');
const path = require('path');
const argv = process.argv.slice(2);
const arg = (k, d) => { const i = argv.indexOf(`--${k}`); return i >= 0 ? argv[i + 1] : d; };
const SUMMARY = path.resolve(arg('summary', path.join(require('./lib/paths').P, 'results', 'summary.json')));
const OUT = path.resolve(arg('out', path.join(require('./lib/paths').P, 'results', 'report_tables.md')));
const S = JSON.parse(fs.readFileSync(SUMMARY, 'utf8'));

const RULES = { ms: [0.10, 5], bytes: [0.10, 10240], mb: [0.10, 1], kb: [0.10, 5], count: [0.10, 2], alloc: [0.10, 1000] };
const num = (x, d = 0) => (x === null || x === undefined ? '-' : Number(x).toLocaleString('en-US', { minimumFractionDigits: d, maximumFractionDigits: d }));
const kb = (x) => (x === null || x === undefined ? '-' : num(x / 1024, 1));
function verdict(m, b, unit) {
  if (m === null || m === undefined || b === null || b === undefined) return '-';
  const [r, a] = RULES[unit];
  if (b > m * (1 + r) && b - m > a) return 'slower';
  if (b < m * (1 - r) && m - b > a) return 'faster';
  return 'equal';
}
const ratio = (m, b) => (m === null || b === null || m === undefined || b === undefined || m === 0 ? '-' : (b / m).toFixed(2));
const VERS = { 51: 'Redmine 5.1', 61: 'Redmine 6.1' };
const out = [];
const w = (s = '') => out.push(s);

function modeNote(p, variant) {
  const m = p.mode[variant];
  if (m && m.mode === 'timeout') return `timeout (> ${m.timeout_s} s)`;
  return null;
}
function cell(p, key, variant, f) {
  const note = modeNote(p, variant);
  const mm = p.metrics[key] && p.metrics[key][variant];
  if (!mm || mm.median === null) return note || '-';
  return f(mm);
}

const SERVER_ORDER = ['issue_new_s1', 'issue_new_s2', 'issue_new_baseline', 'issue_new_s2_admin', 'issue_edit_s1', 'issue_edit_s2', 'issue_edit_s2_admin',
  'issue_show_s1', 'issue_show_s2', 'issue_show_s2_admin', 'issue_list_s1', 'issue_list_s2', 'bulk_edit_s1', 'bulk_edit_s2',
  'context_menu_s1', 'context_menu_s2', 'issue_update_s1', 'issue_update_s2', 'project_settings_s1', 'project_settings_s2',
  'project_values_s1_city', 'project_values_s2_part', 'project_deps_s1_city', 'project_deps_s2_part', 'admin_cf_city', 'admin_cf_part'];

function serverTimeTable(ver) {
  const srv = S.versions[ver].server;
  w('| page | n main / branch | main median | main p90 | branch median | branch p90 | ratio median | ratio min | verdict |');
  w('|---|---|---|---|---|---|---|---|---|');
  for (const key of SERVER_ORDER) {
    const p = srv[key]; if (!p) continue;
    const t = p.metrics.ms || {};
    const a = t.main; const b = t.branch;
    let v;
    if (!a && b) v = modeNote(p, 'main') ? 'faster (main did not finish)' : '-';
    else v = verdict(a && a.median, b && b.median, 'ms');
    let conf = '';
    if (a && b && (v === 'slower' || v === 'faster')) {
      const dir = v === 'slower' ? 1 : -1;
      const strong = (x, y) => (y / x - 1) * dir >= 0.05; // p90 and min must also differ by at least 5 percent in the same direction
      if (!(strong(a.p90, b.p90) && strong(a.min, b.min))) conf = ' (weak: p90 or min within 5 percent)';
    }
    if (a && b && Math.min(p.n.main, p.n.branch) <= 8) conf += ` (n=${Math.min(p.n.main, p.n.branch)})`;
    w(`| ${key} | ${p.n.main}/${p.n.branch} | ${cell(p, 'ms', 'main', (x) => num(x.median))} | ${a ? num(a.p90) : '-'} | ${cell(p, 'ms', 'branch', (x) => num(x.median))} | ${b ? num(b.p90) : '-'} | ${a && b ? ratio(a.median, b.median) : '-'} | ${a && b ? ratio(a.min, b.min) : '-'} | ${v}${conf} |`);
  }
}

function serverWorkTable(ver) {
  const srv = S.versions[ver].server;
  w('| page | SQL queries main / branch | allocations main / branch (thousands) | CPU ms main / branch | response KB main / branch | gzipped KB main / branch | size verdict |');
  w('|---|---|---|---|---|---|---|');
  for (const key of SERVER_ORDER) {
    const p = srv[key]; if (!p) continue;
    const g = (k, f, v) => { const m = p.metrics[k] && p.metrics[k][v]; return m ? f(m.median) : (modeNote(p, v) || '-'); };
    const bm = p.metrics.bytes || {};
    const sv = bm.main && bm.branch ? verdict(bm.main.median, bm.branch.median, 'bytes') : '-';
    if (key === 'issue_update_s1' || key === 'issue_update_s2') {
      w(`| ${key} | ${g('sql', num, 'main')} / ${g('sql', num, 'branch')} | ${g('alloc', (x) => num(x / 1000, 1), 'main')} / ${g('alloc', (x) => num(x / 1000, 1), 'branch')} | ${g('cpu_ms', num, 'main')} / ${g('cpu_ms', num, 'branch')} | redirect, no body | redirect, no body | - |`);
      continue;
    }
    w(`| ${key} | ${g('sql', num, 'main')} / ${g('sql', num, 'branch')} | ${g('alloc', (x) => num(x / 1000, 1), 'main')} / ${g('alloc', (x) => num(x / 1000, 1), 'branch')} | ${g('cpu_ms', num, 'main')} / ${g('cpu_ms', num, 'branch')} | ${g('bytes', kb, 'main')} / ${g('bytes', kb, 'branch')} | ${g('gzip_bytes', kb, 'main')} / ${g('gzip_bytes', kb, 'branch')} | ${sv} |`);
  }
}

function memoryTable(ver) {
  const sm = S.versions[ver].meta.server;
  const mb = (k) => (k ? num(k / 1024) : '-');
  w('| checkpoint | main RSS MB | branch RSS MB | main peak RSS MB | branch peak RSS MB |');
  w('|---|---|---|---|---|');
  for (const c of sm.memory) {
    const star = (v) => ((c.restarted || []).includes(v) ? ' (server restarted)' : '');
    w(`| ${c.label} | ${mb(c.main && c.main.rss_kb)}${star('main')} | ${mb(c.branch && c.branch.rss_kb)}${star('branch')} | ${mb(c.main && c.main.hwm_kb)} | ${mb(c.branch && c.branch.hwm_kb)} |`);
    if (c.mixed) {
      const m = c.mixed;
      w(`| mixed run of ${m.branch.n} requests: wall seconds, objects allocated (millions), SQL queries | ${num(m.main.ms / 1000)} s, ${num(m.main.alloc_total / 1e6, 1)} M, ${num(m.main.sql)} | ${num(m.branch.ms / 1000)} s, ${num(m.branch.alloc_total / 1e6, 1)} M, ${num(m.branch.sql)} | | |`);
    }
  }
}

const BROWSER_PAGES = ['issue_new_s1', 'issue_new_s2', 'issue_edit_s2', 'context_menu_s1', 'context_menu_s2', 'admin_part_editor'];
function browserTable(ver, metrics) {
  const br = S.versions[ver].browser;
  w(`| page | ${metrics.map((m) => `${m.label} main / branch | verdict`).join(' | ')} |`);
  w(`|---|${metrics.map(() => '---|---|').join('')}`);
  for (const key of BROWSER_PAGES) {
    const p = br[key]; if (!p) continue;
    const cols = metrics.map((m) => {
      const mm = p.metrics[m.key] && p.metrics[m.key].main; const bb = p.metrics[m.key] && p.metrics[m.key].branch;
      if (!bb && !mm) return '- | -';
      const f = m.f || ((x) => num(x, m.d || 0));
      const a = mm ? f(mm.median) : (modeNote(p, 'main') || '-');
      const b = bb ? f(bb.median) : (modeNote(p, 'branch') || '-');
      const v = mm && bb ? verdict(mm.median, bb.median, m.unit) : (!mm && bb && modeNote(p, 'main') ? (m.unit === 'ms' ? 'faster (main did not finish)' : 'main did not finish') : '-');
      return `${a} / ${b} | ${v}`;
    });
    w(`| ${key} | ${cols.join(' | ')} |`);
  }
}
function interactionTable(ver) {
  const br = S.versions[ver].browser;
  w('| interaction | change handler returns (ms) main / branch | verdict | options shown and painted (ms) main / branch | verdict |');
  w('|---|---|---|---|---|');
  for (const key of ['interaction_s1_country', 'interaction_s2_assembly']) {
    const p = br[key]; if (!p) continue;
    const s = p.metrics.sync_ms; const q = p.metrics.paint_ms;
    w(`| ${key} | ${num(s.main.median)} / ${num(s.branch.median)} | ${verdict(s.main.median, s.branch.median, 'ms')} | ${num(q.main.median)} / ${num(q.branch.median)} | ${verdict(q.main.median, q.branch.median, 'ms')} |`);
  }
}
function menuTable(ver) {
  const br = S.versions[ver].browser;
  w('| page | context menu shown (ms) main / branch | verdict | wizard opened (ms) main / branch | verdict | sum of the two medians (ms) main / branch |');
  w('|---|---|---|---|---|---|');
  for (const key of ['context_menu_s1', 'context_menu_s2']) {
    const p = br[key]; const a = p.metrics.menu_ms; const b = p.metrics.wizard_ms;
    w(`| ${key} | ${num(a.main.median)} / ${num(a.branch.median)} | ${verdict(a.main.median, a.branch.median, 'ms')} | ${num(b.main.median)} / ${num(b.branch.median)} | ${verdict(b.main.median, b.branch.median, 'ms')} | ${num(a.main.median + b.main.median)} / ${num(a.branch.median + b.branch.median)} |`);
  }
}

for (const ver of Object.keys(S.versions)) {
  w(`<!-- ${VERS[ver]} -->`);
  w(`### SERVER TIME ${VERS[ver]}`); w(); serverTimeTable(ver); w();
  w(`### SERVER WORK ${VERS[ver]}`); w(); serverWorkTable(ver); w();
  w(`### MEMORY ${VERS[ver]}`); w(); memoryTable(ver); w();
  w(`### BROWSER LOAD ${VERS[ver]}`); w();
  browserTable(ver, [{ key: 'ttfb_ms', label: 'first byte', unit: 'ms' }, { key: 'dcl_ms', label: 'DOM ready', unit: 'ms' }, { key: 'load_ms', label: 'load', unit: 'ms' }]); w();
  w(`### BROWSER CPU ${VERS[ver]}`); w();
  browserTable(ver, [{ key: 'script_ms', label: 'script ms', unit: 'ms' }, { key: 'task_ms', label: 'main thread tasks ms', unit: 'ms' },
    { key: 'js_heap_mb', label: 'JS heap MB', unit: 'mb', d: 1 }, { key: 'plugin_script_ms', label: 'plugin script ms (profile)', unit: 'ms' }]); w();
  w(`### BROWSER ASSETS ${VERS[ver]}`); w();
  browserTable(ver, [{ key: 'plugin_assets_kb', label: 'plugin asset KB', unit: 'kb', d: 1 }, { key: 'plugin_assets_ms', label: 'plugin asset load ms', unit: 'ms' }, { key: 'nodes', label: 'DOM nodes', unit: 'count' }]); w();
  w(`### INTERACTION ${VERS[ver]}`); w(); interactionTable(ver); w();
  w(`### MENU ${VERS[ver]}`); w(); menuTable(ver); w();
}
fs.writeFileSync(OUT, out.join('\n') + '\n');
console.log(`wrote ${OUT}`);
