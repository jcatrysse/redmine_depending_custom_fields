'use strict';
// WP-25 (limits design 4.10, editor design 5.9, gap 12): the advisory client
// storage estimate of the editor. With data-dcf-editor-storage-limit the
// mapping estimate is storage-base + ceil(utf8(JSON {value_dependencies,
// default_value_dependencies}) x 1.2 (list) or 1.6 (enumeration)); with
// data-dcf-editor-values-limit the possible values cost 4 + sum(utf8(v) + 3)
// (duplicates counted). One div.flash.warning with text_dcf_storage_estimate
// per estimate at or above storage-warn percent; never without the
// attribute; never blocking. mysql_limit carries {{BYTES}} as its base.
const { test, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const E = require('./support/editor_page');
const M = require('../../assets/javascripts/dcf_dependency_editor_model.js');

afterEach(() => E.closeAll());

const LIMIT = 65535;
// The smallest estimate that warns at 90 percent of 65,535 bytes.
const THRESHOLD = Math.ceil((LIMIT * 90) / 100);

// The mapping bytes the editor measures for the untouched mysql_limit page.
function mappingBytes() {
  const html = E.fixture('mysql_limit');
  const attr = (name) => {
    const raw = html.match(new RegExp(`data-dcf-editor-${name}="([^"]*)"`))[1];
    return raw.replace(/&quot;/g, '"').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
  };
  const payload = M.serialize(new M.State(JSON.parse(attr('mapping'))), M.ValueList.fromWire(JSON.parse(attr('parent-values'))),
    M.ValueList.fromWire(M.listValuesFromText(E.LIST_VALUES.join('\n'))), { multiple: false, kind: 'list', base: attr('base') });
  return M.utf8Bytes(JSON.stringify({ value_dependencies: payload.value_dependencies,
                                      default_value_dependencies: payload.default_value_dependencies }));
}

const withBase = (bytes) => E.fixture('mysql_limit').replace('{{BYTES}}', String(bytes));
const warnings = (p) => Array.from(p.root.querySelectorAll('.flash.warning'))
  .filter((n) => n.textContent.includes('bytes that can be stored'));

test('mapping estimate: one warning at 90 percent of the storage limit, none one byte below', async () => {
  const cost = Math.ceil(mappingBytes() * 1.2);
  const at = await E.load('mysql_limit', { html: withBase(THRESHOLD - cost) });
  const shown = warnings(at);
  assert.equal(shown.length, 1);
  assert.equal(shown[0].getAttribute('data-dcf-ed-notice'), 'storage_mapping');
  assert.equal(shown[0].textContent, at.t('storageEstimate', { label: 'Dependency mapping', size: '58,982', limit: '65,535',
                                                               percent: '90' }));
  assert.equal(at.submit().defaultPrevented, false, 'advisory only');

  const below = await E.load('mysql_limit', { html: withBase(THRESHOLD - cost - 1) });
  assert.equal(warnings(below).length, 0);
});

test('mapping estimate follows the state: a new link can raise the warning, removing links clears it', async () => {
  const cost = Math.ceil(mappingBytes() * 1.2);
  const p = await E.load('mysql_limit', { html: withBase(THRESHOLD - cost - 1) });
  assert.equal(warnings(p).length, 0);
  p.tick(p.open(p.section('Germany')), 'Lyon');
  p.clock.tick(150);
  assert.equal(warnings(p).length, 1);
  p.root.querySelector('details[data-dcf-ed-section="Germany"]').querySelector('[data-dcf-ed-uncheck-shown]').click();
  p.open(p.section('Belgium')).querySelector('[data-dcf-ed-uncheck-shown]').click();
  p.clock.tick(150);
  assert.equal(warnings(p).length, 0);
});

test('no warning without data-dcf-editor-storage-limit, however large the mapping', async () => {
  const children = Array.from({ length: 3000 }, (_, i) => `child value number ${i} ${'x'.repeat(20)}`);
  const p = await E.load('admin_list', { form: { values: children } });
  ['Belgium', 'France', 'Germany'].forEach((k) => p.open(p.section(k)).querySelector('[data-dcf-ed-check-shown]').click());
  p.clock.tick(150);
  assert.ok(Buffer.byteLength(p.input.value) > LIMIT * 3);
  assert.equal(warnings(p).length, 0);
  assert.equal(p.root.querySelectorAll('.flash.warning').length, 1, 'only the orphans notice');
});

test('possible-values estimate against data-dcf-editor-values-limit (duplicates counted)', async () => {
  const base = 4 + E.LIST_VALUES.reduce((sum, v) => sum + Buffer.byteLength(v) + 3, 0);
  const pad = THRESHOLD - base - 3;
  const load = (values) => E.load('mysql_limit', { html: withBase(0), form: { values } });
  const at = await load(E.LIST_VALUES.concat(['y'.repeat(pad)]));
  const notice = at.notice('storage_values');
  assert.equal(notice.textContent, at.t('storageEstimate', { label: 'Possible values', size: '58,982', limit: '65,535',
                                                             percent: '90' }));
  assert.equal(at.notice('storage_mapping'), null);

  const below = await load(E.LIST_VALUES.concat(['y'.repeat(pad - 1)]));
  assert.equal(below.notice('storage_values'), null);
  const duplicate = await load(E.LIST_VALUES.concat(['Lyon', 'y'.repeat(pad - 7)]));
  assert.ok(duplicate.notice('storage_values'), 'a repeated value counts twice');

  const textarea = below.document.querySelector('#custom_field_possible_values');
  textarea.value = `${textarea.value}\nz`;
  below.fire(textarea, 'input');
  below.clock.tick(299);
  assert.equal(below.notice('storage_values'), null);
  below.clock.tick(1);
  assert.ok(below.notice('storage_values'));
});

// WP-31: the project fixtures carry the effective limit (2 MiB) and their
// tiny mappings stay far below it; admin_enumeration has no limit at all.
test('enumeration and project fixtures show no estimate: no values limit and a mapping far below the limit', async () => {
  for (const name of ['admin_enumeration', 'project_list', 'project_enumeration']) {
    const p = await E.load(name);
    assert.equal(p.notice('storage_values'), null, name);
    assert.equal(p.notice('storage_mapping'), null, name);
  }
});

// WP-31 (gap 14): project mode estimates the mapping against
// ProjectStoragePolicy.format_store_limit, rendered on every database.
const PROJECT_LIMIT = 2097152;
const PROJECT_THRESHOLD = Math.ceil((PROJECT_LIMIT * 90) / 100);
const setBase = (bytes) => (r) => r.setAttribute('data-dcf-editor-storage-base', String(bytes));

test('project fixtures: one mapping warning at 90 percent of the effective limit, none one byte below, never values', async () => {
  for (const [name, ratio] of [['project_list', 1.2], ['project_enumeration', 1.6]]) {
    const plain = await E.load(name);
    assert.equal(plain.root.getAttribute('data-dcf-editor-storage-limit'), String(PROJECT_LIMIT), name);
    const payload = plain.payload();
    const cost = Math.ceil(M.utf8Bytes(JSON.stringify({ value_dependencies: payload.value_dependencies,
                                                        default_value_dependencies: payload.default_value_dependencies })) * ratio);
    const at = await E.load(name, { tweak: setBase(PROJECT_THRESHOLD - cost) });
    const shown = warnings(at);
    assert.equal(shown.length, 1, name);
    assert.equal(shown[0].getAttribute('data-dcf-ed-notice'), 'storage_mapping', name);
    assert.equal(shown[0].textContent, at.t('storageEstimate', { label: 'Dependency mapping', size: '1,887,437',
                                                                 limit: '2,097,152', percent: '90' }), name);
    assert.equal(at.notice('storage_values'), null, name);

    const below = await E.load(name, { tweak: setBase(PROJECT_THRESHOLD - cost - 1) });
    assert.equal(warnings(below).length, 0, name);
  }
});

test('project fixtures start with the largest limit the server renders (1 GiB) and not with 17 digits', async () => {
  const limit = (value) => (r) => r.setAttribute('data-dcf-editor-storage-limit', value);
  const largest = await E.load('project_list', { tweak: limit('1073741824') });
  assert.equal(largest.editor().inert, false);
  assert.equal(largest.alerts().length, 0);
  assert.equal(largest.notice('storage_mapping'), null);
  assert.equal(largest.form.querySelector('[data-dcf-editor-submit]').disabled, false);
  const tooLong = await E.load('project_list', { tweak: limit('10000000000000000') });
  assert.equal(tooLong.editor().inert, true);
  assert.equal(tooLong.form.querySelector('[data-dcf-editor-submit]').disabled, true);
});
