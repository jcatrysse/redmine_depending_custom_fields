const X = require('../lib-issue'); const { L } = X;
(async () => {
  const run = await X.begin('bulk-edit');
  const { sel, F, opts, val, pick } = X; const eq = L.expectEqual;
  const C = F(run, 'Country'), CI = F(run, 'City'), D = F(run, 'District'), LA = F(run, 'Languages'), PZ = F(run, 'Postal Zone'), Z = F(run, 'Zone'), SI = F(run, 'Site');
  let A, B, Cc;
  const LS = `#issue_custom_field_values_${LA}_`;
  const open = async () => { await L.goto(run, `/issues/bulk_edit?ids[]=${A}&ids[]=${B}&ids[]=${Cc}`); };
  const submit = async () => { await Promise.all([run.page.waitForLoadState('load'), run.page.click('#bulk_edit_form input[type=submit]')]); await run.page.waitForTimeout(300); };
  const snap = async () => { const o = {}; for (const [k, i] of Object.entries({ A, B, C: Cc })) { const c = await X.issueCf(run, i); o[k] = [c.Country, c.City, c.District, (c.Languages || []).join('+'), c['Postal Zone'], c.Zone, c.Site].join('/'); } return o; };
  await X.S(run, 'create three controlled issues by REST and log in', 'three issues exist', async () => {
    const base = { Country: 'Belgium', 'Postal Zone': 'B-1000', Zone: '1', Site: '4' };
    A = await X.createIssue(run, `E2E bulk A ${run.uniq}`, { ...base, City: 'Brussels', District: 'Ixelles', Languages: ['Dutch', 'French'] });
    B = await X.createIssue(run, `E2E bulk B ${run.uniq}`, { ...base, City: 'Ghent', District: 'Mariakerke', Languages: ['Dutch'] });
    Cc = await X.createIssue(run, `E2E bulk C ${run.uniq}`, { ...base, City: 'Antwerp', Languages: ['German'], 'Postal Zone': 'B-2000' });
    await L.login(run, 'manager');
    return JSON.stringify(await snap());
  });
  await X.S(run, 'bulk edit form: parent on (No change) => children offer all values, hint, no (No change) on multi', 'Country (No change); City lists all 7 cities plus (No change) and (none); Languages has no (No change)', async () => {
    await open();
    const ci = await opts(run, sel(CI));
    const cv = await val(run, sel(C));
    if (cv !== '(No change)') throw new Error('Country shows ' + cv);
    for (const w of ['(No change)', 'none', 'Brussels', 'Ghent', 'Antwerp', 'Amsterdam', 'Utrecht', 'Paris', 'Lyon']) if (!ci.includes(w)) throw new Error('City lacks ' + w + ': ' + ci.join('|'));
    const la = await opts(run, LS);
    return `City options: ${ci.join(', ')}; Languages: ${la.join(', ')} (selected ${(await val(run, LS)).join(',') || 'none'}); City hint '${await X.hintFor(run, sel(CI))}'`;
  });
  await X.S(run, 'save changing only Priority: untouched multi-select Languages is not cleared', 'all three issues keep Languages and all other values', async () => {
    const before = await snap();
    await run.page.selectOption('#issue_priority_id', { label: 'High' });
    await submit();
    const t = await X.errorText(run); const fl = await X.flashText(run);
    const after = await snap();
    eq(after, before, 'values after priority-only bulk edit');
    return `flash '${fl}' error '${t}'`;
  });
  await X.S(run, 'choose parent Netherlands: children filtered, defaults preselected with hint', 'City Amsterdam/Utrecht + (No change) + (none), default Amsterdam hint; Languages Dutch Frisian', async () => {
    await open();
    await pick(run, sel(C), 'Netherlands');
    const ci = await opts(run, sel(CI)); const la = await opts(run, LS);
    eq(ci.filter((x) => !/No change|none/.test(x)).sort(), ['Amsterdam', 'Utrecht'], 'City options');
    eq(la.filter((x) => x !== 'none'), ['Dutch', 'Frisian'], 'Languages');
    return `City selected '${await val(run, sel(CI))}', hint '${await X.hintFor(run, sel(CI))}'; Postal Zone '${await val(run, sel(PZ))}' options ${(await opts(run, sel(PZ))).join(',')}; District '${await val(run, sel(D))}' options ${(await opts(run, sel(D))).join(',')}`;
  });
  await X.S(run, 'save Country Netherlands with City and Languages left on (No change)', 'issues keeping a value Netherlands does not allow are refused and listed; others saved; stored data of refused issues unchanged', async () => {
    await pick(run, sel(CI), '(No change)');
    await pick(run, sel(PZ), '(No change)');
    const before = await snap();
    await submit();
    const t = await X.errorText(run); const fl = await X.flashText(run);
    const after = await snap();
    return `flash '${fl}' error '${t}'\nbefore ${JSON.stringify(before)}\nafter  ${JSON.stringify(after)}`;
  });
  await X.S(run, 'save a consistent change: Netherlands, Utrecht, Frisian, NL-3511 for all', 'all issues saved with the values', async () => {
    await open();
    await pick(run, sel(C), 'Netherlands'); await pick(run, sel(CI), 'Utrecht'); await pick(run, sel(PZ), 'NL-3511');
    await X.pickMulti(run, LS, ['Frisian']);
    await pick(run, sel(D), 'none');
    await submit();
    const t = await X.errorText(run); const fl = await X.flashText(run);
    const after = await snap();
    for (const k of Object.keys(after)) if (!after[k].startsWith('Netherlands/Utrecht//Frisian/NL-3511')) throw new Error(`issue ${k}: ${after[k]} | flash '${fl}' error '${t}'`);
    return `flash '${fl}'; ${JSON.stringify(after)}`;
  });
  await X.S(run, 'parent to Germany: City cleared automatically with hint, required Postal Zone stays (No change)', 'City (none) with "Cleared because..." hint; Postal Zone (No change) with "No values are available..." hint', async () => {
    await open();
    await pick(run, sel(C), 'Germany');
    const ci = await val(run, sel(CI)); const ch = await X.hintFor(run, sel(CI));
    const pz = await val(run, sel(PZ)); const ph = await X.hintFor(run, sel(PZ));
    if (ci !== 'none') throw new Error(`City shows '${ci}' hint '${ch}'`);
    if (!/Cleared because/.test(ch)) throw new Error('City hint: ' + ch);
    if (pz !== '(No change)') throw new Error(`Postal Zone shows '${pz}'`);
    if (!/No values are available/.test(ph)) throw new Error('Postal hint: ' + ph);
    return `City hint '${ch}'; Postal hint '${ph}'; Languages options ${(await opts(run, LS)).join(',')}`;
  });
  await X.S(run, 'save Germany with required Postal Zone left on (No change)', 'issues are refused with "is invalid" because Postal Zone NL-3511 stays, listed above the form (README)', async () => {
    const before = await snap();
    await submit();
    const t = await X.errorText(run); const fl = await X.flashText(run);
    const after = await snap();
    return `flash '${fl}' error '${t}'\nbefore ${JSON.stringify(before)}\nafter  ${JSON.stringify(after)}`;
  });
  await X.S(run, 'enumeration parent in bulk edit: Zone East clears Site; Zone North presets default', 'East: Site (none) hint cleared; North: Site North Dock hint default', async () => {
    await open();
    await pick(run, sel(Z), 'East');
    const e = [await val(run, sel(SI)), await X.hintFor(run, sel(SI))];
    await pick(run, sel(Z), 'North');
    const n = [await val(run, sel(SI)), await X.hintFor(run, sel(SI)), (await opts(run, sel(SI))).join(',')];
    if (e[0] !== 'none') throw new Error('East: ' + e.join(' / '));
    if (n[0] !== 'North Dock') throw new Error('North: ' + n.join(' / '));
    return `East ${e.join(' / ')}; North ${n.join(' / ')}`;
  });
  await X.S(run, 'save Zone North with default Site', 'all three issues Zone North, Site North Dock; other values untouched', async () => {
    const before = await snap();
    await submit();
    const t = await X.errorText(run);
    const after = await snap();
    for (const k of Object.keys(after)) if (!/\/1\/4$/.test(after[k])) throw new Error(`${k}: ${after[k]} error '${t}'`);
    return `error '${t}'`;
  });
  await X.S(run, 'bulk edit with a forced disallowed new value (Country unchanged, City Paris)', 'refused: City is invalid for the listed issues', async () => {
    await open();
    await X.force(run, sel(CI), 'Paris');
    const before = await snap();
    await submit();
    const t = await X.errorText(run); const fl = await X.flashText(run);
    const after = await snap();
    eq(after, before, 'unchanged');
    if (!/City is invalid/.test(t + fl)) throw new Error(`flash '${fl}' error '${t}'`);
    return `flash '${fl}' error '${t}'`;
  });
  await X.end(run);
})().catch((e) => { console.error(e); process.exit(1); });
