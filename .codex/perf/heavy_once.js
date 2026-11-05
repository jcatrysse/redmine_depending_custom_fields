#!/usr/bin/env node
'use strict';
// One request of a heavy page with a long timeout, to learn how long main really needs (the benches stop at HEAVY_TIMEOUT_S).
//   node heavy_once.js --version 51 --variant main|branch --page admin_cf_part [--timeout 600]
const { Client } = require('./lib/client');
const { pages } = require('./lib/pages');
const S = require('./lib/servers');
const argv = process.argv.slice(2);
const arg = (k, d) => { const i = argv.indexOf(`--${k}`); return i >= 0 ? argv[i + 1] : d; };
const VER = arg('version', '51'); const variant = arg('variant', 'main'); const key = arg('page', 'admin_cf_part');
const timeout = parseFloat(arg('timeout', '600')) * 1000;
const ids = S.paths.ids(VER);
const name = (variant === 'main' ? 'm' : 'p') + VER;
(async () => {
  S.start(name);
  try {
    const page = pages(ids).find((p) => p.key === key);
    const c = await new Client(S.PORTS[name]).login(ids.users[page.user].login, ids.users[page.user].password);
    const r = await c.get(page.path, { timeoutMs: timeout });
    console.log(JSON.stringify({ version: VER, variant, page: key, timeout: !!r.timeout, status: r.status, seconds: +(r.ms / 1000).toFixed(1), bytes: r.bytes, rss_kb: S.rssKb(name),
      view_ms: r.headers['x-perf-view'], alloc: r.headers['x-perf-alloc'] }));
  } finally { S.stop(name); }
})().catch((e) => { console.error(e); S.stop(name); process.exit(1); });
