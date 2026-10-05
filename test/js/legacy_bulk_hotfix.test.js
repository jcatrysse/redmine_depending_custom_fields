'use strict';
// WP-03 hotfix: core bulk edit forms have id "bulk_edit_form" (issues and time
// entries). The script looked for "#bulk-edit-form", treated the page as a
// regular form and posted an empty value for untouched multi-value children,
// which cleared them on every selected record.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');

const SCRIPT = fs.readFileSync(path.join(__dirname, '..', '..', 'assets', 'javascripts', 'depending_custom_fields.js'), 'utf8');
const MAPPING = { 2: { parent_id: '1', map: { A: ['a1', 'a2'], B: ['b1'] }, defaults: {}, hide_when_disabled: false } };

function select(prefix, fieldId, options, extra) {
  const multiple = /multiple/.test(extra || '');
  const name = `${prefix}[custom_field_values][${fieldId}]${multiple ? '[]' : ''}`;
  const opts = options.map((v) => `<option value="${v}">${v || 'blank'}</option>`).join('');
  return `<select name="${name}" id="${prefix}_custom_field_values_${fieldId}" ${extra || ''}>${opts}</select>`;
}

function bulkPage(prefix, childOptions, childExtra) {
  const html = `<form id="bulk_edit_form"><p>${select(prefix, 1, ['', '__none__', 'A', 'B'])}</p>` +
    `<p>${select(prefix, 2, childOptions, childExtra)}</p></form>`;
  const dom = new JSDOM(`<!doctype html><html><head></head><body>${html}</body></html>`, { runScripts: 'outside-only' });
  dom.window.DependingCustomFieldData = MAPPING;
  dom.window.eval(SCRIPT);
  dom.window.DependingCustomFields.setup();
  return dom.window;
}

function childEntries(window, prefix) {
  return Array.from(new window.FormData(window.document.forms[0]).entries())
    .filter(([key]) => key.startsWith(`${prefix}[custom_field_values][2]`))
    .map(([key, value]) => `${key}=${value}`);
}

for (const prefix of ['issue', 'time_entry']) {
  test(`${prefix}: an untouched multi-value child posts nothing (no change)`, () => {
    const window = bulkPage(prefix, ['__none__', 'a1', 'a2', 'b1'], 'multiple');
    assert.deepEqual(childEntries(window, prefix), []);
  });

  test(`${prefix}: an untouched required multi-value child posts no empty value`, () => {
    const window = bulkPage(prefix, ['a1', 'a2', 'b1'], 'multiple');
    assert.deepEqual(childEntries(window, prefix).filter((entry) => entry.endsWith('=')), []);
  });
}

test('choosing a parent value still hides "(no change)" on the child and posts one child value', () => {
  const window = bulkPage('issue', ['', '__none__', 'a1', 'a2', 'b1']);
  const parent = window.document.getElementById('issue_custom_field_values_1');
  const child = window.document.getElementById('issue_custom_field_values_2');
  parent.value = 'A';
  parent.dispatchEvent(new window.Event('change', { bubbles: true }));

  assert.equal(child.querySelector('option[value=""]').hidden, true);
  assert.equal(childEntries(window, 'issue').length, 1);
});
