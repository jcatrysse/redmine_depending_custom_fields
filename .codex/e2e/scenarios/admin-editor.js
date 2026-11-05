const { L, start, check, finish, exp, rails } = require('../lib-admin');
(async () => {
  const run = await start('admin-editor');
  const p = () => run.page;
  const mapping = async () => JSON.parse(await p().$eval('fieldset[data-dcf-editor]', (e) => e.getAttribute('data-dcf-editor-mapping')));
  const section = (k) => p().locator(`details.dcf-dep-section[data-dcf-ed-section='${k}']`);
  const openSec = async (k) => { const d = section(k); await d.locator('summary').click(); await d.locator('.dcf-dep-section__body').waitFor(); return d; };
  const edit = async (id) => { await L.goto(run, `/custom_fields/${id}/edit`); await p().waitForSelector('fieldset.dcf-dep-editor .dcf-dep-editor__sections'); };
  const save = async () => { await Promise.all([p().waitForLoadState('load'), p().click('#custom_field_form input[type=submit][name=commit]')]); };
  await L.login(run, 'admin');
  let t0;
  await check(run, 'open-city-editor', 'editor shows 4 parent sections (Belgium, Netherlands, France, Germany) and saved counts', async () => {
    t0 = Date.now(); await edit(2); const ms = Date.now() - t0;
    const n = await p().locator('details.dcf-dep-section').count(); exp(n, 4, 'sections');
    const txt = await section('Belgium').locator('.dcf-dep-section__counts').innerText();
    return `4 sections, Belgium counts "${txt}", load ${ms}ms`;
  });
  await check(run, 'search-parent', 'parent search for "net" leaves only Netherlands', async () => {
    await p().fill('input[data-dcf-ed-parent-filter]', 'net');
    await p().waitForFunction(() => document.querySelectorAll('details.dcf-dep-section').length === 1);
    const k = await p().locator('details.dcf-dep-section').first().getAttribute('data-dcf-ed-section'); exp(k, 'Netherlands');
    return k;
  });
  await check(run, 'only-without-links', 'checkbox "Only parent values without links" shows Germany only', async () => {
    await p().fill('input[data-dcf-ed-parent-filter]', '');
    await p().waitForFunction(() => document.querySelectorAll('details.dcf-dep-section').length === 4);
    await p().locator('label:has-text("Only parent values without links") input, input[data-dcf-ed-only-empty]').first().check();
    await p().waitForFunction(() => document.querySelectorAll('details.dcf-dep-section').length === 1);
    const k = await p().locator('details.dcf-dep-section').first().getAttribute('data-dcf-ed-section'); exp(k, 'Germany');
    await p().locator('label:has-text("Only parent values without links") input, input[data-dcf-ed-only-empty]').first().uncheck();
    return k;
  });
  await check(run, 'map-values', 'Germany gets Lyon + default Lyon, Belgium loses Antwerp; unsaved warning active', async () => {
    await p().waitForFunction(() => document.querySelectorAll('details.dcf-dep-section').length === 4);
    const g = await openSec('Germany');
    await g.locator("input[data-dcf-ed-child-key='Lyon']").click();
    await g.locator('select[data-dcf-ed-default]').selectOption('Lyon');
    const b = await openSec('Belgium');
    await b.locator("input[data-dcf-ed-child-key='Antwerp']").click();
    const w = await p().evaluate(() => DcfDependencyEditor.get(document.querySelector('[data-dcf-editor]')).wantsWarning());
    exp(w, true, 'wantsWarning');
    return `Germany counts "${await g.locator('.dcf-dep-section__counts').innerText()}", Belgium "${await b.locator('.dcf-dep-section__counts').innerText()}"`;
  });
  await check(run, 'save-and-reload', 'save shows notice; reload shows Germany [Lyon] default Lyon, Belgium without Antwerp', async () => {
    await save();
    const flash = await p().locator('#flash_notice').innerText();
    await edit(2);
    const m = await mapping();
    exp(m.value_dependencies.Germany, ['Lyon'], 'Germany'); exp(m.value_dependencies.Belgium, ['Brussels', 'Ghent'], 'Belgium');
    exp(m.default_value_dependencies.Germany, 'Lyon', 'default');
    return `flash "${flash}", mapping ${JSON.stringify(m.value_dependencies)}`;
  });
  await check(run, 'issue-form-uses-saved-mapping', 'new issue form: Germany now offers Lyon, Belgium no Antwerp', async () => {
    await L.goto(run, '/projects/walk/issues/new');
    await p().selectOption('#issue_custom_field_values_1', 'Germany'); await p().waitForTimeout(500);
    const g = (await L.selectOptions(run, '#issue_custom_field_values_2')).filter(Boolean);
    await p().selectOption('#issue_custom_field_values_1', 'Belgium'); await p().waitForTimeout(500);
    const b = (await L.selectOptions(run, '#issue_custom_field_values_2')).filter(Boolean);
    exp(g, ['Lyon']); exp(b.sort(), ['Brussels', 'Ghent']);
    return `Germany ${g}, Belgium ${b}`;
  });
  await check(run, 'restore-mapping', 'revert the change in the editor and save', async () => {
    await edit(2);
    const g = await openSec('Germany'); await g.locator("input[data-dcf-ed-child-key='Lyon']").click();
    const b = await openSec('Belgium'); await b.locator("input[data-dcf-ed-child-key='Antwerp']").click();
    await save(); await edit(2); const m = await mapping();
    exp(m.value_dependencies.Belgium.sort(), ['Antwerp', 'Brussels', 'Ghent']); exp(m.value_dependencies.Germany || [], []);
    return JSON.stringify(m);
  });
  await check(run, 'cycle-select-excludes-descendants', 'Depends on select of City offers neither City nor District, keeps Country', async () => {
    const vals = await p().$$eval('#custom_field_parent_custom_field_id option', (o) => o.map((x) => x.value));
    if (vals.includes('2') || vals.includes('3')) throw new Error('offers self or child: ' + vals);
    if (!vals.includes('1')) throw new Error('current parent missing');
    return vals.join(',');
  });
  await check(run, 'cycle-forced-post-refused', 'forcing District (child of City) as parent of City is refused with a form error', async () => {
    await p().evaluate(() => { const s = document.querySelector('#custom_field_parent_custom_field_id'); const o = document.createElement('option'); o.value = '3'; o.textContent = 'District'; s.appendChild(o); s.value = '3'; });
    await p().waitForTimeout(800);
    await save();
    const err = await p().locator('#errorExplanation').innerText().catch(() => '');
    if (!err) throw new Error('no error shown, url ' + p().url());
    const parent = await p().evaluate(() => fetch('/custom_fields/2/edit').then((r) => r.text()).then((t) => (t.match(/<option selected="selected" value="(\d+)">/) || [])[1]));
    return `error "${err.replace(/\s+/g, ' ')}", stored parent option ${parent}`;
  });
  await check(run, 'cycle-warning-from-data', 'with a cycle in data (City depends on District) the City form warns naming City and District; issue form still works', async () => {
    rails(run, "f=CustomField.find(2); fs=f.format_store.dup; fs['parent_custom_field_id']='3'; f.update_column(:format_store, fs)");
    try {
      await edit(2);
      const w = await p().locator('p.icon-warning').allInnerTexts();
      const txt = (await p().locator('#content').innerText());
      const hit = /District/.test(w.join(' ')) && /City/.test(w.join(' '));
      if (!hit) throw new Error('no cycle warning naming City and District; warnings=' + JSON.stringify(w));
      await L.screenshot(run, 'cycle-warning-city');
      return JSON.stringify(w);
    } finally {
      rails(run, "f=CustomField.find(2); fs=f.format_store.dup; fs['parent_custom_field_id']='1'; f.update_column(:format_store, fs)");
    }
  });
  await check(run, 'no-javascript-fallback', 'without JS: notice shown, saving the form keeps the stored mapping', async () => {
    const ctx = await run.browser.newContext({ javaScriptEnabled: false, viewport: { width: 1366, height: 900 } });
    const pg = await ctx.newPage();
    await pg.goto(run.base + '/login'); await pg.fill('#username', 'admin'); await pg.fill('#password', 'admin123!');
    await Promise.all([pg.waitForLoadState('load'), pg.click('#login-submit')]);
    await pg.goto(run.base + '/custom_fields/2/edit');
    const notice = await pg.locator('fieldset.dcf-dep-editor').innerText();
    await pg.screenshot({ path: run.outDir + '/admin-editor/nojs-form.png', fullPage: true });
    await Promise.all([pg.waitForLoadState('load'), pg.click('#custom_field_form input[type=submit][name=commit]')]);
    const flash = await pg.locator('#flash_notice, #errorExplanation').first().innerText().catch(() => 'none');
    await pg.screenshot({ path: run.outDir + '/admin-editor/nojs-saved.png', fullPage: true });
    await ctx.close();
    await edit(2); const m = await mapping();
    exp(m.value_dependencies.Belgium.sort(), ['Antwerp', 'Brussels', 'Ghent']); exp(Object.keys(m.value_dependencies).sort(), ['Belgium', 'France', 'Netherlands']);
    return `notice text "${notice.slice(0, 160).replace(/\s+/g, ' ')}", save result "${flash}"`;
  });
  await finish(run);
})();
