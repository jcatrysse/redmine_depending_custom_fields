// Proof that the seed works: manager opens Walk's new issue form, picks Belgium, City offers exactly 3 values.
const L = require('../lib');
(async () => {
  const ver = process.argv[2];
  const run = await L.start({ ver, scenario: 'seed-check' });
  const ids = run.ids;
  const cid = ids.fields['Country'].id, cityId = ids.fields['City'].id;
  await L.step(run, 'login as manager', async () => { await L.login(run, 'manager'); });
  await L.step(run, 'new issue form, Belgium gives exactly Brussels, Ghent, Antwerp', async () => {
    await L.goto(run, '/projects/walk/issues/new');
    await run.page.selectOption(L.cfSel(cid), 'Belgium');
    await run.page.waitForTimeout(500);
    const opts = (await L.selectOptions(run, L.cfSel(cityId))).filter((t) => t !== '');
    L.expectEqual(opts.sort(), ['Antwerp', 'Brussels', 'Ghent'], 'City options');
    await L.screenshot(run, 'country-belgium');
    return opts;
  });
  await L.step(run, 'Secret Code visible to manager, hidden from developer', async () => {
    const sid = ids.fields['Secret Code'].id;
    if ((await run.page.locator(L.cfSel(sid)).count()) !== 1) throw new Error('manager does not see Secret Code');
    await L.login(run, 'developer');
    await L.goto(run, '/projects/walk/issues/new');
    await L.assertNotInHtml(run, ['Secret Code', 'Zulu-7731', 'Whiskey-2208', 'Clearance', 'Alpha-Level', 'Bravo-Level']);
  });
  await L.step(run, 'manager reaches project pages and time entry form', async () => {
    await L.login(run, 'manager');
    const res = {};
    for (const k of ['cfc_index', 'cfc_audit', 'cfc_values_city', 'cfc_deps_city', 'cfc_deps_part', 'cfc_values_shared_child', 'cfc_deps_shared_child', 'time_entry_new_walk']) {
      const r = await L.goto(run, ids.urls[k]);
      res[k] = r.status();
      if (r.status() !== 200) throw new Error(`${k} -> ${r.status()}`);
    }
    await L.goto(run, ids.urls.cfc_deps_shared_child);
    await L.screenshot(run, 'shared-deps-page');
    return res;
  });
  await L.step(run, 'developer has no custom field configuration tab', async () => {
    await L.login(run, 'developer');
    const r = await L.goto(run, ids.urls.cfc_index);
    if (r.status() === 200) throw new Error('developer can open the configuration page');
    return r.status();
  });
  const s = await L.finish(run);
  require('fs').copyFileSync(require('path').join(run.outDir, 'seed-check', '01-country-belgium.png'), require('path').join(run.outDir, 'seed-check.png'));
  process.exit(s.failed || s.errors.length || s.responses5xx.length ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(2); });
