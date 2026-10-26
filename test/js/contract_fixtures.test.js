'use strict';
// WP-17: the filtering outcome on every generated markup fixture (WP-16,
// spec/frontend/markup_fixtures_spec.rb): data-dcf-state, enabled and
// selected values per managed control and the spec entry list after load.
// WP-18 and WP-19 regenerate fixtures and must update this table. WP-18:
// my_account is managed (UD-39), read_only_child_carrier shows the UD-37
// warning after a refused parent change, the wizard opens on '(no change)'.
const { test, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');
const D = require('./support/dom');
const E = require('./support/entries');
const F = require('./support/fixtures');
const fire = require('./support/fire');

afterEach(D.closeAll);

const P = 'issue[custom_field_values][9100001]';
const C = 'issue[custom_field_values][9100002]';
const L3 = 'issue[custom_field_values][9100003]';
const ctl = (field, st, enabled, selected, extra) => Object.assign({ field, state: st, enabled, selected }, extra || {});
const unmanaged = { unmanaged: true };
const bulkSingle = (prefix) => ({
  controls: [ctl('9100002', 'unfiltered', ['', '__none__', 'Ant', 'Ape', 'Bee'], [''])],
  entries: [`${prefix}[custom_field_values][9100001]=`, `${prefix}[custom_field_values][9100002]=`]
});

// Frontend design 5.3 to 5.8 applied to the fixtures as rendered at 031ddd0.
const EXPECTED = {
  list_single: { controls: [ctl('9100002', 'ok', ['', 'Ant', 'Ape'], ['Ant'])], entries: [`${P}=Alpha`, `${C}=Ant`] },
  list_single_required: { controls: [ctl('9100002', 'ok', ['', 'Ant', 'Ape'], ['Ant'])], entries: [`${P}=Alpha`, `${C}=Ant`] },
  list_multi_select: { controls: [ctl('9100002', 'ok', ['Ant', 'Ape'], ['Ant', 'Ape'])],
    entries: [`${P}=Alpha`, `${C}[]=Ant`, `${C}[]=Ape`, `${C}[]=`] },
  radio: { controls: [ctl('9100002', 'ok', ['', 'Ant', 'Ape'], ['Ant'])], entries: [`${P}=Alpha`, `${C}=Ant`] },
  // No sentinel until WP-19.
  radio_required: { controls: [ctl('9100002', 'ok', ['Ant', 'Ape'], ['Ant'])], entries: [`${P}=Alpha`, `${C}=Ant`] },
  multi_checkbox: { controls: [ctl('9100002', 'ok', ['Ant', 'Ape'], ['Ant'])], entries: [`${P}=Alpha`, `${C}[]=Ant`, `${C}[]=`] },
  enumeration: { controls: [ctl('9100002', 'ok', ['', '9200004', '9200005'], ['9200004'])], entries: [`${P}=9200001`, `${C}=9200004`] },
  enumeration_inactive_child: { controls: [ctl('9100002', 'legacy', ['', '9200004', '9200007'], ['9200007'],
    { hint: 'Stored values that do not match the selected Parent field are kept until you change Parent field: Cat.' })],
  entries: [`${P}=9200001`, `${C}=9200007`] },
  enumeration_inactive_parent: { controls: [ctl('9100002', 'ok', ['', '9200006'], ['9200006'])], entries: [`${P}=9200003`, `${C}=9200006`] },
  chain_of_three: { controls: [ctl('9100002', 'ok', ['', 'Ant', 'Ape'], ['Ant']), ctl('9100003', 'ok', ['', 'Cub', 'Calf'], ['Cub'])],
    entries: [`${P}=Alpha`, `${C}=Ant`, `${L3}=Cub`] },
  read_only_parent: { controls: [ctl('9100002', 'ok', ['', 'Bee'], ['Bee'])], entries: [`${C}=Bee`] },
  role_invisible_parent: unmanaged,
  parent_unavailable: { controls: [ctl('9100002', 'empty', [''], [''], { hint: 'No values are available for this field.' })],
    entries: [`${C}=`], changes: 1 },
  stored_cycle: unmanaged,
  self_parent: unmanaged,
  dangling_parent: unmanaged,
  legacy_value: { controls: [ctl('9100002', 'legacy', ['', 'Ant', 'Ape', 'Bee'], ['Bee'])], entries: [`${P}=Alpha`, `${C}=Bee`] },
  legacy_value_multi: { controls: [ctl('9100002', 'legacy', ['Ant', 'Ape', 'Bee'], ['Ant', 'Bee'])],
    entries: [`${P}=Alpha`, `${C}[]=Ant`, `${C}[]=Bee`, `${C}[]=`] },
  legacy_parent_value: { controls: [ctl('9100002', 'ok', ['', 'Ape'], ['Ape'])], entries: [`${P}=Gamma`, `${C}=Ape`] },
  // Gap 6, row F6b-a: the copy keeps the legacy value, marked and posted.
  issue_copy: { controls: [ctl('9100002', 'legacy', ['', 'Ant', 'Ape', 'Bee'], ['Bee'],
    { hint: 'Stored values that do not match the selected Parent field are kept until you change Parent field: Bee.', marked: ['Bee'] })],
  entries: [`${P}=Alpha`, `${C}=Bee`] },
  // Row F6b-b: a plain new record drops it and gets the per-parent default
  // (WP-17 review: '' before).
  new_issue: { controls: [ctl('9100002', 'ok', ['', 'Ant', 'Ape'], ['Ape'])], entries: [`${P}=Alpha`, `${C}=Ape`], changes: 1 },
  issue_time_entry_prefixes: {
    controls: [ctl('9100002', 'ok', ['', 'Ant', 'Ape'], ['Ant'], { prefix: 'issue' }),
      ctl('9100004', 'waiting', [''], [''], { prefix: 'time_entry', hint: 'Select a value for Time parent first.' })],
    entries: [`${P}=Alpha`, `${C}=Ant`, 'time_entry[custom_field_values][9100003]=', 'time_entry[custom_field_values][9100004]=']
  },
  project_form: { controls: [ctl('9100002', 'legacy', ['', 'Ant', 'Ape', 'Bee'], ['Bee'])],
    entries: ['project[custom_field_values][9100001]=Alpha', 'project[custom_field_values][9100002]=Bee'] },
  user_form: { controls: [ctl('9100002', 'ok', ['', 'Ant'], ['Ant'])],
    entries: ['user[custom_field_values][9100001]=Alpha', 'user[custom_field_values][9100002]=Ant'] },
  // UD-39 (WP-18): was unmanaged.
  my_account: { controls: [ctl('9100002', 'ok', ['', 'Ant'], ['Ant'])],
    entries: ['user[custom_field_values][9100001]=Alpha', 'user[custom_field_values][9100002]=Ant'] },
  bulk_single: bulkSingle('issue'),
  bulk_multi: { controls: [ctl('9100002', 'unfiltered', ['__none__', 'Ant', 'Ape', 'Bee'], [])], entries: [`${P}=`] },
  bulk_required: { controls: [ctl('9100002', 'unfiltered', ['', 'Ant', 'Ape', 'Bee'], [''])], entries: [`${P}=`, `${C}=`] },
  bulk_chain: { controls: [ctl('9100002', 'unfiltered', ['', '__none__', 'Ant', 'Ape', 'Bee'], ['']),
    ctl('9100003', 'unfiltered', ['', '__none__', 'Cub', 'Calf', 'Colt'], [''])], entries: [`${P}=`, `${C}=`, `${L3}=`] },
  time_entry_bulk: bulkSingle('time_entry'),
  wizard_template: { wizard: true },
  tricky_values: { controls: [ctl('9100002', 'ok', ['', 'a]', 'say "hi"'], ['say "hi"'])], entries: [`${P}=[x]`, `${C}=say "hi"`] },
  // UD-37 (WP-18): was unmanaged (untouched also after changes).
  read_only_child_carrier: { carrier: true },
  role_invisible_child: unmanaged,
  hide_when_disabled: { controls: [ctl('9100002', 'empty', [''], [''], { pHidden: true })], entries: [`${P}=Gamma`, `${C}=`] },
  bulk_hide_when_disabled: { controls: [ctl('9100002', 'unfiltered', ['', '__none__', 'Ant', 'Ape', 'Bee'], [''], { pHidden: false })],
    entries: [`${P}=`, `${C}=`] }
};

const cfEntries = (form) => E.list(form).filter((e) => e.includes('[custom_field_values]'));

// The document of a fixture parsed without any script.
function plain(html) {
  return new JSDOM(`<!doctype html><html><head></head><body>${html}</body></html>`).window.document;
}

// Frontend design 5.6 to 5.8: the runtime writes only these attributes (and
// adds hint elements); everything else stays as rendered. No inline style:
// no fixture has one, and the runtime only clears a server display:none.
const WRITTEN = new Set(['data-dcf-state', 'class', 'aria-describedby', 'disabled', 'hidden']);
const RUNTIME_CLASSES = new Set(['depending-child', 'dcf-auto-applied', 'dcf-legacy-option', 'dcf-hidden']);
function writtenOnly(before, after) {
  const clone = after.body.cloneNode(true);
  clone.querySelectorAll('em.dcf-hint').forEach((em) => em.remove());
  const a = Array.from(before.body.querySelectorAll('*'));
  const b = Array.from(clone.querySelectorAll('*'));
  assert.deepEqual(b.map((el) => el.tagName), a.map((el) => el.tagName), 'no element added or removed but hints');
  a.forEach((el, k) => {
    const other = b[k];
    const names = new Set(Array.from(el.attributes).map((x) => x.name).concat(Array.from(other.attributes).map((x) => x.name)));
    names.forEach((n) => {
      if (el.getAttribute(n) === other.getAttribute(n)) return;
      assert.ok(WRITTEN.has(n), `${el.tagName} ${n} written`);
      if (n === 'class') {
        const extra = Array.from(other.classList).filter((c) => !el.classList.contains(c));
        const gone = Array.from(el.classList).filter((c) => !other.classList.contains(c));
        assert.deepEqual(gone, []);
        extra.forEach((c) => assert.ok(RUNTIME_CLASSES.has(c), c));
      }
    });
  });
}

test('every fixture has an expectation and every expectation a fixture (the WP-16 scenario list)', () => {
  const spec = fs.readFileSync(path.join(__dirname, '..', '..', 'spec', 'frontend', 'markup_fixtures_spec.rb'), 'utf8');
  const listed = /def self\.scenarios\s+%w\[([^\]]*)\]/.exec(spec)[1].split(/\s+/).filter(Boolean).sort();
  assert.equal(F.files().length, 36);
  assert.deepEqual(F.scenarios(), listed);
  assert.deepEqual(Object.keys(EXPECTED).sort(), F.scenarios());
});

Object.keys(EXPECTED).forEach((scenario) => {
  const want = EXPECTED[scenario];
  test(`contract fixture: ${scenario}`, async () => {
    const html = F.read(scenario);
    const pg = await D.page(html);
    const doc = pg.document;
    assert.deepEqual(pg.errors, []);
    if (want.unmanaged) {
      const before = plain(html);
      assert.equal(doc.body.innerHTML, before.body.innerHTML, 'untouched');
      assert.equal(doc.querySelectorAll('[data-dcf-state], em.dcf-hint, .dcf-live').length, 0);
      Array.from(doc.forms).forEach((f, k) => assert.deepEqual(E.entries(f), E.entries(before.forms[k])));
      assert.deepEqual(pg.updates, []);
      // WP-17 resume: also after a change of every select on the page.
      doc.querySelectorAll('select').forEach((s) => {
        const values = Array.from(s.options).map((o) => o.value);
        fire.choose(pg.window, s, s.multiple ? [values[values.length - 1]] : values[values.length - 1]);
      });
      assert.equal(doc.body.innerHTML, before.body.innerHTML, 'untouched after changes');
      assert.equal(doc.querySelectorAll('[data-dcf-state], em.dcf-hint, .dcf-live').length, 0);
      assert.deepEqual(pg.updates, []);
      assert.deepEqual(pg.errors, []);
      return;
    }
    if (want.carrier) {
      const before = plain(html);
      assert.equal(doc.body.innerHTML, before.body.innerHTML, 'untouched at load (the stored parent value)');
      const parent = D.byName(doc, P);
      fire.choose(pg.window, parent, 'Gamma');
      const hints = Array.from(doc.querySelectorAll('em.dcf-hint'));
      assert.deepEqual(hints.map((h) => [h.className, h.hidden, h.textContent]),
        [['info dcf-hint dcf-hint--locked', false,
          'A dependent field that you cannot edit has a value that this choice does not allow; saving will be refused.']]);
      assert.equal(parent.getAttribute('aria-describedby'), hints[0].id);
      fire.choose(pg.window, parent, 'Alpha');
      assert.equal(hints[0].hidden, true);
      assert.equal(parent.hasAttribute('aria-describedby'), false);
      hints[0].remove();
      doc.getElementById('dcf-live').remove();
      assert.equal(doc.body.innerHTML, before.body.innerHTML, 'only the warning and the live region were added');
      assert.deepEqual(pg.updates, []);
      assert.deepEqual(pg.errors, []);
      return;
    }
    if (want.wizard) {
      assert.equal(doc.querySelectorAll('[data-dcf-state]').length, 0, 'the template is inert');
      const template = doc.querySelector('template');
      assert.equal(template.content.querySelectorAll('[data-dcf-state]').length, 0);
      const container = doc.createElement('div');
      container.id = 'cf-wizard-container';
      container.className = 'context-menu cf-wizard';
      doc.body.appendChild(container);
      container.appendChild(template.content.cloneNode(true));
      await D.microtask();
      const form = container.querySelector('form');
      ['9100002', '9100003'].forEach((id) => assert.equal(D.state(D.control(form, id)), 'unfiltered', id));
      // UD-11 (WP-18): every field, the root with a default included, on '(no change)'.
      assert.deepEqual(Array.from(form.querySelectorAll('select')).map((sel) => sel.value), ['', '', '']);
      assert.equal(form.querySelectorAll('[data-field-id]').length, 0);
      assert.equal(form.querySelectorAll('div.cf-wizard-field[data-dcf-wizard-field] > label.cf-wizard-label > select').length, 3);
      const rendered = plain(`<div>${template.innerHTML}</div>`).querySelector('form');
      assert.deepEqual(E.entries(form), E.entries(rendered));
      assert.deepEqual(E.entries(form), E.serialized(pg.window, form));
      return;
    }
    want.controls.forEach((w) => {
      const c = D.control(doc, w.field, w.prefix);
      assert.ok(c, `control ${w.field}`);
      assert.equal(D.state(c), w.state, `${w.field} state`);
      assert.deepEqual(D.enabled(c), w.enabled, `${w.field} enabled`);
      assert.deepEqual(D.selected(c), w.selected, `${w.field} selected`);
      assert.ok(c.classList.contains('depending-child'));
      if (w.hint) assert.equal(D.hintText(c), w.hint, `${w.field} hint`);
      if (w.marked) {
        assert.deepEqual(D.items(c).filter((o) => (c.tagName === 'SELECT' ? o : o.closest('label')).classList.contains('dcf-legacy-option')).map((o) => o.value), w.marked);
      }
      if (w.pHidden !== undefined) {
        assert.equal(c.closest('p').hidden, w.pHidden);
        assert.equal(c.closest('p').classList.contains('dcf-hidden'), w.pHidden);
      }
    });
    writtenOnly(plain(html), doc);
    const form = doc.forms[0];
    assert.deepEqual(cfEntries(form), want.entries);
    assert.deepEqual(E.entries(form), E.serialized(pg.window, form), 'jQuery serialize carries the same');
    assert.equal(pg.changes.length, want.changes || 0, 'change events at load');
    doc.querySelectorAll('select').forEach((s) => {
      assert.equal(s.disabled, false);
      Array.from(s.options).forEach((o) => assert.ok(!(o.selected && o.disabled)));
    });
  });
});
