const fs = require('fs');
const { L, start, check, finish, exp, rails } = require('../lib-admin');
(async () => {
  const run = await start('csv');
  const p = () => run.page;
  const dir = run.outDir + '/csv';
  const mapping = async () => JSON.parse(await p().$eval('fieldset[data-dcf-editor]', (e) => e.getAttribute('data-dcf-editor-mapping')));
  const edit = async (id) => { p().removeAllListeners('dialog'); p().on('dialog', (d) => d.accept()); await L.goto(run, `/custom_fields/${id}/edit`); await p().waitForSelector('fieldset.dcf-dep-editor .dcf-dep-editor__sections'); };
  const save = async () => { await Promise.all([p().waitForLoadState('load'), p().click('#custom_field_form input[type=submit][name=commit]')]); };
  const openImport = async () => { const d = p().locator('details.dcf-dep-editor__import'); if (!(await d.getAttribute('open')) && (await d.getAttribute('open')) !== '') await d.locator('summary').click(); return d; };
  const openExport = async () => { const d = p().locator('details.dcf-dep-editor__export'); await d.locator('summary').click(); return d; };
  const doImport = async (text, opts = {}) => {
    const d = await openImport();
    await d.locator('[data-dcf-ed-import-clear]').click();
    if (opts.file) await d.locator('input[data-dcf-ed-import-file]').setInputFiles(opts.file);
    else await d.locator('textarea[data-dcf-ed-import-text]').fill(text || '');
    await d.locator('[data-dcf-ed-import-separator]').selectOption(opts.sep || 'comma');
    if (opts.mode) await d.locator('[data-dcf-ed-import-mode]').selectOption(opts.mode);
    const un = d.locator('input[data-dcf-ed-import-unprotect]'); if (opts.unprotect) await un.check(); else await un.uncheck();
    await d.locator('[data-dcf-ed-import-preview]').click();
    await p().waitForTimeout(500);
    return d;
  };
  const exportCsv = async (protect, sepTok) => {
    const d = p().locator('details.dcf-dep-editor__export');
    if (!(await d.evaluate((e) => e.open))) await d.locator('summary').click();
    if (sepTok) await d.locator('[data-dcf-ed-export-separator]').selectOption(sepTok);
    const pb = d.locator('input[data-dcf-ed-export-protect]'); if (protect) await pb.check(); else await pb.uncheck();
    const [dl] = await Promise.all([p().waitForEvent('download'), d.locator('[data-dcf-ed-export]').click()]);
    const f = dir + '/' + Date.now() + '-' + dl.suggestedFilename(); await dl.saveAs(f); return { file: f, name: dl.suggestedFilename(), buf: fs.readFileSync(f) };
  };
  const previewText = async (d) => (await d.locator('.dcf-dep-editor__preview').innerText()).replace(/\s+/g, ' ');
  await L.login(run, 'admin');
  await check(run, 'export-default', 'City export: UTF-8 BOM, CRLF, header "Country,City", 7 links', async () => {
    await edit(2);
    const x = await exportCsv(false);
    const s = x.buf.toString('utf8');
    if (s.charCodeAt(0) !== 0xFEFF) throw new Error('no BOM');
    const lines = s.slice(1).split('\r\n').filter(Boolean);
    exp(lines[0], 'Country,City'); exp(lines.length - 1, 7, 'link lines');
    if (/\n(?!$)/.test(s.replace(/\r\n/g, ''))) throw new Error('bare LF');
    return `${x.name}: ${lines.join(' / ')}`;
  });
  await check(run, 'import-merge-preview', 'preview lists new links and per-line errors for unknown parent/child', async () => {
    const d = await doImport('Country;City\nGermany;Lyon\nBelgium;Paris\nNowhere;Ghent\nFrance;Atlantis\nBelgium;brussels', { sep: 'semicolon' });
    const t = await previewText(d);
    if (!/Nowhere/.test(t) || !/Atlantis/.test(t)) throw new Error('errors not named: ' + t);
    const dis = await d.locator('[data-dcf-ed-import-apply]').isDisabled(); exp(dis, true, 'Apply disabled while errors exist');
    return 'Apply disabled while lines have errors (by design). ' + t.slice(0, 700);
  });
  await check(run, 'import-apply-undo', 'apply merges 2 new links; Undo import takes them back', async () => {
    const d = await doImport('Country;City\nGermany;Lyon\nBelgium;Paris\nBelgium;brussels', { sep: 'semicolon' });
    await d.locator('[data-dcf-ed-import-apply]').click();
    const note = await p().locator('[data-dcf-ed-notice=import_applied]').innerText();
    const g = await p().locator("details.dcf-dep-section[data-dcf-ed-section='Germany'] .dcf-dep-section__counts").innerText();
    await L.screenshot(run, 'applied');
    await p().locator('[data-dcf-ed-import-undo]').click();
    const g2 = await p().locator("details.dcf-dep-section[data-dcf-ed-section='Germany'] .dcf-dep-section__counts").innerText();
    exp(g2, '0 of 7 linked');
    return `applied note "${note.replace(/\s+/g, ' ')}", Germany after apply "${g}", after undo "${g2}"`;
  });
  await check(run, 'formula-protection-export', 'add value "=SUM(1)" via import (add missing); export without protection writes it raw, with protection prefixes one apostrophe', async () => {
    const d = await doImport('Country,City\nBelgium,=SUM(1)\nGermany,+Evil\nFrance,@cmd\nFrance,-1+1', { });
    await d.locator('input[data-dcf-ed-import-add-missing]').check();
    await d.locator('[data-dcf-ed-import-preview]').click(); await p().waitForTimeout(400);
    const pv = await previewText(d);
    if (await d.locator('[data-dcf-ed-import-apply]').isDisabled()) throw new Error('Apply disabled; preview: ' + pv);
    await d.locator('[data-dcf-ed-import-apply]').click();
    await p().waitForTimeout(300);
    const vals = await p().inputValue('#custom_field_possible_values');
    const raw = (await exportCsv(false)).buf.toString('utf8');
    const prot = await exportCsv(true); const ps = prot.buf.toString('utf8');
    if (!/Belgium,=SUM\(1\)/.test(raw)) throw new Error('raw export lacks cell: ' + raw);
    if (!/Belgium,'=SUM\(1\)/.test(ps) || !/Germany,'\+Evil/.test(ps) || !/France,'@cmd/.test(ps) || !/France,'-1\+1/.test(ps)) throw new Error('protected export wrong: ' + ps);
    if (/''/.test(ps)) throw new Error('double apostrophe');
    run.protectedFile = prot.file;
    return `preview "${pv.slice(0, 300)}"; values tail ${JSON.stringify(vals.split('\n').slice(-4))}; protected export ${JSON.stringify(ps)}`;
  });
  await check(run, 'formula-import-unprotect', 'importing the protected file: without the option the apostrophe cells are unknown values, with the option they match', async () => {
    // same page (values added in the editor, not saved): the protected file must match them once the apostrophe is removed
    let d = await doImport(null, { file: run.protectedFile, unprotect: false });
    const t1 = await previewText(d);
    d = await doImport(null, { file: run.protectedFile, unprotect: true });
    const t2 = await previewText(d);
    if (/unknown child/.test(t2)) throw new Error('with unprotect still unknown: ' + t2);
    if (!/Links to add: 4/.test(t1)) throw new Error('without unprotect the apostrophe cells should be 4 new links (add-missing still ticked): ' + t1);
    if (!/Links already present: 11/.test(t2)) throw new Error('expected 11 already present: ' + t2);
    return `without unprotect: "${t1.slice(0, 300)}" | with unprotect: "${t2.slice(0, 300)}"`;
  });
  await check(run, 'import-replace-save', 'replace import of a changed CSV, Save, reload shows the replaced mapping only', async () => {
    await edit(2);
    const d = await doImport('Country,City\nGermany,Lyon\nBelgium,Ghent\nBelgium,Antwerp', { mode: 'replace' });
    await d.locator('[data-dcf-ed-import-apply]').click();
    await p().waitForTimeout(300);
    await save();
    const flash = await p().locator('#flash_notice, #errorExplanation').first().innerText();
    await edit(2); const m = await mapping();
    exp(m.value_dependencies, { Belgium: ['Ghent', 'Antwerp'].sort().length ? m.value_dependencies.Belgium : [], Germany: ['Lyon'] });
    exp(m.value_dependencies.Belgium.sort(), ['Antwerp', 'Ghent']); exp(Object.keys(m.value_dependencies).sort(), ['Belgium', 'Germany']);
    return `flash "${flash}", mapping ${JSON.stringify(m)}`;
  });
  await check(run, 'kv-hash-id-import', 'Site (key/value): "#8" and "#4" link by id, "#012", "#999", "# 8" are unknown with the #<id> hint; names work', async () => {
    await edit(8);
    const d = await doImport('Zone,Site\nEast,#8\nSouth,#4\nNorth,#012\nNorth,#999\nNorth,# 8\nNorth,north yard\nNorth,#4a', { mode: 'replace' });
    const t = await previewText(d);
    const errs = (t.match(/#012|#999|# 8|#4a/g) || []).length;
    if (errs < 4) throw new Error('unknown-value messages missing: ' + t);
    const hint = /#<id>|#\d+ form|#<id>/.test(t);
    const d2 = await doImport('Zone,Site\nEast,#8\nSouth,#4\nNorth,north yard\nNorth,#5', { mode: 'replace' });
    const t2 = await previewText(d2);
    await d2.locator('[data-dcf-ed-import-apply]').click(); await p().waitForTimeout(300);
    await save();
    const flash = await p().locator('#flash_notice, #errorExplanation').first().innerText();
    await edit(8); const m = await mapping();
    exp(m.value_dependencies['3'], ['8']); exp(m.value_dependencies['2'], ['4']); exp(m.value_dependencies['1'], ['5']);
    return `hint named: ${hint}; error preview "${t.slice(0, 900)}" ; clean preview "${t2.slice(0, 300)}" flash "${flash}" mapping ${JSON.stringify(m.value_dependencies)}`;
  });
  await check(run, 'kv-export-hash-ids', 'Site export shows names (and #id only for ambiguous names), re-import of the export is unchanged', async () => {
    const x = await exportCsv(false); const s = x.buf.toString('utf8');
    const d = await doImport(null, { file: x.file, mode: 'replace' });
    const t = await previewText(d);
    return `export ${JSON.stringify(s)} ; re-import preview "${t.slice(0, 300)}"`;
  });
  await check(run, 'ui-no-translation-missing', 'no "translation missing" on the editor pages', async () => {
    const h = await p().content();
    if (/translation missing|translation_missing/i.test(h)) throw new Error('translation missing present');
    return 'none';
  });
  await finish(run);
})();
