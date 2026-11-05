const X = require('../lib-issue'); const { L } = X;
(async () => {
  const run = await X.begin('issue-new');
  const { sel, F, opts, val, pick } = X;
  const C = F(run, 'Country'), CI = F(run, 'City'), D = F(run, 'District'), LA = F(run, 'Languages'), PZ = F(run, 'Postal Zone'), LM = F(run, 'Landmark'), Z = F(run, 'Zone'), SI = F(run, 'Site');
  const eq = L.expectEqual;
  await X.S(run, 'login and open new issue form', 'form shows, Country offers 4 values, City empty with hint', async () => {
    await L.login(run, 'manager'); await L.goto(run, '/projects/walk/issues/new');
    eq((await opts(run, sel(C))).map((s) => s.trim()).filter(Boolean), ['Belgium', 'Netherlands', 'France', 'Germany'], 'Country');
    eq((await opts(run, sel(CI))).map((s) => s.trim()).filter(Boolean), [], 'City without parent');
    return 'City hint: ' + await X.hintFor(run, sel(CI));
  });
  await X.S(run, 'Country Belgium filters City and District, defaults filled', 'City: Brussels Ghent Antwerp (Brussels default); District Ixelles Schaerbeek Uccle (Ixelles default); Languages Dutch French German with Dutch+French', async () => {
    await pick(run, sel(C), 'Belgium');
    eq((await opts(run, sel(CI))).filter((s) => s.trim()), ['Brussels', 'Ghent', 'Antwerp'], 'City');
    eq(await val(run, sel(CI)), 'Brussels', 'City default');
    eq((await opts(run, sel(D))).filter((s) => s.trim()), ['Ixelles', 'Schaerbeek', 'Uccle'], 'District');
    eq(await val(run, sel(D)), 'Ixelles', 'District default');
    eq(await opts(run, sel(LA)), ['Dutch', 'French', 'German'], 'Languages');
    eq(await val(run, sel(LA)), ['Dutch', 'French'], 'Languages default');
    eq(await val(run, sel(PZ)), 'B-1000', 'Postal default');
  });
  await X.S(run, 'second level: City Ghent filters District', 'District: Gentbrugge, Mariakerke', async () => {
    await pick(run, sel(CI), 'Ghent');
    eq((await opts(run, sel(D))).filter((s) => s.trim()), ['Gentbrugge', 'Mariakerke'], 'District');
    await pick(run, sel(D), 'Mariakerke');
  });
  await X.S(run, 'change Country to Netherlands re-filters whole chain', 'City Amsterdam/Utrecht (default Amsterdam), District Centrum Zuid Noord, Languages Dutch Frisian', async () => {
    await pick(run, sel(C), 'Netherlands');
    eq((await opts(run, sel(CI))).filter((s) => s.trim()), ['Amsterdam', 'Utrecht'], 'City');
    eq(await val(run, sel(CI)), 'Amsterdam', 'City after parent change');
    eq((await opts(run, sel(D))).filter((s) => s.trim()), ['Centrum', 'Zuid', 'Noord'], 'District');
    eq(await opts(run, sel(LA)), ['Dutch', 'Frisian'], 'Languages');
    return `District now '${await val(run, sel(D))}', Languages '${(await val(run, sel(LA))).join(',')}'`;
  });
  await X.S(run, 'switch back to Belgium: last picked values return', 'City Ghent and District Mariakerke come back (README: value last picked for each parent value comes back)', async () => {
    await pick(run, sel(C), 'Belgium');
    eq(await val(run, sel(CI)), 'Ghent', 'City');
    eq(await val(run, sel(D)), 'Mariakerke', 'District');
  });
  await X.S(run, 'Country Germany: City has no values, hint, Landmark hidden, Postal Zone not required', 'City only blank with hint "No values are available for the selected Country."; Landmark hidden with label; Postal Zone not required', async () => {
    await pick(run, sel(C), 'Germany');
    eq((await opts(run, sel(CI))).filter((s) => s.trim()), [], 'City');
    const h = await X.hintFor(run, sel(CI));
    if (!/No values are available for the selected Country/.test(h)) throw new Error('hint: ' + h);
    if (await X.visible(run, sel(LM))) throw new Error('Landmark still visible');
    const lbl = await run.page.evaluate((id) => { const l = document.querySelector(`label[for=issue_custom_field_values_${id}]`); return l && l.offsetParent !== null; }, LM);
    if (lbl) throw new Error('Landmark label still visible');
    const req = await run.page.evaluate((id) => !!document.querySelector(`label[for=issue_custom_field_values_${id}] span.required`)?.offsetParent, PZ);
    return 'Landmark hidden; Postal Zone required marker visible: ' + req + '; hint: ' + h;
  });
  await X.S(run, 'Country Belgium again: Landmark visible with Atomium, Manneken-Pis', 'Landmark visible, 2 values', async () => {
    await pick(run, sel(C), 'Belgium');
    if (!(await X.visible(run, sel(LM)))) throw new Error('Landmark hidden');
    eq((await opts(run, sel(LM))).filter((s) => s.trim()), ['Atomium', 'Manneken-Pis'], 'Landmark');
  });
  await X.S(run, 'multi-select child follows parent', 'France: only French; Belgium: pick Dutch+German kept', async () => {
    await pick(run, sel(C), 'France');
    eq(await opts(run, sel(LA)), ['French'], 'Languages France');
    await pick(run, sel(C), 'Belgium');
    await X.pickMulti(run, sel(LA), ['Dutch', 'German']);
    eq(await val(run, sel(LA)), ['Dutch', 'German'], 'Languages picked');
  });
  await X.S(run, 'enumeration child: Zone North/South/East', 'North: North Dock, North Yard; South: South Dock, South Yard; East: none', async () => {
    await pick(run, sel(Z), 'North');
    const n = (await opts(run, sel(SI))).filter((s) => s.trim());
    await pick(run, sel(Z), 'South');
    const s = (await opts(run, sel(SI))).filter((x) => x.trim());
    await pick(run, sel(Z), 'East');
    const e = (await opts(run, sel(SI))).filter((x) => x.trim());
    eq([n, s, e], [['North Dock', 'North Yard'], ['South Dock', 'South Yard'], []], 'Site');
    const h = await X.hintFor(run, sel(SI));
    await pick(run, sel(Z), 'North'); await pick(run, sel(SI), 'North Yard');
    return 'East hint: ' + h;
  });
  await X.S(run, 'required child: blank Postal Zone is refused on save', 'error "Postal Zone cannot be blank"', async () => {
    await run.page.fill('#issue_subject', `E2E new required ${run.uniq}`);
    await run.page.selectOption(sel(PZ), { label: '--- Please select ---' });
    await X.submitIssue(run);
    const t = await X.errorText(run);
    if (!/Postal zone cannot be blank/i.test(t)) throw new Error('error text: ' + t);
    return t;
  });
  await X.S(run, 'after the error the form keeps parent choices and filtering', 'Country Belgium, City list filtered, Languages Dutch+German kept', async () => {
    eq(await val(run, sel(C)), 'Belgium', 'Country');
    eq((await opts(run, sel(CI))).filter((s) => s.trim()), ['Brussels', 'Ghent', 'Antwerp'], 'City options');
    eq(await val(run, sel(LA)), ['Dutch', 'German'], 'Languages');
    return `City '${await val(run, sel(CI))}', District '${await val(run, sel(D))}'`;
  });
  await X.S(run, 'forced disallowed City (Paris under Belgium) is refused on save', 'error "City is invalid"', async () => {
    await run.page.selectOption(sel(PZ), { label: 'B-9000' });
    await X.force(run, sel(CI), 'Paris');
    await X.submitIssue(run);
    const t = await X.errorText(run);
    if (!/City is invalid/.test(t)) throw new Error('error text: ' + t);
    return t;
  });
  await X.S(run, 'forced disallowed multi value and District refused', 'errors for Languages and District', async () => {
    await X.force(run, sel(LA), 'Frisian');
    await X.force(run, sel(D), 'Centrum');
    await X.submitIssue(run);
    const t = await X.errorText(run);
    if (!/Languages is invalid/.test(t) || !/District is invalid/.test(t)) throw new Error('error text: ' + t);
    return t;
  });
  await X.S(run, 'forced disallowed enumeration Site (South Dock under North) refused', 'error "Site is invalid"', async () => {
    const t0 = await run.page.evaluate((id) => [...document.querySelector(`#issue_custom_field_values_${id}`).options].map((o) => o.value + '=' + o.textContent).join(','), SI);
    await X.force(run, sel(SI), '6');
    await X.submitIssue(run);
    const t = await X.errorText(run);
    if (!/Site is invalid/.test(t)) throw new Error('error text: ' + t + ' | options ' + t0);
    return t;
  });
  let newId;
  await X.S(run, 'valid save: Belgium/Ghent/Mariakerke, Dutch+German, B-9000, North/North Yard', 'issue created, show page lists the values', async () => {
    await L.goto(run, '/projects/walk/issues/new');
    await run.page.fill('#issue_subject', `E2E new valid ${run.uniq}`);
    await pick(run, sel(C), 'Belgium'); await pick(run, sel(CI), 'Ghent'); await pick(run, sel(D), 'Mariakerke');
    await X.pickMulti(run, sel(LA), ['Dutch', 'German']); await pick(run, sel(PZ), 'B-9000');
    await pick(run, sel(Z), 'North'); await pick(run, sel(SI), 'North Yard');
    await X.submitIssue(run);
    newId = X.issueIdFromUrl(run.page.url());
    if (!newId) throw new Error('not created: ' + (await X.errorText(run)));
    const cf = await X.issueCf(run, newId);
    eq([cf.Country, cf.City, cf.District, cf.Languages, cf['Postal Zone'], cf.Zone, cf.Site], ['Belgium', 'Ghent', 'Mariakerke', ['Dutch', 'German'], 'B-9000', '1', '5'], 'stored values');
    const txt = await X.content(run);
    for (const w of ['Ghent', 'Mariakerke', 'Dutch', 'German', 'B-9000', 'North Yard']) if (!txt.includes(w)) throw new Error('show page lacks ' + w + ' :: ' + txt.slice(0, 400));
    return `issue #${newId}, flash: ${await X.flashText(run)}`;
  });
  await X.S(run, 'two-level chain with Germany (no City) saves without City', 'issue saved with no City/District/Postal Zone', async () => {
    await L.goto(run, '/projects/walk/issues/new');
    await run.page.fill('#issue_subject', `E2E new germany ${run.uniq}`);
    await pick(run, sel(C), 'Germany');
    await X.submitIssue(run);
    const id = X.issueIdFromUrl(run.page.url());
    if (!id) throw new Error('not created: ' + (await X.errorText(run)));
    const cf = await X.issueCf(run, id);
    return `issue #${id} City='${cf.City}' Postal='${cf['Postal Zone']}'`;
  });
  await X.S(run, 'tracker change refresh keeps the dependent values', 'switching tracker to Feature (form refresh) keeps Belgium/City choice', async () => {
    await L.goto(run, '/projects/walk/issues/new');
    await pick(run, sel(C), 'Belgium'); await pick(run, sel(CI), 'Antwerp');
    await run.page.selectOption('#issue_tracker_id', { label: 'Feature' });
    await run.page.waitForTimeout(6000);
    eq(await val(run, sel(C)), 'Belgium', 'Country after refresh');
    eq(await val(run, sel(CI)), 'Antwerp', 'City after refresh');
    eq((await opts(run, sel(CI))).filter((s) => s.trim()), ['Brussels', 'Ghent', 'Antwerp'], 'City options after refresh');
  });
  await X.end(run);
})().catch((e) => { console.error(e); process.exit(1); });
