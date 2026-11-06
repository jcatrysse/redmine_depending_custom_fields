#!/usr/bin/env node
'use strict';
/*
 * summary.json of a run with the variant `none` (Redmine without the plugin) to the markdown tables of section 13 of the report:
 * medians of none / main / branch per page and metric, branch minus none (absolute and percent of none), memory and browser.
 * Every number comes from the file; nothing is typed by hand.
 *
 *   node report_noplugin.js [--summary results/summary.json] > tables.md
 */
const fs = require('fs');
const path = require('path');

const argv = process.argv.slice(2);
const arg = (k, d) => { const i = argv.indexOf(`--${k}`); return i >= 0 ? argv[i + 1] : d; };
const SUM = JSON.parse(fs.readFileSync(path.resolve(arg('summary', 'results/summary.json')), 'utf8'));
const VERS = { 51: 'Redmine 5.1', 61: 'Redmine 6.1' };
const PAGES = ['issue_new_s1', 'issue_edit_s1', 'issue_show_s1', 'issue_list_s1', 'bulk_edit_s1', 'context_menu_s1', 'issue_update_s1', 'project_settings_s1'];

const num = (x, d) => (x === null || x === undefined || Number.isNaN(x) ? '-' : (Math.abs(x) >= 1000 ? Math.round(x).toLocaleString('en-US') : x.toFixed(d)));
const sgn = (x, d) => (x === null || x === undefined ? '-' : `${x > 0 ? '+' : ''}${num(x, d)}`);
const med = (m, v) => (m && m[v] && m[v].median !== null && m[v].median !== undefined ? m[v].median : null);

function row(label, m, d, scale = 1) {
  const n = med(m, 'none'); const a = med(m, 'main'); const b = med(m, 'branch');
  if (n === null && a === null && b === null) return null;
  const f = (x) => (x === null ? null : x / scale);
  const diff = n !== null && b !== null ? (b - n) / scale : null;
  const pct = n !== null && b !== null && n !== 0 ? ((b - n) / n) * 100 : null;
  return `| ${label} | ${num(f(n), d)} | ${num(f(a), d)} | ${num(f(b), d)} | ${sgn(diff, d)} | ${pct === null ? '-' : sgn(pct, 1)} |`;
}
const HEAD = '| page | metric | none | main | branch | branch - none | branch - none (%) |\n|---|---|---|---|---|---|---|';

function serverTable(data, metrics) {
  const out = [HEAD];
  for (const p of PAGES) {
    const page = data.server[p];
    if (!page) continue;
    for (const [k, label, d, scale] of metrics) {
      const r = row(`${p} | ${label}`, page.metrics[k], d, scale || 1);
      if (r) out.push(r);
    }
  }
  return out.join('\n');
}

const out = [];
for (const [ver, data] of Object.entries(SUM.versions)) {
  if (!data.server || !data.server[PAGES[0]] || !data.server[PAGES[0]].n.none) continue;
  const sm = data.meta.server; const bm = data.meta.browser;
  out.push(`### 13.${ver === '51' ? 'a' : 'b'} ${VERS[ver]}: server, per request (medians of ${sm.rounds} rounds)\n`);
  out.push('Time (ms):\n');
  out.push(serverTable(data, [['ms', 'wall', 1], ['cpu_ms', 'CPU', 1], ['view_ms', 'view', 1], ['db_ms', 'ActiveRecord', 1]]));
  out.push('\nWork and size per request:\n');
  out.push(serverTable(data, [['sql', 'SQL queries', 0], ['alloc', 'allocations (objects)', 0], ['bytes', 'response (KB)', 1, 1024], ['gzip_bytes', 'gzipped (KB)', 1, 1024]]));

  out.push(`\nMemory of the Puma worker, ${VERS[ver]} (RSS in MB):\n`);
  out.push('| checkpoint | none | main | branch | branch - none (MB) | branch - none (%) |\n|---|---|---|---|---|---|');
  for (const c of sm.memory) {
    if (!['after_boot', 'after_warmup', 'after_rounds'].includes(c.label)) continue;
    const g = (v) => (c[v] && c[v].rss_kb ? c[v].rss_kb / 1024 : null);
    const n = g('none'); const b = g('branch');
    out.push(`| ${c.label} | ${num(n, 0)} | ${num(g('main'), 0)} | ${num(b, 0)} | ${sgn(b - n, 0)} | ${sgn(((b - n) / n) * 100, 1)} |`);
  }
  const heap = sm.memory.find((c) => c.label === 'after_rounds');
  if (heap) {
    const h = (v) => (heap[v] ? heap[v].heap_live_slots : null);
    out.push(`\nRuby heap_live_slots after the rounds: none ${num(h('none'), 0)}, main ${num(h('main'), 0)}, branch ${num(h('branch'), 0)}.`);
  }

  out.push(`\nBrowser, ${VERS[ver]} (Chromium ${bm.chromium}, ${bm.reps} repetitions, medians):\n`);
  out.push('| page | metric | none | main | branch | branch - none | branch - none (%) |\n|---|---|---|---|---|---|---|');
  const B = [['issue_new_s1', [['load_ms', 'load event (ms)', 0], ['dcl_ms', 'domContentLoaded (ms)', 0], ['js_heap_mb', 'JS heap (MB)', 2], ['script_ms', 'script duration (ms)', 1],
    ['plugin_script_ms', 'plugin script CPU profile (ms)', 1], ['plugin_assets_kb', 'plugin asset bytes (KB)', 1]]],
  ['interaction_s1_country', [['paint_ms', 'parent change to options painted (ms)', 1], ['sync_ms', 'parent change handler (ms)', 1]]],
  ['context_menu_s1', [['load_ms', 'load event (ms)', 0], ['dcl_ms', 'domContentLoaded (ms)', 0], ['js_heap_mb', 'JS heap (MB)', 2], ['script_ms', 'script duration (ms)', 1],
    ['plugin_assets_kb', 'plugin asset bytes (KB)', 1], ['menu_ms', 'right click to menu shown (ms)', 1], ['wizard_ms', 'wizard opened (ms, no hover)', 1]]]];
  for (const [pk, metrics] of B) {
    const page = data.browser[pk];
    if (!page) continue;
    for (const [k, label, d] of metrics) {
      const r = row(`${pk} | ${label}`, page.metrics[k], d);
      if (r) out.push(r);
    }
  }
  out.push('');
}
process.stdout.write(out.join('\n') + '\n');
