'use strict';
// WP-16: the legacy runtime ignores the data-dcf-* contract. Each generated
// markup fixture (test/js/fixtures/markup, spec/frontend/markup_fixtures_spec.rb)
// runs the legacy script twice with the global mapping the head hook builds
// for its fields (test/js/fixtures/legacy_mapping, MappingBuilder.build):
// once as rendered and once with every data-dcf-* attribute removed (template
// contents included). After setup and after a parent change the two
// documents must be equal (attributes aside) and report the same kinds of
// error: none, except the legacy RangeError on stored cycles and
// self-parents (characterization X2; how often it fires depends on the
// stack). The wizard fixture is opened through the legacy wizard script
// first.
// WP-18 deletes this file and the legacy mappings with the legacy script.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');
const L = require('./support/legacy_dom');

// Scenarios whose parent is not on the page (dangling, not available,
// read-only or role-invisible): no parent control to change.
const NO_PARENT_CONTROL = ['dangling_parent', 'parent_unavailable', 'read_only_parent', 'role_invisible_parent'];
const DIR = path.join(__dirname, 'fixtures', 'markup');
const MAPPINGS = path.join(__dirname, 'fixtures', 'legacy_mapping');
const fixtures = fs.existsSync(DIR) ? fs.readdirSync(DIR).filter((f) => f.endsWith('.html')).sort() : [];

// <scenario>.html or <scenario>.redmine-<x.y>.html: the mapping of the same
// version when present, else the base one.
function mappingPath(file) {
  const variant = path.join(MAPPINGS, file.replace(/\.html$/, '.json'));
  if (fs.existsSync(variant)) return variant;
  return path.join(MAPPINGS, file.replace(/(\.redmine-\d+\.\d+)?\.html$/, '.json'));
}

function mappingOf(file) {
  return JSON.parse(fs.readFileSync(mappingPath(file), 'utf8'));
}

function stripDcf(root) {
  root.querySelectorAll('*').forEach((el) => {
    Array.from(el.attributes).map((a) => a.name).filter((n) => n.startsWith('data-dcf-')).forEach((n) => el.removeAttribute(n));
    if (el.tagName === 'TEMPLATE') stripDcf(el.content);
  });
}

// The fixture body without data-dcf-*, parsed without running any script.
function stripped(html) {
  const dom = new JSDOM(`<!doctype html><html><head></head><body>${html}</body></html>`);
  stripDcf(dom.window.document.body);
  return dom.window.document.body.innerHTML;
}

// True when a parent chain of the mapping comes back to a field.
function cyclic(mapping) {
  return Object.keys(mapping).some((start) => {
    const seen = new Set();
    for (let id = start; mapping[id]; id = String(mapping[id].parent_id)) {
      if (seen.has(id)) return true;
      seen.add(id);
    }
    return false;
  });
}

function state(pg) {
  const clone = pg.document.body.cloneNode(true);
  stripDcf(clone);
  const controls = Array.from(clone.querySelectorAll('select, input')).map((el) => [el.name, el.disabled, el.hidden, el.style.display]);
  const options = Array.from(pg.document.querySelectorAll('option')).map((o) => [o.value, o.selected, o.disabled, o.hidden]);
  const checks = Array.from(pg.document.querySelectorAll('input')).map((i) => [i.name, i.value, i.checked, i.disabled]);
  return JSON.stringify({ html: clone.innerHTML, controls, options, checks });
}

// The first parent control of a mapping entry that is on the page (an open
// wizard included, templates not).
function parentControl(pg, mapping) {
  const selects = Array.from(pg.document.querySelectorAll('select'));
  for (const info of Object.values(mapping)) {
    const name = `[custom_field_values][${info.parent_id}]`;
    const found = selects.find((s) => s.name.endsWith(name) || s.name.endsWith(`${name}[]`));
    if (found) return found;
  }
  return null;
}

// The context-menu wizard runs through the head page order (its script
// waits for DOMContentLoaded) and is opened by a click on its entry.
async function page(html, mapping, wizard) {
  if (!wizard) return L.legacyPage(html, { mapping, jquery: true });
  const pg = await L.headPage(html, { mapping, jquery: true, wizard: true });
  const link = pg.document.querySelector('li.cf-parent > a.submenu');
  link.dispatchEvent(new pg.window.MouseEvent('click', { bubbles: true, cancelable: true }));
  assert.ok(pg.document.querySelector('#cf-wizard-container select'), 'the wizard opened');
  return pg;
}

test('the markup fixtures exist, each with its legacy mapping', () => {
  assert.ok(fixtures.length >= 30, `expected the generated fixtures in ${DIR}`);
  fixtures.forEach((file) => assert.ok(fs.existsSync(mappingPath(file)), `legacy mapping of ${file}`));
});

fixtures.forEach((file) => {
  test(`the legacy script behaves the same with and without data-dcf-* on ${file}`, async () => {
    const html = fs.readFileSync(path.join(DIR, file), 'utf8');
    const mapping = mappingOf(file);
    const wizard = html.includes('class="folder cf-parent"');
    const plain = stripped(html);
    assert.ok(!plain.includes('data-dcf-'), 'every data-dcf-* attribute removed');

    const withAttrs = await page(html, mapping, wizard);
    const without = await page(plain, mapping, wizard);
    withAttrs.clock.tick(1000);
    without.clock.tick(1000);
    assert.equal(state(withAttrs), state(without), 'after setup');

    const a = parentControl(withAttrs, mapping);
    const scenario = file.replace(/(\.redmine-\d+\.\d+)?\.html$/, '');
    assert.equal(Boolean(a), !NO_PARENT_CONTROL.includes(scenario), 'a parent control to change');
    if (a) {
      const b = Array.from(without.document.querySelectorAll('select')).find((s) => s.name === a.name);
      const values = Array.from(a.options).map((o) => o.value).filter((v) => v !== '' && v !== '__none__');
      const target = values[values.length - 1];
      L.choose(withAttrs.window, a, a.multiple ? [target] : target);
      L.choose(without.window, b, b.multiple ? [target] : target);
      withAttrs.clock.tick(1000);
      without.clock.tick(1000);
      assert.equal(state(withAttrs), state(without), 'after a parent change');
    }
    const kinds = (pg) => Array.from(new Set(pg.errors.map(String))).sort();
    assert.deepEqual(kinds(withAttrs), kinds(without));
    assert.deepEqual(kinds(withAttrs), cyclic(mapping) ? ['RangeError: Maximum call stack size exceeded'] : []);
  });
});
