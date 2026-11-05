const { L, start, check, finish, exp } = require('../lib-admin');
(async () => {
  const run = await start('large-list');
  const p = () => run.page;
  const timings = {};
  const timed = async (name, path) => { const t = Date.now(); const r = await L.goto(run, path); timings[name] = Date.now() - t; if (r.status() !== 200) throw new Error(name + ' status ' + r.status()); return timings[name]; };
  await L.login(run, 'admin');
  await check(run, 'admin-editor-part-load', 'admin editor of Part (25,000 values, 500 parents) loads, 100 parent sections, usable', async () => {
    const ms = await timed('admin_edit_part', '/custom_fields/18/edit');
    const t = Date.now();
    await p().waitForSelector('fieldset.dcf-dep-editor .dcf-dep-editor__sections');
    const ready = Date.now() - t;
    const n = await p().locator('details.dcf-dep-section').count();
    const more = await p().locator('button[data-dcf-ed-more-sections]').innerText().catch(() => 'none');
    const usage = await p().locator('.dcf-storage-usage, p.dcf-storage').allInnerTexts().catch(() => []);
    exp(n, 100, 'sections');
    return `navigation ${ms}ms, editor ready +${ready}ms, ${n} sections, more button "${more}", storage hints ${JSON.stringify(usage)}`;
  });
  await check(run, 'admin-editor-interaction', 'filter parents to A123 and open it (50 linked of 25,000) quickly', async () => {
    const t = Date.now();
    await p().fill('input[data-dcf-ed-parent-filter]', 'A123');
    await p().waitForFunction(() => document.querySelectorAll('details.dcf-dep-section').length === 1, null, { timeout: 15000 });
    const filterMs = Date.now() - t;
    const d = p().locator("details.dcf-dep-section[data-dcf-ed-section='A123']");
    const t2 = Date.now(); await d.locator('summary').click(); await d.locator('.dcf-dep-section__body').waitFor();
    const openMs = Date.now() - t2;
    const counts = await d.locator('.dcf-dep-section__counts').innerText();
    const rows = await d.locator('input[data-dcf-ed-child-key]').count();
    timings.editor_filter_ms = filterMs; timings.editor_open_section_ms = openMs;
    return `filter ${filterMs}ms, open section ${openMs}ms, counts "${counts}", rendered rows ${rows}`;
  });
  await check(run, 'project-values-page-part', 'project values page: paginated (25,000 values), per-page text, pager', async () => {
    const ms = await timed('project_values_part', '/projects/walk/custom_field_configuration/fields/18');
    const rows = await p().locator('table.dcf-values tbody tr').count();
    const pager = await p().locator('span.pagination').innerText().catch(() => 'none');
    const info = await p().locator('p.info').allInnerTexts();
    if (rows > 500) throw new Error('rows ' + rows);
    if (rows < 2) throw new Error('rows ' + rows);
    return `${ms}ms, ${rows} rows, pager "${pager.replace(/\s+/g, ' ').slice(0, 150)}", info ${JSON.stringify(info)}`;
  });
  await check(run, 'project-values-page-2-and-last', 'page 2 and a page beyond the last (page=9999) show rows (last page)', async () => {
    const t = Date.now(); await L.goto(run, '/projects/walk/custom_field_configuration/fields/18?page=2'); const ms2 = Date.now() - t;
    const first2 = await p().locator('table.dcf-values tbody tr').first().getAttribute('data-dcf-value');
    const r = await L.goto(run, '/projects/walk/custom_field_configuration/fields/18?page=99999');
    const rows = await p().locator('table.dcf-values tbody tr').count();
    const last = await p().locator('table.dcf-values tbody tr').last().getAttribute('data-dcf-value');
    if (r.status() !== 200 || rows < 1) throw new Error('beyond-last: status ' + r.status() + ' rows ' + rows);
    return `page2 first ${first2} (${ms2}ms); page 99999 -> status ${r.status()}, ${rows} rows, last ${last}`;
  });
  await check(run, 'project-values-search', 'search "A123-P0" finds 9 values; "a123 p07" (words, case) finds 1; no match shows message', async () => {
    const t = Date.now(); await L.goto(run, '/projects/walk/custom_field_configuration/fields/18'); 
    await p().fill('#dcf_values_q', 'A123-P0');
    const t1 = Date.now(); await Promise.all([p().waitForLoadState('load'), p().click('form.dcf-values-filter input[type=submit]')]);
    const ms = Date.now() - t1;
    const rows1 = await p().locator('table.dcf-values tbody tr').count();
    const info = await p().locator('p.info').first().innerText();
    await p().fill('#dcf_values_q', 'a123 p07'); await Promise.all([p().waitForLoadState('load'), p().click('form.dcf-values-filter input[type=submit]')]);
    const rows2 = await p().locator('table.dcf-values tbody tr').count();
    await p().fill('#dcf_values_q', 'zzzz-none'); await Promise.all([p().waitForLoadState('load'), p().click('form.dcf-values-filter input[type=submit]')]);
    const none = await p().locator('p.nodata').innerText();
    timings.values_search_ms = ms;
    exp(rows1, 9, 'rows for A123-P0'); exp(rows2, 1, 'rows for a123 p07');
    return `search ${ms}ms; info "${info}"; none "${none}"`;
  });
  await check(run, 'project-values-per-page', 'per-page link 100 limits rows to 100', async () => {
    await L.goto(run, '/projects/walk/custom_field_configuration/fields/18?per_page=100');
    const rows = await p().locator('table.dcf-values tbody tr').count();
    const links = await p().locator('span.pagination a').allInnerTexts();
    return `rows ${rows}, pager links ${JSON.stringify(links.slice(0, 12))}`;
  });
  await check(run, 'project-dependency-page-part', 'project dependency page of Part loads; sections paged', async () => {
    const ms = await timed('project_deps_part', '/projects/walk/custom_field_configuration/fields/18/dependencies');
    await p().waitForSelector('fieldset.dcf-dep-editor .dcf-dep-editor__sections', { timeout: 30000 });
    const n = await p().locator('details.dcf-dep-section').count();
    return `${ms}ms, ${n} sections`;
  });
  await check(run, 'issue-form-assembly-part', 'Feature form in Walk: Assembly A007 -> Part offers only A007-P01..P50; Assembly change swaps the set', async () => {
    const ms = await timed('new_issue_feature', '/projects/walk/issues/new?issue[tracker_id]=2');
    const aId = run.ids.fields['Assembly'].id, pId = run.ids.fields['Part'].id;
    const t = Date.now(); await p().selectOption(L.cfSel(aId), 'A007'); await p().waitForTimeout(600);
    const opts = (await L.selectOptions(run, L.cfSel(pId))).filter(Boolean); const selMs = Date.now() - t;
    exp(opts.length, 50, 'count'); if (!opts.every((o) => o.startsWith('A007-P'))) throw new Error('foreign values ' + opts.slice(0, 5));
    await p().selectOption(L.cfSel(aId), 'A008'); await p().waitForTimeout(600);
    const opts2 = (await L.selectOptions(run, L.cfSel(pId))).filter(Boolean);
    if (!opts2.every((o) => o.startsWith('A008-P')) || opts2.length !== 50) throw new Error('swap wrong ' + opts2.slice(0, 3));
    const all = (await L.selectOptions(run, L.cfSel(pId), true)).length;
    timings.issue_form_select_ms = selMs;
    return `form load ${ms}ms; select Assembly ${selMs}ms; offered ${opts.length} (${opts[0]}..${opts[opts.length - 1]}); after A008 ${opts2[0]}; total option elements in DOM ${all}`;
  });
  await check(run, 'issue-form-bug-light', 'Bug form (no Assembly/Part) loads fast', async () => {
    const ms = await timed('new_issue_bug', '/projects/walk/issues/new');
    return `${ms}ms`;
  });
  await check(run, 'existing-feature-issue-edit', 'editing a Feature issue keeps its saved Part selectable', async () => {
    const id = 2;
    const ms = await timed('edit_feature_issue', `/issues/${id}/edit`);
    const aId = run.ids.fields['Assembly'].id, pId = run.ids.fields['Part'].id;
    const a = await p().inputValue(L.cfSel(aId)), pv = await p().inputValue(L.cfSel(pId));
    if (!pv.startsWith(a + '-P')) throw new Error(`Assembly ${a} Part ${pv}`);
    return `${ms}ms, Assembly ${a}, Part ${pv}`;
  });
  fs_write(run, timings);
  await finish(run);
  function fs_write(run, t) { require('fs').writeFileSync(run.outDir + '/large-list-timings.json', JSON.stringify(t, null, 2)); console.log('TIMINGS', JSON.stringify(t)); }
})();
