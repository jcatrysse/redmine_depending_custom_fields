const X = require('../lib-issue'); const { L } = X;
(async () => {
  const run = await X.begin('time-entry');
  const { opts, val, pick } = X; const eq = L.expectEqual;
  const K = run.ids.fields['Work Kind'].id, DT = run.ids.fields['Work Detail'].id;
  const ts = (id) => `#time_entry_custom_field_values_${id}`;
  const nonBlank = (a) => a.filter((x) => x.trim());
  const act = async () => { await run.page.selectOption('#time_entry_activity_id', { label: 'Development' }); };
  const submit = async () => { await run.page.waitForTimeout(800); if (await run.page.locator('#time_entry_activity_id').count()) await act(); await Promise.all([run.page.waitForLoadState('load'), run.page.click('#content form input[name=commit]')]); await run.page.waitForTimeout(300); };
  const teCf = async (id) => { const r = await X.api(run, 'GET', `/time_entries/${id}.json`); const o = {}; for (const c of (r.json.time_entry.custom_fields || [])) o[c.name] = c.value; return o; };
  let teId;
  await X.S(run, 'login as manager, open the time entry form of Walk', 'Work Kind offers 3 values, Work Detail empty with a hint', async () => {
    await L.login(run, 'manager'); await L.goto(run, '/projects/walk/time_entries/new');
    eq(nonBlank(await opts(run, ts(K))), ['Development', 'Operations', 'Support'], 'Work Kind');
    eq(nonBlank(await opts(run, ts(DT))), [], 'Work Detail without parent');
    return 'hint: ' + await X.hintFor(run, ts(DT));
  });
  await X.S(run, 'parent choices filter the child, default per parent', 'Development: Coding Review Testing (default Coding); Operations: Deploy Monitor and Support: Triage without a default', async () => {
    const res = {};
    for (const k of ['Development', 'Operations', 'Support']) { await pick(run, ts(K), k); res[k] = [nonBlank(await opts(run, ts(DT))), await val(run, ts(DT))]; }
    eq(res, { Development: [['Coding', 'Review', 'Testing'], 'Coding'], Operations: [['Deploy', 'Monitor'], ''], Support: [['Triage'], ''] }, 'filtering');
    return JSON.stringify(res);
  });
  await X.S(run, 'last picked child returns when the parent is switched back', 'Development/Testing, Operations, back to Development gives Testing', async () => {
    await pick(run, ts(K), 'Development'); await pick(run, ts(DT), 'Testing');
    await pick(run, ts(K), 'Operations'); await pick(run, ts(K), 'Development');
    eq(await val(run, ts(DT)), 'Testing', 'Work Detail');
  });
  await X.S(run, 'clearing the parent empties the child choices', 'blank parent: child has only the blank choice and a hint', async () => {
    await run.page.selectOption(ts(K), { label: ' ' }); await run.page.waitForTimeout(500);
    eq(nonBlank(await opts(run, ts(DT))), [], 'Work Detail');
    return 'hint: ' + await X.hintFor(run, ts(DT));
  });
  await X.S(run, 'forced disallowed Work Detail (Deploy under Development) is refused', 'error "Work detail is invalid"', async () => {
    await run.page.fill('#time_entry_issue_id', '1').catch(() => {});
    await run.page.fill('#time_entry_hours', '1'); await act();
    await pick(run, ts(K), 'Development'); await X.force(run, ts(DT), 'Deploy');
    await submit();
    const t = await X.errorText(run);
    if (!/Work detail is invalid/i.test(t)) throw new Error('error text: ' + t + ' url ' + run.page.url());
    return t;
  });
  await X.S(run, 'after the refusal the form still filters', 'Work Kind Development kept, Work Detail options Coding Review Testing', async () => {
    eq(await val(run, ts(K)), 'Development', 'Work Kind');
    eq(nonBlank(await opts(run, ts(DT))), ['Coding', 'Review', 'Testing'], 'Work Detail');
    return 'Work Detail now ' + await val(run, ts(DT));
  });
  await X.S(run, 'valid save: 1.5 h on issue #1, Operations / Monitor', 'time entry created with the values', async () => {
    await L.goto(run, '/projects/walk/time_entries/new');
    await run.page.fill('#time_entry_issue_id', '1'); await run.page.fill('#time_entry_hours', '1.5'); await act(); await run.page.fill('#time_entry_comments', `E2E time ${run.uniq}`);
    await pick(run, ts(K), 'Operations'); await pick(run, ts(DT), 'Monitor');
    await submit();
    const t = await X.errorText(run); if (t) throw new Error('refused: ' + t);
    const r = await X.api(run, 'GET', '/time_entries.json?project_id=1&limit=100');
    const te = r.json.time_entries.filter((x) => x.comments === `E2E time ${run.uniq}`)[0];
    if (!te) throw new Error('entry not found; page ' + run.page.url());
    teId = te.id;
    const cf = await teCf(teId); eq([cf['Work Kind'], cf['Work Detail']], ['Operations', 'Monitor'], 'stored');
    return `entry #${teId}; flash '${await X.flashText(run)}'`;
  });
  await X.S(run, 'time entry list shows both fields as columns', 'Work Kind and Work Detail columns with values', async () => {
    await L.goto(run, `/projects/walk/time_entries?set_filter=1&c[]=spent_on&c[]=user&c[]=activity&c[]=issue&c[]=comments&c[]=hours&c[]=cf_${K}&c[]=cf_${DT}&f[]=spent_on&op[spent_on]=*`);
    const row = await run.page.locator(`tr.time-entry:has-text("E2E time ${run.uniq}")`).first().innerText();
    if (!/Operations/.test(row) || !/Monitor/.test(row)) throw new Error('row: ' + row.replace(/\s+/g, ' '));
    const heads = await run.page.$$eval('table.list.time-entries thead th', (t) => t.map((x) => x.innerText.trim()).filter(Boolean));
    return 'heads: ' + heads.join(', ');
  });
  await X.S(run, 'filter list: Work Detail is not offered as a filter because the seed has is_filter false', 'filter dropdown has no Work Kind/Work Detail (Redmine only lists custom fields flagged "Used as a filter"); not a plugin matter', async () => {
    await L.goto(run, '/projects/walk/time_entries');
    const names = await run.page.$$eval('#add_filter_select option', (o) => o.map((x) => x.textContent.trim()));
    return 'filters offered: ' + names.filter(Boolean).join(', ');
  });
  await X.S(run, 'edit the time entry: change parent to Support, child filtered, save', 'Support / Triage stored', async () => {
    await L.goto(run, `/time_entries/${teId}/edit`);
    eq([await val(run, ts(K)), await val(run, ts(DT))], ['Operations', 'Monitor'], 'stored on form');
    await pick(run, ts(K), 'Support');
    eq(nonBlank(await opts(run, ts(DT))), ['Triage'], 'child options');
    await pick(run, ts(DT), 'Triage');
    await submit();
    const t = await X.errorText(run); if (t) throw new Error('refused: ' + t);
    const cf = await teCf(teId); eq([cf['Work Kind'], cf['Work Detail']], ['Support', 'Triage'], 'stored');
  });
  await X.S(run, 'edit with forced disallowed child is refused', 'Work detail is invalid and stored values unchanged', async () => {
    await L.goto(run, `/time_entries/${teId}/edit`);
    await X.force(run, ts(DT), 'Coding');
    await submit();
    const t = await X.errorText(run); if (!/Work detail is invalid/i.test(t)) throw new Error('error text: ' + t);
    const cf = await teCf(teId); eq([cf['Work Kind'], cf['Work Detail']], ['Support', 'Triage'], 'stored');
    return t;
  });
  await X.S(run, 'log time from the issue page of #1', 'form opens with issue preset and the same filtering', async () => {
    await L.goto(run, '/issues/1/time_entries/new');
    await pick(run, ts(K), 'Development');
    eq(nonBlank(await opts(run, ts(DT))), ['Coding', 'Review', 'Testing'], 'child');
  });
  await X.S(run, 'bulk edit of time entries: parent change with child on (No change)', 'form filters per chosen parent; server refuses entries keeping a disallowed child', async () => {
    const te2 = await (async () => { await L.goto(run, '/projects/walk/time_entries/new'); await run.page.fill('#time_entry_issue_id', '1'); await run.page.fill('#time_entry_hours', '0.5'); await act(); await run.page.fill('#time_entry_comments', `E2E time b ${run.uniq}`); await pick(run, ts(K), 'Development'); await pick(run, ts(DT), 'Review'); await submit(); })();
    const r = await X.api(run, 'GET', '/time_entries.json?project_id=1&limit=100');
    const ids = r.json.time_entries.filter((x) => x.comments && x.comments.includes(run.uniq)).map((x) => x.id);
    await L.goto(run, `/time_entries/bulk_edit?${ids.map((i) => 'ids[]=' + i).join('&')}`);
    const before = await opts(run, ts(DT));
    await pick(run, ts(K), 'Support');
    const after = nonBlank(await opts(run, ts(DT)));
    await pick(run, ts(DT), '(No change)');
    await Promise.all([run.page.waitForLoadState('load'), run.page.click('#bulk_edit_form input[type=submit]')]);
    const t = await X.errorText(run); const fl = await X.flashText(run);
    return `entries ${ids.join(',')}; child options before parent choice: ${before.join(',')}; after Support: ${after.join(',')}; result flash '${fl}' error '${t}'`;
  });
  await X.S(run, 'developer logs time with the fields', 'developer can log Development / Testing', async () => {
    await L.login(run, 'developer'); await L.goto(run, '/projects/walk/time_entries/new');
    await run.page.fill('#time_entry_issue_id', '2'); await run.page.fill('#time_entry_hours', '1'); await act(); await run.page.fill('#time_entry_comments', `E2E time dev ${run.uniq}`);
    await pick(run, ts(K), 'Development'); await pick(run, ts(DT), 'Testing');
    await submit();
    const t = await X.errorText(run); if (t) throw new Error('refused: ' + t);
    return 'flash: ' + await X.flashText(run);
  });
  await X.S(run, 'hidden-field rule on time entries', 'not applicable: the seed has no role-restricted time entry field', async () => 'not run: no hidden time entry field is seeded (fields 19 and 20 are visible to every role)');
  await X.end(run);
})().catch((e) => { console.error(e); process.exit(1); });
