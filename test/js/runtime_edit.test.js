'use strict';
// WP-17: the issue-form runtime on edit forms (data-dcf-context="form"),
// behaviour rows F1..F20 and X10 of frontend design 9, on the generated
// markup fixtures (test/js/fixtures/markup); hand-written markup only where
// no fixture can express the row (marked).
const { test, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const D = require('./support/dom');
const E = require('./support/entries');
const F = require('./support/fixtures');
const fire = require('./support/fire');

afterEach(D.closeAll);

const PARENT = 'issue[custom_field_values][9100001]';
const CHILD = 'issue[custom_field_values][9100002]';
const load = (source, opts) => D.page(source.includes('<') ? source : F.read(source), opts);
const child = (pg, id) => D.control(pg.document, id || '9100002');
const parentOf = (pg, name) => D.byName(pg.document, name || PARENT);
const childEntries = (pg, name) => E.list(pg.document.forms[0], name || CHILD);
const since = (list, n) => list.slice(n);

// Point 2 invariants after every scenario: no select or group disabled, no
// option both selected and disabled, the entry list equals jQuery serialize.
function invariants(pg) {
  pg.document.querySelectorAll('select').forEach((s) => {
    assert.equal(s.disabled, false, `select ${s.name} disabled`);
    Array.from(s.options).forEach((o) => assert.ok(!(o.selected && o.disabled), `${s.name}: ${o.value} selected and disabled`));
  });
  pg.document.querySelectorAll('.check_box_group').forEach((g) => assert.ok(!g.hasAttribute('disabled')));
  Array.from(pg.document.forms).forEach((f) => assert.deepEqual(E.entries(f), E.serialized(pg.window, f)));
  assert.deepEqual(pg.errors, []);
}

const blankParentNewIssue = () => F.tweak('new_issue', (doc) => {
  F.selectValues(F.named(doc, PARENT), ['']);
  F.selectValues(F.named(doc, CHILD), ['']);
  F.named(doc, CHILD).setAttribute('aria-describedby', 'foo');
});

test('F1 form, parent blank: control enabled, concrete options hidden and disabled, "" selected, hint tied by aria-describedby', async () => {
  const pg = await load(blankParentNewIssue());
  const c = child(pg);
  assert.equal(c.disabled, false);
  assert.deepEqual(D.enabled(c), ['']);
  assert.deepEqual(D.hiddenValues(c), ['Ant', 'Ape', 'Bee']);
  assert.deepEqual(D.selected(c), ['']);
  assert.equal(D.state(c), 'waiting');
  const hint = D.hint(c);
  assert.ok(hint, 'a visible hint');
  assert.match(hint.id, /^dcf-hint-\d+$/);
  assert.equal(hint.tagName, 'EM');
  assert.ok(hint.classList.contains('info') && hint.classList.contains('dcf-hint'));
  assert.equal(hint.hasAttribute('role'), false);
  assert.deepEqual(Array.from(hint.attributes).map((a) => a.name).filter((n) => n.startsWith('data-')), []);
  assert.equal(hint.textContent, 'Select a value for Parent field first.');
  assert.equal(c.getAttribute('aria-describedby'), `foo ${hint.id}`);
  assert.equal(hint.parentNode, c.closest('p'));
  assert.deepEqual(childEntries(pg), [`${CHILD}=`]);
  assert.deepEqual(pg.changes, []);
  invariants(pg);
});

test('F2 parent set: the default for a new record, hint hidden and its id removed; a replaced parent value carries nothing', async () => {
  const pg = await load(blankParentNewIssue());
  const c = child(pg);
  const hintId = D.hint(c).id;
  const n = pg.changes.length;
  fire.choose(pg.window, parentOf(pg), 'Alpha');
  assert.deepEqual(D.selected(c), ['Ape']);
  assert.deepEqual(D.enabled(c), ['', 'Ant', 'Ape']);
  assert.equal(D.state(c), 'ok');
  assert.equal(pg.document.getElementById(hintId).hidden, true);
  assert.equal(c.getAttribute('aria-describedby'), 'foo');
  assert.equal(D.hintElements(c).length, 1, 'the hidden hint element is kept for reuse');
  assert.deepEqual(since(pg.changes, n), [PARENT, CHILD]);
  fire.choose(pg.window, parentOf(pg), 'Beta');
  assert.deepEqual(D.selected(c), ['']);
  assert.deepEqual(D.enabled(c), ['', 'Bee']);
  invariants(pg);
});

test('F2 a change event only when the child value changes; dcf:updated for every evaluation', async () => {
  const pg = await load('list_single');
  const c = child(pg);
  fire.choose(pg.window, parentOf(pg), 'Beta');
  const n = pg.changes.length;
  const u = pg.updates.length;
  fire.choose(pg.window, parentOf(pg), 'Gamma');
  assert.deepEqual(since(pg.changes, n), [PARENT], 'the child stays "" and fires no change');
  assert.deepEqual(since(pg.updates, u).map((x) => [x.fieldId, x.state, x.changed]), [['9100002', 'empty', false]]);
  assert.deepEqual(D.selected(c), ['']);
  invariants(pg);
});

test('F3 the user pick under A comes back after A to B to A (fixes the legacy restore of the last captured value)', async () => {
  const pg = await load('list_single');
  const c = child(pg);
  fire.choose(pg.window, c, 'Ape');
  fire.choose(pg.window, parentOf(pg), 'Beta');
  assert.deepEqual(D.selected(c), ['']);
  fire.choose(pg.window, parentOf(pg), 'Alpha');
  assert.deepEqual(D.selected(c), ['Ape']);
  invariants(pg);
});

test('F3 an explicit clear under A comes back as "" after A to B to A, not the stored value', async () => {
  const pg = await load('list_single');
  const c = child(pg);
  fire.choose(pg.window, c, '');
  fire.choose(pg.window, parentOf(pg), 'Beta');
  fire.choose(pg.window, parentOf(pg), 'Alpha');
  assert.deepEqual(D.selected(c), ['']);
  assert.deepEqual(childEntries(pg), [`${CHILD}=`]);
  invariants(pg);
});

test('F4 parent cleared in a chain: children cleared and enabled with hints, change only where the value changed', async () => {
  const pg = await load('chain_of_three');
  const middle = child(pg, '9100002');
  const leaf = child(pg, '9100003');
  const n = pg.changes.length;
  fire.choose(pg.window, parentOf(pg), '');
  assert.deepEqual(since(pg.changes, n), [PARENT, 'issue[custom_field_values][9100002]', 'issue[custom_field_values][9100003]']);
  assert.deepEqual([D.selected(middle), D.state(middle), D.hintText(middle)], [[''], 'waiting', 'Select a value for Root field first.']);
  assert.deepEqual([D.selected(leaf), D.state(leaf), D.hintText(leaf)], [[''], 'waiting', 'Select a value for Middle field first.']);
  assert.deepEqual(since(pg.updates, 0).slice(-2).map((x) => x.fieldId), ['9100002', '9100003']);
  invariants(pg);
});

test('F5 a stored allowed child is kept at load without a change event, with one dcf:updated', async () => {
  const pg = await load('list_single');
  assert.deepEqual(D.selected(child(pg)), ['Ant']);
  assert.deepEqual(pg.changes, []);
  assert.deepEqual(JSON.parse(JSON.stringify(pg.updates.map(({ target, ...rest }) => rest))),
    [{ fieldId: '9100002', state: 'ok', values: ['Ant'], changed: false }]);
  assert.equal(pg.updates[0].target, child(pg));
  assert.equal(D.hintElements(child(pg)).length, 0, 'no hint element without a hint');
  invariants(pg);
});

test('F6 a persisted legacy value under its stored parent stays selected, enabled, marked, hinted and posted (UD-04)', async () => {
  const pg = await load('legacy_value');
  const c = child(pg);
  const bee = Array.from(c.options).find((o) => o.value === 'Bee');
  assert.deepEqual(D.selected(c), ['Bee']);
  assert.equal(bee.disabled, false);
  assert.equal(bee.hidden, false);
  assert.ok(bee.classList.contains('dcf-legacy-option'));
  assert.equal(D.state(c), 'legacy');
  const hint = D.hint(c);
  assert.equal(hint.textContent, 'Stored values that do not match the selected Parent field are kept until you change Parent field: Bee.');
  assert.ok(hint.classList.contains('dcf-hint--legacy'));
  assert.deepEqual(childEntries(pg), [`${CHILD}=Bee`]);
  assert.deepEqual(pg.changes, []);
  invariants(pg);
});

test('F6a the legacy value is dropped under another parent value and restored and marked on return', async () => {
  const pg = await load('legacy_value');
  const c = child(pg);
  fire.choose(pg.window, parentOf(pg), 'Gamma');
  assert.deepEqual([D.selected(c), D.state(c), D.hintText(c)], [[''], 'empty', 'No values are available for the selected Parent field.']);
  assert.ok(D.disabled(c).includes('Bee'));
  assert.equal(D.hint(c).classList.contains('dcf-hint--legacy'), false);
  fire.choose(pg.window, parentOf(pg), 'Alpha');
  assert.deepEqual([D.selected(c), D.state(c)], [['Bee'], 'legacy']);
  assert.ok(D.hint(c).classList.contains('dcf-hint--legacy'));
  // Beta allows Bee, but a replaced parent value carries nothing.
  fire.choose(pg.window, parentOf(pg), 'Beta');
  assert.deepEqual([D.selected(c), D.state(c)], [[''], 'ok']);
  assert.ok(D.enabled(c).includes('Bee'));
  assert.equal(Array.from(c.options).find((o) => o.value === 'Bee').classList.contains('dcf-legacy-option'), false);
  invariants(pg);
});

test('F6b-a issue copy with data-dcf-stored keeps the legacy value enabled, marked and posted, no default at load', async () => {
  const pg = await load('issue_copy');
  const c = child(pg);
  assert.deepEqual([D.selected(c), D.state(c)], [['Bee'], 'legacy']);
  assert.ok(D.enabled(c).includes('Bee'));
  assert.deepEqual(childEntries(pg), [`${CHILD}=Bee`]);
  assert.deepEqual(pg.changes, []);
  fire.choose(pg.window, parentOf(pg), 'Beta');
  fire.choose(pg.window, parentOf(pg), 'Alpha');
  assert.deepEqual([D.selected(c), D.state(c)], [['Bee'], 'legacy']);
  invariants(pg);
});

// WP-17 review: the per-parent default replaces the dropped value, as the
// legacy script does (F6b-b, UD-12); it was '' before.
test('F6b-b plain new record without data-dcf-stored drops the disallowed value at load and fills the default', async () => {
  const pg = await load('new_issue');
  const c = child(pg);
  const bee = Array.from(c.options).find((o) => o.value === 'Bee');
  assert.deepEqual([bee.disabled, bee.hidden], [true, true]);
  assert.deepEqual(D.selected(c), ['Ape']);
  assert.equal(D.state(c), 'ok');
  assert.deepEqual(childEntries(pg), [`${CHILD}=Ape`]);
  assert.deepEqual(pg.changes, [CHILD]);
  invariants(pg);
});

test('F6c a posted, non-stored disallowed value shown after a failed save is dropped, never legacy', async () => {
  const html = F.tweak('list_single', (doc) => F.selectValues(F.named(doc, CHILD), ['Bee']));
  const pg = await load(html);
  const c = child(pg);
  assert.deepEqual([D.selected(c), D.state(c)], [[''], 'ok']);
  assert.equal(Array.from(c.options).some((o) => o.classList.contains('dcf-legacy-option')), false);
  invariants(pg);
});

test('F6d a multi child with legacy Bee: adding an allowed value posts both, each once', async () => {
  const pg = await load('legacy_value_multi');
  const c = child(pg);
  assert.deepEqual(childEntries(pg), [`${CHILD}[]=Ant`, `${CHILD}[]=Bee`, `${CHILD}[]=`]);
  fire.choose(pg.window, c, ['Ant', 'Ape', 'Bee']);
  assert.deepEqual(childEntries(pg), [`${CHILD}[]=Ant`, `${CHILD}[]=Ape`, `${CHILD}[]=Bee`, `${CHILD}[]=`]);
  const bee = Array.from(c.options).find((o) => o.value === 'Bee');
  assert.equal(bee.disabled, false);
  assert.ok(bee.classList.contains('dcf-legacy-option'));
  // Bee deselected, then Beta and back to Alpha: the pick comes back, Bee
  // stays eligible (enabled and marked) without being selected or posted.
  fire.choose(pg.window, c, ['Ant']);
  fire.choose(pg.window, parentOf(pg), 'Beta');
  fire.choose(pg.window, parentOf(pg), 'Alpha');
  assert.deepEqual(D.selected(c), ['Ant']);
  assert.deepEqual([bee.disabled, bee.hidden, bee.selected], [false, false, false]);
  assert.ok(bee.classList.contains('dcf-legacy-option'));
  assert.deepEqual(childEntries(pg), [`${CHILD}[]=Ant`, `${CHILD}[]=`]);
  assert.deepEqual([D.state(c), D.hintText(c)], ['ok', null]);
  invariants(pg);
});

test('F6e the legacy state and hint follow the user pick: replaced gives the base state, picked again gives legacy', async () => {
  const LEGACY = 'Stored values that do not match the selected Parent field are kept until you change Parent field: Bee.';
  const pg = await load('legacy_value');
  const c = child(pg);
  const id = D.hint(c).id;
  ['Ant', ''].forEach((v) => {
    fire.choose(pg.window, c, v);
    assert.deepEqual([D.state(c), D.hintText(c), D.selected(c)], ['ok', null, [v]], v);
    assert.equal(pg.document.getElementById(id).hidden, true);
    assert.equal(c.hasAttribute('aria-describedby'), false);
    assert.deepEqual(childEntries(pg), [`${CHILD}=${v}`]);
  });
  fire.choose(pg.window, c, 'Bee');
  assert.deepEqual([D.state(c), D.hintText(c)], ['legacy', LEGACY]);
  assert.equal(c.getAttribute('aria-describedby'), id);
  assert.ok(D.hint(c).classList.contains('dcf-hint--legacy'));
  assert.equal(D.hintElements(c).length, 1);
  invariants(pg);

  const multi = await load('legacy_value_multi');
  const m = child(multi);
  fire.choose(multi.window, m, ['Ant']);
  assert.deepEqual([D.state(m), D.hintText(m)], ['ok', null]);
  fire.choose(multi.window, m, ['Ant', 'Bee']);
  assert.deepEqual([D.state(m), D.hintText(m)], ['legacy', LEGACY]);
  invariants(multi);

  // A legacy value under a parent that allows nothing: the base state is
  // empty with its hint (not hidden while the user picks).
  const empty = await load(F.tweak('hide_when_disabled', (doc) => {
    const s = F.named(doc, CHILD);
    s.setAttribute('data-dcf-stored', JSON.stringify({ child: ['Bee'], parent: ['Gamma'] }));
    F.selectValues(s, ['Bee']);
  }));
  const e = child(empty);
  assert.equal(D.state(e), 'legacy');
  fire.choose(empty.window, e, '');
  assert.deepEqual([D.state(e), D.hintText(e)], ['empty', 'No values are available for the selected Parent field.']);
  assert.equal(D.hint(e).classList.contains('dcf-hint--legacy'), false);
  assert.equal(e.closest('p').hidden, false);
  fire.choose(empty.window, e, 'Bee');
  assert.deepEqual([D.state(e), D.hint(e).classList.contains('dcf-hint--legacy')], ['legacy', true]);
  invariants(empty);
});

test('F7 a cleared multi select posts core hidden name[]= once; no mirror input', async () => {
  const pg = await load('list_multi_select');
  const named = () => Array.from(pg.document.querySelectorAll('[name]')).filter((el) => el.name === `${CHILD}[]`).length;
  assert.equal(named(), 2);
  fire.choose(pg.window, child(pg), []);
  assert.deepEqual(childEntries(pg), [`${CHILD}[]=`]);
  assert.equal(named(), 2);
  assert.equal(pg.document.getElementById('issue_custom_field_values_9100002_').value, '');
  invariants(pg);
});

// Tag and name of every change target (capture phase), plus a jQuery handler
// bound directly to the choice inputs of a group (design 5.12).
function changeTargets(pg, group) {
  const targets = [];
  let jq = 0;
  pg.document.addEventListener('change', (e) => targets.push([e.target.tagName, e.target.name || '']), true);
  pg.window.jQuery(D.choices(group)).on('change', () => { jq += 1; });
  return { targets, jq: () => jq };
}

test('F8 multi check box child: only disallowed inputs disabled, their labels hidden', async () => {
  const pg = await load('multi_checkbox');
  const c = child(pg);
  assert.equal(D.state(c), 'ok');
  assert.deepEqual(D.disabled(c), ['Bee']);
  assert.deepEqual(D.hiddenValues(c), ['Bee']);
  assert.deepEqual(D.selected(c), ['Ant']);
  assert.deepEqual(childEntries(pg), [`${CHILD}[]=Ant`, `${CHILD}[]=`]);
  const seen = changeTargets(pg, c);
  fire.choose(pg.window, parentOf(pg), 'Beta');
  assert.deepEqual(seen.targets, [['SELECT', PARENT], ['INPUT', `${CHILD}[]`]]);
  assert.equal(seen.jq(), 1, 'a jQuery handler bound to the inputs runs once');
  assert.deepEqual(D.disabled(c), ['Ant', 'Ape']);
  assert.deepEqual(D.hiddenValues(c), ['Ant', 'Ape']);
  assert.deepEqual(D.selected(c), []);
  assert.deepEqual(childEntries(pg), [`${CHILD}[]=`]);
  const hidden = Array.from(c.querySelectorAll('input[type="hidden"]'));
  assert.deepEqual(hidden.map((i) => [i.value, i.disabled]), [['', false]]);
  invariants(pg);
});

test('F9 single radio, not required: "(none)" checked and enabled when nothing is usable, posts ""', async () => {
  const pg = await load('radio');
  const c = child(pg);
  assert.deepEqual([D.state(c), D.selected(c)], ['ok', ['Ant']]);
  assert.deepEqual(D.disabled(c), ['Bee']);
  const seen = changeTargets(pg, c);
  fire.choose(pg.window, parentOf(pg), 'Gamma');
  assert.deepEqual(seen.targets, [['SELECT', PARENT], ['INPUT', CHILD]]);
  assert.equal(seen.jq(), 1, 'a jQuery handler bound to the inputs runs once');
  assert.deepEqual(D.selected(c), ['']);
  assert.deepEqual(D.enabled(c), ['']);
  assert.deepEqual(D.hiddenValues(c), ['Ant', 'Ape', 'Bee']);
  assert.deepEqual(childEntries(pg), [`${CHILD}=`]);
  invariants(pg);
});

// The WP-19 sentinel is injected (hand-written, pre-WP-19 markup); WP-19
// regenerates radio_required with it.
test('F10 required radio: all radios unchecked, the injected WP-19 sentinel posts "" and stays untouched', async () => {
  const sentinel = '<input type="hidden" name="issue[custom_field_values][9100002]" value="" data-dcf-blank="1">';
  const html = F.tweak('radio_required', (doc) => {
    const span = doc.querySelector('.check_box_group');
    span.insertAdjacentHTML('beforebegin', sentinel);
  });
  const pg = await load(html);
  const c = child(pg);
  fire.choose(pg.window, parentOf(pg), 'Gamma');
  assert.deepEqual(D.selected(c), []);
  assert.deepEqual(childEntries(pg), [`${CHILD}=`]);
  const s = pg.document.querySelector('input[data-dcf-blank]');
  assert.deepEqual([s.value, s.disabled, s.hidden, s.getAttribute('aria-describedby')], ['', false, false, null]);
  assert.equal(c.previousElementSibling, s);
  invariants(pg);

  const plain = await load('radio_required');
  fire.choose(plain.window, parentOf(plain), 'Gamma');
  assert.deepEqual(D.selected(child(plain)), []);
  assert.deepEqual(childEntries(plain), [], 'without the sentinel nothing is posted');
});

test('F11 explicit BFS cascade and depth-ordered init, independent of DOM order', async () => {
  const html = F.tweak('chain_of_three', (doc) => {
    const leafP = F.named(doc, 'issue[custom_field_values][9100003]').closest('p');
    const middleP = F.named(doc, CHILD).closest('p');
    middleP.parentNode.insertBefore(leafP, middleP);
    F.selectValues(F.named(doc, CHILD), ['Bee']);
  });
  const pg = await load(html);
  const middle = child(pg, '9100002');
  const leaf = child(pg, '9100003');
  assert.deepEqual([D.selected(middle), D.state(middle)], [[''], 'ok']);
  assert.deepEqual([D.selected(leaf), D.state(leaf)], [[''], 'waiting']);
  assert.deepEqual(pg.updates.map((x) => x.fieldId), ['9100002', '9100003']);
  fire.choose(pg.window, parentOf(pg), 'Beta');
  assert.deepEqual(D.enabled(middle), ['', 'Bee']);
  invariants(pg);
});

test('F12 multi parent: union of the map, defaults of added parent values merged into a multi child', async () => {
  const html = F.tweak('list_multi_select', (doc) => {
    const p = F.named(doc, PARENT);
    p.setAttribute('name', `${PARENT}[]`);
    p.setAttribute('multiple', 'multiple');
    p.querySelector('option[value=""]').remove();
    F.named(doc, `${CHILD}[]`).setAttribute('data-dcf-defaults', JSON.stringify({ Alpha: 'Ape', Beta: 'Bee' }));
  });
  const pg = await load(html);
  const c = child(pg);
  assert.deepEqual(D.selected(c), ['Ant', 'Ape']);
  fire.choose(pg.window, D.byName(pg.document, PARENT), ['Alpha', 'Beta']);
  assert.deepEqual(D.enabled(c), ['Ant', 'Ape', 'Bee']);
  assert.deepEqual(D.selected(c), ['Ant', 'Ape', 'Bee']);
  invariants(pg);
});

test('F13 parent read-only by workflow: filtered by data-dcf-parent-values; a stored disallowed value kept with the locked hint', async () => {
  const pg = await load('read_only_parent');
  const c = child(pg);
  assert.deepEqual([D.state(c), D.enabled(c), D.selected(c)], ['ok', ['', 'Bee'], ['Bee']]);
  const html = F.tweak('read_only_parent', (doc) => {
    const s = F.named(doc, CHILD);
    s.setAttribute('data-dcf-stored', JSON.stringify({ child: ['Ant'], parent: ['Beta'] }));
    F.selectValues(s, ['Ant']);
  });
  const locked = await load(html);
  const lc = child(locked);
  assert.deepEqual([D.state(lc), D.selected(lc)], ['legacy', ['Ant']]);
  assert.equal(D.hintText(lc), 'Stored values that do not match Parent field (not editable here) are kept unchanged: Ant.');
  invariants(locked);
});

// WP-17 review: a read-only parent is unchanged only when its values equal
// the stored baseline, as the server's ParentState#changed? (it was always
// unchanged before).
test('F13c read-only parent that differs from the baseline (default filled in): the stored value is dropped, not legacy', async () => {
  const html = F.tweak('read_only_parent', (doc) => {
    const s = F.named(doc, CHILD);
    s.setAttribute('data-dcf-parent-values', JSON.stringify(['Alpha']));
    s.setAttribute('data-dcf-stored', JSON.stringify({ child: ['Bee'], parent: [] }));
  });
  const pg = await load(html);
  const c = child(pg);
  assert.deepEqual([D.state(c), D.selected(c), D.enabled(c), D.hintText(c)], ['ok', [''], ['', 'Ant', 'Ape'], null]);
  assert.equal(Array.from(c.options).some((o) => o.classList.contains('dcf-legacy-option')), false);
  assert.deepEqual(childEntries(pg), [`${CHILD}=`]);
  invariants(pg);
});

test('F13b parent not available: stored value dropped and posted blank, generic hint (UD-05); hide_when_disabled hides it', async () => {
  const pg = await load('parent_unavailable');
  const c = child(pg);
  assert.deepEqual([D.selected(c), D.state(c), D.hintText(c)], [[''], 'empty', 'No values are available for this field.']);
  assert.deepEqual(childEntries(pg), [`${CHILD}=`]);
  assert.deepEqual(pg.changes, [CHILD]);
  const hidden = await load(F.tweak('parent_unavailable', (doc) => F.named(doc, CHILD).setAttribute('data-dcf-hide', '1')));
  const p = child(hidden).closest('p');
  assert.deepEqual([p.hidden, p.classList.contains('dcf-hidden')], [true, true]);
  assert.deepEqual(childEntries(hidden), [`${CHILD}=`]);
  invariants(pg);
});

test('F16 hide_when_disabled: own p hidden while nothing is allowed, shown with the default, hidden again', async () => {
  const pg = await load('hide_when_disabled');
  const c = child(pg);
  const p = c.closest('p');
  assert.deepEqual([p.hidden, p.classList.contains('dcf-hidden'), D.state(c)], [true, true, 'empty']);
  assert.deepEqual(childEntries(pg), [`${CHILD}=`]);
  fire.choose(pg.window, parentOf(pg), 'Alpha');
  assert.deepEqual([p.hidden, p.classList.contains('dcf-hidden'), D.selected(c)], [false, false, ['Ape']]);
  fire.choose(pg.window, parentOf(pg), 'Gamma');
  assert.deepEqual([p.hidden, D.selected(c)], [true, ['']]);
  assert.equal(parentOf(pg).closest('p').hidden, false);
  invariants(pg);
});

test('F16 hide_when_disabled: never while a legacy value is selected; a p hidden by someone else stays hidden', async () => {
  const legacy = await load(F.tweak('hide_when_disabled', (doc) => {
    const s = F.named(doc, CHILD);
    s.setAttribute('data-dcf-stored', JSON.stringify({ child: ['Bee'], parent: ['Gamma'] }));
    F.selectValues(s, ['Bee']);
  }));
  const lc = child(legacy);
  assert.deepEqual([lc.closest('p').hidden, D.state(lc)], [false, 'legacy']);
  const theirs = await load(F.tweak('hide_when_disabled', (doc) => F.named(doc, CHILD).closest('p').setAttribute('hidden', 'hidden')));
  const tc = child(theirs);
  fire.choose(theirs.window, parentOf(theirs), 'Alpha');
  assert.equal(tc.closest('p').hidden, true);
  assert.equal(tc.closest('p').classList.contains('dcf-hidden'), false);
  assert.deepEqual(D.selected(tc), ['Ape']);
});

test('F16 hide_when_disabled: a p that also holds another field\'s control is never hidden', async () => {
  const pg = await load(F.tweak('hide_when_disabled', (doc) => {
    F.named(doc, CHILD).closest('p').insertAdjacentHTML('beforeend', '<input type="text" name="issue[custom_field_values][9100009]" value="x">');
  }));
  const c = child(pg);
  const p = c.closest('p');
  assert.deepEqual([p.hidden, p.classList.contains('dcf-hidden')], [false, false]);
  assert.deepEqual([D.state(c), D.selected(c), D.hintText(c)], ['empty', [''], 'No values are available for the selected Parent field.']);
  invariants(pg);
});

test('F17 time-entry fields inside the issue form are prefix-aware', async () => {
  const pg = await load('issue_time_entry_prefixes');
  const issueChild = D.control(pg.document, '9100002', 'issue');
  const timeChild = D.control(pg.document, '9100004', 'time_entry');
  assert.deepEqual([D.state(issueChild), D.selected(issueChild)], ['ok', ['Ant']]);
  assert.deepEqual([D.state(timeChild), D.enabled(timeChild)], ['waiting', ['']]);
  assert.equal(D.hintText(timeChild), 'Select a value for Time parent first.');
  const u = pg.updates.length;
  fire.choose(pg.window, D.byName(pg.document, 'time_entry[custom_field_values][9100003]'), 'Alpha');
  assert.deepEqual(D.enabled(timeChild), ['', 'Ant']);
  assert.ok(D.disabled(timeChild).includes('Bee'));
  assert.deepEqual(since(pg.updates, u).map((x) => x.fieldId), ['9100004']);
  fire.choose(pg.window, parentOf(pg), 'Beta');
  assert.deepEqual(D.enabled(timeChild), ['', 'Ant']);
  assert.deepEqual(D.enabled(issueChild), ['', 'Bee']);
  invariants(pg);
});

test('F18 project, user and My account forms behave like the issue form (a form without id)', async () => {
  const project = await load('project_form');
  const pc = D.control(project.document, '9100002');
  assert.deepEqual([D.state(pc), D.selected(pc)], ['legacy', ['Bee']]);
  const user = await load('user_form');
  const uc = D.control(user.document, '9100002');
  assert.deepEqual([D.state(uc), D.enabled(uc), D.selected(uc)], ['ok', ['', 'Ant'], ['Ant']]);
  fire.choose(user.window, D.byName(user.document, 'user[custom_field_values][9100001]'), 'Beta');
  assert.deepEqual(D.selected(uc), ['']);
  const account = await load('my_account');
  const ac = D.control(account.document, '9100002');
  assert.equal(D.state(ac), null);
  assert.deepEqual(D.enabled(ac), ['', 'Ant', 'Bee']);
  invariants(project);
  invariants(user);
});

// Hand-written: inline-edit rows with a nested prefix (no fixture renders one).
test('F19 inline-edit rows with a nested prefix issues[7] are filtered by their own parent only', async () => {
  const row = (n, parentValue) => {
    const p = `issues[${n}][custom_field_values][9100001]`;
    const c = `issues[${n}][custom_field_values][9100002]`;
    return `<p><label>Parent</label><select name="${p}"><option value=""></option><option value="Alpha"${parentValue === 'Alpha' ? ' selected' : ''}>Alpha</option><option value="Beta"${parentValue === 'Beta' ? ' selected' : ''}>Beta</option></select></p>` +
      `<p><label>Child</label><select name="${c}" data-dcf-field="9100002" data-dcf-parent="9100001" data-dcf-context="form" data-dcf-parent-name="${p}" data-dcf-map="{&quot;Alpha&quot;:[&quot;Ant&quot;],&quot;Beta&quot;:[&quot;Bee&quot;]}"><option value=""></option><option value="Ant">Ant</option><option value="Bee">Bee</option></select></p>`;
  };
  const pg = await load(`<form id="inline_edit_form">${row(7, 'Alpha')}${row(8, 'Beta')}</form>`);
  const c7 = D.byName(pg.document, 'issues[7][custom_field_values][9100002]');
  const c8 = D.byName(pg.document, 'issues[8][custom_field_values][9100002]');
  assert.deepEqual([D.enabled(c7), D.enabled(c8)], [['', 'Ant'], ['', 'Bee']]);
  fire.choose(pg.window, D.byName(pg.document, 'issues[7][custom_field_values][9100001]'), 'Beta');
  assert.deepEqual([D.enabled(c7), D.enabled(c8)], [['', 'Bee'], ['', 'Bee']]);
  invariants(pg);
});

// Hand-written: a third-party select_tag without data attributes.
test('F19b a third-party select without data-dcf-* is not filtered', async () => {
  const body = '<form><p><select name="issue[custom_field_values][9100001]"><option value="Alpha">Alpha</option><option value="Beta">Beta</option></select></p>' +
    '<p><select name="issue[custom_field_values][9100002]" id="issue_custom_field_values_9100002"><option value="Ant">Ant</option><option value="Bee">Bee</option></select></p></form>';
  const pg = await load(body);
  const c = D.byName(pg.document, CHILD);
  fire.choose(pg.window, D.byName(pg.document, PARENT), 'Beta');
  assert.deepEqual([D.enabled(c), D.selected(c), c.className, c.hasAttribute('data-dcf-state')], [['Ant', 'Bee'], ['Ant'], '', false]);
  assert.deepEqual(pg.updates, []);
});

// Hand-written: #inline_edit_form with an empty multi select child.
test('F19c an empty multi select in an inline edit form posts core name[]= only', async () => {
  const body = '<form id="inline_edit_form"><p><select name="issues[7][custom_field_values][9100001]"><option value="Alpha" selected>Alpha</option></select></p>' +
    '<p><select multiple name="issues[7][custom_field_values][9100002][]" data-dcf-field="9100002" data-dcf-parent="9100001" data-dcf-context="form" ' +
    'data-dcf-parent-name="issues[7][custom_field_values][9100001]" data-dcf-map="{&quot;Alpha&quot;:[&quot;Ant&quot;]}"><option value="Ant">Ant</option><option value="Bee">Bee</option></select>' +
    '<input type="hidden" name="issues[7][custom_field_values][9100002][]" value=""></p></form>';
  const pg = await load(body);
  assert.deepEqual(E.list(pg.document.forms[0], 'issues[7][custom_field_values][9100002]'), ['issues[7][custom_field_values][9100002][]=']);
  invariants(pg);
});

test('F20 an existing record with an empty child is not filled at load (UD-12); defaults apply on parent changes', async () => {
  const html = F.tweak('list_single', (doc) => {
    const s = F.named(doc, CHILD);
    F.selectValues(s, ['']);
    s.setAttribute('data-dcf-stored', JSON.stringify({ child: [], parent: ['Alpha'] }));
  });
  const pg = await load(html);
  assert.deepEqual([D.selected(child(pg)), D.state(child(pg))], [[''], 'ok']);
  assert.deepEqual(pg.changes, []);
  // The same markup without the baseline is a new record: the default at load.
  const fresh = await load(F.tweak(html, (doc) => F.named(doc, CHILD).removeAttribute('data-dcf-stored')));
  assert.deepEqual(D.selected(child(fresh)), ['Ape']);
  // A persisted record gets the default on a parent change.
  const hide = await load('hide_when_disabled');
  fire.choose(hide.window, parentOf(hide), 'Alpha');
  assert.deepEqual(D.selected(child(hide)), ['Ape']);
  invariants(pg);
});

// Derived from fixtures with the labels removed (hand-modified): no parent
// label resolves, so the generic texts of design 5.7 apply.
const unlabelled = (scenario) => F.tweak(scenario, (doc) => {
  F.named(doc, PARENT).closest('p').querySelector('label').remove();
  F.named(doc, CHILD).removeAttribute('data-dcf-parent-label');
});

test('X10 without any parent label: legacyGeneric for a legacy value, noOptionsGeneric for a blank parent', async () => {
  const pg = await load(unlabelled('legacy_value'));
  const c = child(pg);
  assert.deepEqual([D.state(c), D.hintText(c)], ['legacy', 'Stored values that do not match the current selection are kept unchanged: Bee.']);
  fire.choose(pg.window, parentOf(pg), '');
  assert.deepEqual([D.state(c), D.hintText(c)], ['waiting', 'No values are available for this field.']);
  invariants(pg);
});

test('X10 the required mark of a label is not part of hint or live texts', async () => {
  const pg = await load(F.tweak('list_single', (doc) => {
    F.named(doc, PARENT).closest('p').querySelector('label').insertAdjacentHTML('beforeend', ' <span class="required">*</span>');
    F.named(doc, CHILD).removeAttribute('data-dcf-parent-label');
  }));
  fire.choose(pg.window, parentOf(pg), '');
  assert.equal(D.hintText(child(pg)), 'Select a value for Parent field first.');
  const req = await load('list_single_required');
  fire.choose(req.window, parentOf(req), '');
  req.clock.tick(400);
  assert.equal(req.document.getElementById('dcf-live').textContent, 'Child field: Select a value for Parent field first.');
});

test('X10 legacy hint: at most 3 option labels, then ", ..."', async () => {
  const html = F.tweak('legacy_value_multi', (doc) => {
    const s = F.named(doc, `${CHILD}[]`);
    ['Cat', 'Cow', 'Dog'].forEach((v) => {
      const o = doc.createElement('option');
      o.value = v;
      o.textContent = `${v} label`;
      s.appendChild(o);
    });
    s.setAttribute('data-dcf-stored', JSON.stringify({ child: ['Bee', 'Cat', 'Cow', 'Dog'], parent: ['Alpha'] }));
    F.selectValues(s, ['Bee', 'Cat', 'Cow', 'Dog']);
  });
  const pg = await load(html);
  assert.equal(D.hintText(child(pg)),
    'Stored values that do not match the selected Parent field are kept until you change Parent field: Bee, Cat label, Cow label, ....');
});

test('X10 hint texts are set as text: markup characters of labels and values stay text', async () => {
  const html = F.tweak('tricky_values', (doc) => {
    const s = F.named(doc, CHILD);
    s.setAttribute('data-dcf-stored', JSON.stringify({ child: ['<b>&"'], parent: ['[x]'] }));
    F.selectValues(s, ['<b>&"']);
  });
  const pg = await load(html);
  const c = child(pg);
  const hint = D.hint(c);
  assert.equal(hint.textContent, 'Stored values that do not match the selected Parent <b>"& are kept until you change Parent <b>"&: <b>&".');
  assert.equal(hint.children.length, 0);
  assert.equal(pg.document.querySelectorAll('form b, form script').length, 0);
  fire.choose(pg.window, parentOf(pg), '');
  assert.equal(D.hintText(c), 'Select a value for Parent <b>"& first.');
  assert.equal(pg.document.querySelectorAll('form b, form script').length, 0);
  invariants(pg);
});

test('X10 hint ids are page unique across two forms; every choice input of a group carries the id', async () => {
  const pg = await load(F.read('radio').replace('id="issue-form"', 'id="a"') + F.read('radio').replace('id="issue-form"', 'id="b"'));
  pg.document.querySelectorAll('form').forEach((f) => fire.choose(pg.window, D.byName(f, PARENT), ''));
  const hints = Array.from(pg.document.querySelectorAll('em.dcf-hint'));
  assert.equal(hints.length, 2);
  assert.notEqual(hints[0].id, hints[1].id);
  pg.document.querySelectorAll('.check_box_group').forEach((g, k) => {
    D.choices(g).forEach((i) => assert.equal(i.getAttribute('aria-describedby'), hints[k].id));
  });
  // Hints carry no role; the live region (created with the first queued
  // message since the WP-17 review) is the only element with one.
  assert.deepEqual(Array.from(pg.document.querySelectorAll('[role]')).map((el) => el.id), ['dcf-live']);
});

// The tests clear the region text between steps, so a later write (or its
// absence) is observable.
test('X10 live region: nothing during init; created empty at the first message, filled after 400 ms, polite', async () => {
  const pg = await load('list_single');
  assert.equal(pg.document.querySelector('.dcf-live'), null);
  assert.equal(pg.clock.pending(), 0);
  fire.choose(pg.window, parentOf(pg), '');
  const live = pg.document.querySelector('.dcf-live');
  assert.ok(live, 'the live region exists before its text changes');
  assert.equal(live.id, 'dcf-live');
  assert.ok(live.classList.contains('hidden-for-sighted'));
  assert.deepEqual([live.getAttribute('role'), live.getAttribute('aria-live')], ['status', 'polite']);
  assert.equal(live.textContent, '');
  pg.clock.tick(399);
  assert.equal(live.textContent, '');
  pg.clock.tick(1);
  assert.equal(live.textContent, 'Child field: Select a value for Parent field first.');
  // Two changes of one field within 400 ms give that field's latest message only.
  live.textContent = '';
  fire.choose(pg.window, parentOf(pg), 'Gamma');
  pg.clock.tick(200);
  fire.choose(pg.window, parentOf(pg), '');
  pg.clock.tick(399);
  assert.equal(live.textContent, '');
  pg.clock.tick(1);
  assert.equal(live.textContent, 'Child field: Select a value for Parent field first.');
  assert.equal(pg.document.querySelectorAll('.dcf-live').length, 1);
});

test('X10 live region: a hint hidden again within 400 ms is not announced', async () => {
  const pg = await load('list_single');
  fire.choose(pg.window, parentOf(pg), 'Gamma');
  pg.clock.tick(100);
  fire.choose(pg.window, parentOf(pg), 'Alpha');
  pg.clock.tick(400);
  assert.deepEqual([D.state(child(pg)), D.hintText(child(pg))], ['ok', null]);
  assert.equal(pg.document.getElementById('dcf-live').textContent, '');
  assert.equal(pg.clock.pending(), 0);
});

test('X10 live region: a control removed within 400 ms is not announced', async () => {
  const pg = await load('list_single');
  fire.choose(pg.window, parentOf(pg), 'Gamma');
  pg.clock.tick(100);
  child(pg).closest('p').remove();
  pg.clock.tick(400);
  assert.equal(pg.document.getElementById('dcf-live').textContent, '');
});

test('X10 live region: a change that leaves the hint text unchanged announces nothing', async () => {
  const pg = await load(F.tweak('list_single', (doc) => {
    F.named(doc, PARENT).insertAdjacentHTML('beforeend', '<option value="Delta">Delta</option>');
  }));
  fire.choose(pg.window, parentOf(pg), 'Gamma');
  pg.clock.tick(400);
  const live = pg.document.getElementById('dcf-live');
  assert.equal(live.textContent, 'Child field: No values are available for the selected Parent field.');
  live.textContent = '';
  fire.choose(pg.window, parentOf(pg), 'Delta');
  pg.clock.tick(400);
  assert.equal(D.hintText(child(pg)), 'No values are available for the selected Parent field.');
  assert.equal(live.textContent, '');
});
