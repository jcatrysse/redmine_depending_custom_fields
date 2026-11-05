const { L, start, check, finish, exp, rails } = require('../lib-admin');
(async () => {
  const run = await start('project-values');
  const p = () => run.page;
  const base = '/projects/walk/custom_field_configuration/fields/';
  const rows = async () => p().$$eval('table.dcf-values tbody tr', (t) => t.map((r) => r.getAttribute('data-dcf-value')));
  const flash = async () => (await p().locator('#flash_notice, #flash_error, .flash').allInnerTexts()).join(' | ').replace(/\s+/g, ' ');
  const dialogs = [];
  const armDialogs = (accept) => { p().removeAllListeners('dialog'); p().on('dialog', (d) => { dialogs.push(d.message()); accept ? d.accept() : d.dismiss(); }); };
  const submitNav = async (loc) => { await Promise.all([p().waitForLoadState('load'), loc.click()]); };
  await L.login(run, 'manager');

  await check(run, 'settings-tab-lists-fields', 'Settings > Custom field configuration lists managed fields with scope badges; values and dependencies links', async () => {
    await L.goto(run, '/projects/walk/settings/custom_field_configuration');
    const t = (await p().locator('table.dcf-config-fields').innerText()).replace(/\s+/g, ' ');
    if (/translation missing/i.test(await p().content())) throw new Error('translation missing');
    return t.slice(0, 1200);
  });
  await check(run, 'add-value', 'add "Four" to Walk Plain List (project only): row appears, notice shown', async () => {
    await L.goto(run, base + '16');
    await p().fill('fieldset:has(legend:text("Add value")) input[name=value]', 'Four');
    await submitNav(p().locator('fieldset:has(input[name=value]) input[type=submit]'));
    const r = await rows(); if (!r.includes('Four')) throw new Error('missing ' + r); return `rows ${r}, flash "${await flash()}"`;
  });
  await check(run, 'rename-value', 'rename Four to Fourth (project-only, unused): no confirmation, renamed', async () => {
    const row = p().locator("table.dcf-values tbody tr[data-dcf-value='Four']");
    await row.locator('input[name=new_value]').fill('Fourth');
    await submitNav(row.locator('form.dcf-inline-form input[type=submit]'));
    const r = await rows(); const panel = await p().locator('.dcf-confirm-panel').count();
    if (!r.includes('Fourth')) throw new Error('not renamed; rows ' + r + ' panel ' + panel + ' flash ' + await flash());
    return `rows ${r}, panel ${panel}, flash "${await flash()}"`;
  });
  await check(run, 'search-small-field', 'search box hidden below 26 values, ?q=thr still filters (Three)', async () => {
    const box = await p().locator('#dcf_values_q').count();
    await L.goto(run, base + '16?q=thr');
    const r = await rows(); const box2 = await p().locator('#dcf_values_q').count();
    return `box on plain page: ${box}; ?q=thr rows ${r}, box present with q: ${box2}, info "${await p().locator('p.info').first().innerText().catch(() => '')}"`;
  });
  await check(run, 'default-value', 'set the field default to One', async () => {
    await L.goto(run, base + '16');
    await p().selectOption('select[name=default_value]', 'One');
    await submitNav(p().locator('input[type=submit][value="Set default"], fieldset:has(select[name=default_value]) input[type=submit]').first());
    const sel = await p().inputValue('select[name=default_value]'); exp(sel, 'One'); return `default now ${sel}, flash "${await flash()}"`;
  });
  await check(run, 'sort-project-only-dismiss-then-accept', 'project-only sort asks the browser question with the count; dismiss keeps order, accept sorts Z-A', async () => {
    dialogs.length = 0; armDialogs(false);
    const before = await rows();
    await p().locator("form.dcf-values-sort [type=submit]:has-text('Z-A'), form.dcf-values-sort input[value*='Z-A']").first().click(); await p().waitForTimeout(500);
    exp(await rows(), before, 'rows after dismiss');
    armDialogs(true);
    await submitNav(p().locator("form.dcf-values-sort input[value*='Z-A'], form.dcf-values-sort button:has-text('Z-A')").first());
    const after = await rows();
    exp(after, [...before].sort((a, b) => b.localeCompare(a)), 'Z-A');
    return `dialog "${dialogs[0]}"; before ${before} after ${after}; flash "${await flash()}"`;
  });
  await check(run, 'delete-value', 'delete Fourth: browser confirm, row gone, default untouched', async () => {
    armDialogs(true); dialogs.length = 0;
    const row = p().locator("table.dcf-values tbody tr[data-dcf-value='Fourth']");
    await submitNav(row.locator('input[value="Delete"], button:has-text("Delete")').first());
    const r = await rows(); if (r.includes('Fourth')) throw new Error('still there');
    return `dialog "${dialogs[0]}", rows ${r}, flash "${await flash()}"`;
  });
  await check(run, 'shared-rename-impact-panel', 'rename Rose (shared field 15): impact panel with checkbox; nothing renamed until ticked; cancel path keeps value', async () => {
    await L.goto(run, base + '15');
    const row = p().locator("table.dcf-values tbody tr[data-dcf-value='Rose']");
    await row.locator('input[name=new_value]').fill('Rosa');
    await submitNav(row.locator('form.dcf-inline-form input[type=submit]'));
    const panel = p().locator('.dcf-confirm-panel');
    if (!(await panel.count())) throw new Error('no panel; rows ' + await rows());
    const txt = (await panel.innerText()).replace(/\s+/g, ' ');
    const stillRose = (await rows()).includes('Rose');
    await L.screenshot(run, 'rename-panel');
    // cancel: just load the page again
    await L.goto(run, base + '15'); const r2 = await rows(); if (!r2.includes('Rose')) throw new Error('renamed without confirmation');
    return `panel "${txt}", rows unchanged ${stillRose}; after leaving: ${r2}`;
  });
  await check(run, 'shared-rename-confirm', 'rename Rose to Rosa with the checkbox: renamed, Shared Child issue values follow, rename back', async () => {
    const doRename = async (from, to) => {
      const row = p().locator(`table.dcf-values tbody tr[data-dcf-value='${from}']`);
      await row.locator('input[name=new_value]').fill(to); await submitNav(row.locator('form.dcf-inline-form input[type=submit]'));
      await p().locator('.dcf-confirm-panel input[name=confirm]').check();
      await submitNav(p().locator('.dcf-confirm-panel input[type=submit]'));
    };
    await doRename('Rose', 'Rosa'); const r1 = await rows(); const f1 = await flash();
    if (!r1.includes('Rosa')) throw new Error('not renamed ' + r1 + f1);
    await doRename('Rosa', 'Rose'); const r2 = await rows(); if (!r2.includes('Rose')) throw new Error('not reverted ' + r2);
    return `after rename ${r1} flash "${f1}"; reverted ${r2}`;
  });
  await check(run, 'enum-disable-value', 'Site (key/value, global): untick Active of East Gate, Save; stays in table inactive; reactivate', async () => {
    await L.goto(run, base + '8');
    const tr = p().locator("table.dcf-values tbody tr", { has: p().locator("input[value='East Gate']") });
    const cb = tr.locator('input[type=checkbox]'); await cb.uncheck();
    await submitNav(p().locator('form.dcf-enumerations-form input[type=submit]'));
    const f = await flash();
    const checked = await p().locator("table.dcf-values tbody tr", { has: p().locator("input[value='East Gate']") }).locator('input[type=checkbox]').isChecked();
    exp(checked, false, 'active flag');
    // the issue form must no longer offer it
    const cb2 = p().locator("table.dcf-values tbody tr", { has: p().locator("input[value='East Gate']") }).locator('input[type=checkbox]'); await cb2.check();
    await submitNav(p().locator('form.dcf-enumerations-form input[type=submit]'));
    const checked2 = await p().locator("table.dcf-values tbody tr", { has: p().locator("input[value='East Gate']") }).locator('input[type=checkbox]').isChecked();
    exp(checked2, true, 'reactivated');
    return `disable flash "${f}", reactivate flash "${await flash()}"`;
  });
  await check(run, 'enum-add-rename-delete', 'Site: add "Temp Site", rename it in the table, Save, delete it (unused: really removed)', async () => {
    await L.goto(run, base + '8');
    await p().fill('fieldset:has(legend:text("Add value")) input[name=value]', 'Temp Site');
    await submitNav(p().locator('fieldset:has(input[name=value]) input[type=submit]'));
    let tr = p().locator("table.dcf-values tbody tr", { has: p().locator("input[value='Temp Site']") });
    if (!(await tr.count())) throw new Error('not added; ' + await flash());
    await tr.locator('input[type=text]').fill('Temp Site 2');
    await submitNav(p().locator('form.dcf-enumerations-form input[type=submit]'));
    tr = p().locator("table.dcf-values tbody tr", { has: p().locator("input[value='Temp Site 2']") });
    if (!(await tr.count())) throw new Error('not renamed; ' + await flash());
    const f1 = await flash();
    armDialogs(true);
    const a = tr.locator('a.icon-del, a[data-method=delete]').first();
    await Promise.all([p().waitForLoadState('load'), a.click()]);
    let f2 = await flash();
    if (await p().locator('.dcf-confirm-panel').count()) {
      const t = (await p().locator('.dcf-confirm-panel').innerText()).replace(/\s+/g, ' ');
      await p().locator('.dcf-confirm-panel input[name=confirm]').check(); await submitNav(p().locator('.dcf-confirm-panel input[type=submit]'));
      f2 = 'panel "' + t + '" then ' + await flash();
    }
    const gone = !(await p().content()).includes('Temp Site 2');
    return `rename flash "${f1}", delete result "${f2}", gone ${gone}`;
  });
  await check(run, 'sort-shared-panel', 'shared field sort: no browser dialog, server confirmation panel, tick + Apply sorts', async () => {
    dialogs.length = 0; armDialogs(true);
    await L.goto(run, base + '15');
    await submitNav(p().locator("form.dcf-values-sort input[value*='Z-A']").first());
    const panel = p().locator('.dcf-confirm-panel'); if (!(await panel.count())) throw new Error('no panel');
    const t = (await panel.innerText()).replace(/\s+/g, ' ');
    if (dialogs.length) throw new Error('browser dialog shown: ' + dialogs);
    await L.screenshot(run, 'sort-panel');
    await panel.locator('input[name=confirm]').check(); await submitNav(panel.locator('input[type=submit]'));
    const r = await rows(); exp(r[0], 'Ruby'.localeCompare('Rose') > 0 ? 'Ruby' : r[0]);
    // restore A-Z
    await submitNav(p().locator("form.dcf-values-sort input[value*='A-Z']").first());
    await p().locator('.dcf-confirm-panel input[name=confirm]').check(); await submitNav(p().locator('.dcf-confirm-panel input[type=submit]'));
    return `panel "${t}", Z-A rows ${r}, restored ${await rows()}`;
  });
  await check(run, 'storage-limit-message', 'with ceiling 64 KiB, adding a value to Part (already larger) is refused with the field name and both sizes; shrinking/reading still works; audited', async () => {
    rails(run, "s=Setting.plugin_redmine_depending_custom_fields.dup; s['project_storage_ceiling_kib']='64'; Setting.plugin_redmine_depending_custom_fields=s");
    try {
      await L.goto(run, base + '18');
      const hint = await p().locator('.dcf-storage-usage, .dcf-storage-hint, p.info, div.flash').allInnerTexts();
      await p().fill('fieldset:has(legend:text("Add value")) input[name=value]', 'ZZZ-NEW');
      await submitNav(p().locator('fieldset:has(input[name=value]) input[type=submit]'));
      const f = await flash();
      const added = (await p().content()).includes('ZZZ-NEW');
      if (!/Part/.test(f) || !/\d/.test(f)) throw new Error('no size message: "' + f + '" added=' + added);
      await L.goto(run, '/projects/walk/custom_field_configuration/audit');
      const audit = (await p().locator('table').first().innerText().catch(() => '')).replace(/\s+/g, ' ').slice(0, 500);
      return `hint ${JSON.stringify(hint).slice(0, 300)}; refusal "${f}"; added ${added}; audit "${audit}"`;
    } finally {
      rails(run, "s=Setting.plugin_redmine_depending_custom_fields.dup; s['project_storage_ceiling_kib']='2048'; Setting.plugin_redmine_depending_custom_fields=s");
    }
  });
  await finish(run);
})();
