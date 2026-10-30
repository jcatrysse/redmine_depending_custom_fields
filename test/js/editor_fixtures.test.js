'use strict';
// WP-24: the generated editor fixtures (spec/frontend/editor_fixtures_spec.rb,
// test/js/fixtures/editor/<scenario>.html and the reviewed
// <scenario>.redmine-5.1.html variants) and test/js/fixtures/value_options.json
// decode with the WP-23 model as WP-25 will read them: ValueList.fromWire for
// the value lists, State for the mappings, isDigest for the base. One named
// control, always blank; every attribute in the data-dcf-editor namespace;
// the mode-specific attributes of the editor design table.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');
const M = require('../../assets/javascripts/dcf_dependency_editor_model.js');

const DIR = path.join(__dirname, 'fixtures', 'editor');
const VALUE_OPTIONS = path.join(__dirname, 'fixtures', 'value_options.json');
const SCENARIOS = ['admin_conflict', 'admin_enumeration', 'admin_list', 'admin_new', 'mysql_limit',
  'project_enumeration', 'project_list'];
const VARIANT = /(\.redmine-\d+\.\d+)?\.html$/;
const ADMIN_ONLY = ['data-dcf-editor-base', 'data-dcf-editor-values-url', 'data-dcf-editor-parent-source',
  'data-dcf-editor-multiple-source', 'data-dcf-editor-required-source', 'data-dcf-editor-format-source',
  'data-dcf-editor-default-value-row', 'data-dcf-editor-values-source', 'data-dcf-editor-allow-add-values'];

// WP-25: DependencyEditorConfig::I18N (was ['storageEstimate'] only).
// WP-26: plus the import and export keys and the reused core keys.
const I18N_KEYS = ['storageEstimate', 'too_large_to_send', 'form_too_large', 'unavailable', 'no_parent_values',
  'no_child_values', 'enumeration_save_first', 'enumeration_hint', 'loading', 'load_failed', 'parent_changed', 'orphans',
  'format_change_confirm', 'conflict', 'use_mine', 'keep_current', 'export_mine', 'mine_loaded', 'filter_parents',
  'filter_children', 'only_parents_without_links', 'show', 'show_all', 'show_linked', 'show_not_linked', 'show_unlinked',
  'check_shown', 'uncheck_shown', 'show_more', 'linked_count', 'default_summary', 'inactive', 'no_matches',
  'status_sections', 'status_parents_without_links', 'status_unlinked_children', 'unlinked_list', 'collapse_all', 'clear',
  'default_value', 'unsaved', 'no_default', 'label_value_dependencies', 'label_possible_values',
  'import_title', 'import_help', 'import_paste', 'import_file', 'file_used', 'auto', 'tab', 'import_header', 'import_mode',
  'mode_merge', 'mode_replace', 'add_missing', 'unprotect', 'apply', 'undo', 'applied', 'lines', 'to_add', 'existing',
  'to_remove', 'new_values', 'duplicates', 'header_skipped', 'separator_used', 'decoded_as', 'preview_rows', 'status_new',
  'status_existing', 'errors_intro', 'more_errors', 'nothing', 'err_columns', 'err_blank_value', 'err_unknown_parent',
  'err_unknown_child', 'err_ambiguous_parent', 'err_ambiguous_child', 'err_unterminated_quote', 'err_bad_quote',
  'err_too_large', 'err_too_many_lines', 'err_multiline_value', 'err_nul_value', 'err_unreadable', 'warn_inactive',
  'export_title', 'export_help', 'protect', 'export', 'preview', 'separator', 'comma', 'semicolon', 'yes', 'no', 'status'];

const files = () => (fs.existsSync(DIR) ? fs.readdirSync(DIR).sort() : []);

function load(file) {
  const html = fs.readFileSync(path.join(DIR, file), 'utf8');
  const doc = new JSDOM(`<!doctype html><html><head></head><body>${html}</body></html>`).window.document;
  return { doc, root: doc.querySelector('[data-dcf-editor]') };
}

const json = (root, name) => JSON.parse(root.getAttribute(`data-dcf-editor-${name}`));

test('one editor fixture per scenario (plus reviewed variants) and value_options.json', () => {
  assert.deepEqual(Array.from(new Set(files().map((f) => f.replace(VARIANT, '')))).sort(), SCENARIOS);
  files().forEach((f) => assert.match(f, /^[a-z_]+(\.redmine-5\.1)?\.html$/, f));
  assert.ok(fs.existsSync(VALUE_OPTIONS), 'value_options.json');
});

test('every fixture has one editor root, one blank named control and only data-dcf-editor names', () => {
  files().forEach((file) => {
    const { doc, root } = load(file);
    assert.equal(doc.querySelectorAll('[data-dcf-editor]').length, 1, file);
    assert.equal(root.tagName, 'FIELDSET', file);
    const named = doc.querySelectorAll('[name]');
    assert.equal(named.length, 1, file);
    assert.equal(named[0].type, 'hidden', file);
    assert.equal(named[0].value, '', file);
    assert.equal(named[0].getAttribute('autocomplete'), 'off', file);
    assert.equal(doc.querySelectorAll('script').length, 0, file);
    doc.querySelectorAll('*').forEach((el) => {
      Array.from(el.attributes).filter((a) => a.name.startsWith('data-')).forEach((a) => {
        assert.match(a.name, /^data-dcf-editor(-[a-z0-9]+)*$/, `${file} ${a.name}`);
      });
    });
    assert.ok(root.querySelector('[data-dcf-editor-placeholder]'), file);
    assert.ok(root.querySelector('[data-dcf-editor-required-warning]'), file);
    assert.ok(root.querySelector('[data-dcf-editor-app][hidden]'), file);
  });
});

test('the value lists, mappings and base decode with the editor model', () => {
  files().forEach((file) => {
    const { root } = load(file);
    const parents = M.ValueList.fromWire(json(root, 'parent-values'));
    if (root.hasAttribute('data-dcf-editor-child-values')) M.ValueList.fromWire(json(root, 'child-values'));
    const mapping = json(root, 'mapping');
    assert.deepEqual(Object.keys(mapping), ['value_dependencies', 'default_value_dependencies'], file);
    const state = new M.State(mapping);
    if (root.hasAttribute('data-dcf-editor-conflict-mapping')) new M.State(json(root, 'conflict-mapping'));
    if (root.hasAttribute('data-dcf-editor-base')) assert.ok(M.isDigest(root.getAttribute('data-dcf-editor-base')), file);
    assert.equal(parents.items.length > 0, root.hasAttribute('data-dcf-editor-parent-id'), file);
    assert.ok(state.links instanceof Map, file);
    assert.deepEqual(Object.keys(json(root, 'i18n')), I18N_KEYS, file);
    assert.deepEqual(json(root, 'max-form-bytes'), { multipart: 16252928, urlencoded: 4128768 }, file);
    assert.equal(root.getAttribute('data-dcf-editor-max-payload-bytes'), '4194304', file);
  });
});

test('mode-specific attributes follow the editor design table', () => {
  files().forEach((file) => {
    const { doc, root } = load(file);
    const mode = root.getAttribute('data-dcf-editor-mode');
    const kind = root.getAttribute('data-dcf-editor-kind');
    const input = doc.querySelector('[name]');
    if (mode === 'project') {
      ADMIN_ONLY.forEach((name) => assert.equal(root.hasAttribute(name), false, `${file} ${name}`));
      assert.equal(root.getAttribute('data-dcf-editor-always-submit'), '1', file);
      assert.equal(input.name, 'dependencies_json', file);
    } else {
      assert.equal(mode, 'admin', file);
      assert.equal(root.hasAttribute('data-dcf-editor-always-submit'), false, file);
      assert.equal(input.name, 'custom_field[dependencies_json]', file);
      assert.equal(root.getAttribute('data-dcf-editor-values-url'), '/dcf_dependency_editor/values', file);
      assert.equal(root.hasAttribute('data-dcf-editor-allow-add-values'), kind === 'list', file);
      assert.equal(root.hasAttribute('data-dcf-editor-child-values'), kind !== 'list', file);
    }
    const storage = ['storage-limit', 'storage-base', 'storage-warn', 'values-limit']
      .filter((name) => root.hasAttribute(`data-dcf-editor-${name}`));
    assert.deepEqual(storage, file.startsWith('mysql_limit') ? ['storage-limit', 'storage-base', 'storage-warn', 'values-limit'] : [], file);
  });
});

test('value_options.json holds the compact wire shape of a list and an enumeration', () => {
  const data = JSON.parse(fs.readFileSync(VALUE_OPTIONS, 'utf8'));
  assert.deepEqual(Object.keys(data).sort(), ['enumeration', 'list']);
  const list = M.ValueList.fromWire(data.list);
  assert.ok(data.list.every((v) => Object.keys(v).join() === 'key'));
  assert.ok(list.has('__proto__') && list.has('constructor') && list.has('</script>'));
  const enumeration = M.ValueList.fromWire(data.enumeration);
  assert.deepEqual(enumeration.items.map((i) => i.active), [true, true, false, true]);
  assert.equal(enumeration.items[3].label, enumeration.items[3].key);
  assert.ok(data.enumeration.every((v) => v.active === undefined || v.active === false));
});
