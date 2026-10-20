'use strict';
// WP-17: the runtime in bulk edit and the context-menu wizard
// (data-dcf-context="bulk"), revised D2 (UD-09) and the required '(none)'
// option (UD-10), rows B1..B9 of frontend design 9 on the generated fixtures.
const { test, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const D = require('./support/dom');
const E = require('./support/entries');
const F = require('./support/fixtures');
const fire = require('./support/fire');

afterEach(D.closeAll);

const name = (prefix, id) => `${prefix}[custom_field_values][${id}]`;
const PARENT = name('issue', 9100001);
const CHILD = name('issue', 9100002);
const load = (source, opts) => D.page(source.includes('<') ? source : F.read(source), opts);
const child = (pg, id) => D.control(pg.document, id || '9100002');
const parentOf = (pg, n) => D.byName(pg.document, n || PARENT);
const childEntries = (pg, n) => E.list(pg.document.forms[0], n || CHILD);
const since = (list, n) => list.slice(n);
const option = (sel, value) => Array.from(sel.options).find((o) => o.value === value);

function invariants(pg) {
  pg.document.querySelectorAll('select').forEach((s) => {
    assert.equal(s.disabled, false, `select ${s.name} disabled`);
    Array.from(s.options).forEach((o) => assert.ok(!(o.selected && o.disabled), `${s.name}: ${o.value} selected and disabled`));
  });
  Array.from(pg.document.forms).forEach((f) => assert.deepEqual(E.entries(f), E.serialized(pg.window, f)));
  assert.deepEqual(pg.errors, []);
}

// The WP-19 required '(none)' option, injected right after "(No change)"
// (hand-written, pre-WP-19 markup); WP-19 regenerates bulk_required with it.
const requiredNone = () => F.tweak('bulk_required', (doc) => {
  const blank = F.named(doc, CHILD).querySelector('option[value=""]');
  blank.insertAdjacentHTML('afterend', '<option value="__none__" data-dcf-required-none="1">none</option>');
});

['issue', 'time_entry'].forEach((prefix) => {
  const scenario = prefix === 'issue' ? 'bulk_single' : 'time_entry_bulk';
  test(`B1${prefix === 'issue' ? '' : ' B7'} ${prefix}: parent (no change), untouched single child posts "", unfiltered`, async () => {
    const pg = await load(scenario);
    const c = child(pg);
    assert.equal(D.state(c), 'unfiltered');
    assert.deepEqual(D.disabled(c), []);
    assert.deepEqual(D.hiddenValues(c), []);
    assert.deepEqual(childEntries(pg, name(prefix, 9100002)), [`${name(prefix, 9100002)}=`]);
    assert.deepEqual(pg.changes, []);
    invariants(pg);
  });
});

test('B1m an untouched multi child posts nothing (the WP-03 hotfix outcome)', async () => {
  const pg = await load('bulk_multi');
  const c = child(pg);
  assert.deepEqual([D.state(c), D.selected(c)], ['unfiltered', []]);
  assert.deepEqual(childEntries(pg), []);
  assert.deepEqual(pg.changes, []);
  invariants(pg);
});

test('B1r a required multi child (no __none__ option) stays enabled and posts nothing', async () => {
  const html = F.tweak('bulk_multi', (doc) => F.named(doc, `${CHILD}[]`).querySelector('option[value="__none__"]').remove());
  const pg = await load(html);
  assert.deepEqual(D.disabled(child(pg)), []);
  assert.deepEqual(childEntries(pg), []);
  fire.choose(pg.window, parentOf(pg), 'Alpha');
  assert.deepEqual([D.selected(child(pg)), childEntries(pg)], [['Ape'], [`${CHILD}[]=Ape`]]);
  invariants(pg);
});

test('B2 a concrete parent without a default keeps (no change) selected, visible and enabled; disallowed hidden', async () => {
  const pg = await load('bulk_single');
  const c = child(pg);
  const n = pg.changes.length;
  fire.choose(pg.window, parentOf(pg), 'Beta');
  assert.deepEqual(D.selected(c), ['']);
  assert.deepEqual(D.enabled(c), ['', '__none__', 'Bee']);
  assert.deepEqual(D.hiddenValues(c), ['Ant', 'Ape']);
  assert.equal(D.state(c), 'ok');
  assert.equal(D.hintText(c), null);
  assert.deepEqual(since(pg.changes, n), [PARENT]);
  invariants(pg);
});

test('B2d the per-parent default with its hint and dcf-auto-applied; (no change) stays; a user change removes the mark', async () => {
  const pg = await load('bulk_single');
  const c = child(pg);
  fire.choose(pg.window, parentOf(pg), 'Alpha');
  assert.deepEqual(D.selected(c), ['Ape']);
  assert.ok(c.classList.contains('dcf-auto-applied'));
  assert.equal(D.hintText(c), 'Set to the default for the selected Parent field. Choose (No change) to keep the current values.');
  assert.ok(D.enabled(c).includes(''));
  const id = D.hint(c).id;
  fire.choose(pg.window, c, '');
  assert.equal(c.classList.contains('dcf-auto-applied'), false);
  assert.equal(pg.document.getElementById(id).hidden, true);
  assert.equal(c.getAttribute('aria-describedby'), null);
  assert.deepEqual(childEntries(pg), [`${CHILD}=`]);
  invariants(pg);
});

test('B2d a default hint the user removes within 400 ms is not announced', async () => {
  const pg = await load('bulk_single');
  const c = child(pg);
  fire.choose(pg.window, parentOf(pg), 'Alpha');
  pg.clock.tick(100);
  fire.choose(pg.window, c, 'Ant');
  pg.clock.tick(400);
  assert.equal(D.hintText(c), null);
  assert.equal(pg.document.getElementById('dcf-live').textContent, '');
});

test('B2e a parent value without links: child (none) with the cleared hint, (no change) disabled', async () => {
  const pg = await load('bulk_single');
  const c = child(pg);
  fire.choose(pg.window, parentOf(pg), 'Gamma');
  assert.deepEqual(D.selected(c), ['__none__']);
  assert.deepEqual(D.enabled(c), ['__none__']);
  assert.equal(option(c, '').disabled, true);
  assert.equal(D.state(c), 'empty');
  assert.equal(D.hintText(c), 'Cleared because the current choice for Parent field allows no values for this field.');
  // WP-17 review: dcf-auto-applied marks the bulk default only, not a clear.
  assert.equal(c.classList.contains('dcf-auto-applied'), false);
  assert.deepEqual(childEntries(pg), [`${CHILD}=__none__`]);
  // A user change of the child still hides the cleared hint.
  fire.choose(pg.window, c, '__none__');
  assert.equal(D.hintText(c), null);
  invariants(pg);
});

test('B2g grandchild unfiltered while its parent stays (no change), filtered by its parent default', async () => {
  const pg = await load('bulk_chain');
  const middle = child(pg, '9100002');
  const leaf = child(pg, '9100003');
  fire.choose(pg.window, parentOf(pg), 'Alpha');
  assert.deepEqual([D.selected(middle), D.state(middle)], [[''], 'ok']);
  assert.deepEqual([D.state(leaf), D.disabled(leaf)], ['unfiltered', []]);
  fire.choose(pg.window, middle, 'Ant');
  assert.deepEqual([D.selected(leaf), D.state(leaf)], [['Calf'], 'ok']);
  assert.ok(leaf.classList.contains('dcf-auto-applied'));
  assert.deepEqual(D.hiddenValues(leaf), ['Colt']);
  invariants(pg);
});

test('B3 parent (none): child __none__, (no change) disabled, the cascade continues', async () => {
  const pg = await load('bulk_chain');
  const middle = child(pg, '9100002');
  const leaf = child(pg, '9100003');
  fire.choose(pg.window, parentOf(pg), '__none__');
  [middle, leaf].forEach((c) => {
    assert.deepEqual([D.selected(c), D.state(c)], [['__none__'], 'none']);
    assert.equal(option(c, '').disabled, true);
  });
  assert.deepEqual(E.list(pg.document.forms[0], 'issue[custom_field_values]'),
    [`${PARENT}=__none__`, `${CHILD}=__none__`, `${name('issue', 9100003)}=__none__`]);
  // A user change of the child hides its cleared hint, also under (none).
  assert.equal(D.hintText(middle), 'Cleared because the current choice for Root field allows no values for this field.');
  fire.choose(pg.window, middle, '__none__');
  assert.equal(D.hintText(middle), null);
  invariants(pg);
});

test('B3r required child as rendered (no __none__): parent (none) keeps "" with the empty hint', async () => {
  const pg = await load('bulk_required');
  const c = child(pg);
  fire.choose(pg.window, parentOf(pg), '__none__');
  assert.deepEqual([D.selected(c), D.state(c)], [[''], 'none']);
  assert.equal(D.hintText(c), 'No values are available for the selected Parent field.');
  fire.choose(pg.window, parentOf(pg), 'Gamma');
  assert.deepEqual([D.selected(c), D.state(c)], [[''], 'empty']);
  invariants(pg);
});

test('B3r UD-10: the data-dcf-required-none option is enabled only while nothing is allowed, never a fallback', async () => {
  const pg = await load(requiredNone());
  const c = child(pg);
  const none = option(c, '__none__');
  assert.deepEqual([none.disabled, none.hidden], [true, true], 'at load (no change)');
  fire.choose(pg.window, parentOf(pg), 'Alpha');
  assert.deepEqual([none.disabled, none.hidden, D.selected(c)], [true, true, ['Ape']]);
  fire.choose(pg.window, parentOf(pg), '__none__');
  assert.deepEqual([none.disabled, none.hidden, D.selected(c)], [false, false, ['__none__']]);
  assert.equal(D.hintText(c), 'Cleared because the current choice for Parent field allows no values for this field.');
  assert.equal(c.classList.contains('dcf-auto-applied'), false, 'a clear is not a default');
  fire.choose(pg.window, parentOf(pg), 'Gamma');
  assert.deepEqual([none.disabled, D.selected(c)], [false, ['__none__']]);
  fire.choose(pg.window, parentOf(pg), '');
  assert.deepEqual([none.disabled, none.hidden, D.selected(c)], [true, true, ['']]);
  fire.choose(pg.window, parentOf(pg), 'Beta');
  assert.deepEqual([none.disabled, D.selected(c)], [true, ['']]);
  invariants(pg);
});

test('B4 parent back to (no change) restores the pre-cascade value and unfilters', async () => {
  const pg = await load('bulk_single');
  const c = child(pg);
  fire.choose(pg.window, c, 'Bee');
  fire.choose(pg.window, parentOf(pg), '__none__');
  assert.deepEqual(D.selected(c), ['__none__']);
  fire.choose(pg.window, parentOf(pg), '');
  assert.deepEqual([D.selected(c), D.state(c), D.disabled(c)], [['Bee'], 'unfiltered', []]);
  fire.choose(pg.window, parentOf(pg), 'Alpha');
  fire.choose(pg.window, parentOf(pg), '');
  assert.deepEqual(D.selected(c), ['Bee']);
  invariants(pg);
});

test('B5 a pick under (no change) is kept when the parent allows it', async () => {
  const pg = await load('bulk_single');
  const c = child(pg);
  fire.choose(pg.window, c, 'Bee');
  fire.choose(pg.window, parentOf(pg), 'Beta');
  assert.deepEqual([D.selected(c), c.classList.contains('dcf-auto-applied')], [['Bee'], false]);
  fire.choose(pg.window, parentOf(pg), 'Alpha');
  assert.deepEqual([D.selected(c), c.classList.contains('dcf-auto-applied')], [['Ape'], true]);
  // A pick under a concrete parent comes back for that parent.
  fire.choose(pg.window, c, 'Ant');
  fire.choose(pg.window, parentOf(pg), 'Beta');
  fire.choose(pg.window, parentOf(pg), 'Alpha');
  assert.deepEqual(D.selected(c), ['Ant']);
  invariants(pg);
});

test('B6 hide_when_disabled is never applied in bulk', async () => {
  const pg = await load('bulk_hide_when_disabled');
  const c = child(pg);
  fire.choose(pg.window, parentOf(pg), 'Gamma');
  assert.deepEqual([c.closest('p').hidden, c.closest('p').classList.contains('dcf-hidden'), D.selected(c)], [false, false, ['__none__']]);
  fire.choose(pg.window, parentOf(pg), '__none__');
  assert.equal(c.closest('p').hidden, false);
  invariants(pg);
});

test('B7 time-entry bulk edit: concrete parent and (none) as in B2 and B3', async () => {
  const pg = await load('time_entry_bulk');
  const c = child(pg);
  const parent = parentOf(pg, name('time_entry', 9100001));
  fire.choose(pg.window, parent, 'Alpha');
  assert.deepEqual([D.selected(c), D.hiddenValues(c)], [[''], ['Bee']]);
  fire.choose(pg.window, parent, '__none__');
  assert.deepEqual(D.selected(c), ['__none__']);
  invariants(pg);
});

test('B8 bulk refresh: the observer initialises the new form with the posted values, memory starts fresh', async () => {
  const body = `<div id="content">${F.read('bulk_single')}</div>`;
  const pg = await load(body);
  fire.choose(pg.window, child(pg), 'Bee');
  const fresh = F.tweak('bulk_single', (doc) => {
    F.selectValues(F.named(doc, PARENT), ['Alpha']);
    F.selectValues(F.named(doc, CHILD), ['Ant']);
  });
  const content = pg.document.getElementById('content');
  while (content.firstChild) content.removeChild(content.firstChild);
  const holder = pg.document.createElement('div');
  holder.innerHTML = fresh;
  while (holder.firstChild) content.appendChild(holder.firstChild);
  await D.microtask();
  const c = child(pg);
  assert.deepEqual([D.selected(c), D.state(c)], [['Ant'], 'ok']);
  assert.deepEqual(D.hiddenValues(c), ['Bee']);
  // WP-17 review: (no change) restores the pre-cascade value, and a form
  // rendered with a concrete parent has none, so the child goes back to
  // (no change) (B4, UD-09); it kept the rendered Ant before.
  fire.choose(pg.window, parentOf(pg), '');
  assert.deepEqual([D.selected(c), D.state(c)], [[''], 'unfiltered']);
  assert.deepEqual(childEntries(pg), [`${CHILD}=`]);
  invariants(pg);
});

// Replaces the content of #content with markup, as a bulk refresh does.
async function refresh(pg, markup) {
  const content = pg.document.getElementById('content');
  while (content.firstChild) content.removeChild(content.firstChild);
  const holder = pg.document.createElement('div');
  holder.innerHTML = markup;
  while (holder.firstChild) content.appendChild(holder.firstChild);
  await D.microtask();
}

test('B8 bulk refresh, multi child: back to (no change) selects nothing and posts nothing', async () => {
  const pg = await load(`<div id="content">${F.read('bulk_multi')}</div>`);
  await refresh(pg, F.tweak('bulk_multi', (doc) => {
    F.selectValues(F.named(doc, PARENT), ['Alpha']);
    F.selectValues(F.named(doc, `${CHILD}[]`), ['Ant']);
  }));
  const c = child(pg);
  assert.deepEqual([D.selected(c), D.state(c)], [['Ant'], 'ok']);
  fire.choose(pg.window, parentOf(pg), '');
  assert.deepEqual([D.selected(c), D.state(c)], [[], 'unfiltered']);
  assert.deepEqual(childEntries(pg), []);
  invariants(pg);
});

test('B8 bulk refresh with a parent value without links: (none) at load without hint or mark; the hint after a change', async () => {
  const pg = await load(`<div id="content">${F.read('bulk_single')}</div>`);
  await refresh(pg, F.tweak('bulk_single', (doc) => F.selectValues(F.named(doc, PARENT), ['Gamma'])));
  const c = child(pg);
  assert.deepEqual([D.selected(c), D.state(c), D.hintText(c)], [['__none__'], 'empty', null]);
  assert.equal(c.classList.contains('dcf-auto-applied'), false);
  fire.choose(pg.window, parentOf(pg), 'Alpha');
  fire.choose(pg.window, parentOf(pg), 'Gamma');
  assert.deepEqual([D.selected(c), D.hintText(c)],
    [['__none__'], 'Cleared because the current choice for Parent field allows no values for this field.']);
  assert.equal(c.classList.contains('dcf-auto-applied'), false);
  invariants(pg);
});

// Derived from bulk_single with the parent label removed (hand-modified).
test('bulk without a parent label: the default and the clear are applied without hint text', async () => {
  const pg = await load(F.tweak('bulk_single', (doc) => F.named(doc, PARENT).closest('p').querySelector('label').remove()));
  const c = child(pg);
  fire.choose(pg.window, parentOf(pg), 'Alpha');
  assert.deepEqual([D.selected(c), c.classList.contains('dcf-auto-applied'), D.hintText(c)], [['Ape'], true, null]);
  fire.choose(pg.window, parentOf(pg), 'Gamma');
  assert.deepEqual([D.selected(c), D.state(c), D.hintText(c)], [['__none__'], 'empty', null]);
  invariants(pg);
});

test('B9 a parent not common to the selection (absent) leaves the child unfiltered', async () => {
  const html = F.tweak('bulk_single', (doc) => F.named(doc, PARENT).closest('p').remove());
  const pg = await load(html);
  const c = child(pg);
  assert.deepEqual([D.state(c), D.disabled(c), D.selected(c)], ['unfiltered', [], ['']]);
  invariants(pg);
});

test('bulk multi child: a user pick of __none__ plus values is left as is', async () => {
  const pg = await load('bulk_multi');
  const c = child(pg);
  fire.choose(pg.window, c, ['__none__', 'Ant']);
  assert.deepEqual(childEntries(pg), [`${CHILD}[]=__none__`, `${CHILD}[]=Ant`]);
  invariants(pg);
});

// The wizard template is inert; cloned into the container as
// context_menu_wizard.js does, it is a bulk form of its own.
test('wizard template: inert until cloned, then bulk context scoped to its form (W1..W6 are WP-18)', async () => {
  const pg = await load(`${F.read('list_single')}${F.read('wizard_template')}`);
  const issueChild = pg.document.querySelector('#issue-form [data-dcf-field="9100002"]');
  assert.equal(pg.document.querySelectorAll('#context-menu [data-dcf-state]').length, 0);
  assert.equal(pg.document.querySelector('template').content.querySelectorAll('[data-dcf-state]').length, 0);
  const container = pg.document.createElement('div');
  container.id = 'cf-wizard-container';
  container.className = 'context-menu cf-wizard';
  pg.document.body.appendChild(container);
  container.appendChild(pg.document.querySelector('template').content.cloneNode(true));
  await D.microtask();
  const form = container.querySelector('form.cf-wizard-form');
  const middle = D.control(form, '9100002');
  const leaf = D.control(form, '9100003');
  assert.deepEqual([D.state(middle), D.state(leaf)], ['unfiltered', 'unfiltered']);
  fire.choose(pg.window, D.byName(form, PARENT), 'Alpha');
  assert.deepEqual([D.selected(middle), D.enabled(middle)], [[''], ['', '__none__', 'Ant', 'Ape']]);
  assert.equal(middle.classList.contains('dcf-auto-applied'), false);
  assert.deepEqual([D.state(issueChild), D.selected(issueChild)], ['ok', ['Ant']], 'the issue form is untouched');
  fire.choose(pg.window, D.byName(pg.document.getElementById('issue-form'), PARENT), 'Beta');
  assert.deepEqual(D.enabled(middle), ['', '__none__', 'Ant', 'Ape'], 'the wizard is untouched');
  assert.equal(D.hintText(D.control(form, '9100002')), null);
  fire.choose(pg.window, middle, 'Ant');
  assert.deepEqual(D.selected(leaf), ['Calf']);
  assert.equal(D.hintText(leaf), 'Set to the default for the selected Middle field. Choose (No change) to keep the current values.',
    'the parent label comes from the .field-description of its .cf-wizard-field');
  assert.equal(D.hint(leaf).parentNode, leaf.closest('.cf-wizard-field'));
  fire.choose(pg.window, D.byName(form, PARENT), 'Beta');
  fire.choose(pg.window, middle, 'Bee');
  assert.deepEqual(D.selected(leaf), [''], 'Bee has no default for the leaf');
  assert.deepEqual(D.enabled(leaf), ['', '__none__', 'Colt']);
  invariants(pg);
});
