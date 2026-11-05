const X = require('../lib-issue'); const { L } = X;
(async () => {
  const run = await X.begin('issue-edit');
  const { sel, F, opts, val, pick } = X; const eq = L.expectEqual;
  const C = F(run, 'Country'), CI = F(run, 'City'), D = F(run, 'District'), LA = F(run, 'Languages'), PZ = F(run, 'Postal Zone'), Z = F(run, 'Zone'), SI = F(run, 'Site');
  await X.S(run, 'login as manager, open edit form of legacy issue #31 (Belgium, City Paris)', 'stored City Paris stays selected and marked with a hint, other Belgium cities offered', async () => {
    await L.login(run, 'manager'); await L.goto(run, '/issues/31/edit');
    eq(await val(run, sel(CI)), 'Paris', 'City kept');
    const o = (await opts(run, sel(CI))).filter((s) => s.trim());
    const marked = await run.page.evaluate((id) => { const s = document.querySelector('#issue_custom_field_values_' + id); const o = s.selectedOptions[0]; return [o.className, o.textContent, o.dataset ? JSON.stringify(o.dataset) : ''].join(' | '); }, CI);
    return `options ${o.join(',')}; selected option: ${marked}; hint: ${await X.hintFor(run, sel(CI))}`;
  });
  await X.S(run, 'save a note only: kept stored value accepted', 'saved, journal note shown, City still Paris', async () => {
    await run.page.fill('#issue_notes', `note ${run.uniq}`);
    await X.submitIssue(run);
    const t = await X.errorText(run); if (t) throw new Error('refused: ' + t);
    const txt = await run.page.locator('#history').innerText();
    if (!txt.includes(`note ${run.uniq}`)) throw new Error('note not in history');
    eq((await X.issueCf(run, 31)).City, 'Paris', 'City stored');
    return 'history: ' + txt.replace(/\s+/g, ' ').slice(-200);
  });
  await X.S(run, 'parent change with the stored mismatching City forced is refused', 'Country Netherlands + City Paris => "City is invalid"; issue unchanged', async () => {
    await L.goto(run, '/issues/31/edit');
    await pick(run, sel(C), 'Netherlands'); await pick(run, sel(PZ), 'NL-1011');
    await X.force(run, sel(CI), 'Paris');
    await X.submitIssue(run);
    const t = await X.errorText(run);
    if (!/City is invalid/.test(t)) throw new Error('error text: ' + t);
    const cf = await X.issueCf(run, 31);
    eq([cf.Country, cf.City], ['Belgium', 'Paris'], 'issue unchanged');
    return t;
  });
  await X.S(run, 'after the refusal the form shows the entered parent and a valid City list', 'Country Netherlands, City options Amsterdam Utrecht', async () => {
    eq(await val(run, sel(C)), 'Netherlands', 'Country');
    eq((await opts(run, sel(CI))).filter((s) => s.trim()), ['Amsterdam', 'Utrecht'], 'City options');
    return 'City now: ' + await val(run, sel(CI));
  });
  await X.S(run, 'forced disallowed value on a kept parent (Country unchanged) is refused too if it is new', 'City Utrecht under Belgium refused', async () => {
    await L.goto(run, '/issues/31/edit');
    await X.force(run, sel(CI), 'Utrecht');
    await X.submitIssue(run);
    const t = await X.errorText(run);
    if (!/City is invalid/.test(t)) throw new Error('error text: ' + t);
    return t;
  });
  const id = await (async () => X.createIssue(run, `E2E edit target ${run.uniq}`, { Country: 'Belgium', City: 'Ghent', District: 'Gentbrugge', Languages: ['Dutch'], 'Postal Zone': 'B-9000', Zone: '1', Site: '4' }))();
  await X.S(run, `open the issue page of a fresh issue #${id} and click Edit`, 'inline edit form opens with Ghent/Gentbrugge', async () => {
    await L.goto(run, `/issues/${id}`);
    await run.page.click('#content a.icon-edit');
    await run.page.waitForSelector(sel(CI), { state: 'visible' });
    eq([await val(run, sel(CI)), await val(run, sel(D))], ['Ghent', 'Gentbrugge'], 'stored');
  });
  await X.S(run, 'change parent: Country Netherlands, Zone South, note', 'saved; journal lists Country, City, Postal Zone, Languages, Zone, Site changes with readable names', async () => {
    await pick(run, sel(C), 'Netherlands');
    const dflt = [await val(run, sel(CI)), await val(run, sel(D)), (await val(run, sel(LA))).join(','), await val(run, sel(PZ))];
    await pick(run, sel(CI), 'Utrecht'); await pick(run, sel(D), 'Overvecht'); await pick(run, sel(PZ), 'NL-3511');
    await X.pickMulti(run, sel(LA), ['Frisian']);
    await pick(run, sel(Z), 'South'); await pick(run, sel(SI), 'South Yard');
    await run.page.fill('#issue_notes', `parent change ${run.uniq}`);
    await X.submitIssue(run);
    const t = await X.errorText(run); if (t) throw new Error('refused: ' + t);
    const cf = await X.issueCf(run, id);
    eq([cf.Country, cf.City, cf.District, cf.Languages, cf['Postal Zone'], cf.Zone, cf.Site], ['Netherlands', 'Utrecht', 'Overvecht', ['Frisian'], 'NL-3511', '2', '7'], 'stored');
    const h = (await run.page.locator('#history').innerText()).replace(/\s+/g, ' ');
    return `defaults after parent change: ${dflt.join(' / ')}; history: ${h}`;
  });
  await X.S(run, 'journal details show names, not raw ids', 'journal for Zone/Site mentions South / South Yard, not 2 / 7', async () => {
    const h = (await run.page.locator('#history').allInnerTexts()).join(' || ').replace(/\s+/g, ' ');
    for (const w of ['Country', 'City', 'Overvecht', 'Frisian', 'NL-3511']) if (!h.includes(w)) throw new Error(`journal lacks ${w}: ${h}`);
    if (!/Site changed from North Dock to South Yard|Site.*South Yard/.test(h)) throw new Error('Site change not readable: ' + h);
    return h;
  });
  await X.S(run, 'a tracker change on the edit form keeps dependent selections', 'Feature tracker refresh keeps Country/City', async () => {
    await L.goto(run, `/issues/${id}/edit`);
    const before = [await val(run, sel(C)), await val(run, sel(CI))];
    await run.page.selectOption('#issue_tracker_id', { label: 'Feature' });
    await run.page.waitForTimeout(6000);
    eq([await val(run, sel(C)), await val(run, sel(CI))], before, 'after refresh');
    return 'values ' + before.join('/');
  });
  await X.S(run, 'clear the parent: Country blank clears City and District, required Postal Zone', 'Country blank leaves City empty; Postal Zone not required without a parent value', async () => {
    await L.goto(run, `/issues/${id}/edit`);
    await run.page.selectOption(sel(C), { label: ' ' });
    await run.page.waitForTimeout(600);
    const st = [await val(run, sel(CI)), await val(run, sel(D)), (await val(run, sel(LA))).join(','), (await opts(run, sel(CI))).filter((s) => s.trim()).join(',')];
    await X.submitIssue(run);
    const t = await X.errorText(run);
    return `form after clearing: ${st.join(' / ')}; save error: '${t}'; stored: ${JSON.stringify(await X.issueCf(run, id))}`;
  });
  await X.end(run);
})().catch((e) => { console.error(e); process.exit(1); });
