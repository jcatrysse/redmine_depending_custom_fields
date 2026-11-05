#!/usr/bin/env node
'use strict';
/*
 * Checks that main and branch show the same dependency mapping on the issue form of the migrated data (upgrade path check):
 *  - the stored settings (custom_fields.format_store, possible_values) are byte-identical in both databases,
 *  - in Chromium, on the new issue form, every parent value of Country (6), plus Zone (enumeration) and Assembly (a sample of 8)
 *    offers exactly the allowed child options, on both variants; the issue edit form of the stored issue shows the stored child.
 *   node verify_mapping.js --version 51|61      exit code 1 when anything differs; writes results/mapping_check_<ver>.json
 */
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');
const { Client } = require('./lib/client');
const S = require('./lib/servers');

const argv = process.argv.slice(2);
const arg = (k, d) => { const i = argv.indexOf(`--${k}`); return i >= 0 ? argv[i + 1] : d; };
const VER = arg('version', '51');
const OUTDIR = path.resolve(arg('out', path.join(S.P, 'results')));
const ids = S.paths.ids(VER);
const F = ids.fields; const V = ids.values;
const NAMES = { main: `m${VER}`, branch: `p${VER}` };
const report = { version: VER, db: {}, form: {}, ok: true };

(async () => {
  fs.mkdirSync(OUTDIR, { recursive: true });
  // 1. stored settings
  const q = 'SELECT string_agg(id || \':\' || md5(coalesce(format_store,\'\') || coalesce(possible_values,\'\') || coalesce(default_value,\'\')), \',\' ORDER BY id) FROM custom_fields';
  report.db = { main: S.psql(`dcf_perf_m${VER}`, q), branch: S.psql(`dcf_perf_p${VER}`, q) };
  report.db_equal = report.db.main === report.db.branch;
  const enumQ = 'SELECT md5(string_agg(id || name || custom_field_id, \',\' ORDER BY id)) FROM custom_field_enumerations';
  report.enum_equal = S.psql(`dcf_perf_m${VER}`, enumQ) === S.psql(`dcf_perf_p${VER}`, enumQ);
  // 2. forms in the browser
  for (const v of ['main', 'branch']) S.start(NAMES[v]);
  const browser = await chromium.launch();
  try {
    for (const v of ['main', 'branch']) {
      const port = S.PORTS[NAMES[v]];
      const c = await new Client(port).login(ids.users.member.login, ids.users.member.password);
      const ctx = await browser.newContext();
      await ctx.addCookies([{ name: '_redmine_session', value: c.cookies._redmine_session, domain: '127.0.0.1', path: '/' }]);
      const res = { checked: 0, bad: [] };
      const check = async (page, label, parentId, childId, value, allowed) => {
        const got = await page.evaluate(({ parentId, childId, value }) => {
          const p = document.querySelector(`#issue_custom_field_values_${parentId}`);
          const c2 = document.querySelector(`#issue_custom_field_values_${childId}`);
          p.value = value; p.dispatchEvent(new Event('change', { bubbles: true }));
          return Array.from(c2.options).filter((o) => o.value && !o.hidden && !o.disabled && o.style.display !== 'none').map((o) => o.value);
        }, { parentId, childId, value });
        res.checked++;
        if (got.length !== allowed.length || !allowed.every((a) => got.includes(a))) res.bad.push({ label, value, got: got.slice(0, 5), expected: allowed.slice(0, 5) });
      };
      const s1 = await ctx.newPage();
      await s1.goto(`http://127.0.0.1:${port}/projects/perf-a/issues/new?issue[tracker_id]=1`, { waitUntil: 'load' });
      for (const country of V.countries) {
        await check(s1, 'Country->City', F.Country.id, F.City.id, country, V.cities[country]);
        await check(s1, 'Country->Languages', F.Country.id, F.Languages.id, country, V.langs[country]);
        for (const city of V.cities[country].slice(0, 2)) await check(s1, 'City->District', F.City.id, F.District.id, city, V.districts[city]);
      }
      for (const z of V.zone_ids) await check(s1, 'Zone->Site (enumeration)', F.Zone.id, F.Site.id, z, V.sites_by_zone[z]);
      await s1.close();
      const s2 = await ctx.newPage();
      await s2.goto(`http://127.0.0.1:${port}/projects/perf-large/issues/new?issue[tracker_id]=2`, { waitUntil: 'load' });
      for (const n of [1, 2, 77, 250, 499, 500, 123, 321]) {
        const a = `A${String(n).padStart(3, '0')}`;
        await check(s2, 'Assembly->Part', F.Assembly.id, F.Part.id, a, Array.from({ length: 50 }, (_, k) => `${a}-P${String(k + 1).padStart(2, '0')}`));
      }
      await s2.close();
      // stored issue: the edit form shows the stored child selected
      const e = await ctx.newPage();
      await e.goto(`http://127.0.0.1:${port}/issues/${ids.issues.s1_show}/edit`, { waitUntil: 'load' });
      const stored = await e.evaluate((cid) => { const s = document.querySelector(`#issue_custom_field_values_${cid}`); return s.value; }, F.City.id);
      res.stored_city = stored;
      if (stored !== V.s1_show.city) res.bad.push({ label: 'stored City', got: stored, expected: V.s1_show.city });
      await e.close(); await ctx.close(); c.close();
      report.form[v] = res;
    }
  } finally {
    await browser.close().catch(() => {});
    for (const v of ['main', 'branch']) S.stop(NAMES[v]);
  }
  report.ok = report.db_equal && report.enum_equal && Object.values(report.form).every((r) => r.bad.length === 0);
  fs.writeFileSync(path.join(OUTDIR, `mapping_check_${VER}.json`), JSON.stringify(report, null, 1));
  console.log(`mapping check ${VER}: db equal ${report.db_equal}, enumerations equal ${report.enum_equal}, main ${report.form.main.checked} checks / ${report.form.main.bad.length} bad, branch ${report.form.branch.checked} checks / ${report.form.branch.bad.length} bad -> ${report.ok ? 'OK' : 'MISMATCH'}`);
  process.exit(report.ok ? 0 : 1);
})().catch((e) => { console.error(e); for (const v of ['main', 'branch']) S.stop(NAMES[v]); process.exit(2); });
