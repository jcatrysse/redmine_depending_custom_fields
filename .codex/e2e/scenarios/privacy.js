const X = require('../lib-issue'); const { L } = X;
(async () => {
  const run = await X.begin('privacy');
  const { sel, F, opts, val, pick } = X; const eq = L.expectEqual;
  const C = F(run, 'Country'), CI = F(run, 'City'), PZ = F(run, 'Postal Zone'), SC = F(run, 'Secret Code'), CL = F(run, 'Clearance'), AA = F(run, 'Access Area');
  const FORBIDDEN = ['Secret Code', 'Zulu-7731', 'Zulu-7732', 'Yankee-4410', 'Xray-9981', 'Whiskey-2208', 'Clearance', 'Alpha-Level', 'Bravo-Level'];
  const WEAK = [new RegExp(`custom_field_values[_\\]\\[]+${SC}\\b`), new RegExp(`\\bcf_${SC}\\b`), new RegExp(`\\bcf_${CL}\\b`), new RegExp(`custom_field_values[_\\]\\[]+${CL}\\b`), new RegExp(`data-dcf-field="${SC}"`), new RegExp(`data-dcf-parent="${CL}"`), new RegExp(`"id":\\s*${SC}\\b`), new RegExp(`"id":\\s*${CL}\\b`), /secret_code|secretcode/i];
  const weakHits = [];
  function scan(label, text) {
    const strong = FORBIDDEN.filter((s) => text.toLowerCase().includes(s.toLowerCase()));
    const weak = WEAK.filter((r) => r.test(text)).map(String);
    if (weak.length) weakHits.push(`${label}: ${weak.join(' ')}`);
    return { strong, weak };
  }
  async function getText(p, user) {
    if (user) { const r = await X.api(run, 'GET', p, null, user); return { status: r.status, text: r.text }; }
    const r = await run.context.request.get(run.base + p); return { status: r.status(), text: await r.text() };
  }
  async function checkUrls(user, urls) {
    const res = [];
    for (const u of urls) {
      const { status, text } = await getText(u, null);
      const s = scan(u, text);
      res.push(`${status} ${u.slice(0, 70)} len=${text.length}${s.strong.length ? ' LEAK ' + JSON.stringify(s.strong) : ''}`);
      if (s.strong.length) throw new Error(`${user}: leak on ${u}: ${JSON.stringify(s.strong)} (status ${status})`);
    }
    return res.join('\n');
  }
  let P, P2;
  await X.S(run, 'setup by manager: issue with hidden Secret Code, Clearance and a journal entry on the hidden field', 'issue created; manager sees Secret Code in the form', async () => {
    P = await X.createIssue(run, `E2E privacy ${run.uniq}`, { Country: 'Belgium', City: 'Brussels', 'Postal Zone': 'B-1000', 'Secret Code': 'Zulu-7732', Clearance: 'Alpha-Level', 'Access Area': 'Area-51' }, { assigned_to_id: 6 });
    const r = await X.api(run, 'PUT', `/issues/${P}.json`, { issue: { notes: 'hidden change', custom_fields: [{ id: SC, value: 'Zulu-7731' }] } });
    if (r.status !== 204) throw new Error('PUT ' + r.status + r.text);
    await L.login(run, 'manager'); await L.goto(run, `/issues/${P}/edit`);
    if ((await run.page.locator(sel(SC)).count()) !== 1) throw new Error('manager does not see Secret Code');
    await L.goto(run, `/issues/${P}`);
    const t = (await run.page.locator('#history').innerText()).replace(/\s+/g, ' ');
    return `issue #${P}; manager history: ${t.slice(0, 250)}`;
  });
  for (const user of ['developer', 'reporter']) {
    await X.S(run, `${user}: new issue form (HTML after JS filtering)`, 'no hidden field name, value, mapping', async () => {
      await L.login(run, user); await L.goto(run, '/projects/walk/issues/new');
      await pick(run, sel(C), 'Belgium');
      const s = scan('new issue DOM', await run.page.content());
      if (s.strong.length) throw new Error('leak: ' + JSON.stringify(s.strong));
      const aa = (await opts(run, sel(AA))).join(',');
      return `Access Area options ${aa}; weak markers: ${JSON.stringify(s.weak)}`;
    });
    await X.S(run, `${user}: server HTML of new, show, edit, bulk edit, context menu, wizard, lists`, 'all clean', async () => {
      await L.login(run, user);
      return checkUrls(user, [
        '/projects/walk/issues/new', `/issues/${P}`, `/issues/${P}/edit`, `/issues/bulk_edit?ids[]=${P}&ids[]=2&ids[]=3`, `/issues/context_menu?ids[]=${P}`,
        `/issues/context_menu?ids[]=${P}&ids[]=2`, `/depending_custom_fields/wizard?parent_id=${C}&ids[]=${P}`, `/depending_custom_fields/wizard?parent_id=${SC}&ids[]=${P}`, `/depending_custom_fields/wizard?parent_id=${CL}&ids[]=${P}`,
        '/projects/walk/issues?per_page=100', `/projects/walk/issues?set_filter=1&c[]=subject&c[]=cf_${SC}&c[]=cf_${CL}&c[]=cf_${AA}&f[]=cf_${SC}&op[cf_${SC}]==&v[cf_${SC}][]=ZZZ`,
        `/projects/walk/issues?set_filter=1&sort=cf_${SC}&group_by=cf_${SC}`, `/projects/walk/issues.csv?c[]=subject&c[]=cf_${SC}&c[]=cf_${CL}`, `/issues.atom?project_id=1`,
        '/projects/walk/queries/new', '/depending_custom_fields.json', `/issues/${P}.json?include=journals`, '/issues.json?project_id=1&limit=100', '/time_entries/new?project_id=1', `/issues/${P}/time_entries/new`,
      ]);
    });
    await X.S(run, `${user}: search for hidden values finds nothing`, 'search results list no issue for hidden values', async () => {
      const out = [];
      for (const q of ['Zulu-7731', 'Zulu-7732', 'Alpha-Level']) {
        const { text } = await getText(`/search?q=${q}&issues=1&all_words=1`, null);
        const m = /<dl id="search-results">([\s\S]*?)<\/dl>/.exec(text); const body = m ? m[1] : '';
        const hits = (body.match(/<dt/g) || []).length;
        const s = scan('search results ' + q, body); if (s.strong.length || hits) throw new Error(`search ${q}: ${hits} results, leak ${JSON.stringify(s.strong)}`);
        out.push(`${q}: ${hits} results`);
      }
      return out.join(', ');
    });
    await X.S(run, `${user}: REST JSON with API login (single issue, journals, list, filters)`, 'JSON holds no hidden field', async () => {
      const out = [];
      for (const p of [`/issues/${P}.json?include=journals`, '/issues.json?project_id=1&limit=100', `/issues.json?cf_${SC}=Zulu-7731`, `/issues.json?project_id=1&cf_${CL}=Alpha-Level&limit=100`, '/depending_custom_fields.json', `/issues/${P}.xml?include=journals`]) {
        const { status, text } = await getText(p, user); const s = scan('API ' + p, text);
        out.push(`${status} ${p} len=${text.length}${s.strong.length ? ' LEAK ' + JSON.stringify(s.strong) : ''}`);
        if (s.strong.length) throw new Error(`API leak ${p}: ${JSON.stringify(s.strong)}`);
      }
      const j = await getText(`/issues.json?cf_${SC}=Zulu-7731&limit=100`, user); const all = await getText('/issues.json?project_id=1&limit=100', user);
      const cnt = (t) => JSON.parse(t).total_count;
      out.push(`filter on hidden field returns ${cnt(j.text)} of ${cnt(all.text)} total (equal means ignored)`);
      return out.join('\n');
    });
    await X.S(run, `${user}: issue show page and journal screenshot`, 'history shows no Secret Code change', async () => {
      await L.goto(run, `/issues/${P}`);
      const h = (await run.page.locator('#history').innerText()).replace(/\s+/g, ' ');
      const s = scan('show DOM', await run.page.content()); if (s.strong.length) throw new Error('leak ' + JSON.stringify(s.strong));
      return 'history: ' + h.slice(0, 300);
    });
    await X.S(run, `${user}: context menu and wizard in the browser`, 'wizard fields have no hidden field; menu has no Clearance entry', async () => {
      await L.goto(run, `/projects/walk/issues?set_filter=1&f[]=subject&op[subject]=~&v[subject][]=E2E+privacy+${run.uniq}`);
      await run.page.locator(`tr#issue-${P} td.status`).click({ button: 'right' });
      await run.page.waitForSelector('#context-menu li', { state: 'visible' });
      const entries = await run.page.$$eval('#context-menu li.cf-parent', (l) => l.map((x) => x.innerText.trim()));
      let s = scan('context menu DOM', await run.page.content()); if (s.strong.length) throw new Error('menu leak ' + JSON.stringify(s.strong));
      if (!entries.length) return 'no wizard entries for ' + user;
      await run.page.click('#context-menu li.cf-parent > a.submenu');
      await run.page.waitForSelector('#cf-wizard-container form.cf-wizard-form', { timeout: 15000 });
      const labels = await run.page.$$eval('#cf-wizard-container .cf-wizard-label', (l) => l.map((x) => x.innerText.trim().split('\n')[0]));
      s = scan('wizard DOM', await run.page.content()); if (s.strong.length) throw new Error('wizard leak ' + JSON.stringify(s.strong));
      return `entries: ${entries.join(', ')}; wizard fields: ${labels.join(', ')}`;
    });
    await X.S(run, `${user}: edit refused for a parent change that conflicts with the hidden Secret Code (form)`, 'refused; message does not name Secret Code or a value', async () => {
      const ed = await run.context.request.get(run.base + `/issues/${P}/edit`);
      if (ed.status() === 403 || !(await ed.text()).includes(`issue_custom_field_values_${C}"`)) return `${user} has no Edit issues permission on #${P}: /issues/${P}/edit answers ${ed.status()} without a form (step not applicable)`;
      await L.goto(run, `/issues/${P}/edit`);
      await pick(run, sel(C), 'Netherlands'); await pick(run, sel(CI), 'Amsterdam'); await pick(run, sel(PZ), 'NL-1011');
      await X.submitIssue(run);
      const t = await X.errorText(run);
      const s = scan('edit refusal page', await run.page.content());
      if (s.strong.length) throw new Error(`leak ${JSON.stringify(s.strong)} error '${t}'`);
      if (!t) throw new Error('not refused: ' + run.page.url());
      const cf = await X.issueCf(run, P); eq(cf.Country, 'Belgium', 'issue unchanged');
      return `error: '${t}'`;
    });
    await X.S(run, `${user}: REST update refused (422) without naming the hidden field`, '422 with a generic or parent-level message', async () => {
      const ed = await run.context.request.get(run.base + `/issues/${P}/edit`);
      if (ed.status() === 403 || !(await ed.text()).includes(`issue_custom_field_values_${C}"`)) return `${user} has no Edit issues permission on #${P}: /issues/${P}/edit answers ${ed.status()} without a form (step not applicable)`;
      const r = await X.api(run, 'PUT', `/issues/${P}.json`, { issue: { custom_fields: [{ id: C, value: 'Netherlands' }, { id: CI, value: 'Amsterdam' }, { id: PZ, value: 'NL-1011' }] } }, user);
      const s = scan('PUT refusal', r.text); if (s.strong.length) throw new Error(`leak ${JSON.stringify(s.strong)} body ${r.text}`);
      return `status ${r.status} body ${r.text.slice(0, 300)}`;
    });
    await X.S(run, `${user}: bulk edit refused (parent change)`, 'refused; message generic', async () => {
      const ed = await run.context.request.get(run.base + `/issues/${P}/edit`);
      if (ed.status() === 403 || !(await ed.text()).includes(`issue_custom_field_values_${C}"`)) return `${user} has no Edit issues permission on #${P}: /issues/${P}/edit answers ${ed.status()} without a form (step not applicable)`;
      await L.goto(run, `/issues/bulk_edit?ids[]=${P}`);
      await pick(run, sel(C), 'Netherlands'); await pick(run, sel(CI), 'Amsterdam'); await pick(run, sel(PZ), 'NL-1011');
      await Promise.all([run.page.waitForLoadState('load'), run.page.click('#bulk_edit_form input[type=submit]')]);
      const t = await X.errorText(run); const fl = await X.flashText(run);
      const s = scan('bulk refusal page', await run.page.content()); if (s.strong.length) throw new Error(`leak ${JSON.stringify(s.strong)} error '${t}'`);
      return `flash '${fl}' error '${t}'`;
    });
    await X.S(run, `${user}: wizard save refused (parent change)`, 'alert text generic', async () => {
      const ed = await run.context.request.get(run.base + `/issues/${P}/edit`);
      if (ed.status() === 403 || !(await ed.text()).includes(`issue_custom_field_values_${C}"`)) return `${user} has no Edit issues permission on #${P}: /issues/${P}/edit answers ${ed.status()} without a form (step not applicable)`;
      const dialogs = []; run.page.on('dialog', async (d) => { dialogs.push(d.message()); await d.accept(); });
      await L.goto(run, `/projects/walk/issues?set_filter=1&f[]=subject&op[subject]=~&v[subject][]=E2E+privacy+${run.uniq}`);
      await run.page.locator(`tr#issue-${P} td.status`).click({ button: 'right' });
      await run.page.waitForSelector('#context-menu li.cf-parent', { state: 'visible' });
      await run.page.click(`#context-menu li.cf-parent[data-parent-id='${C}'] > a.submenu`);
      await run.page.waitForSelector('#cf-wizard-container form.cf-wizard-form', { timeout: 15000 });
      await pick(run, `#cf-wizard-container ${sel(C)}`, 'Netherlands'); await pick(run, `#cf-wizard-container ${sel(CI)}`, 'Amsterdam'); await pick(run, `#cf-wizard-container ${sel(PZ)}`, 'NL-1011');
      await run.page.click('#cf-wizard-container button[type=submit]'); await run.page.waitForTimeout(2500);
      const s = scan('wizard refusal', dialogs.join(' ') + await run.page.content()); if (s.strong.length) throw new Error(`leak ${JSON.stringify(s.strong)} dialogs ${JSON.stringify(dialogs)}`);
      return `dialogs ${JSON.stringify(dialogs)}; reloaded: ${!(await X.visible(run, '#cf-wizard-container'))}`;
    });
    await X.S(run, `${user}: Access Area (visible child of hidden Clearance) with a value its hidden parent does not allow`, 'refused as "Access Area is invalid" without naming Clearance or its value', async () => {
      const ed = await run.context.request.get(run.base + `/issues/${P}/edit`);
      if (ed.status() === 403 || !(await ed.text()).includes(`issue_custom_field_values_${C}"`)) return `${user} has no Edit issues permission on #${P}: /issues/${P}/edit answers ${ed.status()} without a form (step not applicable)`;
      await L.goto(run, `/issues/${P}/edit`);
      await X.force(run, sel(AA), 'Area-61');
      await X.submitIssue(run);
      const t = await X.errorText(run);
      const s = scan('Access Area refusal', await run.page.content()); if (s.strong.length) throw new Error(`leak ${JSON.stringify(s.strong)} error '${t}'`);
      return `error '${t}' (issue Access Area now '${(await X.issueCf(run, P))['Access Area']}')`;
    });
    await X.S(run, `${user}: new issue with a country whose default hidden code conflicts (France)`, 'created or refused without naming the hidden field', async () => {
      await L.goto(run, '/projects/walk/issues/new');
      await run.page.fill('#issue_subject', `E2E privacy new ${user} ${run.uniq}`);
      await pick(run, sel(C), 'France'); await pick(run, sel(PZ), 'F-75001');
      await X.submitIssue(run);
      const t = await X.errorText(run);
      const s = scan('new issue save', await run.page.content()); if (s.strong.length) throw new Error(`leak ${JSON.stringify(s.strong)} error '${t}'`);
      const id = X.issueIdFromUrl(run.page.url());
      return id ? `created #${id}; hidden Secret Code stored by manager view: '${(await X.issueCf(run, id))['Secret Code']}'` : `refused: '${t}'`;
    });
    await X.S(run, `${user}: time entry form and list`, 'no hidden field', async () => {
      await L.goto(run, '/projects/walk/time_entries/new');
      let s = scan('time entry new', await run.page.content()); if (s.strong.length) throw new Error('leak ' + JSON.stringify(s.strong));
      return checkUrls(user, ['/projects/walk/time_entries', '/projects/walk/time_entries/new']);
    });
  }
  await X.S(run, 'weak markers: ids of the hidden fields in markup', 'none (informational)', async () => {
    return weakHits.length ? 'markers found: ' + weakHits.join(' || ') : 'none found';
  });
  await X.end(run);
})().catch((e) => { console.error(e); process.exit(1); });
