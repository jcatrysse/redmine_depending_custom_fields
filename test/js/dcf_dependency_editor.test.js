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
    w.createSVGIcon = () => {
      const svg = w.document.createElementNS('http://www.w3.org/2000/svg', 'svg');
      svg.setAttribute('class', 's18 icon-svg');
      return svg;
    };
  };
  const sprite = await E.load('admin_list', { before: spriteStub });
  assert.ok(sprite.notice('orphans').querySelector('svg.icon-svg'));
  assert.equal(sprite.notice('orphans').textContent, sprite.t('orphans', { count: '1' }));

  // The UD-17 conflict panel is a div.flash.warning too.
  const panelOf = (q) => q.root.querySelector('.dcf-dep-editor__conflict');
  const conflict = await E.load('admin_conflict');
  assert.equal(panelOf(conflict).querySelectorAll('svg').length, 0);
  const conflictSprite = await E.load('admin_conflict', { before: spriteStub });
  assert.equal(panelOf(conflictSprite).querySelectorAll('svg').length, 1);
  assert.equal(panelOf(conflictSprite).firstChild.getAttribute('class'), 's18 icon-svg');
  assert.equal(panelOf(conflictSprite).querySelector('p').textContent,
    conflictSprite.t('conflict', { only_mine: '1', only_current: '3' }));
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
