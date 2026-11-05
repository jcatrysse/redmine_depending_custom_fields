'use strict';
// Chromium walkthrough of 2026-11-05 (docs/reviews/chromium-walkthrough-2026-11-05.md):
// the issue-form runtime findings ux-7 (hint aligned with the indented
// control), ux-10 (a required field whose parent value allows nothing) and
// ux-11 (a form re-rendered after a refused save keeps a posted blank).
const { test, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const D = require('./support/dom');
const F = require('./support/fixtures');
const fire = require('./support/fire');

afterEach(D.closeAll);

const PARENT = 'issue[custom_field_values][9100001]';
const CHILD = 'issue[custom_field_values][9100002]';
const load = (source, opts) => D.page(source.includes('<') ? source : F.read(source), opts);
const child = (pg) => D.control(pg.document, '9100002');
const parentOf = (pg) => D.byName(pg.document, PARENT);

// ux-7: the hint of a dependent field carries the indent class of its control.
test('the hint of a dependent field is marked for the indent of its control (ux-7)', async () => {
  const pg = await load('legacy_value');
  const c = child(pg);
  assert.ok(c.classList.contains('depending-child'));
  assert.ok(D.hint(c).classList.contains('dcf-hint--child'));
  fire.choose(pg.window, parentOf(pg), 'Gamma');
  assert.ok(D.hint(c).classList.contains('dcf-hint--child'));
});

// ux-10: a required field whose parent value allows nothing stays empty and
// the form can still be saved (UD-10); an optional field keeps its text.
test('a required field whose parent value allows nothing says that it stays empty and the form can be saved (ux-10)', async () => {
  const pg = await load('list_single_required');
  const c = child(pg);
  fire.choose(pg.window, parentOf(pg), 'Gamma');
  assert.deepEqual([D.selected(c), D.state(c)], [[''], 'empty']);
  assert.equal(D.hintText(c),
    'No values are available for the selected Parent field, so this required field stays empty and the form can still be saved.');

  const optional = await load('legacy_value');
  fire.choose(optional.window, parentOf(optional), 'Gamma');
  assert.equal(D.hintText(child(optional)), 'No values are available for the selected Parent field.');
});

test('the required text comes from the meta tag when it is present (ux-10)', async () => {
  const pg = await load('list_single_required', { meta: { noOptionsRequired: 'Leer: %{parent}.' } });
  fire.choose(pg.window, parentOf(pg), 'Gamma');
  assert.equal(D.hintText(child(pg)), 'Leer: Parent field.');
});

// ux-11: core renders div#errorExplanation inside the form after a refused
// save; the runtime keeps the posted blank there instead of the default.
const reRendered = (withErrors, parent) => F.tweak('new_issue', (doc) => {
  F.selectValues(F.named(doc, PARENT), [parent || 'Alpha']);
  F.selectValues(F.named(doc, CHILD), ['']);
  if (withErrors) {
    const box = doc.createElement('div');
    box.id = 'errorExplanation';
    box.textContent = 'Child field cannot be blank';
    doc.querySelector('form').insertBefore(box, doc.querySelector('form').firstChild);
  }
});

test('a new form re-rendered after a refused save keeps the posted blank, a fresh one takes the default (ux-11)', async () => {
  const errored = await load(reRendered(true));
  assert.deepEqual(D.selected(child(errored)), ['']);
  assert.deepEqual(errored.changes, []);

  const fresh = await load(reRendered(false));
  assert.deepEqual(D.selected(child(fresh)), ['Ape']);
});

test('after a refused save a parent change still applies the default of the new parent value (ux-11)', async () => {
  const pg = await load(reRendered(true, 'Beta'));
  const c = child(pg);
  assert.deepEqual(D.selected(c), ['']);
  fire.choose(pg.window, parentOf(pg), 'Alpha');
  assert.deepEqual(D.selected(c), ['Ape']);
});
