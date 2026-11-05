const X = require('../lib-issue'); const { L } = X;
(async () => {
  const run = await X.begin('issue-list');
  const { F } = X; const eq = L.expectEqual;
  const ids = ['Country', 'City', 'District', 'Languages', 'Postal Zone', 'Landmark', 'Zone', 'Site'].map((n) => F(run, n));
  const cols = ['subject', ...ids.map((i) => 'cf_' + i)];
  const colQ = cols.map((c) => `c[]=${c}`).join('&');
  const rows = () => run.page.$$eval('table.list.issues tbody tr.issue', (trs) => trs.map((tr) => {
    const o = { id: +tr.id.replace('issue-', '') };
    tr.querySelectorAll('td').forEach((td) => { const c = [...td.classList].find((x) => /^cf_\d+$/.test(x) || x === 'subject'); if (c) o[c] = td.innerText.trim(); });
    return o;
  }));
  await X.S(run, 'login, list with depending fields as columns', 'columns for Country, City, District, Languages, Postal Zone, Landmark, Zone, Site; no raw ids in Zone/Site cells', async () => {
    await L.login(run, 'manager');
    await L.goto(run, `/projects/walk/issues?set_filter=1&f[]=status_id&op[status_id]=*&${colQ}&per_page=100&sort=id`);
    const heads = await run.page.$$eval('table.list.issues thead th', (t) => t.map((x) => x.innerText.trim()).filter(Boolean));
    const r = await rows();
    const issue2 = r.find((x) => x.id === 2);
    const issue1 = r.find((x) => x.id === 1);
    if (!/Brussels/.test(issue1['cf_' + ids[1]])) throw new Error('issue 1 City cell: ' + JSON.stringify(issue1));
    const zone = issue2['cf_' + ids[6]], site = issue2['cf_' + ids[7]];
    if (!(zone === 'South' && site === 'South Dock')) throw new Error(`Zone/Site cells show '${zone}'/'${site}' for issue 2`);
    return `heads: ${heads.join(', ')}; issue1: ${JSON.stringify(issue1)}; issue2: ${JSON.stringify(issue2)}`;
  });
  await X.S(run, 'filter City = Brussels', 'every row has City Brussels; count equals the rows with Brussels in the unfiltered list', async () => {
    await L.goto(run, `/projects/walk/issues?set_filter=1&f[]=status_id&op[status_id]=*&${colQ}&per_page=100&sort=id`);
    const all = await rows();
    const expected = all.filter((x) => x['cf_' + ids[1]] === 'Brussels').map((x) => x.id);
    await L.goto(run, `/projects/walk/issues?set_filter=1&f[]=status_id&op[status_id]=*&f[]=cf_${ids[1]}&op[cf_${ids[1]}]==&v[cf_${ids[1]}][]=Brussels&${colQ}&per_page=100&sort=id`);
    const got = (await rows()).map((x) => x.id);
    eq(got, expected, 'issue ids');
    return `${got.length} rows: ${got.join(',')}`;
  });
  await X.S(run, 'filter through the UI: add City filter, choose Ghent, apply', 'filter select offers the depending fields; result rows all Ghent', async () => {
    await L.goto(run, `/projects/walk/issues?set_filter=1&f[]=status_id&op[status_id]=*&${colQ}&per_page=100`);
    const names = await run.page.$$eval('#add_filter_select option', (o) => o.map((x) => x.textContent.trim()));
    for (const n of ['Country', 'City', 'District', 'Languages', 'Postal Zone', 'Landmark', 'Zone', 'Site']) if (!names.includes(n)) throw new Error('filter list lacks ' + n + ': ' + names.join('|'));
    await run.page.selectOption('#add_filter_select', { label: 'City' });
    await run.page.waitForSelector(`#tr_cf_${ids[1]}`);
    const valOpts = await run.page.$$eval(`#values_cf_${ids[1]}_1 option`, (o) => o.map((x) => x.textContent.trim()));
    await run.page.selectOption(`#values_cf_${ids[1]}_1`, { label: 'Ghent' });
    await Promise.all([run.page.waitForLoadState('load'), run.page.click('#query_form a.icon-checked, #query_form .buttons a.icon-checked')]);
    const r = await rows();
    if (!r.length || !r.every((x) => x['cf_' + ids[1]] === 'Ghent')) throw new Error('rows: ' + JSON.stringify(r.slice(0, 5)));
    return `filter value options: ${valOpts.join(',')}; ${r.length} Ghent rows`;
  });
  await X.S(run, 'filter Languages (multi) = French and Site (enumeration) = South Dock', 'rows hold the values', async () => {
    const q = `f[]=cf_${ids[3]}&op[cf_${ids[3]}]==&v[cf_${ids[3]}][]=French`;
    await L.goto(run, `/projects/walk/issues?set_filter=1&f[]=status_id&op[status_id]=*&${q}&${colQ}&per_page=100`);
    const r1 = await rows(); if (!r1.length || !r1.every((x) => /French/.test(x['cf_' + ids[3]]))) throw new Error('Languages rows: ' + JSON.stringify(r1.slice(0, 4)));
    const q2 = `f[]=cf_${ids[7]}&op[cf_${ids[7]}]==&v[cf_${ids[7]}][]=6`;
    await L.goto(run, `/projects/walk/issues?set_filter=1&f[]=status_id&op[status_id]=*&${q2}&${colQ}&per_page=100`);
    const r2 = await rows(); if (!r2.length || !r2.every((x) => x['cf_' + ids[7]] === 'South Dock')) throw new Error('Site rows: ' + JSON.stringify(r2.slice(0, 4)));
    const opt = await run.page.$$eval(`#values_cf_${ids[7]}_1 option`, (o) => o.map((x) => x.textContent.trim() + '=' + x.value));
    return `Languages rows ${r1.length}, Site rows ${r2.length}; Site filter options ${opt.join(',')}`;
  });
  await X.S(run, 'sort by City and group by Country', 'list renders groups, sort works, no error', async () => {
    await L.goto(run, `/projects/walk/issues?set_filter=1&f[]=status_id&op[status_id]=*&${colQ}&sort=cf_${ids[1]}&group_by=cf_${ids[0]}&per_page=100`);
    const groups = await run.page.$$eval('tr.group td.name, tr.group span.name', (e) => e.map((x) => x.innerText.trim().replace(/\s+/g, ' ')));
    if (!groups.length) throw new Error('no groups; flash: ' + await X.flashText(run));
    return 'groups: ' + groups.join(' | ');
  });
  await X.S(run, 'filter on a stored mismatching value (City Paris) shows legacy issues 31', 'Seed legacy mismatch 1 listed for City = Paris', async () => {
    await L.goto(run, `/projects/walk/issues?set_filter=1&f[]=status_id&op[status_id]=*&f[]=cf_${ids[1]}&op[cf_${ids[1]}]==&v[cf_${ids[1]}][]=Paris&${colQ}&per_page=100`);
    const r = (await rows()).map((x) => x.id); if (!r.includes(31)) throw new Error('rows ' + r);
    return r.join(',');
  });
  await X.S(run, 'issue show page of #2 (Feature) and #31 (legacy)', 'values listed; show page uses names for Zone/Site; legacy City shown', async () => {
    await L.goto(run, '/issues/1');
    let t = await run.page.locator('div.issue .attributes').innerText();
    for (const w of ['Belgium', 'Brussels']) if (!t.includes(w)) throw new Error('#1 lacks ' + w + ' :: ' + t.replace(/\s+/g, ' '));
    await L.goto(run, '/issues/3');
    t = (await run.page.locator('div.issue .attributes').innerText()).replace(/\s+/g, ' ');
    const hasIdLeak = /Site:?\s*\d+\b/.test(t) || /Zone:?\s*\d+\b/.test(t);
    if (hasIdLeak) throw new Error('raw enumeration id on show page: ' + t);
    await L.goto(run, '/issues/31');
    const t31 = (await run.page.locator('div.issue .attributes').innerText()).replace(/\s+/g, ' ');
    if (!t31.includes('Paris')) throw new Error('#31 lacks Paris: ' + t31);
    return '#3 attrs: ' + t;
  });
  await X.S(run, 'saved query with depending columns and filter', 'query saves and reopens with columns', async () => {
    await L.goto(run, `/projects/walk/issues?set_filter=1&f[]=status_id&op[status_id]=*&f[]=cf_${ids[0]}&op[cf_${ids[0]}]==&v[cf_${ids[0]}][]=Belgium&${colQ}`);
    await L.goto(run, `/projects/walk/queries/new?set_filter=1&f[]=cf_${ids[0]}&op[cf_${ids[0]}]==&v[cf_${ids[0]}][]=Belgium&${colQ}`);
    await run.page.fill('#query_name', `E2E query ${run.uniq}`);
    await Promise.all([run.page.waitForLoadState('load'), run.page.click('#query-form input[type=submit]')]);
    const t = await X.flashText(run);
    const n = await run.page.locator('table.list.issues tbody tr.issue').count();
    return `flash '${t}', rows ${n}, url ${run.page.url()}`;
  });
  await X.end(run);
})().catch((e) => { console.error(e); process.exit(1); });
