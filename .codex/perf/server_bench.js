#!/usr/bin/env node
'use strict';
/*
 * Server harness: one puma process per variant (1 thread, production), sequential requests, a logged-in admin and a logged-in
 * non-admin member session per variant. Per request: wall time, view/ActiveRecord ms and allocations of the Rails "Completed"
 * line, SQL query count, process CPU ms, response bytes (and gzip bytes) and status. The probe initializer
 * (lib/zz_perf_probe.rb, one file for both variants) publishes the per-request numbers as X-Perf-* response headers.
 *
 *   node server_bench.js --version 51|61 [--rounds 30] [--warmup 5] [--mixed 300] [--only regex] [--out results/raw]
 *
 * Phases: boot RSS, login, functional check of the update pages, warm-up rounds, memory checkpoint, measured rounds (main and
 * branch interleaved per page, first variant alternates per round), mixed run of N requests, memory checkpoint, heavy pages.
 * Heavy pages (marked heavy in lib/pages.js: the admin editor and the project pages of the 25,000 value field) are probed once
 * per variant with a timeout; a variant that needs longer than HEAVY_SLOW_MS gets HEAVY_ROUNDS rounds, one that exceeds
 * HEAVY_TIMEOUT_S is recorded as timeout (and its server restarted), the other variant still gets all rounds.
 */
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const { Client } = require('./lib/client');
const { pages } = require('./lib/pages');
const S = require('./lib/servers');

const argv = process.argv.slice(2);
const arg = (k, d) => { const i = argv.indexOf(`--${k}`); return i >= 0 ? argv[i + 1] : d; };
const VER = arg('version', '51');
const N = parseInt(arg('rounds', '30'), 10);
const WARM = parseInt(arg('warmup', '5'), 10);
const MIXED = parseInt(arg('mixed', '300'), 10);
const ONLY = arg('only', null);
const OUT = path.resolve(arg('out', path.join(S.P, 'results', 'raw')));
const HEAVY_TIMEOUT_MS = parseFloat(process.env.HEAVY_TIMEOUT_S || '45') * 1000;
const HEAVY_SLOW_MS = parseFloat(process.env.HEAVY_SLOW_MS || '8000');
const HEAVY_ROUNDS = parseInt(process.env.HEAVY_ROUNDS || '3', 10);
const NORMAL_TIMEOUT_MS = 90000;
// pages marked secondary (admin copies of the S2 pages, baseline, S2 bulk edit and settings) get min(N, SEC_ROUNDS) rounds
const SEC_ROUNDS = parseInt(process.env.SEC_ROUNDS || '8', 10);
const SEC_WARM = 1;
// heavy-flagged pages that are fast (the branch) get min(N, HEAVY_NORMAL_ROUNDS) rounds
const HEAVY_NORMAL_ROUNDS = parseInt(process.env.HEAVY_NORMAL_ROUNDS || '15', 10);
const log = (...a) => console.error(`[server_bench ${VER} ${new Date().toISOString().slice(11, 19)}]`, ...a);

const ids = S.paths.ids(VER);
const ALL = pages(ids).filter((p) => !ONLY || new RegExp(ONLY).test(p.key));
const NAMES = { main: `m${VER}`, branch: `p${VER}` };
const DBS = { main: `dcf_perf_m${VER}`, branch: `dcf_perf_p${VER}` };
const VARIANTS = ['main', 'branch'];

const clients = {}; // clients[variant][user]
const csrf = {}; // csrf[variant][page.key]
const up = {}; // started variants

function rngFactory(seed) { let s = seed >>> 0; return () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296; }; }

async function login(variant) {
  const port = S.PORTS[NAMES[variant]];
  clients[variant] = {
    admin: await new Client(port).login(ids.users.admin.login, ids.users.admin.password),
    member: await new Client(port).login(ids.users.member.login, ids.users.member.password)
  };
  csrf[variant] = {};
  for (const p of ALL.filter((x) => x.csrfFrom)) {
    const r = await clients[variant][p.user].get(p.csrfFrom);
    csrf[variant][p.key] = Client.token(r.body.toString());
  }
}

function toSample(r, page, extra = {}) {
  const h = r.headers;
  const num = (k) => (h[k] === undefined ? null : parseFloat(h[k]));
  const body = r.body.toString('latin1');
  let ok = r.status === (page.expect || 200);
  if (ok && page.marker && !body.includes(page.marker)) ok = false;
  if (ok && page.rows) ok = (body.match(/<tr id="issue-\d+"/g) || []).length === page.rows;
  return {
    ms: r.ms, status: r.status, ok, bytes: r.bytes, gzip_bytes: r.status === 200 && r.bytes < 8e6 ? zlib.gzipSync(r.body, { level: 6 }).length : null,
    sql: num('x-perf-sql'), view_ms: num('x-perf-view'), db_ms: num('x-perf-db'), alloc: num('x-perf-alloc'),
    alloc_total: num('x-perf-alloc-total'), heap_live: num('x-perf-heap-live'), cpu_ms: num('x-perf-cpu'), server_ms: num('x-perf-duration'), ...extra
  };
}

// One request of a page by a variant. PATCH pages: the timed PATCH, then an untimed reset PATCH.
async function hit(variant, page, timeoutMs = NORMAL_TIMEOUT_MS) {
  const c = clients[variant][page.user];
  let r;
  if (page.method === 'PATCH') {
    r = await c.request('PATCH', page.path, { form: [['authenticity_token', csrf[variant][page.key]], ...page.form], timeoutMs });
    if (r.timeout) return { timeout: true, ms: r.ms };
    const s = toSample(r, page);
    const back = await c.request('PATCH', page.path, { form: [['authenticity_token', csrf[variant][page.key]], ...page.reset], timeoutMs });
    if (back.status !== 302) s.ok = false;
    return s;
  }
  r = await c.get(page.path, { timeoutMs });
  if (r.timeout) return { timeout: true, ms: r.ms };
  return toSample(r, page);
}

const samples = {}; // samples[variant][page.key] = []
const notes = {};
function record(variant, page, s, phase) {
  ((samples[variant] ||= {})[page.key] ||= []).push({ phase, ...s });
}

// Updates change data: check that the PATCH really stores the new values and that the reset restores them.
async function verifyUpdates(variant) {
  const out = {};
  for (const p of ALL.filter((x) => x.method === 'PATCH')) {
    const c = clients[variant][p.user];
    const id = p.path.split('/').pop();
    // the last single-value field of the form is the child (S1: District, S2: Part); the edit form marks the stored value selected
    const last = (f) => f.filter(([k]) => !k.endsWith('[]')).map(([, v]) => v).slice(-1)[0];
    const sel = (v) => `selected="selected" value="${v}"`;
    const r = await c.request('PATCH', p.path, { form: [['authenticity_token', csrf[variant][p.key]], ...p.form] });
    const e1 = (await c.get(`/issues/${id}/edit`)).body.toString();
    const changed = r.status === 302 && e1.includes(sel(last(p.form))) && !e1.includes(sel(last(p.reset)));
    const back = await c.request('PATCH', p.path, { form: [['authenticity_token', csrf[variant][p.key]], ...p.reset] });
    const e2 = (await c.get(`/issues/${id}/edit`)).body.toString();
    out[p.key] = { patch_status: r.status, changed, reset_status: back.status, restored: e2.includes(sel(last(p.reset))) && !e2.includes(sel(last(p.form))) };
  }
  return out;
}

function memCheckpoint(label) {
  const out = {};
  for (const v of Object.keys(up)) {
    const name = NAMES[v];
    const tail = S.probeTail(name, 5);
    const heap = tail.map((t) => t.heap_live_slots).filter((x) => x).sort((a, b) => a - b);
    let hwm = null;
    try { hwm = parseInt(/VmHWM:\s+(\d+) kB/.exec(fs.readFileSync(`/proc/${S.pid(name)}/status`, 'utf8'))[1], 10); } catch (e) { /* gone */ }
    out[v] = { rss_kb: S.rssKb(name), hwm_kb: hwm, heap_live_slots: heap.length ? heap[heap.length >> 1] : null };
  }
  return { label, ...out };
}

const restarted = new Set();
async function restart(variant) {
  restarted.add(variant);
  S.start(NAMES[variant]);
  await login(variant);
}

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const t0 = Date.now();
  const meta = { kind: 'server', version: VER, rounds: N, warmup: WARM, mixed: MIXED, started: new Date().toISOString(), load_at_start: S.loadavg1(), notes: {} };
  const ruby = (() => { try { return require('child_process').execSync(`ls ${S.E}/${NAMES.main}/.ruby-version 2>/dev/null; true`).toString().trim(); } catch (e) { return ''; } })();
  meta.ruby_hint = ruby;

  // clean update targets (journals left by earlier runs)
  const targets = [ids.issues.s1_update, ids.issues.s2_update].join(',');
  for (const v of VARIANTS) {
    try {
      S.psql(DBS[v], `DELETE FROM journal_details WHERE journal_id IN (SELECT id FROM journals WHERE journalized_type='Issue' AND journalized_id IN (${targets})); DELETE FROM journals WHERE journalized_type='Issue' AND journalized_id IN (${targets});`);
    } catch (e) { log('journal cleanup failed', e.message); }
  }

  const boot = {};
  for (const v of VARIANTS) {
    try {
      const out = S.start(NAMES[v]);
      up[v] = true;
      boot[v] = { rss_kb: S.rssKb(NAMES[v]), start: out };
      log(out, `rss ${boot[v].rss_kb} kB`);
    } catch (e) {
      meta.notes[`boot_failed_${v}`] = String(e.stdout || e.message).slice(-1500);
      log(`BOOT FAILED for ${v}`);
    }
  }
  if (!up.branch) { log('branch did not boot, aborting'); S.stop(NAMES.main); process.exit(2); }
  const active = () => VARIANTS.filter((v) => up[v]);
  try {
    for (const v of active()) await login(v);
    meta.verify = {};
    for (const v of active()) { meta.verify[v] = await verifyUpdates(v); log('update check', v, JSON.stringify(meta.verify[v])); }

    const normal = ALL.filter((p) => !p.heavy);
    const memory = [{ label: 'after_boot', ...Object.fromEntries(active().map((v) => [v, { rss_kb: boot[v].rss_kb }])) }];
    const order = (r) => (r % 2 === 0 ? active() : active().reverse());

    // warm-up
    for (let r = 0; r < WARM; r++) {
      for (const p of normal.filter((x) => !x.secondary || r < SEC_WARM)) for (const v of order(r)) { const s = await hit(v, p); if (s.timeout) throw new Error(`timeout in warm-up: ${v} ${p.key}`); record(v, p, s, 'warmup'); }
      log(`warm-up ${r + 1}/${WARM}`);
    }
    memory.push(memCheckpoint('after_warmup'));

    // measured rounds
    for (let r = 0; r < N; r++) {
      for (const p of normal.filter((x) => !x.secondary || r < SEC_ROUNDS)) for (const v of order(r)) { const s = await hit(v, p); if (s.timeout) throw new Error(`timeout: ${v} ${p.key}`); record(v, p, s, 'measured'); }
      if ((r + 1) % 5 === 0 || r + 1 === N) log(`round ${r + 1}/${N} (${((Date.now() - t0) / 60000).toFixed(1)} min)`);
    }
    memory.push(memCheckpoint('after_rounds'));

    // mixed run, same sequence for both variants
    const rnd = rngFactory(424242);
    const weighted = normal.flatMap((p) => Array(p.mix || 1).fill(p));
    const seq = Array.from({ length: MIXED }, () => weighted[Math.floor(rnd() * weighted.length)]);
    const mixed = Object.fromEntries(active().map((v) => [v, { n: 0, ms: 0, alloc_total: 0, sql: 0, errors: 0 }]));
    // both variants at the same time (two servers, two client loops): the mixed run feeds the memory checkpoint only
    await Promise.all(active().map(async (v) => {
      for (const p of seq) {
        const s = await hit(v, p);
        if (s.timeout) throw new Error(`timeout in mixed run: ${v} ${p.key}`);
        const m = mixed[v]; m.n++; m.ms += s.ms; m.alloc_total += s.alloc_total || 0; m.sql += s.sql || 0; if (!s.ok) m.errors++;
      }
    }));
    memory.push({ ...memCheckpoint('after_mixed'), mixed });
    log('mixed run done', JSON.stringify(mixed));

    // heavy pages
    const modes = {};
    for (const p of ALL.filter((x) => x.heavy)) {
      modes[p.key] = {};
      for (const v of active()) {
        const s = await hit(v, p, HEAVY_TIMEOUT_MS);
        if (s.timeout) {
          modes[p.key][v] = { mode: 'timeout', timeout_s: HEAVY_TIMEOUT_MS / 1000 };
          log(`heavy ${p.key} ${v}: timeout after ${HEAVY_TIMEOUT_MS / 1000}s, restarting server`);
          await restart(v);
        } else if (s.status === 404) {
          modes[p.key][v] = { mode: 'na' };
        } else {
          const slow = s.ms > HEAVY_SLOW_MS;
          record(v, p, s, slow ? 'measured' : 'probe'); // a slow first request counts as the first heavy round
          modes[p.key][v] = { mode: slow ? 'heavy' : 'normal', first_ms: s.ms };
          log(`heavy ${p.key} ${v}: first request ${s.ms.toFixed(0)} ms -> ${modes[p.key][v].mode}`);
        }
      }
      // rounds: normal variants get warm-up and N rounds, heavy variants HEAVY_ROUNDS, interleaved where possible
      const live = active().filter((v) => ['normal', 'heavy'].includes(modes[p.key][v].mode));
      const need = Object.fromEntries(live.map((v) => [v, modes[p.key][v].mode === 'normal' ? Math.min(N, HEAVY_NORMAL_ROUNDS) : HEAVY_ROUNDS - 1]));
      for (const v of live) if (modes[p.key][v].mode === 'normal') for (let i = 0; i < 2; i++) await hit(v, p, HEAVY_TIMEOUT_MS);
      const total = Math.max(0, ...Object.values(need));
      for (let r = 0; r < total; r++) {
        for (const v of (r % 2 === 0 ? live : [...live].reverse())) {
          if (r >= need[v]) continue;
          const s = await hit(v, p, HEAVY_TIMEOUT_MS);
          if (s.timeout) { modes[p.key][v] = { mode: 'timeout', timeout_s: HEAVY_TIMEOUT_MS / 1000, after_rounds: r }; need[v] = 0; await restart(v); continue; }
          record(v, p, s, 'measured');
        }
      }
    }
    memory.push({ ...memCheckpoint('after_heavy'), restarted: [...restarted] });

    // raw files per page and variant
    const stamp = new Date().toISOString();
    for (const p of ALL) {
      for (const v of VARIANTS) {
        const arr = (samples[v] && samples[v][p.key]) || [];
        const mode = p.heavy ? (modes[p.key] && modes[p.key][v]) || { mode: 'not_run' } : { mode: 'normal' };
        if (!up[v]) { var raw = { kind: 'server', version: VER, variant: v, page: p.key, user: p.user, mode: { mode: 'not_available', reason: 'variant did not boot' }, samples: [], time: stamp }; }
        else {
          var raw = { kind: 'server', version: VER, variant: v, page: p.key, user: p.user, path: p.path.slice(0, 300), mode, samples: arr, time: stamp };
          if (arr.length && arr.every((s) => s.status === 404)) raw.mode = { mode: 'na', reason: 'HTTP 404' };
        }
        fs.writeFileSync(path.join(OUT, `server_${VER}_${v}_${p.key}.json`), JSON.stringify(raw));
      }
    }
    meta.boot = boot; meta.memory = memory; meta.heavy_modes = modes;
    meta.finished = new Date().toISOString(); meta.minutes = (Date.now() - t0) / 60000; meta.load_at_end = S.loadavg1();
    meta.config = { heavy_timeout_s: HEAVY_TIMEOUT_MS / 1000, heavy_slow_ms: HEAVY_SLOW_MS, heavy_rounds: HEAVY_ROUNDS };
    fs.writeFileSync(path.join(OUT, `server_${VER}_meta.json`), JSON.stringify(meta, null, 1));
    log(`done in ${meta.minutes.toFixed(1)} min`);
  } finally {
    for (const v of VARIANTS) S.stop(NAMES[v]);
  }
})().catch((e) => { console.error(e); for (const v of VARIANTS) S.stop(NAMES[v]); process.exit(1); });
