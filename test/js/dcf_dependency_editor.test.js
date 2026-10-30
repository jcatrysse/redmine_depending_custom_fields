'use strict';
// WP-25 (editor design 5.4 to 5.11, UD-16, UD-17, UD-20, QA-24): the editor
// DOM layer assets/javascripts/dcf_dependency_editor.js on the generated
// editor fixtures (each with its .redmine-5.1 variant where it matters),
// wrapped in core-like forms by test/js/support/editor_page.js.
const { test, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { performance } = require('node:perf_hooks');
const E = require('./support/editor_page');
const L = require('./support/large_list');

afterEach(() => E.closeAll());

const VARIANTS = [false, true];
const wire = (keys) => JSON.stringify(keys.map((key) => ({ key })));
const setJson = (root, name, value) => root.setAttribute(`data-dcf-editor-${name}`, JSON.stringify(value));
const BASE_OF = (p) => p.root.getAttribute('data-dcf-editor-base');

test('lazy sections: 100 summaries, bodies on open only, 200 rows per page, Show more moves focus (UD-20)', async () => {
  const parents = L.names(250, { prefix: 'P ' });
  const children = L.names(450, { prefix: 'C ', offset: 1000 });
  const p = await E.load('admin_list', {
    form: { values: children },
    tweak: (root) => {
      root.setAttribute('data-dcf-editor-parent-values', wire(parents));
      setJson(root, 'mapping', { value_dependencies: {}, default_value_dependencies: {} });
    }
  });
  assert.equal(p.sections().length, 100);
  assert.equal(p.root.querySelectorAll('.dcf-dep-section__body').length, 0);
  assert.equal(p.root.querySelectorAll('input[data-dcf-ed-child-key]').length, 0);
  const moreSections = p.root.querySelector('button[data-dcf-ed-more-sections]');
  assert.equal(moreSections.textContent, 'Show more (150 remaining)');
  assert.equal(moreSections.type, 'button');
  assert.equal(p.root.querySelectorAll('summary button, summary input, summary select').length, 0);

  const first = p.open(p.sections()[0]);
  p.open(first);
  assert.equal(first.querySelectorAll('.dcf-dep-section__body').length, 1, 'one body after two toggles');
  assert.equal(p.rows(first).length, 200);
  const moreRows = first.querySelector('button[data-dcf-ed-more-rows]');
  assert.equal(moreRows.textContent, 'Show more (250 remaining)');
  moreRows.click();
  assert.equal(p.rows(first).length, 400);
  assert.equal(p.document.activeElement, p.rows(first)[200]);
  p.close(first);
  assert.equal(first.querySelectorAll('.dcf-dep-section__body').length, 0);

  moreSections.click();
  assert.equal(p.sections().length, 200);
  assert.equal(p.document.activeElement, p.sections()[100].querySelector('summary'));
  assert.equal(moreSections.textContent, 'Show more (50 remaining)');
  moreSections.click();
  assert.equal(p.sections().length, 250);
  assert.equal(moreSections.hidden, true);
});

test('5,000 parents initial render bounded (UD-20, G6)', async () => {
  const parents = L.names(5000, { prefix: 'P ' });
  const children = L.names(2000, { prefix: 'C ', offset: 7000 });
  const links = {};
  parents.slice(0, 3000).forEach((pk, i) => { links[pk] = [children[i % 2000], children[(i * 7) % 2000]]; });
  const p = await E.load('admin_list', {
    noEditor: true,
    form: { values: children },
    tweak: (root) => {
      root.setAttribute('data-dcf-editor-parent-values', wire(parents));
      setJson(root, 'mapping', { value_dependencies: links, default_value_dependencies: {} });
    }
  });
  const source = E.editorSource();
  const t0 = performance.now();
  p.window.eval(source);
  const ms = performance.now() - t0;
  console.log(`DCF PERF editor init 5,000 parents x 2,000 children: ${ms.toFixed(1)} ms (budget 2,000)`);
  assert.equal(p.sections().length, 100);
  assert.equal(p.root.querySelectorAll('.dcf-dep-section__body, input[data-dcf-ed-child-key]').length, 0);
  assert.equal(p.root.querySelector('button[data-dcf-ed-more-sections]').textContent, 'Show more (4,900 remaining)');
  assert.ok(ms < 2000, `${ms} ms`);
});

test('single named control: editor controls are unnamed and the named set is unchanged', async () => {
  const p = await E.load('admin_list', { noEditor: true });
  const before = p.named();
  p.window.eval(E.editorSource());
  const germany = p.open(p.section('Germany'));
  p.tick(germany, 'Lyon');
  const filter = p.root.querySelector('input[data-dcf-ed-parent-filter]');
  filter.value = 'ger';
  p.fire(filter, 'input');
  p.clock.tick(200);
  assert.deepEqual(p.named(), before);
  assert.deepEqual(Array.from(p.root.querySelectorAll('[name]')).map((e) => e.name), ['custom_field[dependencies_json]']);
  assert.equal(p.root.querySelectorAll('[id]').length, 1);
  p.root.querySelectorAll('button').forEach((b) => assert.equal(b.type, 'button'));
  p.root.querySelectorAll('[data-dcf-editor-app] input, [data-dcf-editor-app] select').forEach((c) => {
    assert.ok(c.closest('label'), `${c.tagName} wrapped by its label`);
  });
});

test('untouched admin form posts an empty string, also when the browser pre-filled the input', async () => {
  for (const variant of VARIANTS) {
    const p = await E.load('admin_list', { variant, tweak: (root) => { root.querySelector('input').value = '{"value_dependencies":{}}'; } });
    assert.equal(p.input.value, '');
    const ev = p.submit();
    assert.equal(ev.defaultPrevented, false);
    assert.equal(p.input.value, '');
    assert.equal(p.editor().dirty, false);
  }
});

test('dirty flag: a tick writes the payload with the base 150 ms later and synchronously on submit', async () => {
  const p = await E.load('admin_list');
  const germany = p.open(p.section('Germany'));
  p.tick(germany, 'Lyon');
  assert.equal(p.input.value, '');
  p.clock.tick(149);
  assert.equal(p.input.value, '');
  p.clock.tick(1);
  const payload = p.payload();
  assert.equal(payload.base, BASE_OF(p));
  assert.equal(payload.version, 1);
  assert.equal(payload.source, 'editor');
  assert.deepEqual(payload.value_dependencies, { Belgium: ['Antwerp', 'Brussels'], France: ['Paris'], Germany: ['Lyon'] });
  assert.deepEqual(payload.default_value_dependencies, { Belgium: 'Brussels' });

  const q = await E.load('admin_list');
  const france = q.open(q.section('France'));
  q.tick(france, 'Paris', false);
  assert.equal(q.input.value, '');
  assert.equal(q.submit().defaultPrevented, false);
  assert.deepEqual(q.payload().value_dependencies, { Belgium: ['Antwerp', 'Brussels'] });
  assert.equal(q.editor().submitting, true);
});

test('failed-save fixture starts dirty and writes the payload at init (gap 1)', async () => {
  for (const variant of VARIANTS) {
    const p = await E.load('admin_list', { variant, tweak: (root) => root.setAttribute('data-dcf-editor-dirty', '1') });
    assert.equal(p.payload().base, BASE_OF(p));
    assert.deepEqual(p.payload().value_dependencies, { Belgium: ['Antwerp', 'Brussels'], France: ['Paris'] });
    assert.equal(p.editor().dirty, true);
  }
});

test('inert mode on truncated mapping and other bad attributes (QA-24): no write, no multipart switch, no fetch', async () => {
  const cases = [
    ['mapping', (r) => r.setAttribute('data-dcf-editor-mapping', '{"value_dependencies":{')],
    ['mapping array', (r) => r.setAttribute('data-dcf-editor-mapping', '[]')],
    ['base', (r) => r.setAttribute('data-dcf-editor-base', 'xyz')],
    ['parent values', (r) => r.setAttribute('data-dcf-editor-parent-values', '[{"label":"x"}]')],
    ['mode', (r) => r.setAttribute('data-dcf-editor-mode', 'other')],
    ['kind', (r) => r.setAttribute('data-dcf-editor-kind', 'tree')],
    ['max payload', (r) => r.setAttribute('data-dcf-editor-max-payload-bytes', '4 MiB')],
    ['max form', (r) => r.setAttribute('data-dcf-editor-max-form-bytes', '[1]')],
    ['selector', (r) => r.setAttribute('data-dcf-editor-parent-source', '#[')],
    ['conflict', (r) => r.setAttribute('data-dcf-editor-conflict-mapping', 'null')]
  ];
  for (const variant of VARIANTS) {
    for (const [name, tweak] of cases) {
      const p = await E.load('admin_list', { variant, tweak });
      const alerts = p.alerts();
      assert.equal(alerts.length, 1, name);
      assert.ok(alerts[0].classList.contains('flash') && alerts[0].classList.contains('error'), name);
      assert.equal(alerts[0].textContent, p.i18n.unavailable, name);
      assert.ok(!alerts[0].closest('[hidden]'), `${name}: visible`);
      assert.equal(p.form.getAttribute('enctype'), null, name);
      assert.equal(p.input.value, '', name);
      assert.equal(p.editor().inert, true, name);
      const select = p.document.querySelector('#custom_field_parent_custom_field_id');
      select.value = '9100050';
      p.fire(select, 'change');
      await E.flush();
      assert.equal(p.fetchCalls.length, 0, name);
      assert.equal(p.submit().defaultPrevented, false, name);
      assert.equal(p.input.value, '', name);
      assert.equal(p.fire(p.window, 'beforeunload').defaultPrevented, false, name);
    }
  }
  const broken = await E.load('admin_list', { tweak: (r) => r.setAttribute('data-dcf-editor-i18n', '{') });
  assert.equal(broken.root.querySelector('[role=alert]').textContent,
    'The dependency editor could not be started. Reload the page.');
});

test('inert project page keeps Save disabled; a working one enables it (submit gate, UD-16)', async () => {
  const bad = await E.load('project_list', { tweak: (r) => r.setAttribute('data-dcf-editor-mapping', '{') });
  assert.equal(bad.form.querySelector('[data-dcf-editor-submit]').disabled, true);
  assert.equal(bad.input.value, '');
  const good = await E.load('project_list');
  assert.equal(good.form.querySelector('[data-dcf-editor-submit]').disabled, false);
});

test('without the model: one console.warn, inert, hidden input untouched', async () => {
  const p = await E.load('admin_list', { noModel: true, tweak: (r) => { r.querySelector('input').value = 'x'; } });
  assert.equal(p.warns.length, 1);
  assert.match(p.warns[0], /DcfDependencyEditorModel/);
  assert.equal(p.input.value, 'x');
  assert.equal(p.form.getAttribute('enctype'), null);
  assert.equal(p.root.querySelector('[role=alert]').textContent, p.i18n.unavailable);
});

test('multipart switch after init only (UD-16), also after the /new AJAX re-render', async () => {
  for (const variant of VARIANTS) {
    const p = await E.load('admin_list', { variant, noEditor: true });
    assert.equal(p.form.getAttribute('enctype'), null);
    p.window.eval(E.editorSource());
    assert.equal(p.form.getAttribute('enctype'), 'multipart/form-data');
    assert.equal(p.root.querySelector('[data-dcf-editor-app]').hidden, false);
  }
  const project = await E.load('project_list');
  assert.equal(project.form.getAttribute('enctype'), 'multipart/form-data');

  const p = await E.load('admin_new');
  const content = p.document.getElementById('content');
  content.innerHTML = '<form id="custom_field_form" action="/custom_fields" method="post"><input name="custom_field[name]"></form>';
  await E.microtask();
  assert.equal(p.document.getElementById('custom_field_form').getAttribute('enctype'), null);
  const html = E.fixture('admin_new');
  content.innerHTML = `<form id="custom_field_form" action="/custom_fields" method="post">${html}</form>`;
  await E.microtask();
  const root = p.document.querySelector('[data-dcf-editor]');
  assert.ok(p.window.DcfDependencyEditor.get(root), 'initialized by the MutationObserver');
  assert.equal(p.document.getElementById('custom_field_form').getAttribute('enctype'), 'multipart/form-data');
});

test('load guard: a second inclusion keeps one instance and one beforeunload listener', async () => {
  let unload = 0;
  const p = await E.load('admin_list', {
    twice: true,
    before: (w) => {
      const add = w.addEventListener.bind(w);
      w.addEventListener = (type, fn, o) => { if (type === 'beforeunload') unload += 1; return add(type, fn, o); };
    }
  });
  assert.equal(unload, 1);
  assert.equal(p.root.querySelectorAll('.dcf-dep-editor__notices').length, 1);
  p.window.DcfDependencyEditor.init(p.document);
  assert.equal(p.root.querySelectorAll('.dcf-dep-editor__notices').length, 1);
});

test('pre-check block/allow per enctype: 4,194,304 bytes pass, 4,194,305 are blocked (QA-10)', async () => {
  const probe = await E.load('admin_list', { form: { values: E.LIST_VALUES.concat(['x']) } });
  const germany = probe.open(probe.section('Germany'));
  probe.tick(germany, 'x');
  probe.clock.tick(150);
  const overhead = Buffer.byteLength(probe.input.value) - 1;
  const at = async (bytes, enctype) => {
    const big = 'x'.repeat(bytes - overhead);
    const p = await E.load('admin_list', { form: { values: E.LIST_VALUES.concat([big]) } });
    const section = p.open(p.section('Germany'));
    p.tick(section, big);
    if (enctype) p.form.enctype = enctype;
    let reached = false;
    p.document.addEventListener('submit', () => { reached = true; });
    const ev = p.submit();
    return { p, ev, reached, size: Buffer.byteLength(p.input.value) };
  };
  const ok = await at(4194304);
  assert.equal(ok.size, 4194304);
  assert.equal(ok.ev.defaultPrevented, false);
  assert.equal(ok.reached, true);
  assert.equal(ok.p.alerts().length, 0);
  E.closeAll();

  const over = await at(4194305);
  assert.equal(over.size, 4194305);
  assert.equal(over.ev.defaultPrevented, true);
  assert.equal(over.reached, false, 'a blocked submit does not reach document listeners (rails-ujs)');
  const error = over.p.notice('too_large');
  assert.equal(error.getAttribute('role'), 'alert');
  assert.equal(error.getAttribute('tabindex'), '-1');
  assert.equal(error.textContent, over.p.t('too_large_to_send', { size: '4,194,305', limit: '4,194,304' }));
  assert.equal(over.p.document.activeElement, error);
  assert.equal(over.p.editor().submitting, false);
  assert.equal(over.p.fire(over.p.window, 'beforeunload').defaultPrevented, true, 'still warns after a blocked submit');
  E.closeAll();

  const url = await at(4194304, 'application/x-www-form-urlencoded');
  assert.equal(url.ev.defaultPrevented, true);
  assert.match(url.p.notice('form_too_large').textContent, /^This form is too large to be sent \(8,3\d\d,\d{3} bytes/);
  assert.match(url.p.notice('form_too_large').textContent, /at most 4,128,768 bytes/);
});

test('conflict panel actions: use mine, keep current, export mine (UD-17)', async () => {
  for (const variant of VARIANTS) {
    const p = await E.load('admin_conflict', { variant });
    const panel = p.root.querySelector('.dcf-dep-editor__conflict');
    assert.ok(panel.classList.contains('flash') && panel.classList.contains('warning'));
    assert.equal(panel.getAttribute('role'), 'alert');
    assert.equal(panel.querySelector('p').textContent, p.t('conflict', { only_mine: '1', only_current: '3' }));
    assert.deepEqual(Array.from(panel.querySelectorAll('button')).map((b) => [b.type, b.textContent]),
      [['button', 'Use my version'], ['button', 'Keep the current version'], ['button', 'Export my version (CSV)']]);
    assert.equal(p.input.value, '');
    assert.equal(p.editor().dirty, false);

    let blob = null;
    const revoked = [];
    p.window.URL.createObjectURL = (b) => { blob = b; return 'blob:x'; };
    p.window.URL.revokeObjectURL = (u) => { revoked.push(u); };
    panel.querySelector('[data-dcf-ed-export-mine]').click();
    assert.ok(blob, 'a Blob was downloaded');
    assert.deepEqual(revoked, [], 'the object URL outlives the click (late download start)');
    assert.equal(p.document.querySelectorAll('a[download]').length, 1);
    p.clock.tick(1000);
    assert.deepEqual(revoked, ['blob:x']);
    assert.equal(p.document.querySelectorAll('a[download]').length, 0);
    const bytes = Buffer.from(await blob.arrayBuffer());
    assert.deepEqual(Array.from(bytes.subarray(0, 3)), [0xef, 0xbb, 0xbf], 'UTF-8 BOM');
    assert.equal(bytes.subarray(3).toString('utf8'), 'Country,City\r\nGermany,Lyon\r\n');
    assert.equal(p.window.__dcfClicked, 'dependency-mapping.csv');
    assert.equal(p.input.value, '');

    panel.querySelector('[data-dcf-ed-use-mine]').click();
    assert.equal(p.root.querySelector('.dcf-dep-editor__conflict'), null);
    assert.equal(p.notice('mine_loaded').textContent, p.t('mine_loaded'));
    p.clock.tick(150);
    const payload = p.payload();
    assert.equal(payload.base, BASE_OF(p));
    assert.deepEqual(payload.value_dependencies, { Germany: ['Lyon'] });
    assert.deepEqual(payload.default_value_dependencies, { Germany: 'Lyon' });
    p.clock.tick(400);
    assert.equal(p.root.querySelector('[role=status]').textContent, p.t('mine_loaded'));

    const q = await E.load('admin_conflict', { variant });
    q.root.querySelector('[data-dcf-ed-keep-current]').click();
    assert.equal(q.root.querySelector('.dcf-dep-editor__conflict'), null);
    assert.equal(q.input.value, '');
    assert.equal(q.editor().dirty, false);
    assert.equal(q.submit().defaultPrevented, false);
    assert.equal(q.input.value, '');
  }
  // The locale separator normalized to ; , or TAB: ';' stays, core ro '.' is ','.
  for (const [sep, csv] of [[';', 'Country;City\r\nGermany;Lyon\r\n'], ['.', 'Country,City\r\nGermany,Lyon\r\n']]) {
    const c = await E.load('admin_conflict', { tweak: (r) => r.setAttribute('data-dcf-editor-csv-separator', sep) });
    let got = null;
    c.window.URL.createObjectURL = (b) => { got = b; return 'blob:y'; };
    c.window.URL.revokeObjectURL = () => {};
    c.root.querySelector('[data-dcf-ed-export-mine]').click();
    const bytes = Buffer.from(await got.arrayBuffer());
    assert.deepEqual(Array.from(bytes.subarray(0, 3)), [0xef, 0xbb, 0xbf], sep);
    assert.equal(bytes.subarray(3).toString('utf8'), csv, sep);
    assert.equal(c.window.__dcfClicked, 'dependency-mapping.csv');
  }
});

test('project fixture: always-submit, no base, conflict panel and use mine', async () => {
  const p = await E.load('project_list');
  const untouched = p.payload();
  assert.equal(untouched.base, undefined);
  assert.deepEqual(untouched.value_dependencies, { Belgium: ['Antwerp', 'Brussels'], France: ['Paris'] });
  assert.equal(p.editor().dirty, false);
  assert.equal(p.fire(p.window, 'beforeunload').defaultPrevented, false);

  const q = await E.load('project_list', {
    tweak: (r) => setJson(r, 'conflict-mapping', { value_dependencies: { Germany: ['Lyon'] }, default_value_dependencies: {},
                                                    source: 'editor', import: null })
  });
  assert.equal(q.root.querySelector('.dcf-dep-editor__conflict p').textContent, q.t('conflict', { only_mine: '1', only_current: '3' }));
  q.root.querySelector('[data-dcf-ed-use-mine]').click();
  q.clock.tick(150);
  assert.deepEqual(q.payload().value_dependencies, { Germany: ['Lyon'] });
  assert.equal(q.payload().base, undefined);
});

test('filters and views: parent filter, only without links, child views, Enter and Escape', async () => {
  const p = await E.load('admin_list');
  const filter = p.root.querySelector('input[data-dcf-ed-parent-filter]');
  assert.equal(filter.closest('label').textContent.trim(), p.t('filter_parents'));
  filter.value = 'BEL';
  p.fire(filter, 'input');
  p.clock.tick(149);
  assert.equal(p.sections().length, 3);
  p.clock.tick(1);
  assert.deepEqual(p.sections().map((d) => d.getAttribute('data-dcf-ed-section')), ['Belgium']);
  assert.equal(p.key(filter, 'Enter').defaultPrevented, true);
  p.clock.tick(400);
  assert.equal(p.root.querySelector('p[role=status][aria-live=polite]').textContent,
    p.root.querySelector('.dcf-dep-editor__status').textContent);
  assert.equal(p.key(filter, 'Escape').defaultPrevented, true);
  assert.equal(filter.value, '');
  assert.equal(p.sections().length, 3);
  assert.equal(p.key(filter, 'Escape').defaultPrevented, false);

  const only = p.root.querySelector('input[data-dcf-ed-only-unlinked]');
  only.checked = true;
  p.fire(only, 'change');
  assert.deepEqual(p.sections().map((d) => d.getAttribute('data-dcf-ed-section')), ['Germany']);
  only.checked = false;
  p.fire(only, 'change');

  const belgium = p.open(p.section('Belgium'));
  const view = belgium.querySelector('select[data-dcf-ed-child-view]');
  assert.equal(view.name, '');
  const keys = () => p.rows(belgium).map((b) => b.getAttribute('data-dcf-ed-child-key'));
  const show = (v) => { view.value = v; p.fire(view, 'change'); return keys(); };
  assert.deepEqual(show('linked'), ['Antwerp', 'Brussels']);
  assert.deepEqual(show('not_linked'), ['Paris', 'Lyon']);
  assert.deepEqual(show('unlinked'), ['Lyon']);
  assert.deepEqual(show('all'), ['Antwerp', 'Brussels', 'Paris', 'Lyon']);
  const childFilter = belgium.querySelector('input[data-dcf-ed-child-filter]');
  childFilter.value = 'par';
  p.fire(childFilter, 'input');
  p.clock.tick(150);
  assert.deepEqual(keys(), ['Paris']);
  assert.equal(belgium.querySelector('[data-dcf-ed-check-shown]').textContent, 'Check all shown (1)');
  childFilter.value = 'zzz';
  p.fire(childFilter, 'input');
  p.clock.tick(150);
  assert.equal(belgium.querySelector('.dcf-dep-section__rows').textContent, p.t('no_matches'));
  filter.value = 'nothing here';
  p.fire(filter, 'input');
  p.clock.tick(150);
  assert.equal(p.root.querySelector('.dcf-dep-editor__sections').textContent, p.t('no_matches'));
  assert.equal(p.input.value, '', 'filters never make the editor dirty');
});

test('child filters debounce per section; check shown, more rows and view act on the filter as typed', async () => {
  const p = await E.load('admin_list');
  const belgium = p.open(p.section('Belgium'));
  const france = p.open(p.section('France'));
  const keys = (d) => p.rows(d).map((b) => b.getAttribute('data-dcf-ed-child-key'));
  const typeInto = (d, text) => {
    const input = d.querySelector('input[data-dcf-ed-child-filter]');
    input.value = text;
    p.fire(input, 'input');
  };
  typeInto(belgium, 'par');
  p.clock.tick(100);
  typeInto(france, 'ly');
  p.clock.tick(150);
  assert.deepEqual(keys(belgium), ['Paris'], 'a filter in another section does not cancel this one');
  assert.deepEqual(keys(france), ['Lyon']);

  const germany = p.open(p.section('Germany'));
  typeInto(germany, 'ly');
  germany.querySelector('[data-dcf-ed-check-shown]').click();
  assert.deepEqual(keys(germany), ['Lyon']);
  p.clock.tick(150);
  assert.deepEqual(p.payload().value_dependencies.Germany, ['Lyon']);

  typeInto(belgium, 'br');
  const view = belgium.querySelector('select[data-dcf-ed-child-view]');
  view.value = 'not_linked';
  p.fire(view, 'change');
  assert.equal(belgium.querySelector('.dcf-dep-section__rows').textContent, p.t('no_matches'));
  p.clock.tick(150);
  assert.equal(belgium.querySelector('.dcf-dep-section__rows').textContent, p.t('no_matches'));

  const children = L.names(450, { prefix: 'C ', offset: 3000 });
  const q = await E.load('admin_list', { form: { values: children } });
  const b = q.open(q.section('Belgium'));
  const input = b.querySelector('input[data-dcf-ed-child-filter]');
  input.value = children[449];
  q.fire(input, 'input');
  b.querySelector('[data-dcf-ed-more-rows]').click();
  const shown = q.rows(b).map((r) => r.getAttribute('data-dcf-ed-child-key'));
  assert.ok(shown.length < 200, `more rows used the typed filter (${shown.length} rows)`);
  assert.ok(shown.includes(children[449]));
});

test('check all shown acts on unrendered rows and drops the default on uncheck', async () => {
  const children = L.names(450, { prefix: 'C ', offset: 3000 });
  const p = await E.load('admin_list', { form: { values: children } });
  const belgium = p.open(p.section('Belgium'));
  assert.equal(p.rows(belgium).length, 200);
  const check = belgium.querySelector('[data-dcf-ed-check-shown]');
  assert.equal(check.textContent, 'Check all shown (450)');
  check.click();
  p.clock.tick(150);
  assert.equal(p.payload().value_dependencies.Belgium.length, 450);
  assert.ok(p.rows(belgium).every((b) => b.checked));
  assert.equal(belgium.querySelector('.dcf-dep-section__counts').textContent, '450 of 450 linked');
  p.clock.tick(400);
  assert.equal(p.root.querySelector('[role=status]').textContent, '450 of 450 linked');

  const q = await E.load('admin_list');
  const b = q.open(q.section('Belgium'));
  b.querySelector('[data-dcf-ed-uncheck-shown]').click();
  q.clock.tick(150);
  assert.equal(q.payload().value_dependencies.Belgium, undefined);
  assert.equal(q.payload().default_value_dependencies.Belgium, undefined);
  assert.ok(b.querySelector('.dcf-dep-section__counts').classList.contains('dcf-dep-section__counts--none'));
});

test('counters, orphans notice and default summary on admin_list', async () => {
  for (const variant of VARIANTS) {
    const p = await E.load('admin_list', { variant });
    assert.equal(p.root.getAttribute('data-dcf-ed-orphans'), '1');
    assert.equal(p.notice('orphans').textContent, p.t('orphans', { count: '1' }));
    assert.equal(p.root.querySelector('.dcf-dep-editor__status').textContent,
      'Parent values shown: 3 of 3. Parent values without links: 1. Child values not linked to any parent value: 1.');
    const summary = p.section('Belgium').querySelector('summary');
    assert.equal(summary.querySelector('.dcf-dep-section__label').textContent, 'Belgium');
    assert.equal(summary.querySelector('.dcf-dep-section__counts').textContent, '2 of 4 linked');
    assert.equal(summary.querySelector('.dcf-dep-section__default').textContent, 'Default: Brussels');
    assert.ok(p.section('Germany').querySelector('.dcf-dep-section__counts--none'));
    assert.equal(p.root.querySelector('details.dcf-dep-editor__unlinked summary').textContent,
      'Child values not linked to any parent value (1)');
  }
});

test('per-parent default: disabled without links, enabled after a tick, multiple list box with Clear', async () => {
  const p = await E.load('admin_list');
  const germany = p.open(p.section('Germany'));
  const select = () => germany.querySelector('select[data-dcf-ed-default]');
  assert.equal(select().disabled, true);
  assert.equal(select().closest('label').textContent.trim().startsWith(p.t('default_value')), true);
  p.tick(germany, 'Lyon');
  assert.equal(select().disabled, false);
  assert.deepEqual(Array.from(select().options).map((o) => [o.value, o.textContent]), [['', '(no default)'], ['Lyon', 'Lyon']]);
  select().value = 'Lyon';
  p.fire(select(), 'change');
  assert.equal(germany.querySelector('.dcf-dep-section__default').textContent, 'Default: Lyon');
  p.clock.tick(150);
  assert.equal(p.payload().default_value_dependencies.Germany, 'Lyon');

  const multiple = p.document.querySelector('#custom_field_multiple');
  multiple.checked = true;
  p.fire(multiple, 'change');
  assert.equal(select().multiple, true);
  assert.equal(select().size, 5);
  assert.ok(germany.querySelector('button[data-dcf-ed-clear-default]'));
  p.clock.tick(150);
  assert.deepEqual(p.payload().default_value_dependencies, { Belgium: ['Brussels'], Germany: ['Lyon'] });
  germany.querySelector('button[data-dcf-ed-clear-default]').click();
  p.clock.tick(150);
  assert.deepEqual(p.payload().default_value_dependencies, { Belgium: ['Brussels'] });
});

test('inactive values carry a badge and keep their links; enumeration hint (admin_enumeration)', async () => {
  for (const variant of VARIANTS) {
    const p = await E.load('admin_enumeration', { variant });
    const keys = JSON.parse(p.root.getAttribute('data-dcf-editor-parent-values')).map((v) => v.key);
    const childKeys = JSON.parse(p.root.getAttribute('data-dcf-editor-child-values')).map((v) => v.key);
    const old = p.section(keys[2]);
    assert.equal(old.querySelector('summary .badge.badge-status-locked').textContent, 'inactive');
    const north = p.open(p.section(keys[0]));
    const retired = p.box(north, childKeys[2]);
    assert.equal(retired.closest('label').querySelector('.badge').textContent, 'inactive');
    assert.equal(p.notice('enumeration_hint').textContent, p.t('enumeration_hint'));
    const select = north.querySelector('select[data-dcf-ed-default]');
    assert.equal(select.multiple, true);
    p.tick(north, childKeys[2]);
    p.clock.tick(150);
    const payload = p.payload();
    assert.deepEqual(payload.value_dependencies[keys[2]], [Number(childKeys[2])]);
    assert.deepEqual(payload.value_dependencies[keys[0]], childKeys.map(Number));
    assert.deepEqual(payload.default_value_dependencies[keys[0]], [Number(childKeys[1])]);
  }
});

test('textarea rebuild after 300 ms keeps links of removed values (state superset)', async () => {
  const p = await E.load('admin_list');
  const textarea = p.document.querySelector('#custom_field_possible_values');
  textarea.value = 'Brussels\nParis\nLyon\nGhent';
  p.fire(textarea, 'input');
  p.clock.tick(299);
  assert.ok(p.section('Belgium').querySelector('summary').textContent.includes('2 of 4 linked'));
  p.clock.tick(1);
  assert.ok(p.section('Belgium').querySelector('summary').textContent.includes('1 of 4 linked'));
  assert.equal(p.input.value, '', 'a textarea edit alone is not dirty');
  textarea.value = 'Antwerp\nBrussels\nParis\nLyon\nGhent';
  p.fire(textarea, 'input');
  p.clock.tick(300);
  const belgium = p.open(p.section('Belgium'));
  assert.deepEqual(p.rows(belgium).map((b) => b.getAttribute('data-dcf-ed-child-key')), ['Antwerp', 'Brussels', 'Paris', 'Lyon', 'Ghent']);
  p.tick(belgium, 'Ghent');
  p.clock.tick(150);
  assert.deepEqual(p.payload().value_dependencies.Belgium, ['Antwerp', 'Brussels', 'Ghent']);
});

test('required warning live from the links and #custom_field_is_required', async () => {
  const p = await E.load('admin_list');
  const warning = p.root.querySelector('p[data-dcf-editor-required-warning]');
  assert.equal(warning.classList.contains('dcf-hidden'), false);
  const html = warning.innerHTML;
  const germany = p.open(p.section('Germany'));
  p.tick(germany, 'Lyon');
  assert.equal(warning.classList.contains('dcf-hidden'), true);
  p.tick(germany, 'Lyon', false);
  assert.equal(warning.classList.contains('dcf-hidden'), false);
  const required = p.document.querySelector('#custom_field_is_required');
  required.checked = false;
  p.fire(required, 'change');
  assert.equal(warning.classList.contains('dcf-hidden'), true);
  assert.equal(warning.innerHTML, html, 'the server markup is never rebuilt');
});

test('parent change fetch + notice cleared on revert; stale responses ignored; blank parent', async () => {
  const pending = new Map();
  const p = await E.load('admin_list', {
    fetch: (url) => {
      const d = E.deferred();
      pending.set(new URL(url).searchParams.get('custom_field_id'), d);
      return d.promise;
    }
  });
  const select = p.document.querySelector('#custom_field_parent_custom_field_id');
  const row = p.document.querySelector('[data-dcf-default-value-row]');
  select.value = '9100050';
  p.fire(select, 'change');
  assert.equal(p.fetchCalls.length, 1);
  const call = p.fetchCalls[0];
  assert.equal(call.url, 'http://redmine.test/dcf_dependency_editor/values?custom_field_id=9100050&type=IssueCustomField&kind=list');
  assert.doesNotMatch(call.url, /\.json|format=/);
  assert.deepEqual(JSON.parse(JSON.stringify(call.init.headers)), { 'X-Requested-With': 'XMLHttpRequest', Accept: 'application/json' });
  assert.equal(call.init.credentials, 'same-origin');
  assert.equal(p.root.getAttribute('aria-busy'), 'true');
  assert.equal(p.notice('loading').textContent, p.t('loading'));
  pending.get('9100050').resolve(E.response(200, { id: 9100050, name: 'Other', kind: 'list',
                                                  values: [{ key: 'Belgium' }, { key: 'Spain' }] }));
  await E.flush();
  assert.equal(p.root.getAttribute('aria-busy'), null);
  assert.deepEqual(p.sections().map((d) => d.getAttribute('data-dcf-ed-section')), ['Belgium', 'Spain']);
  assert.equal(p.notice('parent_changed').textContent, p.t('parent_changed', { count: '2' }));
  assert.equal(row.classList.contains('dcf-hidden'), true);
  p.clock.tick(150);
  assert.deepEqual(p.payload().value_dependencies, { Belgium: ['Antwerp', 'Brussels'] });

  select.value = '9100001';
  p.fire(select, 'change');
  assert.equal(p.fetchCalls.length, 1, 'the rendered parent needs no request');
  assert.equal(p.notice('parent_changed'), null);
  p.clock.tick(150);
  assert.deepEqual(p.payload().value_dependencies, { Belgium: ['Antwerp', 'Brussels'], France: ['Paris'] });

  // A -> B -> C with B answering last: only C is rendered.
  const c = p.document.createElement('option');
  c.value = '9100060';
  select.appendChild(c);
  select.value = '9100050';
  p.fire(select, 'change');
  select.value = '9100060';
  p.fire(select, 'change');
  pending.get('9100060').resolve(E.response(200, { id: '9100060', values: [{ key: 'Gamma' }] }));
  await E.flush();
  pending.get('9100050').resolve(E.response(200, { id: '9100050', values: [{ key: 'Late' }] }));
  await E.flush();
  assert.deepEqual(p.sections().map((d) => d.getAttribute('data-dcf-ed-section')), ['Gamma']);

  select.value = '';
  p.fire(select, 'change');
  p.clock.tick(150);
  assert.equal(p.input.value, '');
  assert.equal(row.classList.contains('dcf-hidden'), false);
  assert.equal(p.root.querySelector('[data-dcf-editor-placeholder]').classList.contains('dcf-hidden'), false);
  assert.equal(p.submit().defaultPrevented, false);
  assert.equal(p.input.value, '');
});

test('values fetch failures: 404, 403 with an empty body, a network error and a bad body give load_failed', async () => {
  const answers = [() => Promise.resolve(E.response(404, { error: 'not_found' })), () => Promise.resolve(E.response(403)),
    () => Promise.reject(new TypeError('network')), () => Promise.resolve(E.response(200, { id: '9100050', values: [{ label: 'x' }] })),
    () => Promise.resolve(E.response(200, { id: '1', values: [] }))];
  for (const answer of answers) {
    const p = await E.load('admin_list', { fetch: answer });
    const select = p.document.querySelector('#custom_field_parent_custom_field_id');
    select.value = '9100050';
    p.fire(select, 'change');
    await E.flush();
    const notice = p.notice('load_failed');
    assert.equal(notice.textContent, p.t('load_failed'));
    assert.equal(notice.getAttribute('role'), 'alert');
    p.clock.tick(150);
    assert.deepEqual(Object.keys(p.payload().value_dependencies), ['Belgium', 'France'], 'unpruned: every known parent key');
  }
});

test('cross-origin values URL gives no fetch and the load_failed notice (SP-15, gap 12)', async () => {
  for (const url of ['https://evil.example/x', '//evil.example/x', 'javascript:alert(1)', 'http://[']) {
    const p = await E.load('admin_list', { tweak: (r) => r.setAttribute('data-dcf-editor-values-url', url) });
    const select = p.document.querySelector('#custom_field_parent_custom_field_id');
    select.value = '9100050';
    p.fire(select, 'change');
    await E.flush();
    assert.equal(p.fetchCalls.length, 0, url);
    assert.equal(p.notice('load_failed').textContent, p.t('load_failed'), url);
    p.clock.tick(150);
    assert.ok(p.payload().value_dependencies.France, url);
  }
});

test('init with a restored parent select different from the rendered parent fetches at once', async () => {
  const d = E.deferred();
  const p = await E.load('admin_list', { form: { parent: '9100050' }, fetch: () => d.promise });
  assert.equal(p.fetchCalls.length, 1);
  assert.match(p.fetchCalls[0].url, /custom_field_id=9100050/);
  assert.equal(p.editor().dirty, true, 'a restored parent change marks dirty (contract-js-15)');
  d.resolve(E.response(200, { id: 9100050, name: 'Other', kind: 'list',
                              values: [{ key: 'Belgium' }, { key: 'Spain' }] }));
  await E.flush();
  assert.equal(p.notice('parent_changed').textContent, p.t('parent_changed', { count: '2' }));
  const payload = JSON.parse(p.input.value);
  assert.equal(payload.base, BASE_OF(p));
  assert.deepEqual(payload.value_dependencies, { Belgium: ['Antwerp', 'Brussels'] });
  assert.equal(p.submit().defaultPrevented, false);
  assert.deepEqual(JSON.parse(p.input.value).value_dependencies, { Belgium: ['Antwerp', 'Brussels'] });
});

test('format-switch cancel stops core handler; confirm empties the hidden input before core serializes', async () => {
  for (const answer of [false, true]) {
    let asked = 0;
    const p = await E.load('admin_list', { form: { formatEnabled: true }, confirm: () => { asked += 1; return answer; } });
    const $ = p.window.jQuery;
    const seen = [];
    $('#custom_field_field_format').change(() => seen.push($('#custom_field_form').serialize()));
    const germany = p.open(p.section('Germany'));
    p.tick(germany, 'Lyon');
    p.clock.tick(150);
    assert.notEqual(p.input.value, '');
    const format = p.document.querySelector('#custom_field_field_format');
    format.value = 'string';
    p.fire(format, 'change');
    assert.equal(asked, 1);
    if (answer) {
      assert.equal(seen.length, 1);
      assert.match(seen[0], /custom_field%5Bdependencies_json%5D=&/);
      assert.equal(format.value, 'string');
    } else {
      assert.equal(seen.length, 0, 'core handler not called');
      assert.equal(format.value, 'depending_list');
      assert.notEqual(p.input.value, '');
    }
  }
  const clean = await E.load('admin_list', { form: { formatEnabled: true }, confirm: () => assert.fail('no confirm when not dirty') });
  const format = clean.document.querySelector('#custom_field_field_format');
  format.value = 'string';
  clean.fire(format, 'change');
  assert.equal(clean.input.value, '');
});

test('beforeunload only when dirty, not submitting, warn-unsaved 1 and connected', async () => {
  const unload = (p) => p.fire(p.window, 'beforeunload').defaultPrevented;
  const p = await E.load('admin_list');
  assert.equal(unload(p), false, 'untouched');
  const germany = p.open(p.section('Germany'));
  p.tick(germany, 'Lyon');
  assert.equal(unload(p), true, 'dirty');
  p.submit();
  assert.equal(unload(p), false, 'submitting');
  const show = new p.window.Event('pageshow');
  Object.defineProperty(show, 'persisted', { value: true });
  p.window.dispatchEvent(show);
  assert.equal(unload(p), true, 'bfcache restore resets submitting');
  p.root.remove();
  assert.equal(unload(p), false, 'root removed');
  assert.equal(p.window.onbeforeunload, null);

  const off = await E.load('admin_list', { tweak: (r) => r.setAttribute('data-dcf-editor-warn-unsaved', '0') });
  off.tick(off.open(off.section('Germany')), 'Lyon');
  assert.equal(unload(off), false, 'preference off');
});

test('new enumeration field: save first, no sections, hidden input stays empty', async () => {
  const p = await E.load('admin_new', {
    form: { values: null, format: 'depending_enumeration', parent: '9100001' },
    tweak: (r) => {
      r.setAttribute('data-dcf-editor-kind', 'enumeration');
      r.setAttribute('data-dcf-editor-child-values', '[]');
      r.setAttribute('data-dcf-editor-dirty', '1');
      r.removeAttribute('data-dcf-editor-values-source');
      r.removeAttribute('data-dcf-editor-allow-add-values');
    }
  });
  assert.equal(p.notice('save_first').textContent, p.t('enumeration_save_first'));
  assert.equal(p.sections().length, 0);
  assert.equal(p.input.value, '');
  p.submit();
  assert.equal(p.input.value, '');
});

test('empty states: no parent values and no child values', async () => {
  const p = await E.load('admin_list', { tweak: (r) => r.setAttribute('data-dcf-editor-parent-values', '[]') });
  assert.equal(p.root.querySelector('.dcf-dep-editor__sections em.info').textContent, p.t('no_parent_values'));
  const q = await E.load('admin_list', { form: { values: [] } });
  assert.equal(q.root.querySelector('.dcf-dep-editor__sections em.info').textContent, q.t('no_child_values'));
});

test('tricky values render as text only; no element from markup; payload keeps __proto__ (QA-11)', async () => {
  const data = JSON.parse(fs.readFileSync(require('node:path').join(__dirname, 'fixtures', 'value_options.json'), 'utf8'));
  const keys = data.list.map((v) => v.key);
  const p = await E.load('admin_list', {
    form: { values: keys },
    tweak: (r) => {
      r.setAttribute('data-dcf-editor-parent-values', JSON.stringify(data.list));
      setJson(r, 'mapping', { value_dependencies: {}, default_value_dependencies: {} });
    }
  });
  assert.equal(p.root.querySelectorAll('script, img, b').length, 0);
  assert.deepEqual(p.sections().map((d) => d.querySelector('.dcf-dep-section__label').textContent), keys);
  const proto = p.open(p.section('__proto__'));
  assert.deepEqual(p.rows(proto).map((b) => b.closest('label').textContent.trim()), keys.map((k) => k.trim()));
  p.tick(proto, '__proto__');
  p.tick(proto, 'a]');
  p.tick(proto, '"><script>alert(1)</script>');
  p.clock.tick(150);
  const vd = JSON.parse(p.input.value).value_dependencies;
  assert.deepEqual(Object.keys(vd), ['__proto__']);
  assert.deepEqual(vd.__proto__, ['a]', '"><script>alert(1)</script>', '__proto__']);
  assert.equal(p.root.querySelectorAll('script, img').length, 0);
  assert.doesNotMatch(E.editorSource(), /innerHTML|outerHTML|insertAdjacentHTML|document\.write|\beval\(|new Function/);
});

test('JS notices prepend the warning sprite only with createSVGIcon and #icon-copy-source (UX-10)', async () => {
  const plain = await E.load('admin_list');
  assert.equal(plain.notice('orphans').querySelector('svg'), null);
  const spriteStub = (w) => {
    const holder = w.document.createElement('div');
    holder.id = 'icon-copy-source';
    holder.appendChild(w.document.createElementNS('http://www.w3.org/2000/svg', 'svg'));
    w.document.body.appendChild(holder);
    w.createSVGIcon = (name) => {
      const svg = w.document.createElementNS('http://www.w3.org/2000/svg', 'svg');
      svg.setAttribute('class', 's18 icon-svg');
      svg.setAttribute('data-icon', name);
      return svg;
    };
  };
  const sprite = await E.load('admin_list', { before: spriteStub });
  assert.ok(sprite.notice('orphans').querySelector('svg.icon-svg'));
  assert.equal(sprite.notice('orphans').textContent, sprite.t('orphans', { count: '1' }));
  // The sprite follows core notice_icon: notice is 'checked', warning and error 'warning' (WP-26 review round 2).
  assert.equal(sprite.notice('orphans').querySelector('svg').getAttribute('data-icon'), 'warning');
  const bad = preview(sprite, 'Nowhere,Paris', { header: 'no' });
  assert.equal(bad.preview.querySelector('.flash.error > svg').getAttribute('data-icon'), 'warning');
  preview(sprite, 'Germany,Lyon', { header: 'no' }).apply.click();
  const applied = sprite.notice('import_applied');
  assert.ok(applied.classList.contains('notice'));
  assert.deepEqual(Array.from(applied.querySelectorAll('svg'), (svg) => svg.getAttribute('data-icon')), ['checked']);
  assert.equal(applied.firstChild.tagName.toLowerCase(), 'svg');

  // The UD-17 conflict panel is a div.flash.warning too.
  const panelOf = (q) => q.root.querySelector('.dcf-dep-editor__conflict');
  const conflict = await E.load('admin_conflict');
  assert.equal(panelOf(conflict).querySelectorAll('svg').length, 0);
  const conflictSprite = await E.load('admin_conflict', { before: spriteStub });
  assert.equal(panelOf(conflictSprite).querySelectorAll('svg').length, 1);
  assert.equal(panelOf(conflictSprite).firstChild.getAttribute('class'), 's18 icon-svg');
  assert.equal(panelOf(conflictSprite).querySelector('p').textContent,
    conflictSprite.t('conflict', { only_mine: '1', only_current: '3' }));
  assert.equal(panelOf(conflictSprite).firstChild.getAttribute('data-icon'), 'warning');
  conflictSprite.root.querySelector('[data-dcf-ed-use-mine]').click();
  assert.equal(conflictSprite.notice('mine_loaded').querySelector('svg').getAttribute('data-icon'), 'checked');
});

test('collapse all and one polite live region', async () => {
  const p = await E.load('admin_list');
  p.open(p.section('Belgium'));
  p.open(p.section('France'));
  p.root.querySelector('button[data-dcf-ed-collapse-all]').click();
  assert.equal(p.root.querySelectorAll('.dcf-dep-section__body').length, 0);
  assert.ok(p.sections().every((d) => !d.open));
  assert.equal(p.root.querySelectorAll('[role=status]').length, 1);
  assert.ok(p.root.querySelector('[role=status]').classList.contains('hidden-for-sighted'));
});

// ---------------------------------------------------------------- WP-26 import and export
// Editor design 6.4 to 6.8 (UD-18, UD-19, gap 12, FM-25): the import and
// export panels of the DOM layer on the generated fixtures.

function panels(p) {
  const imp = p.root.querySelector('details.dcf-dep-editor__import');
  const exp = p.root.querySelector('details.dcf-dep-editor__export');
  const q = (s) => (imp ? imp.querySelector(s) : null);
  const x = (s) => (exp ? exp.querySelector(s) : null);
  return {
    imp,
    exp,
    text: q('textarea[data-dcf-ed-import-text]'),
    file: q('input[data-dcf-ed-import-file]'),
    fileInfo: q('.dcf-dep-editor__file-info'),
    separator: q('select[data-dcf-ed-import-separator]'),
    header: q('select[data-dcf-ed-import-header]'),
    mode: q('select[data-dcf-ed-import-mode]'),
    addMissing: q('input[data-dcf-ed-import-add-missing]'),
    unprotect: q('input[data-dcf-ed-import-unprotect]'),
    previewButton: q('button[data-dcf-ed-import-preview]'),
    apply: q('button[data-dcf-ed-import-apply]'),
    clear: q('button[data-dcf-ed-import-clear]'),
    preview: q('.dcf-dep-editor__preview'),
    exportSeparator: x('select[data-dcf-ed-export-separator]'),
    protect: x('input[data-dcf-ed-export-protect]'),
    exportButton: x('button[data-dcf-ed-export]')
  };
}

// Pastes +text+, sets the options (select values, checkboxes) and clicks Preview.
function preview(p, text, opts) {
  const o = opts || {};
  const ui = panels(p);
  ui.imp.open = true;
  ui.text.value = text;
  p.fire(ui.text, 'input');
  [['separator', 'separator'], ['header', 'header'], ['mode', 'mode']].forEach(([key, el]) => {
    if (o[key] !== undefined) {
      ui[el].value = o[key];
      p.fire(ui[el], 'change');
    }
  });
  ['addMissing', 'unprotect'].forEach((key) => {
    if (o[key] !== undefined) {
      ui[key].checked = o[key];
      p.fire(ui[key], 'change');
    }
  });
  ui.previewButton.click();
  return ui;
}

const summaryText = (ui, key) => {
  const li = ui.preview.querySelector(`li[data-dcf-ed-summary="${key}"]`);
  return li ? li.textContent : null;
};
const errorItems = (ui) => Array.from(ui.preview.querySelectorAll('.flash.error li')).map((li) => li.textContent);
const tableRows = (ui) => Array.from(ui.preview.querySelectorAll('table.list tbody tr'))
  .map((tr) => Array.from(tr.children).map((td) => td.textContent));
const fileOf = (p, parts, name) => new p.window.File(parts.map((x) => (typeof x === 'number' ? Uint8Array.of(x) : x)), name || 'links.csv');
async function chooseFile(p, file) {
  const ui = panels(p);
  ui.imp.open = true;
  Object.defineProperty(ui.file, 'files', { value: file ? [file] : [], configurable: true });
  p.fire(ui.file, 'change');
  await E.flush();
  await E.flush();
  return ui;
}

test('import and export panels: placement, markup, defaults, unnamed controls (editor design 6.8)', async () => {
  for (const variant of VARIANTS) {
    const p = await E.load('admin_list', { variant, noEditor: true });
    const named = p.named();
    p.window.eval(E.editorSource());
    const body = p.root.querySelector('.dcf-dep-editor__body');
    assert.deepEqual(Array.from(body.children).map((n) => n.className || n.tagName),
      ['dcf-dep-editor__toolbar', 'dcf-dep-editor__status', 'dcf-dep-editor__sections', 'BUTTON', 'dcf-dep-editor__unlinked',
        'dcf-dep-editor__panel dcf-dep-editor__import', 'dcf-dep-editor__panel dcf-dep-editor__export']);
    const ui = panels(p);
    assert.equal(ui.imp.hidden, false);
    assert.equal(ui.imp.open, false);
    assert.equal(ui.imp.querySelector('summary').textContent, p.t('import_title'));
    assert.equal(ui.imp.querySelector('p > em.info').textContent, p.t('import_help'));
    assert.equal(ui.text.getAttribute('rows'), '8');
    assert.equal(ui.text.getAttribute('spellcheck'), 'false');
    assert.equal(ui.text.closest('label').textContent.trim(), p.t('import_paste'));
    assert.equal(ui.file.type, 'file');
    assert.equal(ui.file.getAttribute('accept'), '.csv,.txt,text/csv,text/plain');
    assert.ok(ui.file.closest('label').textContent.startsWith(p.t('import_file')));
    const options = (select) => Array.from(select.options).map((o) => [o.value, o.textContent]);
    assert.deepEqual(options(ui.separator), [['auto', p.t('auto')], ['semicolon', p.t('semicolon')], ['comma', p.t('comma')],
      ['tab', p.t('tab')]]);
    assert.deepEqual(options(ui.header), [['auto', p.t('auto')], ['yes', p.t('yes')], ['no', p.t('no')]]);
    assert.deepEqual(options(ui.mode), [['merge', p.t('mode_merge')], ['replace', p.t('mode_replace')]]);
    assert.deepEqual([ui.separator.value, ui.header.value, ui.mode.value], ['auto', 'auto', 'merge']);
    assert.equal(ui.separator.closest('label').textContent.startsWith(p.t('separator')), true);
    assert.equal(ui.header.closest('label').textContent.startsWith(p.t('import_header')), true);
    assert.equal(ui.mode.closest('label').textContent.startsWith(p.t('import_mode')), true);
    assert.equal(ui.separator.closest('p').classList.contains('dcf-dep-editor__options'), true);
    assert.deepEqual([ui.addMissing.checked, ui.unprotect.checked], [false, false]);
    assert.equal(ui.addMissing.closest('label').textContent.trim(), p.t('add_missing'));
    assert.equal(ui.unprotect.closest('label').textContent.trim(), p.t('unprotect'));
    assert.deepEqual([ui.previewButton, ui.apply, ui.clear].map((b) => [b.type, b.textContent, b.disabled]),
      [['button', p.t('preview'), false], ['button', p.t('apply'), true], ['button', p.t('clear'), false]]);
    assert.equal(ui.preview.getAttribute('role'), 'region');
    assert.equal(ui.preview.children.length, 0);
    assert.equal(ui.exp.querySelector('summary').textContent, p.t('export_title'));
    assert.equal(ui.exp.querySelector('p > em.info').textContent, p.t('export_help'));
    assert.deepEqual(options(ui.exportSeparator), [['comma', p.t('comma')], ['semicolon', p.t('semicolon')], ['tab', p.t('tab')]]);
    assert.equal(ui.exportSeparator.value, 'comma');
    assert.equal(ui.protect.checked, false);
    assert.equal(ui.protect.closest('label').textContent.trim(), p.t('protect'));
    assert.deepEqual([ui.exportButton.type, ui.exportButton.textContent], ['button', p.t('export')]);
    assert.deepEqual(p.named(), named);
    assert.deepEqual(Array.from(p.root.querySelectorAll('[name]')).map((e) => e.name), ['custom_field[dependencies_json]']);
    assert.equal(p.root.querySelectorAll('[id], [form]').length, 1);
    p.root.querySelectorAll('[data-dcf-editor-app] input, [data-dcf-editor-app] select, [data-dcf-editor-app] textarea')
      .forEach((c) => assert.ok(c.closest('label'), `${c.tagName} wrapped by its label`));
    p.root.querySelectorAll('button').forEach((b) => assert.equal(b.type, 'button'));
    assert.equal(p.root.querySelectorAll('summary button, summary input, summary select').length, 0);
    assert.equal(p.root.querySelectorAll('[data-dcf-blank], [data-dcf-required-none]').length, 0);
  }
});

test('gap 12 (FM-25): Add missing child values only on the admin form for list children', async () => {
  for (const variant of VARIANTS) {
    for (const name of ['project_list', 'project_enumeration', 'admin_enumeration']) {
      const p = await E.load(name, { variant });
      assert.ok(panels(p).imp, name);
      assert.equal(p.root.querySelector('[data-dcf-ed-import-add-missing]'), null, `${name} ${variant}`);
    }
    const admin = await E.load('admin_list', { variant });
    assert.ok(admin.root.querySelector('input[type=checkbox][data-dcf-ed-import-add-missing]'));
  }
  const tampered = await E.load('project_list', { tweak: (r) => r.setAttribute('data-dcf-editor-allow-add-values', '1') });
  assert.equal(tampered.root.querySelector('[data-dcf-ed-import-add-missing]'), null);
  const noAttr = await E.load('admin_list', { tweak: (r) => r.removeAttribute('data-dcf-editor-allow-add-values') });
  assert.equal(noAttr.root.querySelector('[data-dcf-ed-import-add-missing]'), null);
});

test('panels are hidden without parent or child values, with a blank parent, while loading, and absent when inert', async () => {
  const hidden = (p) => {
    const ui = panels(p);
    return !!ui.imp && (ui.imp.hidden || !!ui.imp.closest('[hidden]')) && (ui.exp.hidden || !!ui.exp.closest('[hidden]'));
  };
  assert.equal(hidden(await E.load('admin_list', { tweak: (r) => r.setAttribute('data-dcf-editor-parent-values', '[]') })), true);
  assert.equal(hidden(await E.load('admin_list', { form: { values: [] } })), true);
  assert.equal(hidden(await E.load('admin_new')), true);
  const p = await E.load('admin_list');
  assert.equal(hidden(p), false);
  const select = p.document.querySelector('#custom_field_parent_custom_field_id');
  select.value = '9100050';
  p.fire(select, 'change');
  assert.equal(hidden(p), true, 'while the values load');
  const inert = await E.load('admin_list', { tweak: (r) => r.setAttribute('data-dcf-editor-mapping', '{') });
  assert.equal(inert.root.querySelector('.dcf-dep-editor__panel, [data-dcf-ed-import-text]'), null);
  const p2 = await E.load('admin_list');
  p2.open(p2.section('Belgium'));
  panels(p2).imp.open = true;
  p2.root.querySelector('button[data-dcf-ed-collapse-all]').click();
  assert.equal(panels(p2).imp.open, true, 'collapse all leaves the panels');
});

test('preview: counts, header warning with its cells, separator name, first 20 rows with status, Apply enabled', async () => {
  for (const variant of VARIANTS) {
    const p = await E.load('admin_list', { variant });
    const ui = preview(p, 'Country,City\nBelgium,Paris\nGermany,Lyon\nBelgium,Antwerp\nBelgium,Paris');
    assert.equal(ui.preview.querySelectorAll('.flash.error').length, 0);
    assert.equal(p.alerts().length, 0);
    const warning = ui.preview.querySelector('.flash.warning');
    assert.equal(warning.textContent, p.t('header_skipped', { cells: 'Country, City' }));
    assert.equal(summaryText(ui, 'lines'), p.t('lines', { count: '4' }));
    assert.equal(summaryText(ui, 'to_add'), p.t('to_add', { count: '2' }));
    assert.equal(summaryText(ui, 'existing'), p.t('existing', { count: '1' }));
    assert.equal(summaryText(ui, 'to_remove'), p.t('to_remove', { count: '0' }));
    assert.equal(summaryText(ui, 'duplicates'), p.t('duplicates', { count: '1' }));
    assert.equal(summaryText(ui, 'separator_used'), p.t('separator_used', { name: p.t('comma') }));
    assert.equal(summaryText(ui, 'new_values'), null, 'only with Add missing child values');
    assert.equal(summaryText(ui, 'decoded_as'), null);
    const table = ui.preview.querySelector('table.list');
    assert.equal(table.querySelector('caption').textContent, p.t('preview_rows'));
    assert.deepEqual(Array.from(table.querySelectorAll('thead th')).map((th) => th.textContent), ['Country', 'City', p.t('status')]);
    assert.deepEqual(tableRows(ui), [['Belgium', 'Paris', p.t('status_new')], ['Germany', 'Lyon', p.t('status_new')],
      ['Belgium', 'Antwerp', p.t('status_existing')]]);
    assert.equal(ui.apply.disabled, false);
    assert.equal(p.input.value, '', 'a preview changes nothing');
    assert.equal(p.root.querySelectorAll('[role=status]').length, 1);
  }
  const children = L.names(30, { prefix: 'C ', offset: 500 });
  const q = await E.load('admin_list', { form: { values: children } });
  const lines = children.slice(0, 25).map((c) => `Belgium;${c}`).join('\n');
  const ui = preview(q, lines, { separator: 'semicolon', header: 'no' });
  assert.equal(tableRows(ui).length, 20);
  assert.equal(summaryText(ui, 'separator_used'), q.t('separator_used', { name: q.t('semicolon') }));
  const tab = preview(q, `Belgium\t${children[0]}`, { separator: 'auto' });
  assert.equal(summaryText(tab, 'separator_used'), q.t('separator_used', { name: q.t('tab') }));
  const nothing = preview(q, '\n\n');
  assert.equal(nothing.preview.querySelector('em.info').textContent, q.t('nothing'));
  assert.equal(nothing.apply.disabled, true);
});

test('preview errors: role=alert box with line errors, 200 shown and the rest counted; markup cells stay text', async () => {
  const p = await E.load('admin_list');
  const cells = ['"><script>alert(1)</script>', '</script>', '<img src=x onerror=alert(1)>', '&amp;', 'a$&b %{count}'];
  const ui = preview(p, cells.map((c) => `"${c.replace(/"/g, '""')}";Paris`).join('\n'), { header: 'no' });
  const box = ui.preview.querySelector('.flash.error');
  assert.equal(box.getAttribute('role'), 'alert');
  assert.equal(box.querySelector('p').textContent, p.t('errors_intro'));
  assert.deepEqual(errorItems(ui), cells.map((c, i) => p.t('err_unknown_parent', { line: String(i + 1), value: c })));
  assert.equal(p.root.querySelectorAll('script, img').length, 0);
  assert.equal(ui.apply.disabled, true);
  assert.equal(ui.preview.querySelector('table'), null);

  const many = preview(p, 'Nowhere;Paris\n'.repeat(250), { header: 'no' });
  assert.equal(many.preview.querySelectorAll('.flash.error ul > li').length, 200);
  assert.equal(many.preview.querySelector('.flash.error > p:last-child').textContent, p.t('more_errors', { count: '50' }));
  const long = preview(p, `${'x'.repeat(5000)};Paris`, { header: 'no' });
  assert.equal(errorItems(long)[0], p.t('err_unknown_parent', { line: '1', value: `${'x'.repeat(200)}\u2026` }));
  const longHeader = preview(p, `${'x'.repeat(5000)};City\nBelgium;Paris`, { header: 'auto' });
  assert.equal(longHeader.preview.querySelector('.flash.warning').textContent,
    p.t('header_skipped', { cells: `${'x'.repeat(200)}\u2026, City` }));
  const columns = preview(p, 'Belgium;Paris;Lyon\n"open', { header: 'no', separator: 'semicolon' });
  assert.deepEqual(errorItems(columns), [p.t('err_columns', { line: '1', count: '3' }), p.t('err_unterminated_quote', { line: '2' })]);
  const huge = preview(p, 'Belgium;Paris\n'.repeat(200001));
  assert.deepEqual(errorItems(huge), [p.t('err_too_many_lines', { max: '200,000' })]);
  assert.equal(huge.preview.querySelector('.dcf-dep-editor__summary'), null, 'no counts after a cap error');
  // Header yes with a bad quote in the first cell: the warning still names that cell.
  const badHeader = preview(p, '"Country"x,City\nBelgium,Paris', { header: 'yes', separator: 'auto' });
  assert.deepEqual([errorItems(badHeader), badHeader.preview.querySelector('.flash.warning').textContent],
    [[], p.t('header_skipped', { cells: 'Country' })]);
  // Separator auto with nothing found takes the locale separator.
  const semi = await E.load('admin_list', { tweak: (r) => r.setAttribute('data-dcf-editor-csv-separator', ';') });
  const semiUi = preview(semi, 'Belgium;Paris;Lyon', { header: 'no' });
  assert.deepEqual(errorItems(semiUi), [semi.t('err_columns', { line: '1', count: '3' })]);
  assert.equal(summaryText(semiUi, 'separator_used'), semi.t('separator_used', { name: semi.t('semicolon') }));
  // An active and an inactive enumeration with the same name are ambiguous (UD-19).
  const twins = await E.load('admin_enumeration', { tweak: (r) => setJson(r, 'parent-values', [{ key: '9200001', label: 'North' },
    { key: '9200011', label: 'North', active: false }, { key: '9200002', label: 'South' }]) });
  const twinUi = preview(twins, 'North,Alpha\nSouth,Alpha', { header: 'no' });
  assert.deepEqual(errorItems(twinUi), [twins.t('err_ambiguous_parent', { line: '1', value: 'North' })]);
  assert.equal(twinUi.apply.disabled, true);
});

test('apply: links, source import, import meta, dirty, collapsed panel, notice with Undo, announcement; nothing sent', async () => {
  const p = await E.load('admin_list');
  let submits = 0;
  p.form.addEventListener('submit', () => { submits += 1; });
  const before = Array.from(new p.window.FormData(p.form).entries());
  const required = p.root.querySelector('p[data-dcf-editor-required-warning]');
  assert.equal(required.classList.contains('dcf-hidden'), false, 'Germany has no link yet');
  const ui = preview(p, 'Germany,Lyon\nBelgium,Paris\nBelgium,Antwerp', { header: 'no' });
  assert.equal(required.classList.contains('dcf-hidden'), false, 'a preview changes nothing');
  ui.apply.click();
  assert.equal(required.classList.contains('dcf-hidden'), true, 'the required warning follows the import');
  assert.equal(ui.imp.open, false);
  assert.equal(ui.preview.children.length, 0);
  assert.equal(ui.apply.disabled, true);
  const notice = p.notice('import_applied');
  const text = p.t('applied', { added: '2', removed: '0' });
  assert.ok(notice.textContent.startsWith(text));
  assert.ok(notice.classList.contains('flash'));
  const undo = notice.querySelector('button[data-dcf-ed-import-undo]');
  assert.deepEqual([undo.type, undo.textContent], ['button', p.t('undo')]);
  assert.equal(p.editor().dirty, true);
  p.clock.tick(150);
  const payload = p.payload();
  assert.deepEqual([payload.source, payload.import, payload.base], ['import', { mode: 'merge', rows: 3 }, BASE_OF(p)]);
  assert.deepEqual(payload.value_dependencies, { Belgium: ['Antwerp', 'Brussels', 'Paris'], France: ['Paris'], Germany: ['Lyon'] });
  assert.ok(p.section('Germany').querySelector('.dcf-dep-section__counts').textContent.startsWith('1 of 4'));
  p.clock.tick(400);
  assert.equal(p.root.querySelector('[role=status]').textContent, text);
  assert.equal(p.fetchCalls.length, 0);
  assert.equal(submits, 0);
  const after = Array.from(new p.window.FormData(p.form).entries());
  const changed = before.filter((pair, i) => JSON.stringify(pair) !== JSON.stringify(after[i])).map((pair) => pair[0]);
  assert.deepEqual(changed, ['custom_field[dependencies_json]']);
  assert.equal(after.length, before.length);
  assert.equal(p.fire(p.window, 'beforeunload').defaultPrevented, true);
});

test('undo restores state, source, import meta, the dirty flag and the textarea; a later edit withdraws it', async () => {
  for (const variant of VARIANTS) {
    const p = await E.load('admin_list', { variant });
    const pre = M_payload(p);
    const values = p.document.querySelector('#custom_field_possible_values');
    const valuesBefore = values.value;
    const events = [];
    ['input', 'change'].forEach((type) => values.addEventListener(type, () => events.push(type)));
    const ui = preview(p, 'Belgium,Paris', { header: 'no', mode: 'replace' });
    ui.apply.click();
    p.clock.tick(150);
    assert.deepEqual(p.payload().value_dependencies, { Belgium: ['Paris'] });
    assert.deepEqual(p.payload().default_value_dependencies, {});
    assert.deepEqual(p.payload().import, { mode: 'replace', rows: 1 });
    assert.equal(p.notice('import_applied').textContent.startsWith(p.t('applied', { added: '1', removed: '3' })), true);
    p.notice('import_applied').querySelector('button[data-dcf-ed-import-undo]').click();
    assert.equal(p.notice('import_applied'), null);
    assert.equal(p.editor().dirty, false);
    assert.equal(p.input.value, '', 'an untouched form posts nothing again');
    assert.equal(M_payload(p), pre);
    assert.deepEqual([events, values.value], [[], valuesBefore], 'no new value: the textarea is left alone (core warnLeavingUnsaved)');
    p.clock.tick(400);
    assert.equal(p.root.querySelector('[role=status]').textContent, p.root.querySelector('.dcf-dep-editor__status').textContent);
  }
  // Two imports: one undo brings back the first import's source and meta.
  const q = await E.load('admin_list');
  const qRequired = q.root.querySelector('p[data-dcf-editor-required-warning]');
  preview(q, 'Germany,Lyon', { header: 'no' }).apply.click();
  assert.equal(qRequired.classList.contains('dcf-hidden'), true);
  preview(q, 'Germany,Paris\nFrance,Lyon', { header: 'no', mode: 'replace' }).apply.click();
  assert.equal(qRequired.classList.contains('dcf-hidden'), false, 'Belgium lost its links');
  q.notice('import_applied').querySelector('button').click();
  assert.equal(qRequired.classList.contains('dcf-hidden'), true, 'Undo brings the required warning back in line');
  const back = JSON.parse(M_payload(q));
  assert.deepEqual([back.source, back.import], ['import', { mode: 'merge', rows: 1 }]);
  assert.equal(q.editor().dirty, true);
  // A manual edit after the import withdraws Undo (no silent loss of that edit).
  const r = await E.load('admin_list');
  preview(r, 'Germany,Lyon', { header: 'no' }).apply.click();
  r.tick(r.open(r.section('France')), 'Lyon');
  assert.equal(r.root.querySelector('button[data-dcf-ed-import-undo]'), null);
  // So does a possible-values edit, and it clears a fresh preview.
  const s = await E.load('admin_list');
  const sText = s.document.querySelector('#custom_field_possible_values');
  preview(s, 'Belgium,Zurich', { header: 'no', addMissing: true }).apply.click();
  s.clock.tick(400);
  sText.value += '\nTyped';
  s.fire(sText, 'input');
  s.clock.tick(400);
  assert.equal(s.root.querySelector('button[data-dcf-ed-import-undo]'), null);
  assert.ok(sText.value.endsWith('Zurich\nTyped'));
  const sui = preview(s, 'Germany,Lyon', { header: 'no' });
  assert.equal(sui.apply.disabled, false);
  sText.value += '\nMore';
  s.fire(sText, 'input');
  s.clock.tick(400);
  assert.deepEqual([sui.apply.disabled, sui.preview.children.length], [true, 0]);
  // Undo clicked within the 300 ms values debounce: the edit wins and Undo goes.
  const u = await E.load('admin_list');
  const uText = u.document.querySelector('#custom_field_possible_values');
  preview(u, 'Belgium,Zurich', { header: 'no', addMissing: true }).apply.click();
  u.clock.tick(400);
  const applied = M_payload(u);
  uText.value += '\nManual';
  u.fire(uText, 'input');
  u.clock.tick(100);
  const late = u.root.querySelector('button[data-dcf-ed-import-undo]');
  assert.ok(late, 'still shown before the debounce');
  late.click();
  assert.equal(uText.value, 'Antwerp\nBrussels\nParis\nLyon\nZurich\nManual');
  assert.equal(u.root.querySelector('button[data-dcf-ed-import-undo]'), null);
  assert.equal(M_payload(u), applied);
  assert.equal(u.editor().state.source, 'import');
});

// The instance payload text (independent of the dirty flag and the write timer).
function M_payload(p) {
  const ed = p.editor();
  return p.window.DcfDependencyEditorModel.stringify(ed.payload());
}

test('add missing child values: collected once, appended with input and change, children rebuilt at once, undo', async () => {
  const p = await E.load('admin_list');
  const textarea = p.document.querySelector('#custom_field_possible_values');
  const seen = [];
  p.document.addEventListener('change', (e) => { if (e.target === textarea) seen.push('change'); });
  p.form.addEventListener('input', (e) => { if (e.target === textarea) seen.push('input'); });
  const pre = M_payload(p);
  const ui = preview(p, 'Belgium,Zurich\nBelgium,zurich\nGermany," Berlin "\nGermany,Lyon\nGermany,"ZURICH"',
    { header: 'no', addMissing: true });
  assert.equal(summaryText(ui, 'new_values'), p.t('new_values', { count: '2' }));
  assert.deepEqual(errorItems(ui), []);
  ui.apply.click();
  assert.deepEqual(seen, ['input', 'change']);
  assert.equal(textarea.value, 'Antwerp\nBrussels\nParis\nLyon\nZurich\nBerlin');
  assert.deepEqual(Array.from(p.editor().children.keys()), ['Antwerp', 'Brussels', 'Paris', 'Lyon', 'Zurich', 'Berlin']);
  assert.ok(p.section('Belgium').querySelector('.dcf-dep-section__counts').textContent.startsWith('3 of 6'));
  p.clock.tick(150);
  assert.deepEqual(p.payload().value_dependencies, { Belgium: ['Antwerp', 'Brussels', 'Zurich'], France: ['Paris'],
                                                     Germany: ['Lyon', 'Zurich', 'Berlin'] });
  p.clock.tick(300);
  assert.deepEqual(Array.from(p.editor().children.keys()), ['Antwerp', 'Brussels', 'Paris', 'Lyon', 'Zurich', 'Berlin']);
  assert.equal(p.root.querySelector('button[data-dcf-ed-import-undo]') !== null, true, 'the own textarea events keep Undo');
  p.root.querySelector('button[data-dcf-ed-import-undo]').click();
  assert.equal(textarea.value, 'Antwerp\nBrussels\nParis\nLyon');
  assert.deepEqual(Array.from(p.editor().children.keys()), ['Antwerp', 'Brussels', 'Paris', 'Lyon']);
  assert.equal(M_payload(p), pre);
  assert.deepEqual(seen, ['input', 'change', 'input', 'change']);

  const q = await E.load('admin_list', { form: { values: ['A', 'Lyon\u00a0', '', ''] } });
  const tail = preview(q, 'Belgium;Bar', { header: 'no', addMissing: true });
  tail.apply.click();
  const qText = q.document.querySelector('#custom_field_possible_values').value;
  assert.equal(qText, 'A\nLyon\u00a0\nBar');
  assert.deepEqual(Array.from(q.window.DcfDependencyEditorModel.listValuesFromText(qText), (v) => v.key), ['A', 'Lyon\u00a0', 'Bar']);

  const r = await E.load('admin_list');
  const multi = preview(r, 'Belgium,"New\nLine"', { header: 'no', addMissing: true });
  assert.deepEqual(errorItems(multi), [r.t('err_multiline_value', { line: '1', value: 'New\nLine' })]);
  assert.equal(multi.apply.disabled, true);
  const nul = preview(r, 'Belgium,"New\u0000val"', { header: 'no', addMissing: true });
  assert.deepEqual(errorItems(nul), [r.t('err_nul_value', { line: '1', value: 'New\u0000val' })]);
  assert.notEqual(r.t('err_nul_value'), '[err_nul_value]');
  assert.equal(nul.apply.disabled, true);
  const off = preview(r, 'Belgium,Zurich', { header: 'no', addMissing: false });
  assert.deepEqual(errorItems(off), [r.t('err_unknown_child', { line: '1', value: 'Zurich' })]);
});

test('apply is blocked above the payload cap; the estimate equals the posted bytes (SP-13)', async () => {
  const cases = [['admin_list', 'Germany,Lyon'], ['admin_enumeration', 'South,Alpha']];
  for (const [name, line] of cases) {
    const probe = await E.load(name);
    preview(probe, line, { header: 'no' }).apply.click();
    probe.clock.tick(150);
    const bytes = Buffer.byteLength(probe.input.value, 'utf8');
    E.closeAll();
    const ok = await E.load(name, { tweak: (r) => r.setAttribute('data-dcf-editor-max-payload-bytes', String(bytes)) });
    const okUi = preview(ok, line, { header: 'no' });
    assert.equal(okUi.apply.disabled, false, name);
    okUi.apply.click();
    ok.clock.tick(150);
    assert.equal(Buffer.byteLength(ok.input.value, 'utf8'), bytes, name);
    const over = await E.load(name, { tweak: (r) => r.setAttribute('data-dcf-editor-max-payload-bytes', String(bytes - 1)) });
    const overUi = preview(over, line, { header: 'no' });
    assert.equal(overUi.apply.disabled, true, name);
    const box = overUi.preview.querySelector('.flash.error[role=alert]');
    assert.equal(box.textContent, over.t('too_large_to_send', { size: bytes.toLocaleString('en'),
                                                               limit: (bytes - 1).toLocaleString('en') }));
    overUi.apply.disabled = false;
    overUi.apply.click();
    assert.equal(over.notice('import_applied'), null, `${name}: a forced click applies nothing`);
  }
});

test('preview invalidation: import inputs and editor changes disable Apply; Preview flushes the values debounce', async () => {
  const p = await E.load('admin_list');
  const valid = () => preview(p, 'Germany,Lyon', { header: 'no' });
  let ui = valid();
  assert.equal(ui.apply.disabled, false);
  ui.text.value += '\nFrance,Lyon';
  p.fire(ui.text, 'input');
  assert.deepEqual([ui.apply.disabled, ui.preview.children.length], [true, 0]);
  const held = M_payload(p);
  ui.apply.disabled = false;
  ui.apply.click();
  assert.equal(p.notice('import_applied'), null, 'a forced click without a current preview applies nothing');
  assert.equal(M_payload(p), held);
  for (const [el, value] of [['separator', 'comma'], ['header', 'yes'], ['mode', 'replace']]) {
    ui = valid();
    ui[el].value = value;
    p.fire(ui[el], 'change');
    assert.equal(ui.apply.disabled, true, el);
    ui[el].value = el === 'mode' ? 'merge' : 'auto';
  }
  for (const box of ['addMissing', 'unprotect']) {
    ui = valid();
    ui[box].checked = true;
    p.fire(ui[box], 'change');
    assert.equal(ui.apply.disabled, true, box);
    ui[box].checked = false;
  }
  ui = valid();
  p.tick(p.open(p.section('France')), 'Lyon');
  assert.deepEqual([ui.apply.disabled, ui.preview.children.length], [true, 0]);
  ui = valid();
  const multiple = p.document.querySelector('#custom_field_multiple');
  multiple.checked = true;
  p.fire(multiple, 'change');
  assert.equal(ui.apply.disabled, true, 'multiple toggle');
  const textarea = p.document.querySelector('#custom_field_possible_values');
  textarea.value += '\nZurich';
  p.fire(textarea, 'input');
  ui = preview(p, 'Belgium,Zurich', { header: 'no' });
  assert.deepEqual(errorItems(ui), [], 'the typed value is known');
  assert.equal(ui.apply.disabled, false);
  const select = p.document.querySelector('#custom_field_parent_custom_field_id');
  select.value = '9100050';
  p.fire(select, 'change');
  assert.equal(ui.apply.disabled, true, 'parent change');
  // Apply flushes the values debounce too: a value removed just before the click is not linked.
  const a = await E.load('admin_list');
  const aui = preview(a, 'Germany,Paris', { header: 'no' });
  assert.equal(aui.apply.disabled, false);
  const aText = a.document.querySelector('#custom_field_possible_values');
  aText.value = 'Antwerp\nBrussels\nLyon';
  a.fire(aText, 'input');
  aui.apply.click();
  assert.equal(a.notice('import_applied'), null);
  assert.equal(a.editor().state.isLinked('Germany', 'Paris'), false);
  // Enter in the paste area inserts a line; import controls do not touch the sections.
  const q = await E.load('admin_list');
  const qui = panels(q);
  assert.equal(q.key(qui.text, 'Enter').defaultPrevented, false);
  qui.separator.value = 'tab';
  q.fire(qui.separator, 'change');
  q.clock.tick(500);
  assert.equal(q.input.value, '');
  assert.equal(q.editor().dirty, false);
});

test('file input: UTF-8 with BOM, windows-1252 fallback with notice, size cap, unreadable, stale reads, Clear', async () => {
  const children = ['Antwerp', 'Brussels', 'Montr\u00e9al', '\u20acuro'];
  const p = await E.load('admin_list', { form: { values: children } });
  let ui = await chooseFile(p, fileOf(p, [0xef, 0xbb, 0xbf, 'Country,City\r\nBelgium,Montr\u00e9al\r\n']));
  assert.equal(ui.text.disabled, true);
  assert.equal(ui.fileInfo.textContent, p.t('file_used'));
  ui.previewButton.click();
  assert.deepEqual([errorItems(ui), summaryText(ui, 'decoded_as')], [[], null]);
  assert.deepEqual(tableRows(ui), [['Belgium', 'Montr\u00e9al', p.t('status_new')]]);
  assert.equal(ui.preview.querySelector('.flash.warning').textContent, p.t('header_skipped', { cells: 'Country, City' }));

  ui = await chooseFile(p, fileOf(p, ['Belgium;Montr', 0xe9, 'al\nBelgium;', 0x80, 'uro']));
  ui.previewButton.click();
  assert.deepEqual(errorItems(ui), []);
  assert.equal(summaryText(ui, 'decoded_as'), p.t('decoded_as', { encoding: 'windows-1252' }));
  assert.deepEqual(tableRows(ui).map((r) => r[1]), ['Montr\u00e9al', '\u20acuro']);

  ui = await chooseFile(p, fileOf(p, [0xef, 0xbb, 0xbf, 'Belgium;Montr', 0xe9, 'al']));
  ui.previewButton.click();
  assert.deepEqual([errorItems(ui), tableRows(ui)[0][0]], [[], 'Belgium'], 'the BOM is dropped before the fallback');

  // The locale encoding: core CP932 and CP949 under their WHATWG names; an unknown label gives windows-1252.
  const encodings = [['CP932', ['Belgium;', 0x90, 0x56, 0x8f, 0x68], '\u65b0\u5bbf', 'shift_jis'],
    ['CP949', ['Belgium;', 0xbc, 0xad, 0xbf, 0xef], '\uc11c\uc6b8', 'euc-kr'],
    ['ISO-8859-2', ['Belgium;Gda', 0xf1, 'sk'], 'Gda\u0144sk', 'iso-8859-2'],
    ['x-dcf-unknown', ['Belgium;Montr', 0xe9, 'al'], 'Montr\u00e9al', 'windows-1252']];
  for (const [label, bytes, child, name] of encodings) {
    const cp = await E.load('admin_list', { form: { values: children.concat([child]) },
                                            tweak: (r) => r.setAttribute('data-dcf-editor-csv-encoding', label) });
    ui = await chooseFile(cp, fileOf(cp, bytes));
    ui.previewButton.click();
    assert.deepEqual([errorItems(ui), summaryText(ui, 'decoded_as'), tableRows(ui).map((row) => row[1])],
      [[], cp.t('decoded_as', { encoding: name }), [child]], label);
  }
  const utf = await E.load('admin_list', { form: { values: children }, tweak: (r) => r.setAttribute('data-dcf-editor-csv-encoding', 'UTF-8') });
  ui = await chooseFile(utf, fileOf(utf, ['Belgium;Montr', 0xe9, 'al']));
  ui.previewButton.click();
  assert.deepEqual([summaryText(ui, 'decoded_as'), errorItems(ui)], [utf.t('decoded_as', { encoding: 'windows-1252' }), []]);

  let atCap = 0;
  ui = await chooseFile(p, { name: 'cap.csv', size: 10000000,
                             arrayBuffer: () => { atCap += 1; return Promise.resolve(new TextEncoder().encode('Belgium;Antwerp').buffer); } });
  assert.deepEqual([atCap, errorItems(ui)], [1, []], '10,000,000 bytes are read');
  ui.previewButton.click();
  assert.deepEqual(tableRows(ui).map((r) => r[1]), ['Antwerp']);
  let read = 0;
  ui = await chooseFile(p, { name: 'big.csv', size: 10000001, arrayBuffer: () => { read += 1; return Promise.resolve(new ArrayBuffer(0)); } });
  assert.equal(read, 0);
  assert.deepEqual(errorItems(ui), [p.t('err_too_large', { max: '10,000,000' })]);
  assert.equal(ui.text.disabled, false);
  ui = await chooseFile(p, { name: 'bad.csv', size: 3, arrayBuffer: () => Promise.reject(new Error('io')) });
  assert.deepEqual(errorItems(ui), [p.t('err_unreadable')]);
  assert.equal(ui.apply.disabled, true);

  const first = E.deferred();
  const second = E.deferred();
  ui = panels(p);
  Object.defineProperty(ui.file, 'files', { value: [{ name: 'a.csv', size: 9, arrayBuffer: () => first.promise }], configurable: true });
  p.fire(ui.file, 'change');
  Object.defineProperty(ui.file, 'files', { value: [{ name: 'b.csv', size: 9, arrayBuffer: () => second.promise }], configurable: true });
  p.fire(ui.file, 'change');
  second.resolve(new TextEncoder().encode('Belgium;Antwerp').buffer);
  await E.flush();
  first.resolve(new TextEncoder().encode('Belgium;Brussels').buffer);
  await E.flush();
  ui.previewButton.click();
  assert.deepEqual(tableRows(ui).map((r) => r[1]), ['Antwerp'], 'only the last file choice is used');

  ui.clear.click();
  assert.deepEqual([ui.text.value, ui.text.disabled, ui.file.value, ui.preview.children.length, ui.apply.disabled,
    ui.fileInfo.textContent], ['', false, '', 0, true, '']);
  ui.text.value = 'Belgium;Antwerp';
  ui.previewButton.click();
  assert.equal(tableRows(ui).length, 1, 'the paste is used again');

  // Clear makes a pending read stale.
  const cleared = E.deferred();
  Object.defineProperty(ui.file, 'files', { value: [{ name: 'c.csv', size: 9, arrayBuffer: () => cleared.promise }], configurable: true });
  p.fire(ui.file, 'change');
  assert.equal(ui.text.disabled, true);
  ui.clear.click();
  cleared.resolve(new TextEncoder().encode('Germany;Lyon').buffer);
  await E.flush();
  assert.deepEqual([ui.text.disabled, ui.fileInfo.textContent], [false, '']);
  // Preview and Apply do nothing while a file is being read (not the paste).
  ui.text.value = 'Belgium;Antwerp';
  p.fire(ui.text, 'input');
  ui.previewButton.click();
  assert.equal(ui.apply.disabled, false);
  const slow = E.deferred();
  Object.defineProperty(ui.file, 'files', { value: [{ name: 'd.csv', size: 9, arrayBuffer: () => slow.promise }], configurable: true });
  p.fire(ui.file, 'change');
  ui.previewButton.click();
  assert.deepEqual([ui.preview.children.length, ui.apply.disabled], [0, true]);
  ui.apply.disabled = false;
  ui.apply.click();
  assert.equal(p.notice('import_applied'), null);
  slow.resolve(new TextEncoder().encode('Belgium;Brussels').buffer);
  await E.flush();
  ui.previewButton.click();
  assert.deepEqual(tableRows(ui).map((r) => r[1]), ['Brussels']);
});

test('export panel: locale separator default, Blob download with one BOM, unsaved links, protection, filename, guards', async () => {
  const captured = (p) => {
    const out = { blob: null };
    p.window.URL.createObjectURL = (b) => { out.blob = b; return 'blob:x'; };
    p.window.URL.revokeObjectURL = () => {};
    return out;
  };
  const csvOf = async (blob) => Buffer.from(await blob.arrayBuffer());
  for (const variant of VARIANTS) {
    const p = await E.load('admin_list', { variant });
    const out = captured(p);
    p.tick(p.open(p.section('Germany')), 'Lyon');
    const ui = panels(p);
    ui.exportButton.click();
    const bytes = await csvOf(out.blob);
    assert.deepEqual(Array.from(bytes.subarray(0, 3)), [0xef, 0xbb, 0xbf]);
    assert.notDeepEqual(Array.from(bytes.subarray(3, 6)), [0xef, 0xbb, 0xbf]);
    assert.equal(bytes.subarray(3).toString('utf8'), 'Country,City\r\nBelgium,Antwerp\r\nBelgium,Brussels\r\nFrance,Paris\r\nGermany,Lyon\r\n');
    assert.equal(out.blob.type, 'text/csv;charset=utf-8');
    assert.equal(p.window.__dcfClicked, 'city_dependencies.csv');
    ui.exportSeparator.value = 'semicolon';
    ui.protect.checked = true;
    p.fire(ui.protect, 'change');
    ui.exportButton.click();
    assert.ok((await csvOf(out.blob)).subarray(3).toString('utf8').startsWith('Country;City\r\nBelgium;Antwerp\r\n'));
  }
  for (const [attr, value] of [[';', 'semicolon'], ['\t', 'tab'], ['.', 'comma'], [null, 'comma']]) {
    const q = await E.load('admin_list', { tweak: (r) => (attr === null ? r.removeAttribute('data-dcf-editor-csv-separator')
      : r.setAttribute('data-dcf-editor-csv-separator', attr)) });
    assert.equal(q.editor().inert, false);
    assert.equal(panels(q).exportSeparator.value, value, String(attr));
  }
  const values = E.LIST_VALUES.concat(['=SUM(1)']);
  const f = await E.load('admin_list', { form: { values } });
  const fout = captured(f);
  f.tick(f.open(f.section('Germany')), '=SUM(1)');
  const fui = panels(f);
  fui.exportButton.click();
  assert.ok((await csvOf(fout.blob)).toString('utf8').endsWith('Germany,=SUM(1)\r\n'), 'off by default');
  fui.protect.checked = true;
  fui.exportButton.click();
  assert.ok((await csvOf(fout.blob)).toString('utf8').endsWith("Germany,'=SUM(1)\r\n"));
  const fresh = await E.load('admin_list');
  assert.equal(panels(fresh).protect.checked, false, 'not remembered');

  const en = await E.load('admin_enumeration');
  const eout = captured(en);
  panels(en).exportButton.click();
  assert.equal((await csvOf(eout.blob)).subarray(3).toString('utf8'),
    'Region,Product\r\nNorth,Alpha\r\nNorth,Beta\r\nOld,Retired\r\n');
  assert.equal(en.window.__dcfClicked, 'product_dependencies.csv');
  for (const [name, file] of [['R\u00e9gion / Stad', 'region___stad_dependencies.csv'], ['\u5730\u533a', 'dependencies.csv'],
    ['<img>', '_img__dependencies.csv']]) {
    const n = await E.load('admin_list', { tweak: (r) => r.setAttribute('data-dcf-editor-field-name', name) });
    captured(n);
    panels(n).exportButton.click();
    assert.equal(n.window.__dcfClicked, file, name);
  }
  // Export flushes the values debounce: a value renamed just before the click is left out.
  const g = await E.load('admin_list');
  const gout = captured(g);
  const gText = g.document.querySelector('#custom_field_possible_values');
  gText.value = gText.value.replace('Paris', 'Pariss');
  g.fire(gText, 'input');
  panels(g).exportButton.click();
  assert.equal((await csvOf(gout.blob)).subarray(3).toString('utf8'), 'Country,City\r\nBelgium,Antwerp\r\nBelgium,Brussels\r\n');
  const c = await E.load('admin_conflict');
  const cout = captured(c);
  const cText = c.document.querySelector('#custom_field_possible_values');
  cText.value = cText.value.replace('Lyon', 'Lyons');
  c.fire(cText, 'input');
  c.root.querySelector('[data-dcf-ed-export-mine]').click();
  assert.equal((await csvOf(cout.blob)).subarray(3).toString('utf8'), 'Country,City\r\n', 'export mine');
  const bare = await E.load('admin_list');
  bare.window.__dcfClicked = null;
  panels(bare).exportButton.click();
  assert.equal(bare.window.__dcfClicked, null);
  assert.equal(bare.document.querySelectorAll('a[download]').length, 0);
  assert.doesNotMatch(E.editorSource(), /csvCell|csvText/);
});

test('after a live parent change the export header and the header detection use the new parent name', async () => {
  const d = E.deferred();
  const p = await E.load('admin_list', { fetch: () => d.promise });
  const select = p.document.querySelector('#custom_field_parent_custom_field_id');
  select.value = '9100050';
  p.fire(select, 'change');
  d.resolve(E.response(200, { id: '9100050', name: 'Other', kind: 'list', values: [{ key: 'Belgium' }, { key: 'Spain' }] }));
  await E.flush();
  const out = {};
  p.window.URL.createObjectURL = (b) => { out.blob = b; return 'blob:x'; };
  panels(p).exportButton.click();
  assert.ok(Buffer.from(await out.blob.arrayBuffer()).subarray(3).toString('utf8').startsWith('Other,City\r\n'));
  const ui = preview(p, 'Other,Town\nSpain,Paris');
  assert.equal(ui.preview.querySelector('.flash.warning').textContent, p.t('header_skipped', { cells: 'Other, Town' }));
  assert.deepEqual(tableRows(ui), [['Spain', 'Paris', p.t('status_new')]]);
  // Set back: the rendered name again.
  select.value = p.editor().config.parentId;
  p.fire(select, 'change');
  panels(p).exportButton.click();
  assert.ok(Buffer.from(await out.blob.arrayBuffer()).subarray(3).toString('utf8').startsWith('Country,City\r\n'));
  // A body without name: the option text.
  const d2 = E.deferred();
  const q = await E.load('admin_list', { fetch: () => d2.promise });
  const qSelect = q.document.querySelector('#custom_field_parent_custom_field_id');
  qSelect.value = '9100050';
  q.fire(qSelect, 'change');
  d2.resolve(E.response(200, { id: '9100050', kind: 'list', values: [{ key: 'Belgium' }] }));
  await E.flush();
  const qout = {};
  q.window.URL.createObjectURL = (b) => { qout.blob = b; return 'blob:x'; };
  panels(q).exportButton.click();
  assert.ok(Buffer.from(await qout.blob.arrayBuffer()).subarray(3).toString('utf8').startsWith('Other,City\r\n'));
});

test('project mode: import posts source import and import meta without base; no request (gap 14)', async () => {
  for (const variant of VARIANTS) {
    const p = await E.load('project_list', { variant });
    const ui = preview(p, 'Germany,Lyon\nFrance,Lyon', { header: 'no' });
    ui.apply.click();
    p.clock.tick(150);
    const payload = p.payload();
    assert.deepEqual([payload.source, payload.import, payload.base], ['import', { mode: 'merge', rows: 2 }, undefined]);
    assert.deepEqual(payload.value_dependencies, { Belgium: ['Antwerp', 'Brussels'], France: ['Paris', 'Lyon'], Germany: ['Lyon'] });
    assert.equal(p.fetchCalls.length, 0);
    const en = await E.load('project_enumeration', { variant });
    const eui = preview(en, 'North,Gamma\nSouth,Retired', { header: 'no' });
    assert.deepEqual(errorItems(eui), [en.t('err_unknown_child', { line: '1', value: 'Gamma' })]);
    const wui = preview(en, 'South,Retired', { header: 'no' });
    assert.equal(wui.preview.querySelector('.flash.warning li').textContent, en.t('warn_inactive', { line: '1', value: 'Retired' }));
    wui.apply.click();
    en.clock.tick(150);
    assert.deepEqual(en.payload().value_dependencies['9200002'], [9200005, 9200006]);
  }
});

test('preview table and header warning show markup values as text only (no element created)', async () => {
  const marks = ['"><script>alert(1)</script>', '<img src=x onerror=alert(1)>', '&amp;'];
  const p = await E.load('admin_list', {
    form: { values: ['Paris', '<b>bold</b>'] },
    tweak: (r) => {
      r.setAttribute('data-dcf-editor-parent-values', JSON.stringify(marks.map((key) => ({ key }))));
      setJson(r, 'mapping', { value_dependencies: {}, default_value_dependencies: {} });
    }
  });
  const quote = (s) => `"${s.replace(/"/g, '""')}"`;
  const text = ['<i>x</i>;<u>y</u>'].concat(marks.map((m) => `${quote(m)};${quote('<b>bold</b>')}`)).join('\n');
  const ui = preview(p, text, { separator: 'semicolon' });
  assert.deepEqual(tableRows(ui).map((r) => r.slice(0, 2)), marks.map((m) => [m, '<b>bold</b>']));
  assert.equal(ui.preview.querySelector('.flash.warning').textContent, p.t('header_skipped', { cells: '<i>x</i>, <u>y</u>' }));
  assert.equal(p.root.querySelectorAll('script, img, b, i, u').length, 0);
  assert.equal(ui.apply.disabled, false);
});
