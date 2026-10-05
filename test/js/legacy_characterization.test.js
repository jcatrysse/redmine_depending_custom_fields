'use strict';
// Characterization of the legacy runtime assets/javascripts/depending_custom_fields.js
// as shipped in 0.0.16 (WP-03 hotfix: the bulk form id is "bulk_edit_form").
// Safety net before the WP-17/WP-18 rewrite: it pins what the script does
// today, bugs included. It is NOT a spec of the desired behaviour. Test names
// start with the row id of the behaviour table in
// docs/specs/large_lists_frontend_design.md section 9 and, in parentheses, the
// harness id of its "before" column. WP-18 deletes this file together with
// legacy_bulk_hotfix.test.js and test/js/support/legacy_dom.js.
//
// jsdom caveat: a scoped element.querySelector('#id') returns null in jsdom
// when an element outside the scope, earlier in the document, has the same id
// (browsers find the scoped one). Fixtures therefore never use duplicate ids.
const { test, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const L = require('./support/legacy_dom');

const PARENT = ['A', 'B', 'C']; // C has no linked child values
const CHILD = ['a1', 'a2', 'b1'];
const GRAND = ['x1', 'x2', 'y1'];
const childInfo = (extra) => Object.assign({ parent_id: '1', map: { A: ['a1', 'a2'], B: ['b1'] }, defaults: {}, hide_when_disabled: false }, extra);
const MAP = { 2: childInfo() };
const withChild = (extra) => ({ 2: childInfo(extra) });
const chain = (childExtra, grandExtra) => ({
  2: childInfo(childExtra),
  3: Object.assign({ parent_id: '2', map: { a1: ['x1'], a2: ['x2'], b1: ['y1'] }, defaults: {}, hide_when_disabled: false }, grandExtra)
});

// Every page is checked after its test: the script must not have thrown inside
// a listener unless the test sets expectErrors.
const pages = [];
const page = (body, opts) => { const pg = L.legacyPage(body, opts); pages.push(pg); return pg; };
const realPage = async (body, opts) => { const pg = await L.headPage(body, opts); pages.push(pg); return pg; };
afterEach(() => {
  pages.splice(0).filter((pg) => !pg.expectErrors).forEach((pg) => {
    assert.deepEqual(pg.errors.map(String), [], 'the legacy script reported an error');
  });
});

const issueForm = (parentOpts, childOpts, extra) => '<form id="issue-form">' +
  L.field('Country', L.editSelect('issue', 1, PARENT, parentOpts)) +
  L.field('City', L.editSelect('issue', 2, CHILD, childOpts)) + (extra || '') + '</form>';
const bulkForm = (prefix, parentOpts, childOpts, extra) => '<form id="bulk_edit_form">' +
  L.field('Country', L.bulkSelect(prefix, 1, PARENT, parentOpts)) +
  L.field('City', L.bulkSelect(prefix, 2, CHILD, childOpts)) + (extra || '') + '</form>';
const editEl = (pg, prefix, id) => pg.document.getElementById(L.tagId(prefix, id));
const bulkEl = (pg, prefix, id, multiple) => pg.document.getElementById(L.sanitizeToId(L.tagName(prefix, id, multiple)));
const fieldEntries = (pg, prefix, id, form) => L.entries(pg.window, form, `${prefix}[custom_field_values][${id}]`);
const mirrorOf = (pg, select) => pg.document.querySelector(`span[data-hidden-for="${select.id}"]`);
const inputsOf = (span) => Array.from(span.querySelectorAll('input[type="checkbox"], input[type="radio"]'));
const valuesWhere = (span, pred) => inputsOf(span).filter(pred).map((i) => i.value);
const labelHidden = (input) => input.closest('label').style.display === 'none';
const decode = (s) => decodeURIComponent(s);

// ---------------------------------------------------------------- form rows

test('F1 (E0): form, parent blank: child select disabled, concrete options hidden, a hidden mirror posts ""', () => {
  const pg = page(issueForm(), { mapping: MAP });
  const child = editEl(pg, 'issue', 2);
  assert.equal(child.disabled, true);
  assert.deepEqual(L.visibleOptions(child), ['']);
  assert.deepEqual(L.hiddenOptions(child), CHILD);
  assert.equal(child.querySelector('option[value="a1"]').style.display, 'none');
  const mirror = mirrorOf(pg, child);
  assert.equal(mirror.style.display, 'none');
  assert.equal(mirror.previousElementSibling, child);
  assert.deepEqual(Array.from(mirror.querySelectorAll('input[type="hidden"]')).map((i) => `${i.name}=${i.value}`),
    ['issue[custom_field_values][2]=']);
  assert.deepEqual(fieldEntries(pg, 'issue', 2), ['issue[custom_field_values][2]=']);
});

test('F2: parent set to A filters the child, value "" without default, select and mirror both post the value', () => {
  const pg = page(issueForm(), { mapping: MAP });
  const child = editEl(pg, 'issue', 2);
  L.choose(pg.window, editEl(pg, 'issue', 1), 'A');
  assert.equal(child.disabled, false);
  assert.deepEqual(L.visibleOptions(child), ['', 'a1', 'a2']);
  assert.deepEqual(L.hiddenOptions(child), ['b1']);
  assert.equal(child.value, '');
  assert.deepEqual(fieldEntries(pg, 'issue', 2), ['issue[custom_field_values][2]=', 'issue[custom_field_values][2]=']);
  L.choose(pg.window, child, 'a1');
  assert.deepEqual(fieldEntries(pg, 'issue', 2), ['issue[custom_field_values][2]=a1', 'issue[custom_field_values][2]=a1']);
});

test('F2: parent set to A with default a2 selects the default', () => {
  const pg = page(issueForm(), { mapping: withChild({ defaults: { A: 'a2' } }) });
  L.choose(pg.window, editEl(pg, 'issue', 1), 'A');
  assert.equal(editEl(pg, 'issue', 2).value, 'a2');
});

test('F2: a change event is fired on the child on every parent change, also when its value stays ""', () => {
  const pg = page(issueForm(), { mapping: MAP });
  const parent = editEl(pg, 'issue', 1);
  pg.changes.length = 0;
  L.choose(pg.window, parent, 'A');
  assert.deepEqual(pg.changes, ['issue_custom_field_values_1', 'issue_custom_field_values_2']);
  pg.changes.length = 0;
  L.choose(pg.window, parent, 'B');
  assert.deepEqual(pg.changes, ['issue_custom_field_values_1', 'issue_custom_field_values_2']);
});

test('F3 (E3): pick a1 under A, then A to B to A restores the value captured at the last parent change (""), not a1', () => {
  const pg = page(issueForm(), { mapping: MAP });
  const parent = editEl(pg, 'issue', 1);
  const child = editEl(pg, 'issue', 2);
  L.choose(pg.window, parent, 'A');
  L.choose(pg.window, child, 'a1');
  L.choose(pg.window, parent, 'B');
  assert.equal(child.value, '');
  L.choose(pg.window, parent, 'A');
  assert.equal(child.value, '');
  assert.deepEqual(JSON.parse(child.dataset.valueMap), { combos: { A: [], B: [] } });
});

test('F3 (E3): with default a2 for A, the round trip restores a2 instead of the picked a1', () => {
  const pg = page(issueForm(), { mapping: withChild({ defaults: { A: 'a2' } }) });
  const parent = editEl(pg, 'issue', 1);
  const child = editEl(pg, 'issue', 2);
  L.choose(pg.window, parent, 'A');
  L.choose(pg.window, child, 'a1');
  L.choose(pg.window, parent, 'B');
  L.choose(pg.window, parent, 'A');
  assert.equal(child.value, 'a2');
});

test('F4 (N2): clearing the parent of a chain disables and clears every level, with a change event on every level', () => {
  const body = '<form>' + L.field('Country', L.editSelect('issue', 1, PARENT, { selected: 'A' })) +
    L.field('City', L.editSelect('issue', 2, CHILD, { selected: 'a1' })) +
    L.field('Street', L.editSelect('issue', 3, GRAND, { selected: 'x1' })) + '</form>';
  const pg = page(body, { mapping: chain() });
  assert.equal(editEl(pg, 'issue', 3).value, 'x1');
  pg.changes.length = 0;
  L.choose(pg.window, editEl(pg, 'issue', 1), '');
  assert.deepEqual(pg.changes, ['issue_custom_field_values_1', 'issue_custom_field_values_2', 'issue_custom_field_values_3']);
  [2, 3].forEach((id) => {
    assert.equal(editEl(pg, 'issue', id).disabled, true);
    assert.equal(editEl(pg, 'issue', id).value, '');
  });
  assert.deepEqual(L.entries(pg.window), ['issue[custom_field_values][1]=', 'issue[custom_field_values][2]=', 'issue[custom_field_values][3]=']);
});

test('F5 (F): a stored allowed child value is kept and a change event is fired on the child at setup', () => {
  const pg = page(issueForm({ selected: 'A' }, { selected: 'a1' }), { mapping: MAP });
  assert.equal(editEl(pg, 'issue', 2).value, 'a1');
  assert.deepEqual(pg.changes, ['issue_custom_field_values_2']);
  assert.deepEqual(fieldEntries(pg, 'issue', 2), ['issue[custom_field_values][2]=a1', 'issue[custom_field_values][2]=a1']);
});

test('F6 (I): a stored b1 under stored A is dropped at load, so a notes-only save posts "" and clears it', () => {
  const pg = page(issueForm({ selected: 'A' }, { selected: 'b1' }), { mapping: MAP });
  const child = editEl(pg, 'issue', 2);
  assert.equal(child.value, '');
  assert.equal(child.disabled, false);
  assert.deepEqual(L.hiddenOptions(child), ['b1']);
  assert.deepEqual(fieldEntries(pg, 'issue', 2), ['issue[custom_field_values][2]=', 'issue[custom_field_values][2]=']);
});

test('F6a: after F6, A to B to A does not bring b1 back', () => {
  const pg = page(issueForm({ selected: 'A' }, { selected: 'b1' }), { mapping: MAP });
  L.choose(pg.window, editEl(pg, 'issue', 1), 'B');
  assert.equal(editEl(pg, 'issue', 2).value, '');
  L.choose(pg.window, editEl(pg, 'issue', 1), 'A');
  assert.equal(editEl(pg, 'issue', 2).value, '');
});

test('F6b-a, F6b-b, F6c: a disallowed selected value is dropped at load whatever its origin; data-dcf-stored is ignored', () => {
  for (const attrs of [{ 'data-dcf-stored': '["b1"]' }, undefined]) {
    const pg = page(issueForm({ selected: 'A' }, { selected: 'b1', attrs }), { mapping: MAP });
    assert.equal(editEl(pg, 'issue', 2).value, '');
    assert.deepEqual(fieldEntries(pg, 'issue', 2), ['issue[custom_field_values][2]=', 'issue[custom_field_values][2]=']);
  }
});

test('F6d: a multi child with legacy b1 drops it at load; adding a1 then posts a1 only (twice)', () => {
  const pg = page(issueForm({ selected: 'A' }, { multiple: true, selected: ['b1'] }), { mapping: MAP });
  const child = editEl(pg, 'issue', 2);
  assert.deepEqual(L.selectedValues(child), []);
  assert.deepEqual(fieldEntries(pg, 'issue', 2), ['issue[custom_field_values][2][]=']);
  L.choose(pg.window, child, ['a1']);
  assert.deepEqual(fieldEntries(pg, 'issue', 2), ['issue[custom_field_values][2][]=a1', 'issue[custom_field_values][2][]=a1']);
});

test('F7 (L): multi select child: the core hidden "" input is removed and every value is posted twice', () => {
  const pg = page(issueForm({ selected: 'A' }, { multiple: true, selected: ['a1'] }), { mapping: MAP });
  const child = editEl(pg, 'issue', 2);
  assert.equal(pg.document.getElementById('issue_custom_field_values_2_'), null);
  const hidden = Array.from(child.parentElement.querySelectorAll('input[type="hidden"]'));
  assert.deepEqual(hidden.map((i) => i.parentElement === mirrorOf(pg, child)), [true]);
  assert.deepEqual(fieldEntries(pg, 'issue', 2), ['issue[custom_field_values][2][]=a1', 'issue[custom_field_values][2][]=a1']);
  L.choose(pg.window, child, ['a1', 'a2']);
  assert.deepEqual(fieldEntries(pg, 'issue', 2), ['issue[custom_field_values][2][]=a1', 'issue[custom_field_values][2][]=a2',
    'issue[custom_field_values][2][]=a1', 'issue[custom_field_values][2][]=a2']);
});

test('F7 (L): clearing a multi select child posts name[]= once, through the mirror', () => {
  const pg = page(issueForm({ selected: 'A' }, { multiple: true, selected: ['a1'] }), { mapping: MAP });
  L.choose(pg.window, editEl(pg, 'issue', 2), []);
  assert.deepEqual(fieldEntries(pg, 'issue', 2), ['issue[custom_field_values][2][]=']);
});

test('F8 (P1, P2): multi check box child, parent blank: every check box is disabled and its label hidden', () => {
  const body = '<form>' + L.field('Country', L.editSelect('issue', 1, PARENT)) +
    L.field('City', L.editCheckBoxes('issue', 2, CHILD, { multiple: true, checked: ['a1'] })) + '</form>';
  const pg = page(body, { mapping: MAP });
  const span = pg.document.querySelector('span.check_box_group');
  assert.deepEqual(valuesWhere(span, (i) => i.disabled), CHILD);
  assert.deepEqual(valuesWhere(span, labelHidden), CHILD);
  assert.deepEqual(valuesWhere(span, (i) => i.checked), []);
  assert.equal(pg.document.querySelector('span[data-hidden-for]'), null);
  assert.deepEqual(fieldEntries(pg, 'issue', 2), ['issue[custom_field_values][2][]=']);
  assert.deepEqual(pg.changes, ['issue[custom_field_values][2][]']);
});

test('F8 (P1, P2): multi check box child, parent A: every check box is enabled, a disallowed one only gets its label hidden', () => {
  const body = '<form>' + L.field('Country', L.editSelect('issue', 1, PARENT, { selected: 'A' })) +
    L.field('City', L.editCheckBoxes('issue', 2, CHILD, { multiple: true, checked: ['a1', 'b1'] })) + '</form>';
  const pg = page(body, { mapping: MAP });
  const span = pg.document.querySelector('span.check_box_group');
  assert.deepEqual(valuesWhere(span, (i) => i.disabled), []);
  assert.deepEqual(valuesWhere(span, labelHidden), ['b1']);
  assert.deepEqual(inputsOf(span).map((i) => i.dataset.dependingHiddenOption), ['0', '0', '1']);
  assert.deepEqual(valuesWhere(span, (i) => i.checked), ['a1']);
  assert.deepEqual(fieldEntries(pg, 'issue', 2), ['issue[custom_field_values][2][]=a1', 'issue[custom_field_values][2][]=']);
});

test('F9 (G1): single radio, not required: after a parent change no radio is checked, not even "(none)", and nothing is posted', () => {
  const body = '<form>' + L.field('Country', L.editSelect('issue', 1, PARENT, { selected: 'A' })) +
    L.field('City', L.editCheckBoxes('issue', 2, CHILD, { checked: ['a1'] })) + '</form>';
  const pg = page(body, { mapping: MAP });
  const span = pg.document.querySelector('span.check_box_group');
  assert.deepEqual(fieldEntries(pg, 'issue', 2), ['issue[custom_field_values][2]=a1']);
  L.choose(pg.window, editEl(pg, 'issue', 1), 'B');
  assert.deepEqual(valuesWhere(span, (i) => i.checked), []);
  assert.deepEqual(valuesWhere(span, labelHidden), ['a1', 'a2']);
  assert.deepEqual(fieldEntries(pg, 'issue', 2), []);
});

test('F10 (G1/G2): single radio, required: parent change or blank parent leaves nothing checked and nothing posted', () => {
  const body = '<form>' + L.field('Country', L.editSelect('issue', 1, PARENT, { selected: 'A' })) +
    L.field('City', L.editCheckBoxes('issue', 2, CHILD, { checked: ['a1'], required: true })) + '</form>';
  const pg = page(body, { mapping: MAP });
  const span = pg.document.querySelector('span.check_box_group');
  L.choose(pg.window, editEl(pg, 'issue', 1), 'B');
  assert.deepEqual(valuesWhere(span, (i) => i.checked), []);
  assert.deepEqual(fieldEntries(pg, 'issue', 2), []);
  L.choose(pg.window, editEl(pg, 'issue', 1), '');
  assert.deepEqual(valuesWhere(span, (i) => i.disabled), CHILD);
  assert.deepEqual(fieldEntries(pg, 'issue', 2), []);
});

test('F11: a chain cascades through change events: parent A sets the child default, whose change sets the grandchild default', () => {
  const body = '<form>' + L.field('Country', L.editSelect('issue', 1, PARENT)) +
    L.field('City', L.editSelect('issue', 2, CHILD)) + L.field('Street', L.editSelect('issue', 3, GRAND)) + '</form>';
  const pg = page(body, { mapping: chain({ defaults: { A: 'a2' } }, { defaults: { a2: ['x2'] } }) });
  pg.changes.length = 0;
  L.choose(pg.window, editEl(pg, 'issue', 1), 'A');
  assert.deepEqual(pg.changes, ['issue_custom_field_values_1', 'issue_custom_field_values_2', 'issue_custom_field_values_3']);
  assert.equal(editEl(pg, 'issue', 2).value, 'a2');
  assert.equal(editEl(pg, 'issue', 3).value, 'x2');
  assert.deepEqual(L.visibleOptions(editEl(pg, 'issue', 3)), ['', 'x2']);
});

test('F12: multi parent: allowed values are the union and the defaults of an added parent value are merged', () => {
  const pg = page(issueForm({ multiple: true }, { multiple: true }), { mapping: withChild({ defaults: { A: 'a1', B: ['b1'] } }) });
  const parent = editEl(pg, 'issue', 1);
  const child = editEl(pg, 'issue', 2);
  L.choose(pg.window, parent, ['A']);
  assert.deepEqual(L.selectedValues(child), ['a1']);
  L.choose(pg.window, parent, ['A', 'B']);
  assert.deepEqual(L.visibleOptions(child), ['a1', 'a2', 'b1']);
  assert.deepEqual(L.selectedValues(child), ['a1', 'b1']);
  // The multi parent keeps its core hidden "" input (only children lose it).
  assert.deepEqual(fieldEntries(pg, 'issue', 1), ['issue[custom_field_values][1][]=A', 'issue[custom_field_values][1][]=B',
    'issue[custom_field_values][1][]=']);
});

test('F13 (T): parent read-only by workflow (shown as text, no input): the child stays unfiltered and untouched', () => {
  const body = '<div class="attributes"><div class="cf_1">Country: A</div></div><form id="issue-form">' +
    L.field('City', L.editSelect('issue', 2, CHILD, { selected: 'b1' })) + '</form>';
  const pg = page(body, { mapping: MAP });
  const child = editEl(pg, 'issue', 2);
  assert.equal(child.disabled, false);
  assert.equal(child.value, 'b1');
  assert.deepEqual(L.visibleOptions(child), ['', 'a1', 'a2', 'b1']);
  assert.equal(child.classList.contains('depending-child'), false);
  assert.equal(mirrorOf(pg, child), null);
  assert.deepEqual(pg.changes, []);
  assert.deepEqual(L.entries(pg.window), ['issue[custom_field_values][2]=b1']);
});

test('F13b: parent not available for the tracker: a multi child stays unfiltered and keeps its core hidden input', () => {
  const body = '<form id="issue-form">' + L.field('City', L.editSelect('issue', 2, CHILD, { multiple: true, selected: ['b1'] })) + '</form>';
  const pg = page(body, { mapping: MAP });
  assert.deepEqual(L.visibleOptions(editEl(pg, 'issue', 2)), CHILD);
  assert.notEqual(pg.document.getElementById('issue_custom_field_values_2_'), null);
  assert.deepEqual(L.entries(pg.window), ['issue[custom_field_values][2][]=b1', 'issue[custom_field_values][2][]=']);
});

test('F14: parent invisible to the role: child unfiltered, and the full mapping stays readable on window', () => {
  const body = '<form id="issue-form">' + L.field('City', L.editSelect('issue', 2, CHILD, { selected: 'a2' })) + '</form>';
  const pg = page(body, { mapping: MAP });
  assert.equal(editEl(pg, 'issue', 2).value, 'a2');
  assert.deepEqual(L.visibleOptions(editEl(pg, 'issue', 2)), ['', 'a1', 'a2', 'b1']);
  assert.deepEqual(JSON.parse(JSON.stringify(pg.window.DependingCustomFieldData)), MAP);
});

test('F15: after updateIssueFrom replaces the form, the new child is rescanned only 100 ms after jQuery ajaxComplete', () => {
  const pg = page(`<form id="issue-form"><div id="all_attributes">${issueForm({ selected: 'A' }).replace(/^<form[^>]*>|<\/form>$/g, '')}</div></form>`,
    { mapping: MAP, jquery: true });
  const $ = pg.window.jQuery;
  $('#all_attributes').html(L.field('Country', L.editSelect('issue', 1, PARENT, { selected: 'A' })) +
    L.field('City', L.editSelect('issue', 2, CHILD, { selected: 'a2' })));
  const child = editEl(pg, 'issue', 2);
  assert.equal(child.classList.contains('depending-child'), false);
  assert.equal(pg.clock.pending(), 0);
  $(pg.document).trigger('ajaxComplete');
  assert.equal(pg.clock.pending(), 1);
  pg.clock.tick(99);
  assert.deepEqual(L.visibleOptions(child), ['', 'a1', 'a2', 'b1']);
  pg.clock.tick(1);
  assert.equal(child.classList.contains('depending-child'), true);
  assert.deepEqual(L.visibleOptions(child), ['', 'a1', 'a2']);
  assert.equal(child.value, 'a2');
});

test('F15: jQuery serialize of the issue form carries a disabled child only through its mirror', () => {
  const pg = page(issueForm(), { mapping: MAP, jquery: true });
  assert.equal(editEl(pg, 'issue', 2).disabled, true);
  assert.equal(decode(pg.window.jQuery('#issue-form').serialize()), 'issue[custom_field_values][1]=&issue[custom_field_values][2]=');
});

test('F15: the per-parent memory (data-value-map) is lost with the replaced element', () => {
  const pg = page(`<form id="issue-form"><div id="all_attributes">${issueForm().replace(/^<form[^>]*>|<\/form>$/g, '')}</div></form>`,
    { mapping: MAP, jquery: true });
  const $ = pg.window.jQuery;
  L.choose(pg.window, editEl(pg, 'issue', 1), 'A');
  L.choose(pg.window, editEl(pg, 'issue', 1), 'B');
  assert.deepEqual(JSON.parse(editEl(pg, 'issue', 2).dataset.valueMap), { combos: { A: [], B: [] } });
  $('#all_attributes').html(L.field('Country', L.editSelect('issue', 1, PARENT, { selected: 'B' })) +
    L.field('City', L.editSelect('issue', 2, CHILD)));
  $(pg.document).trigger('ajaxComplete');
  pg.clock.tick(100);
  assert.deepEqual(JSON.parse(editEl(pg, 'issue', 2).dataset.valueMap), { combos: { B: [] } });
});

test('F16: hide_when_disabled on a form: the child <p> is hidden while there are no options and shown otherwise', () => {
  const pg = page(issueForm(), { mapping: withChild({ hide_when_disabled: true }) });
  const p = editEl(pg, 'issue', 2).closest('p');
  assert.equal(p.hidden, true);
  L.choose(pg.window, editEl(pg, 'issue', 1), 'A');
  assert.equal(p.hidden, false);
  L.choose(pg.window, editEl(pg, 'issue', 1), 'C');
  assert.equal(p.hidden, true);
  assert.deepEqual(fieldEntries(pg, 'issue', 2), ['issue[custom_field_values][2]=']);
});

test('F16: without hide_when_disabled the child <p> is forced visible, even when something else hid it', () => {
  const body = '<form>' + L.field('Country', L.editSelect('issue', 1, PARENT)) +
    L.field('City', L.editSelect('issue', 2, CHILD), { hidden: 'hidden' }) + '</form>';
  const pg = page(body, { mapping: MAP });
  assert.equal(editEl(pg, 'issue', 2).closest('p').hidden, false);
});

test('F17: time-entry fields inside the issue form are prefix-aware (same field ids under both prefixes)', () => {
  const body = issueForm({ selected: 'B' }, {}, '<fieldset id="log_time">' +
    L.field('Country', L.editSelect('time_entry', 1, PARENT, { selected: 'A' })) +
    L.field('City', L.editSelect('time_entry', 2, CHILD)) + '</fieldset>');
  const pg = page(body, { mapping: MAP });
  assert.deepEqual(L.visibleOptions(editEl(pg, 'issue', 2)), ['', 'b1']);
  assert.deepEqual(L.visibleOptions(editEl(pg, 'time_entry', 2)), ['', 'a1', 'a2']);
  assert.equal(editEl(pg, 'time_entry', 2).dataset.dependingPrefix, 'time_entry');
  L.choose(pg.window, editEl(pg, 'time_entry', 1), '');
  assert.equal(editEl(pg, 'time_entry', 2).disabled, true);
  assert.equal(editEl(pg, 'issue', 2).disabled, false);
});

for (const prefix of ['project', 'user', 'version', 'group', 'document', 'enumeration', 'time_entry']) {
  test(`F18: ${prefix} form behaves as the issue form (blank parent disables, A filters)`, () => {
    const body = '<form>' + L.field('Country', L.editSelect(prefix, 1, PARENT)) + L.field('City', L.editSelect(prefix, 2, CHILD)) + '</form>';
    const pg = page(body, { mapping: MAP });
    const child = editEl(pg, prefix, 2);
    assert.equal(child.disabled, true);
    assert.deepEqual(fieldEntries(pg, prefix, 2), [`${prefix}[custom_field_values][2]=`]);
    L.choose(pg.window, editEl(pg, prefix, 1), 'A');
    assert.equal(child.disabled, false);
    assert.deepEqual(L.visibleOptions(child), ['', 'a1', 'a2']);
  });
}

test('F19: nested prefix issues[7]: the name regex does not match, the prefix comes from the DOM id and selects are still filtered', () => {
  const sel = (id, values, opts) => L.editSelect('issues[7]', id, values, Object.assign({ id: `issues_7_custom_field_values_${id}` }, opts));
  const body = '<form id="inline">' + L.field('Country', sel(1, PARENT)) + L.field('City', sel(2, CHILD, { selected: 'b1' })) + '</form>';
  const pg = page(body, { mapping: MAP });
  const child = pg.document.getElementById('issues_7_custom_field_values_2');
  assert.equal(child.dataset.dependingPrefix, 'issues_7');
  assert.equal(child.disabled, true);
  assert.deepEqual(L.entries(pg.window), ['issues[7][custom_field_values][1]=', 'issues[7][custom_field_values][2]=']);
  L.choose(pg.window, pg.document.getElementById('issues_7_custom_field_values_1'), 'A');
  assert.deepEqual(L.visibleOptions(child), ['', 'a1', 'a2']);
});

test('F19: nested prefix issues[7]: a check box group child (no DOM id) is not discovered', () => {
  const body = '<form>' + L.field('Country', L.editSelect('issues[7]', 1, PARENT, { id: 'issues_7_custom_field_values_1', selected: 'A' })) +
    L.field('City', L.editCheckBoxes('issues[7]', 2, CHILD, { multiple: true, checked: ['b1'] })) + '</form>';
  const pg = page(body, { mapping: MAP });
  const span = pg.document.querySelector('span.check_box_group');
  assert.equal(span.dataset.dependingFieldId, undefined);
  assert.deepEqual(valuesWhere(span, labelHidden), []);
  assert.deepEqual(L.entries(pg.window, null, 'issues[7][custom_field_values][2]'),
    ['issues[7][custom_field_values][2][]=b1', 'issues[7][custom_field_values][2][]=']);
});

test('F19b: a third-party select without data attributes and with a foreign name is found by its DOM id and filtered', () => {
  const pg = page(issueForm({}, { name: 'cf_2' }), { mapping: MAP });
  const child = editEl(pg, 'issue', 2);
  assert.equal(child.classList.contains('depending-child'), true);
  assert.equal(child.disabled, true);
  assert.deepEqual(L.entries(pg.window, null, 'cf_2'), ['cf_2=']);
  L.choose(pg.window, editEl(pg, 'issue', 1), 'A');
  assert.deepEqual(L.visibleOptions(child), ['', 'a1', 'a2']);
});

test('F19c: #inline_edit_form: an empty multi select child posts a scalar "" (name without [])', () => {
  const pg = page(issueForm({}, { multiple: true }).replace('id="issue-form"', 'id="inline_edit_form"'), { mapping: MAP });
  assert.deepEqual(fieldEntries(pg, 'issue', 2), ['issue[custom_field_values][2]=']);
  L.choose(pg.window, editEl(pg, 'issue', 1), 'A');
  assert.deepEqual(fieldEntries(pg, 'issue', 2), ['issue[custom_field_values][2]=']);
  L.choose(pg.window, editEl(pg, 'issue', 2), ['a1']);
  assert.deepEqual(fieldEntries(pg, 'issue', 2), ['issue[custom_field_values][2][]=a1', 'issue[custom_field_values][2][]=a1']);
});

test('F20 (E1): existing record with an empty child and parent A: the default is filled at load and saved', () => {
  const pg = page(issueForm({ selected: 'A' }, {}), { mapping: withChild({ defaults: { A: 'a2' } }) });
  assert.equal(editEl(pg, 'issue', 2).value, 'a2');
  assert.deepEqual(fieldEntries(pg, 'issue', 2), ['issue[custom_field_values][2]=a2', 'issue[custom_field_values][2]=a2']);
});

// ---------------------------------------------------------------- bulk rows

for (const prefix of ['issue', 'time_entry']) {
  const row = (id) => (prefix === 'time_entry' ? `B7 ${id}` : id);

  test(`${row('B1 (A0)')} ${prefix}: parent "(no change)", untouched single child: enabled, posts "" once (no mirror input)`, () => {
    const pg = page(bulkForm(prefix), { mapping: MAP });
    const child = bulkEl(pg, prefix, 2);
    assert.equal(child.disabled, false);
    assert.deepEqual(L.visibleOptions(child), ['', '__none__']);
    assert.equal(mirrorOf(pg, child).children.length, 0);
    assert.deepEqual(fieldEntries(pg, prefix, 2), [`${prefix}[custom_field_values][2]=`]);
  });

  test(`${row('B1m (B)')} ${prefix}: untouched multi child posts nothing (WP-03 hotfix)`, () => {
    const pg = page(bulkForm(prefix, {}, { multiple: true }), { mapping: MAP });
    const child = bulkEl(pg, prefix, 2, true);
    assert.equal(child.id, `${prefix}_custom_field_values_2_`);
    assert.equal(child.disabled, false);
    assert.deepEqual(L.visibleOptions(child), ['__none__']);
    assert.deepEqual(fieldEntries(pg, prefix, 2), []);
  });

  test(`${row('B1r (B2)')} ${prefix}: required multi child (no __none__ option) is disabled and posts nothing (WP-03 hotfix)`, () => {
    const pg = page(bulkForm(prefix, {}, { multiple: true, required: true }), { mapping: MAP });
    assert.equal(bulkEl(pg, prefix, 2, true).disabled, true);
    assert.deepEqual(fieldEntries(pg, prefix, 2), []);
  });

  test(`${row('B2 (A1)')} ${prefix}: parent to A, no default: "(no change)" hidden but still selected, posts "" once`, () => {
    const pg = page(bulkForm(prefix), { mapping: MAP });
    const child = bulkEl(pg, prefix, 2);
    L.choose(pg.window, bulkEl(pg, prefix, 1), 'A');
    assert.equal(child.value, '');
    assert.equal(child.querySelector('option[value=""]').hidden, true);
    assert.deepEqual(L.visibleOptions(child), ['__none__', 'a1', 'a2']);
    assert.deepEqual(fieldEntries(pg, prefix, 2), [`${prefix}[custom_field_values][2]=`]);
  });

  test(`${row('B3 (A2, Q2)')} ${prefix}: parent "(none)": child disabled on __none__, the mirror posts __none__ once`, () => {
    const pg = page(bulkForm(prefix), { mapping: MAP });
    const child = bulkEl(pg, prefix, 2);
    L.choose(pg.window, bulkEl(pg, prefix, 1), '__none__');
    assert.equal(child.disabled, true);
    assert.equal(child.value, '__none__');
    assert.deepEqual(fieldEntries(pg, prefix, 2), [`${prefix}[custom_field_values][2]=__none__`]);
  });

  test(`${row('B6 (M)')} ${prefix}: hide_when_disabled hides the child <p> while the parent is "(no change)" or "(none)"`, () => {
    const pg = page(bulkForm(prefix), { mapping: withChild({ hide_when_disabled: true }) });
    const p = bulkEl(pg, prefix, 2).closest('p');
    assert.equal(p.hidden, true);
    L.choose(pg.window, bulkEl(pg, prefix, 1), 'A');
    assert.equal(p.hidden, false);
    L.choose(pg.window, bulkEl(pg, prefix, 1), '__none__');
    assert.equal(p.hidden, true);
  });
}

test('B1r (B2): required multi child, parent to A: enabled, nothing selected, still posts nothing', () => {
  const pg = page(bulkForm('issue', {}, { multiple: true, required: true }), { mapping: MAP });
  L.choose(pg.window, bulkEl(pg, 'issue', 1), 'A');
  const child = bulkEl(pg, 'issue', 2, true);
  assert.equal(child.disabled, false);
  assert.deepEqual(L.visibleOptions(child), ['a1', 'a2']);
  assert.deepEqual(fieldEntries(pg, 'issue', 2), []);
});

test('B2 (A1): multi child, parent to A: nothing selected, posts nothing', () => {
  const pg = page(bulkForm('issue', {}, { multiple: true }), { mapping: MAP });
  L.choose(pg.window, bulkEl(pg, 'issue', 1), 'A');
  assert.deepEqual(L.visibleOptions(bulkEl(pg, 'issue', 2, true)), ['__none__', 'a1', 'a2']);
  assert.deepEqual(fieldEntries(pg, 'issue', 2), []);
});

test("B2d (A'): parent to A with default a1: child a1, posted twice (select and mirror)", () => {
  const pg = page(bulkForm('issue'), { mapping: withChild({ defaults: { A: 'a1' } }) });
  L.choose(pg.window, bulkEl(pg, 'issue', 1), 'A');
  assert.equal(bulkEl(pg, 'issue', 2).value, 'a1');
  assert.deepEqual(fieldEntries(pg, 'issue', 2), ['issue[custom_field_values][2]=a1', 'issue[custom_field_values][2]=a1']);
});

test('B2e: parent value without links: child stays on the hidden "(no change)", only __none__ visible, posts ""', () => {
  const pg = page(bulkForm('issue'), { mapping: MAP });
  const child = bulkEl(pg, 'issue', 2);
  L.choose(pg.window, bulkEl(pg, 'issue', 1), 'C');
  assert.equal(child.value, '');
  assert.equal(child.disabled, false);
  assert.deepEqual(L.visibleOptions(child), ['__none__']);
  assert.deepEqual(fieldEntries(pg, 'issue', 2), ['issue[custom_field_values][2]=']);
});

test('B2g (Q1): grandchild stays on a visible "(no change)" while its parent sits on the hidden "(no change)"', () => {
  const body = bulkForm('issue', {}, {}, L.field('Street', L.bulkSelect('issue', 3, GRAND)));
  const pg = page(body, { mapping: chain() });
  L.choose(pg.window, bulkEl(pg, 'issue', 1), 'A');
  const grand = bulkEl(pg, 'issue', 3);
  assert.equal(bulkEl(pg, 'issue', 2).value, '');
  assert.equal(grand.value, '');
  assert.deepEqual(L.visibleOptions(grand), ['', '__none__']);
  assert.deepEqual(fieldEntries(pg, 'issue', 3), ['issue[custom_field_values][3]=']);
});

test('B2g (Q1): when the child got a default, the grandchild is filtered and stays on a hidden "(no change)"', () => {
  const body = bulkForm('issue', {}, {}, L.field('Street', L.bulkSelect('issue', 3, GRAND)));
  const pg = page(body, { mapping: chain({ defaults: { A: 'a1' } }) });
  L.choose(pg.window, bulkEl(pg, 'issue', 1), 'A');
  const grand = bulkEl(pg, 'issue', 3);
  assert.equal(bulkEl(pg, 'issue', 2).value, 'a1');
  assert.equal(grand.value, '');
  assert.deepEqual(L.visibleOptions(grand), ['__none__', 'x1']);
});

test('B3 (A2, Q2): parent "(none)" cascades: the grandchild is disabled on __none__ too', () => {
  const body = bulkForm('issue', {}, {}, L.field('Street', L.bulkSelect('issue', 3, GRAND)));
  const pg = page(body, { mapping: chain() });
  L.choose(pg.window, bulkEl(pg, 'issue', 1), '__none__');
  assert.equal(bulkEl(pg, 'issue', 3).disabled, true);
  assert.deepEqual(L.entries(pg.window), ['issue[custom_field_values][1]=__none__', 'issue[custom_field_values][2]=__none__',
    'issue[custom_field_values][3]=__none__']);
});

test('B3 (A2): multi child, parent "(none)": the mirror posts a scalar __none__ (name without [])', () => {
  const pg = page(bulkForm('issue', {}, { multiple: true }), { mapping: MAP });
  L.choose(pg.window, bulkEl(pg, 'issue', 1), '__none__');
  const child = bulkEl(pg, 'issue', 2, true);
  assert.equal(child.disabled, true);
  assert.deepEqual(L.selectedValues(child), ['__none__']);
  assert.deepEqual(fieldEntries(pg, 'issue', 2), ['issue[custom_field_values][2]=__none__']);
});

test('B3r (U2): required single child (no __none__ option): disabled from load, parent "(none)" leaves no selection and posts nothing', () => {
  const pg = page(bulkForm('issue', {}, { required: true }), { mapping: MAP });
  const child = bulkEl(pg, 'issue', 2);
  assert.equal(child.disabled, true);
  assert.deepEqual(fieldEntries(pg, 'issue', 2), []);
  L.choose(pg.window, bulkEl(pg, 'issue', 1), '__none__');
  assert.equal(child.disabled, true);
  assert.deepEqual(L.selectedValues(child), []);
  assert.deepEqual(fieldEntries(pg, 'issue', 2), []);
});

test('B4: parent back to "(no change)" after "(none)": the forced __none__ is kept, now enabled and posted twice', () => {
  const pg = page(bulkForm('issue'), { mapping: MAP });
  const child = bulkEl(pg, 'issue', 2);
  L.choose(pg.window, bulkEl(pg, 'issue', 1), '__none__');
  L.choose(pg.window, bulkEl(pg, 'issue', 1), '');
  assert.equal(child.value, '__none__');
  assert.equal(child.disabled, false);
  assert.deepEqual(L.visibleOptions(child), ['', '__none__']);
  assert.deepEqual(fieldEntries(pg, 'issue', 2), ['issue[custom_field_values][2]=__none__', 'issue[custom_field_values][2]=__none__']);
});

test('B4: parent back to "(no change)" after a default a1: the child returns to a visible "(no change)"', () => {
  const pg = page(bulkForm('issue'), { mapping: withChild({ defaults: { A: 'a1' } }) });
  const child = bulkEl(pg, 'issue', 2);
  L.choose(pg.window, bulkEl(pg, 'issue', 1), 'A');
  L.choose(pg.window, bulkEl(pg, 'issue', 1), '');
  assert.equal(child.value, '');
  assert.equal(child.querySelector('option[value=""]').hidden, false);
  assert.deepEqual(fieldEntries(pg, 'issue', 2), ['issue[custom_field_values][2]=']);
});

test('B5: a1 set under "(no change)" (option hidden, so only programmatically) is kept when the parent becomes A', () => {
  const pg = page(bulkForm('issue'), { mapping: MAP });
  const child = bulkEl(pg, 'issue', 2);
  assert.equal(child.querySelector('option[value="a1"]').hidden, true);
  L.choose(pg.window, child, 'a1');
  L.choose(pg.window, bulkEl(pg, 'issue', 1), 'A');
  assert.equal(child.value, 'a1');
  assert.deepEqual(fieldEntries(pg, 'issue', 2), ['issue[custom_field_values][2]=a1', 'issue[custom_field_values][2]=a1']);
});

test('B8: bulk refresh (#content replaced): the new form is rescanned 100 ms after ajaxComplete and keeps the re-rendered values', () => {
  const pg = page(`<div id="content">${bulkForm('issue')}</div>`, { mapping: MAP, jquery: true });
  const $ = pg.window.jQuery;
  L.choose(pg.window, bulkEl(pg, 'issue', 1), 'A');
  L.choose(pg.window, bulkEl(pg, 'issue', 2), 'a2');
  assert.equal(decode($('#bulk_edit_form').serialize()),
    'issue[custom_field_values][1]=A&issue[custom_field_values][2]=a2&issue[custom_field_values][2]=a2');
  $('#content').html(bulkForm('issue', { selected: 'A' }, { selected: 'a2' }));
  const child = bulkEl(pg, 'issue', 2);
  assert.deepEqual(L.visibleOptions(child), ['', '__none__', 'a1', 'a2', 'b1']);
  $(pg.document).trigger('ajaxComplete');
  pg.clock.tick(99);
  assert.equal(child.classList.contains('depending-child'), false);
  pg.clock.tick(1);
  assert.equal(child.value, 'a2');
  assert.deepEqual(L.visibleOptions(child), ['__none__', 'a1', 'a2']);
  assert.deepEqual(fieldEntries(pg, 'issue', 2), ['issue[custom_field_values][2]=a2', 'issue[custom_field_values][2]=a2']);
});

test('B9: bulk parent not common to the selection (absent): the child stays unfiltered and posts ""', () => {
  const pg = page(`<form id="bulk_edit_form">${L.field('City', L.bulkSelect('issue', 2, CHILD))}</form>`, { mapping: MAP });
  const child = bulkEl(pg, 'issue', 2);
  assert.deepEqual(L.visibleOptions(child), ['', '__none__', 'a1', 'a2', 'b1']);
  assert.equal(child.classList.contains('depending-child'), false);
  assert.deepEqual(L.entries(pg.window), ['issue[custom_field_values][2]=']);
});

// ---------------------------------------------------------------- wizard rows

const wizardMenu = (rootDefault) => {
  const field = (label, html) => `<div class="cf-wizard-field"><span class="field-description">${label}</span>${html}</div>`;
  return '<div id="context-menu"><ul>' +
    '<li class="folder cf-parent" data-parent-id="1" data-issue-ids="5,6" data-template-id="cf-wizard-1">' +
    '<a href="#" class="submenu" data-template-id="cf-wizard-1">Country</a></li>' +
    '<template id="cf-wizard-1"><form class="cf-wizard-form" data-parent-id="1" data-issue-ids="5,6">' +
    '<input type="hidden" name="ids[]" value="5" /><input type="hidden" name="ids[]" value="6" />' +
    '<input type="hidden" name="issue_ids" value="5,6" /><input type="hidden" name="authenticity_token" value="tok" />' +
    '<div class="cf-cols">' +
    `<div class="cf-col" data-level="0">${field('Country', L.bulkSelect('issue', 1, PARENT, { dataFieldId: '1', selected: rootDefault }))}</div>` +
    `<div class="cf-col" data-level="1">${field('City', L.bulkSelect('issue', 2, CHILD, { dataFieldId: '2' }))}</div>` +
    '</div><div class="cf-actions"><button type="submit" class="icon icon-save">Save</button></div></form></template>' +
    '</ul></div>';
};
const openWizard = (pg) => {
  const link = pg.document.querySelector('li.cf-parent > a.submenu');
  link.dispatchEvent(new pg.window.MouseEvent('click', { bubbles: true, cancelable: true }));
  return pg.document.getElementById('cf-wizard-container');
};
const stubFetch = (pg) => {
  const calls = [];
  pg.window.fetch = (url, init) => { calls.push({ url, body: String(init.body) }); return new Promise(() => {}); };
  return calls;
};
const submit = (pg, form) => form.dispatchEvent(new pg.window.Event('submit', { bubbles: true, cancelable: true }));

test('W1 (J): wizard open: root preselected to its default, setup delayed 100 ms, Save writes the default (twice)', async () => {
  const pg = await realPage(wizardMenu('A'), { mapping: MAP, wizard: true });
  const calls = stubFetch(pg);
  const container = openWizard(pg);
  assert.equal(container.style.display, 'block');
  const root = container.querySelector('select[data-field-id="1"]');
  const child = container.querySelector('select[data-field-id="2"]');
  assert.equal(root.value, 'A');
  assert.equal(pg.clock.pending(), 1);
  pg.clock.tick(99);
  assert.equal(child.classList.contains('depending-child'), false);
  pg.clock.tick(1);
  assert.equal(child.classList.contains('depending-child'), true);
  assert.deepEqual(L.visibleOptions(child), ['__none__', 'a1', 'a2']);
  submit(pg, container.querySelector('form'));
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, '/depending_custom_fields/save');
  assert.deepEqual(Array.from(new URLSearchParams(calls[0].body)).filter(([k]) => k.startsWith('issue[')),
    [['issue[custom_field_values][1]', 'A'], ['issue[custom_field_values][1]', 'A'], ['issue[custom_field_values][2]', '']]);
});

test('W2 (J, K): wizard parent "(none)": child disabled plus mirror __none__, the parent is posted twice', async () => {
  const pg = await realPage(wizardMenu('A'), { mapping: MAP, wizard: true });
  const container = openWizard(pg);
  pg.clock.tick(100);
  const form = container.querySelector('form');
  L.choose(pg.window, container.querySelector('select[data-field-id="1"]'), '__none__');
  assert.equal(container.querySelector('select[data-field-id="2"]').disabled, true);
  assert.deepEqual(L.entries(pg.window, form, 'issue['), ['issue[custom_field_values][1]=__none__',
    'issue[custom_field_values][1]=__none__', 'issue[custom_field_values][2]=__none__']);
});

test('W3: wizard submit URL is basePath + /depending_custom_fields/save; without ContextMenuWizardConfig it throws a TypeError', async () => {
  const pg = await realPage(wizardMenu('A'), { mapping: MAP, wizard: true, basePath: '/redmine' });
  const calls = stubFetch(pg);
  submit(pg, openWizard(pg).querySelector('form'));
  assert.deepEqual(calls.map((c) => c.url), ['/redmine/depending_custom_fields/save']);

  const bare = await realPage(wizardMenu('A'), { mapping: MAP, wizard: true, wizardConfig: false });
  bare.expectErrors = true;
  const bareCalls = stubFetch(bare);
  submit(bare, openWizard(bare).querySelector('form'));
  assert.deepEqual(bareCalls, []);
  assert.equal(bare.errors.length, 1);
  assert.equal(bare.errors[0].name, 'TypeError');
  assert.match(bare.errors[0].message, /basePath/);
});

// W4 (non-JSON error body) is not pinned: the legacy code leaves an unhandled
// promise rejection, which would fail the test process. W6 is server markup.

test('W5: a wizard child whose parent is not in the wizard binds to the issue form parent (document-wide lookup)', () => {
  const body = `<form id="issue-form">${L.field('Country', L.editSelect('issue', 1, PARENT, { selected: 'B' }))}</form>` +
    '<div id="cf-wizard-container" class="context-menu cf-wizard"><form class="cf-wizard-form">' +
    `<div class="cf-wizard-field"><span>City</span>${L.bulkSelect('issue', 2, CHILD, { dataFieldId: '2' })}</div></form></div>`;
  const pg = page(body, { mapping: MAP, setup: false });
  pg.window.DependingCustomFields.setup(pg.document.getElementById('cf-wizard-container'));
  const child = pg.document.querySelector('#cf-wizard-container select');
  assert.deepEqual(L.visibleOptions(child), ['__none__', 'b1']);
  L.choose(pg.window, editEl(pg, 'issue', 1), 'A');
  assert.deepEqual(L.visibleOptions(child), ['__none__', 'a1', 'a2']);
});

// ---------------------------------------------------------------- cross rows

test('X1 (F, N0): setup fires one change event per discovered child, even when nothing changed', () => {
  const pg = page(issueForm(), { mapping: MAP });
  assert.deepEqual(pg.changes, ['issue_custom_field_values_2']);
  pg.window.DependingCustomFields.setup();
  assert.deepEqual(pg.changes, ['issue_custom_field_values_2']);
  pg.changes.length = 0;
  editEl(pg, 'issue', 1).dispatchEvent(new pg.window.Event('change', { bubbles: true }));
  assert.deepEqual(pg.changes, ['issue_custom_field_values_1', 'issue_custom_field_values_2']);
});

test('X2 (C, D, S): a self-parent recurses through change events until a RangeError ends it; setup returns', () => {
  const body = `<form>${L.field('Country', L.editSelect('issue', 1, PARENT, { selected: 'A' }))}</form>`;
  const pg = page(body, { mapping: { 1: { parent_id: '1', map: { A: ['A'] }, defaults: {}, hide_when_disabled: false } } });
  pg.expectErrors = true;
  assert.ok(pg.errors.length >= 1);
  pg.errors.forEach((e) => { assert.equal(e.name, 'RangeError'); assert.match(e.message, /Maximum call stack/); });
  assert.ok(pg.changes.length > 10, `expected a change storm, got ${pg.changes.length}`);
});

test('X2 (C, D, S): a stored two-field cycle recurses through change events until a RangeError ends it; setup returns', () => {
  const mapping = {
    1: { parent_id: '2', map: { a1: ['A'] }, defaults: {}, hide_when_disabled: false },
    2: { parent_id: '1', map: { A: ['a1'] }, defaults: {}, hide_when_disabled: false }
  };
  let pg;
  assert.doesNotThrow(() => { pg = page(issueForm({ selected: 'A' }, { selected: 'a1' }), { mapping }); });
  pg.expectErrors = true;
  assert.ok(pg.errors.length >= 1);
  pg.errors.forEach((e) => { assert.equal(e.name, 'RangeError'); assert.match(e.message, /Maximum call stack/); });
  assert.ok(pg.changes.length > 10, `expected a change storm, got ${pg.changes.length}`);
});

test('X3: discovery scans every mapping key by id suffix: unrelated elements are touched, ids outside the mapping are not', () => {
  const body = issueForm() +
    '<div id="query_form"><select id="query_custom_field_values_2" name="v[cf_2][]"><option value="a1">a1</option><option value="b1">b1</option></select></div>' +
    `<div id="filters">${L.editSelect('filter', 1, PARENT, { selected: 'A' })}${L.editSelect('filter', 2, CHILD)}</div>` +
    '<select id="foo_custom_field_values_9"><option value="z">z</option></select>';
  const pg = page(body, { mapping: MAP });
  const orphan = pg.document.getElementById('query_custom_field_values_2');
  assert.equal(orphan.dataset.dependingFieldId, '2');
  assert.equal(orphan.dataset.dependingPrefix, 'query');
  assert.equal(orphan.classList.contains('depending-child'), false);
  assert.deepEqual(L.visibleOptions(editEl(pg, 'filter', 2)), ['', 'a1', 'a2']);
  assert.deepEqual(Object.keys(pg.document.getElementById('foo_custom_field_values_9').dataset), []);
});

test('X4: a jQuery-triggered change on the parent (select2 style) is missed', () => {
  const pg = page(issueForm(), { mapping: MAP, jquery: true });
  pg.window.jQuery('#issue_custom_field_values_1').val('A').trigger('change');
  assert.equal(editEl(pg, 'issue', 2).disabled, true);
  assert.deepEqual(L.visibleOptions(editEl(pg, 'issue', 2)), ['']);
});

test('X6: loaded from the page head (no <body> yet), the context-menu observer is never attached', async () => {
  const pg = await realPage(issueForm(), { mapping: MAP });
  assert.equal(pg.window.bodyAtLoad, false);
  const menu = pg.document.createElement('div');
  menu.id = 'context-menu';
  pg.document.body.appendChild(menu);
  menu.innerHTML = `<ul><li id="cf-li">${L.bulkSelect('issue', 2, CHILD)}</li></ul>`;
  await L.flush();
  pg.clock.tick(1000);
  assert.equal(menu.dataset.dependingObserver, undefined);
  assert.equal(pg.document.getElementById('cf-li').style.display, '');
});

test('X6: evaluated after <body> exists (harness only), the observer attaches and hides a child <li> in #context-menu after 100 ms', async () => {
  const pg = page(issueForm(), { mapping: MAP });
  await L.loaded(pg.window);
  const menu = pg.document.createElement('div');
  menu.id = 'context-menu';
  pg.document.body.appendChild(menu);
  await L.flush();
  assert.equal(menu.dataset.dependingObserver, '1');
  pg.clock.tick(100);
  menu.innerHTML = `<ul><li id="cf-li">${L.bulkSelect('issue', 2, CHILD)}</li></ul>`;
  await L.flush();
  pg.clock.tick(99);
  assert.equal(pg.document.getElementById('cf-li').style.display, '');
  pg.clock.tick(1);
  assert.equal(pg.document.getElementById('cf-li').style.display, 'none');
});

test('X7: window.DependingCustomFields exposes setup and requestSetup; requestSetup debounces 100 ms', () => {
  const pg = page('<form id="f1">' + L.field('Country', L.editSelect('issue', 1, PARENT)) + '</form>', { mapping: MAP });
  assert.deepEqual(Object.keys(pg.window.DependingCustomFields).sort(), ['requestSetup', 'setup']);
  pg.document.getElementById('f1').insertAdjacentHTML('beforeend', L.field('City', L.editSelect('issue', 2, CHILD)));
  const child = editEl(pg, 'issue', 2);
  pg.window.DependingCustomFields.requestSetup();
  pg.clock.tick(50);
  pg.window.DependingCustomFields.requestSetup();
  pg.clock.tick(99);
  assert.equal(child.classList.contains('depending-child'), false);
  pg.clock.tick(1);
  assert.equal(child.classList.contains('depending-child'), true);
  assert.equal(pg.clock.pending(), 0);
});

test('X7: requestSetup shares one timer: a second call with another root cancels the first root', () => {
  const body = '<form id="f1">' + L.field('Country', L.editSelect('issue', 1, PARENT)) + '</form>' +
    '<form id="f2">' + L.field('Country', L.editSelect('time_entry', 1, PARENT)) + '</form>';
  const pg = page(body, { mapping: MAP });
  pg.document.getElementById('f1').insertAdjacentHTML('beforeend', L.field('City', L.editSelect('issue', 2, CHILD)));
  pg.document.getElementById('f2').insertAdjacentHTML('beforeend', L.field('City', L.editSelect('time_entry', 2, CHILD)));
  pg.window.DependingCustomFields.requestSetup(pg.document.getElementById('f1'));
  pg.clock.tick(50);
  pg.window.DependingCustomFields.requestSetup(pg.document.getElementById('f2'));
  pg.clock.tick(100);
  assert.equal(editEl(pg, 'issue', 2).classList.contains('depending-child'), false);
  assert.equal(editEl(pg, 'time_entry', 2).classList.contains('depending-child'), true);
});

test('X7: requestSetup with real timers runs setup after the 100 ms debounce', async () => {
  const pg = page('<form id="f1">' + L.field('Country', L.editSelect('issue', 1, PARENT)) + '</form>', { mapping: MAP, clock: false });
  await L.loaded(pg.window);
  pg.document.getElementById('f1').insertAdjacentHTML('beforeend', L.field('City', L.editSelect('issue', 2, CHILD)));
  pg.window.DependingCustomFields.requestSetup(pg.document.getElementById('f1'));
  assert.equal(editEl(pg, 'issue', 2).classList.contains('depending-child'), false);
  await new Promise((resolve) => setTimeout(resolve, 150));
  assert.equal(editEl(pg, 'issue', 2).classList.contains('depending-child'), true);
});

test('X8: without the DependingCustomFieldData global, setup is a no-op', () => {
  const pg = page(issueForm({}, { selected: 'b1' }), {});
  assert.equal(pg.window.DependingCustomFieldData, undefined);
  assert.equal(editEl(pg, 'issue', 2).value, 'b1');
  assert.equal(editEl(pg, 'issue', 2).disabled, false);
  assert.equal(pg.document.forms[0].outerHTML.includes('data-depending'), false);
  assert.deepEqual(pg.changes, []);
});

test('X8: the global is read at setup time, so the inline script after the script tag (head hook order) works', async () => {
  const pg = await realPage(issueForm({ selected: 'A' }, { selected: 'b1' }), { mapping: MAP });
  const child = editEl(pg, 'issue', 2);
  assert.equal(child.classList.contains('depending-child'), true);
  assert.deepEqual(L.visibleOptions(child), ['', 'a1', 'a2']);
  assert.equal(child.value, '');
});

test('X8: a global wrapped as { mapping: {...} } is accepted', () => {
  const pg = page(issueForm(), { mapping: { mapping: MAP } });
  assert.equal(editEl(pg, 'issue', 2).disabled, true);
});

test('X10: no hint or accessibility attribute is added', () => {
  const pg = page(issueForm(), { mapping: MAP });
  L.choose(pg.window, editEl(pg, 'issue', 1), 'C');
  assert.equal(pg.document.querySelector('[aria-describedby], [aria-live], [role="status"]'), null);
});
