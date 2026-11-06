#!/usr/bin/env node
'use strict';
/*
 * Reads results/raw/*.json (server_*, browser_*, *_meta.json) and writes results/summary.json and results/summary.md:
 * per version, kind, page and metric: median, p90, min (and n, max) for main and branch, delta (branch - main) and ratio
 * (branch / main), both on the median. Cells without data say why (n/a, timeout, not run). When the raw files hold the variant
 * `none` (Redmine without the plugin, see build_none.sh) every metric also has delta_none / ratio_none (branch - none, branch / none),
 * main_delta_none (main - none), and the markdown tables get the columns none, branch minus none (ms) and branch minus none (percent).
 *
 *   node summarize.js [--dir results] [--raw raw] [--out results]
 */
const fs = require('fs');
const path = require('path');
const { summarize } = require('./lib/stats');

const argv = process.argv.slice(2);
const arg = (k, d) => { const i = argv.indexOf(`--${k}`); return i >= 0 ? argv[i + 1] : d; };
const DIR = path.resolve(arg('dir', path.join(require('./lib/paths').P, 'results')));
const RAW = path.join(DIR, arg('raw', 'raw'));
const OUT = path.resolve(arg('out', DIR));

const SKIP = new Set(['ok', 'phase', 'status', 'round', 'error']);
const VERS = { 51: 'Redmine 5.1', 61: 'Redmine 6.1' };
const files = fs.existsSync(RAW) ? fs.readdirSync(RAW).filter((f) => f.endsWith('.json')) : [];
const read = (f) => JSON.parse(fs.readFileSync(path.join(RAW, f), 'utf8'));

const summary = { generated: new Date().toISOString(), versions: {} };
const metas = {};
for (const f of files) {
  if (f.endsWith('_meta.json')) { const m = read(f); (metas[m.kind] ||= {})[m.version] = m; continue; }
  const r = read(f);
  const v = ((summary.versions[r.version] ||= { server: {}, browser: {} })[r.kind] ||= {});
  const page = (v[r.page] ||= { mode: {}, metrics: {}, failed: {}, n: {} });
  page.mode[r.variant] = r.mode || { mode: 'normal' };
  const measured = (r.samples || []).filter((s) => !s.phase || s.phase === 'measured' || s.phase === 'profile');
  page.n[r.variant] = measured.filter((s) => s.phase !== 'profile').length;
  page.failed[r.variant] = measured.filter((s) => s.ok === false || s.error).length;
  const keys = new Set();
  measured.filter((s) => !s.timeout).forEach((s) => Object.keys(s).forEach((k) => { if (!SKIP.has(k) && typeof s[k] === 'number') keys.add(k); }));
  for (const k of keys) {
    (page.metrics[k] ||= {})[r.variant] = summarize(measured.filter((s) => s.ok !== false && !s.error).map((s) => s[k]));
  }
}
for (const ver of Object.values(summary.versions)) {
  for (const kind of ['server', 'browser']) {
    for (const page of Object.values(ver[kind] || {})) {
      for (const m of Object.values(page.metrics)) {
        const a = m.main; const b = m.branch; const n = m.none;
        if (n && b && n.median !== null && b.median !== null) {
          m.delta_none = b.median - n.median;
          m.ratio_none = n.median === 0 ? null : b.median / n.median;
          if (a && a.median !== null) m.main_delta_none = a.median - n.median;
        }
        if (a && b && a.median !== null && b.median !== null) {
          m.delta = b.median - a.median;
          m.ratio = a.median === 0 ? null : b.median / a.median;
          m.ratio_p90 = a.p90 ? b.p90 / a.p90 : null;
        }
      }
    }
  }
}
for (const kind of Object.keys(metas)) for (const v of Object.keys(metas[kind])) {
  ((summary.versions[v] ||= { server: {}, browser: {} }).meta ||= {})[kind] = metas[kind][v];
}
fs.mkdirSync(OUT, { recursive: true });
fs.writeFileSync(path.join(OUT, 'summary.json'), JSON.stringify(summary, null, 1));

// ------------------------------------------------------------------ markdown
const f1 = (x, d = 1) => (x === null || x === undefined ? '-' : Math.abs(x) >= 1000 ? Math.round(x).toLocaleString('en-US') : Number(x.toFixed(d)).toString());
const cell = (s, d) => (s ? `${f1(s.median, d)} / ${f1(s.p90, d)} / ${f1(s.min, d)}` : '-');
const modeText = (m) => {
  if (!m) return 'not run';
  if (m.mode === 'timeout') return `timeout > ${m.timeout_s} s${m.after_rounds !== undefined ? ` (after ${m.after_rounds} rounds)` : ''}`;
  if (m.mode === 'na') return 'n/a';
  if (m.mode === 'not_available') return `not available (${m.reason})`;
  if (m.mode === 'heavy') return `heavy (${m.first_ms ? (m.first_ms / 1000).toFixed(0) + ' s first' : ''})`;
  return '';
};
const SERVER_METRICS = [['ms', 'Wall time (ms)', 0], ['cpu_ms', 'Process CPU time (ms)', 0], ['view_ms', 'View time (ms), Rails Completed line', 0],
  ['db_ms', 'ActiveRecord time (ms), Rails Completed line', 0], ['alloc', 'Allocations (Rails Completed line)', 0], ['sql', 'SQL queries (without SCHEMA and CACHE)', 0],
  ['bytes', 'Response bytes', 0], ['gzip_bytes', 'Response bytes gzipped', 0]];

const HAS_NONE = Object.values(summary.versions).some((v) => ['server', 'browser'].some((k) => Object.values(v[k] || {}).some((p) => p.n.none !== undefined)));
let md = `# Performance summary: main (0.0.15) versus branch${HAS_NONE ? ' versus Redmine without the plugin (none)' : ''}\n\nGenerated ${summary.generated}. Cells: median / p90 / min. Delta = branch median minus main median, ratio = branch median / main median (below 1 means the branch is faster or smaller).${HAS_NONE ? ' Branch - none is the branch median minus the median of Redmine without the plugin (ms or the unit of the table, and percent of none).' : ''}\n\n`;

function table(first, metricKey, label, digits, pagesObj) {
  const NV = HAS_NONE ? ['none', 'main', 'branch'] : ['main', 'branch'];
  let t = `#### ${label}\n\n| page | ${HAS_NONE ? 'none (med / p90 / min) | ' : ''}main (med / p90 / min) | branch (med / p90 / min) | delta | ratio | ${HAS_NONE ? 'branch - none | branch - none (%) | ' : ''}n ${NV.join('/')} | note |\n|---|${HAS_NONE ? '---|---|---|' : ''}---|---|---|---|---|---|\n`;
  for (const [pk, p] of Object.entries(pagesObj)) {
    const m = p.metrics[metricKey];
    const note = NV.map((v) => { const t2 = modeText(p.mode[v]); return t2 ? `${v}: ${t2}` : ''; }).filter(Boolean).join('; ') +
      NV.map((v) => (p.failed[v] ? ` ${v}: ${p.failed[v]} failed` : '')).join('');
    if (!m && !(first && note)) continue;
    const noneCols = HAS_NONE ? `${cell(m && m.none, digits)} | ` : '';
    const dn = HAS_NONE ? `${m && m.delta_none !== undefined ? f1(m.delta_none, digits) : '-'} | ${m && m.ratio_none !== undefined && m.ratio_none !== null ? f1((m.ratio_none - 1) * 100, 1) : '-'} | ` : '';
    t += `| ${pk} | ${noneCols}${cell(m && m.main, digits)} | ${cell(m && m.branch, digits)} | ${m && m.delta !== undefined ? f1(m.delta, digits) : '-'} | ${m && m.ratio !== undefined && m.ratio !== null ? m.ratio.toFixed(2) : '-'} | ${dn}${NV.map((v) => p.n[v] ?? '-').join('/')} | ${note} |\n`;
  }
  return t + '\n';
}

for (const [ver, data] of Object.entries(summary.versions)) {
  md += `## ${VERS[ver] || ver}\n\n`;
  const sm = data.meta && data.meta.server;
  if (sm) {
    md += `Server bench: ${sm.rounds} measured rounds, ${sm.warmup} warm-up rounds, mixed run ${sm.mixed}, ${sm.minutes ? sm.minutes.toFixed(1) : '?'} min, load average at start ${sm.load_at_start}.\n\n`;
    if (sm.notes && Object.keys(sm.notes).length) md += `Notes: ${JSON.stringify(sm.notes)}\n\n`;
    if (sm.memory) {
      const hasN = !!(sm.variants && sm.variants.includes('none'));
      md += `### Memory (puma worker, 1 thread)\n\n| checkpoint | ${hasN ? 'none RSS (MB) | ' : ''}main RSS (MB) | branch RSS (MB) | ${hasN ? 'none peak RSS (MB) | ' : ''}main peak RSS (MB) | branch peak RSS (MB) | ${hasN ? 'none heap_live_slots | ' : ''}main heap_live_slots | branch heap_live_slots |\n|---|${hasN ? '---|---|---|' : ''}---|---|---|---|---|---|\n`;
      const mb = (k) => (k ? (k / 1024).toFixed(0) : '-');
      for (const c of sm.memory) {
        const star = (v) => ((c.restarted || []).includes(v) ? ' (restarted)' : '');
        const nR = hasN ? `${mb(c.none && c.none.rss_kb)}${star('none')} | ` : '';
        const nP = hasN ? `${mb(c.none && c.none.hwm_kb)} | ` : '';
        const nH = hasN ? `${f1(c.none && c.none.heap_live_slots, 0)} | ` : '';
        md += `| ${c.label} | ${nR}${mb(c.main && c.main.rss_kb)}${star('main')} | ${mb(c.branch && c.branch.rss_kb)}${star('branch')} | ${nP}${mb(c.main && c.main.hwm_kb)} | ${mb(c.branch && c.branch.hwm_kb)} | ${nH}${f1(c.main && c.main.heap_live_slots, 0)} | ${f1(c.branch && c.branch.heap_live_slots, 0)} |\n`;
        if (c.mixed && !hasN) md += `| mixed run totals (${c.mixed.branch ? c.mixed.branch.n : '?'} requests) | time ${c.mixed.main ? (c.mixed.main.ms / 1000).toFixed(0) : '-'} s, objects ${c.mixed.main ? f1(c.mixed.main.alloc_total, 0) : '-'}, SQL ${c.mixed.main ? c.mixed.main.sql : '-'} | time ${(c.mixed.branch.ms / 1000).toFixed(0)} s, objects ${f1(c.mixed.branch.alloc_total, 0)}, SQL ${c.mixed.branch.sql} | | | | |\n`;
      }
      md += '\n';
    }
    if (sm.verify) md += `Update check (PATCH stores the new values, reset restores them): ${JSON.stringify(sm.verify)}\n\n`;
  }
  if (Object.keys(data.server).length) {
    md += `### Server, per request\n\n`;
    SERVER_METRICS.forEach(([k, label, d], i) => { md += table(i === 0, k, label, d, data.server); });
  }
  if (data.meta && data.meta.browser) {
    const bm = data.meta.browser;
    md += `### Browser (Chromium ${bm.chromium || ''})\n\n${bm.reps} measured repetitions per page and variant, ${bm.minutes ? bm.minutes.toFixed(1) : '?'} min.\n\n`;
    if (bm.notes && Object.keys(bm.notes).length) md += `Notes: ${JSON.stringify(bm.notes)}\n\n`;
  }
  if (Object.keys(data.browser).length) {
    const keys = new Set();
    Object.values(data.browser).forEach((p) => Object.keys(p.metrics).forEach((k) => keys.add(k)));
    const labels = { dcl_ms: 'domContentLoaded (ms)', load_ms: 'load event (ms)', ttfb_ms: 'time to first byte (ms)', js_heap_mb: 'JSHeapUsedSize (MB)',
      script_ms: 'ScriptDuration (ms)', task_ms: 'TaskDuration (ms)', layout_ms: 'LayoutDuration (ms)', style_ms: 'RecalcStyleDuration (ms)',
      plugin_script_ms: 'Plugin script time, CPU profile, inclusive (ms)', plugin_assets_kb: 'Plugin asset bytes loaded (KB)', plugin_assets_ms: 'Plugin asset load time (ms)',
      nodes: 'DOM nodes', sync_ms: 'Interaction: change handler returns (ms)', paint_ms: 'Interaction: options shown and painted (ms)',
      menu_ms: 'Context menu shown (ms)', wizard_ms: 'Wizard opened (ms)' };
    let firstB = true;
    for (const k of ['dcl_ms', 'load_ms', 'ttfb_ms', 'js_heap_mb', 'script_ms', 'task_ms', 'layout_ms', 'style_ms', 'nodes', 'plugin_script_ms', 'plugin_assets_kb', 'plugin_assets_ms', 'menu_ms', 'wizard_ms', 'sync_ms', 'paint_ms', 'js_errors']) {
      if (!keys.has(k)) continue;
      md += table(firstB, k, labels[k] || k, k.endsWith('_mb') || k.endsWith('_kb') ? 1 : 0, data.browser);
      firstB = false;
    }
  }
}
fs.writeFileSync(path.join(OUT, 'summary.md'), md);
console.log(`wrote ${path.join(OUT, 'summary.json')} and summary.md`);
