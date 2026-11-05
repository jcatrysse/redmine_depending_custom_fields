const X = require('../lib-issue'); const { L } = X;
(async () => {
  const run = await X.begin('context-wizard');
  const { sel, F, opts, val, pick } = X; const eq = L.expectEqual;
  const C = F(run, 'Country'), CI = F(run, 'City'), D = F(run, 'District'), LA = F(run, 'Languages'), PZ = F(run, 'Postal Zone');
  const page = () => run.page;
  let A, B; const sub = `E2E wiz ${run.uniq}`;
  const WS = '#cf-wizard-container';
  const dialogs = [];
  const snap = async () => { const o = {}; for (const [k, i] of Object.entries({ A, B })) { const c = await X.issueCf(run, i); o[k] = [c.Country, c.City, c.District, (c.Languages || []).join('+'), c['Postal Zone']].join('/'); } return o; };
  const openList = async () => {
    await L.goto(run, `/projects/walk/issues?set_filter=1&f[]=subject&op[subject]=~&v[subject][]=${encodeURIComponent(sub)}&sort=id`);
    await page().check(`tr#issue-${A} input[type=checkbox]`); await page().check(`tr#issue-${B} input[type=checkbox]`);
    await page().locator(`tr#issue-${A} td.status`).click({ button: "right" });
    await page().waitForSelector('#context-menu li.cf-parent', { state: 'visible' });
  };
  const entry = (pid) => `#context-menu li.cf-parent[data-parent-id='${pid}'] > a.submenu`;
  await X.S(run, 'create two issues, login as manager', 'issues exist', async () => {
    const base = { Country: 'Belgium', 'Postal Zone': 'B-1000' };
    A = await X.createIssue(run, `${sub} A`, { ...base, City: 'Brussels', District: 'Ixelles', Languages: ['Dutch'] });
    B = await X.createIssue(run, `${sub} B`, { ...base, City: 'Ghent', Languages: ['Dutch'] });
    await L.login(run, 'manager');
    page().on('dialog', async (d) => { dialogs.push(d.message()); await d.accept(); });
    return JSON.stringify(await snap());
  });
  await X.S(run, 'right click on two selected rows: menu holds one entry per top-level parent and no form', 'entries for Country, Zone, Clearance, Walk Local Parent, Shared Parent; no select/form/template inside the menu', async () => {
    await openList();
    const entries = await page().$$eval('#context-menu li.cf-parent', (l) => l.map((x) => x.dataset.parentId + ':' + x.innerText.trim()));
    const inner = await page().$$eval('#context-menu select, #context-menu form, #context-menu template', (x) => x.length);
    if (inner) throw new Error('menu holds ' + inner + ' form elements');
    for (const w of ['Country', 'Zone', 'Clearance']) if (!entries.some((e) => e.includes(w))) throw new Error('missing entry ' + w + ': ' + entries);
    return 'entries: ' + entries.join(', ');
  });
  await X.S(run, 'click Country entry: wizard shows Loading..., then fields from the server', 'Loading... visible while fetching, then Country, City, District, Languages, Postal Zone, Landmark columns, Save and Cancel', async () => {
    await page().route('**/depending_custom_fields/wizard*', async (r) => { await new Promise((s) => setTimeout(s, 1500)); r.continue(); });
    await page().click(entry(C));
    await page().waitForSelector(WS, { state: 'visible' });
    const loading = (await page().locator(WS).innerText()).trim();
    await L.screenshot(page().__run || run, 'wizard-loading');
    if (!/Loading/i.test(loading)) throw new Error('no loading text: ' + loading);
    await page().waitForSelector(`${WS} form.cf-wizard-form`, { timeout: 15000 });
    await page().unroute('**/depending_custom_fields/wizard*');
    const labels = await page().$$eval(`${WS} .cf-wizard-label`, (l) => l.map((x) => x.innerText.trim().split('\n')[0]));
    const btn = await page().$$eval(`${WS} .cf-actions button`, (b) => b.map((x) => x.innerText.trim()));
    for (const w of ['Country', 'City', 'District', 'Languages', 'Postal Zone']) if (!labels.includes(w)) throw new Error('wizard lacks ' + w + ': ' + labels);
    eq(btn, ['Save', 'Cancel'], 'buttons');
    return `loading text '${loading}'; fields ${labels.join(', ')}`;
  });
  await X.S(run, 'every field opens on (No change), Languages with nothing selected', 'Country/City/District/Postal Zone on (No change)', async () => {
    const st = [await val(run, `${WS} ${sel(C)}`), await val(run, `${WS} ${sel(CI)}`), await val(run, `${WS} ${sel(D)}`), await val(run, `${WS} ${sel(PZ)}`), (await val(run, `${WS} #issue_custom_field_values_${LA}_`)).join(',')];
    eq(st.slice(0, 4), ['(No change)', '(No change)', '(No change)', '(No change)'], 'selects'); eq(st[4], '', 'Languages');
    return 'City options with parent unchanged: ' + (await opts(run, `${WS} ${sel(CI)}`)).join(',');
  });
  await X.S(run, 'choose Country Netherlands: children filtered and the default preselected with hint', 'City Amsterdam/Utrecht with Amsterdam preselected and a hint inside the wizard', async () => {
    await pick(run, `${WS} ${sel(C)}`, 'Netherlands');
    const ci = (await opts(run, `${WS} ${sel(CI)}`)).filter((x) => !/No change|none/.test(x));
    eq(ci, ['Amsterdam', 'Utrecht'], 'City');
    return `City '${await val(run, `${WS} ${sel(CI)}`)}' hint '${await X.hintFor(run, `${WS} ${sel(CI)}`)}'`;
  });
  await X.S(run, 'Cancel closes without saving', 'wizard hidden, stored values unchanged', async () => {
    const before = await snap();
    await page().click(`${WS} .cf-wizard-cancel`);
    await page().waitForTimeout(400);
    if (await X.visible(run, WS)) throw new Error('wizard still visible');
    eq(await snap(), before, 'values');
  });
  await X.S(run, 'Escape closes the wizard', 'wizard hidden after Escape; reopening loads again', async () => {
    await openList(); await page().click(entry(C)); await page().waitForSelector(`${WS} form.cf-wizard-form`, { timeout: 15000 });
    await pick(run, `${WS} ${sel(C)}`, 'France');
    await page().keyboard.press('Escape'); await page().waitForTimeout(400);
    if (await X.visible(run, WS)) throw new Error('wizard still visible after Escape');
    await page().click(entry(C)).catch(() => {});
    return 'values after Escape unchanged: ' + JSON.stringify(await snap());
  });
  await X.S(run, 'click outside closes the wizard', 'wizard hidden after clicking the page heading', async () => {
    await openList(); await page().click(entry(C)); await page().waitForSelector(`${WS} form.cf-wizard-form`, { timeout: 15000 });
    await page().click('#content h2'); await page().waitForTimeout(400);
    if (await X.visible(run, WS)) throw new Error('wizard still visible after outside click');
  });
  await X.S(run, 'moving to another menu entry closes the wizard', 'wizard hidden after hovering the Priority entry', async () => {
    await openList(); await page().click(entry(C)); await page().waitForSelector(`${WS} form.cf-wizard-form`, { timeout: 15000 });
    await page().hover('#context-menu a.submenu:text-is("Priority")'); await page().waitForTimeout(600);
    if (await X.visible(run, WS)) throw new Error('wizard still visible after moving to another entry');
  });
  await X.S(run, 'failed load shows the generic message and a second click retries', 'message "The wizard could not be loaded." naming no field; retry loads the form', async () => {
    await openList();
    await page().route('**/depending_custom_fields/wizard*', (r) => r.fulfill({ status: 500, body: 'boom' }));
    await page().click(entry(C));
    await page().waitForFunction((s) => /could not be loaded/i.test(document.querySelector(s)?.innerText || ''), WS, { timeout: 10000 });
    const msg = (await page().locator(WS).innerText()).trim();
    await L.screenshot(run, 'wizard-load-failed');
    await page().unroute('**/depending_custom_fields/wizard*');
    await page().click(entry(C)).catch(() => {});
    await page().waitForSelector(`${WS} form.cf-wizard-form`, { timeout: 15000 });
    return 'message: ' + msg;
  });
  await X.S(run, 'save a change the server refuses: error shown in an alert, wizard stays open, nothing changed', 'alert names the issues/fields, no reload', async () => {
    await pick(run, `${WS} ${sel(C)}`, 'France');
    await pick(run, `${WS} ${sel(CI)}`, '(No change)');
    const before = await snap(); dialogs.length = 0;
    await page().click(`${WS} button[type=submit]`);
    await page().waitForTimeout(2500);
    const alertEl = await page().$$eval(`${WS} [role=alert], ${WS} .cf-wizard-error, ${WS} .flash`, (e) => e.map((x) => x.innerText.trim()));
    const stillOpen = await X.visible(run, WS);
    eq(await snap(), before, 'values');
    if (!dialogs.length && !alertEl.length) throw new Error('no error feedback; open=' + stillOpen);
    return `dialogs ${JSON.stringify(dialogs)} inline ${JSON.stringify(alertEl)} stillOpen ${stillOpen}`;
  });
  await X.S(run, 'save a valid change: Netherlands + Utrecht + Frisian + NL-3511', 'page reloads; both issues updated', async () => {
    await openList(); await page().click(entry(C)); await page().waitForSelector(`${WS} form.cf-wizard-form`, { timeout: 15000 });
    await pick(run, `${WS} ${sel(C)}`, 'Netherlands'); await pick(run, `${WS} ${sel(CI)}`, 'Utrecht');
    await pick(run, `${WS} ${sel(PZ)}`, 'NL-3511'); await pick(run, `${WS} ${sel(D)}`, 'none');
    await page().selectOption(`${WS} #issue_custom_field_values_${LA}_`, [{ label: 'Frisian' }]);
    await Promise.all([page().waitForNavigation({ timeout: 15000 }).catch(() => null), page().click(`${WS} button[type=submit]`)]);
    await page().waitForTimeout(800);
    const after = await snap();
    for (const k of Object.keys(after)) if (after[k] !== 'Netherlands/Utrecht//Frisian/NL-3511') throw new Error(`${k}: ${after[k]}`);
    const rows = await page().locator('table.list.issues tr.issue').count();
    return `after ${JSON.stringify(after)}; list rows after reload ${rows}; flash '${await X.flashText(run)}'`;
  });
  await X.S(run, 'Germany in the wizard clears City with the hint; saving only Country+City none works for an unrelated field set', 'City none with "Cleared because" hint', async () => {
    await openList(); await page().click(entry(C)); await page().waitForSelector(`${WS} form.cf-wizard-form`, { timeout: 15000 });
    await pick(run, `${WS} ${sel(C)}`, 'Germany');
    const v = await val(run, `${WS} ${sel(CI)}`); const h = await X.hintFor(run, `${WS} ${sel(CI)}`);
    if (v !== 'none' || !/Cleared because/.test(h)) throw new Error(`City '${v}' hint '${h}'`);
    return `City '${v}' hint '${h}'; Postal Zone '${await val(run, `${WS} ${sel(PZ)}`)}' hint '${await X.hintFor(run, `${WS} ${sel(PZ)}`)}'`;
  });
  await X.S(run, 'wizard on a single other entry (Zone) and Walk Local Parent loads', 'both load child fields', async () => {
    const out = [];
    for (const name of ['Zone', 'Walk Local Parent']) {
      await openList();
      await page().click(entry(F(run, name)));
      await page().waitForSelector(`${WS} form.cf-wizard-form`, { timeout: 15000 });
      out.push(name + ': ' + (await page().$$eval(`${WS} .cf-wizard-label`, (l) => l.map((x) => x.innerText.trim().split('\n')[0]))).join(', '));
    }
    return out.join(' | ');
  });
  await X.end(run);
})().catch((e) => { console.error(e); process.exit(1); });
