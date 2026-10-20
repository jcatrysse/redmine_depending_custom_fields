'use strict';
// WP-17: the pure rules of assets/javascripts/depending_custom_fields.js,
// required directly under CommonJS (frontend design 4, 5.3 to 5.5).
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const L = require('./support/large_list');
const R = require('../../assets/javascripts/depending_custom_fields.js');

const FIXTURES = path.join(__dirname, 'fixtures', 'markup');
const set = (s) => Array.from(s);

// One child: options '', a1, a2, b1; parent A allows a1 and a2.
const base = (o) => Object.assign({
  ctx: 'form', kind: 'values', key: R.parentKey(['A']), values: ['A'], prevValues: [],
  allowed: new Set(['a1', 'a2']), current: [''], initial: true, parentChanged: false, multiple: false,
  hasBlank: true, hasNone: false, noneRequired: false, optionValues: new Set(['', 'a1', 'a2', 'b1']),
  defaults: new Map(), memory: new Map(), hide: false, stored: null
}, o);
const bulk = (o) => base(Object.assign({
  ctx: 'bulk', hasNone: true, optionValues: new Set(['', '__none__', 'a1', 'a2', 'b1'])
}, o));

test('CommonJS: require() returns the pure rules, no window and no runtime', () => {
  assert.equal(typeof globalThis.window, 'undefined');
  ['parseFieldName', 'parseJSON', 'normalizeMap', 'normalizeDefaults', 'normalizeList', 'normalizeStored',
    'allowedFor', 'defaultsFor', 'parentKey', 'sameSet', 'parentState', 'legacyEligible', 'decide',
    'optionEnabled', 'orderByDepth', 'interpolate', 'contextOf', 'lockedRefused'].forEach((name) => {
    assert.equal(typeof R[name], 'function', name);
  });
  assert.equal(R.DependingCustomFields, undefined);
  assert.equal(R.init, undefined);
});

test('constants: NONE, BLANK, NOCHANGE_KEY and VERSION', () => {
  assert.equal(R.NONE, '__none__');
  assert.equal(R.BLANK, '');
  assert.equal(typeof R.VERSION, 'string');
  assert.ok(R.VERSION.length > 0);
  // A memory key no parentKey() JSON string can equal.
  [R.NOCHANGE_KEY, R.NONE_KEY].forEach((key) => {
    assert.ok(!key.startsWith('['), key);
    assert.notEqual(key, R.parentKey([]));
  });
  assert.notEqual(R.NOCHANGE_KEY, R.NONE_KEY);
});

test('contextOf: only "bulk" is bulk; missing, "form", "edit" and unknown read as form', () => {
  assert.equal(R.contextOf('bulk'), 'bulk');
  [null, undefined, '', 'form', 'edit', 'BULK', 'other'].forEach((raw) => assert.equal(R.contextOf(raw), 'form', String(raw)));
});

// Ruby blank? is /\A[[:space:]]*\z/ (White_Space): U+0085 is blank, U+FEFF is not.
test('isBlank: nil, empty and the Ruby [[:space:]] set only', () => {
  [null, undefined, '', ' ', '\t\n\v\f\r', '\u0085', '\u00a0', '\u1680', '\u2000\u200a', '\u2028\u2029', '\u202f',
    '\u205f', '\u3000'].forEach((v) => assert.equal(R.isBlank(v), true, JSON.stringify(v)));
  ['\ufeff', '\u200b', '\u180e', 'a', ' a ', '0', 0].forEach((v) => assert.equal(R.isBlank(v), false, JSON.stringify(v)));
  assert.deepEqual(R.normalizeList(['\ufeff', '\u0085', 'a']), ['\ufeff', 'a']);
  assert.deepEqual(set(R.normalizeMap({ A: ['\ufeff', '\u0085'], '\u0085': ['x'] }).get('A')), ['\ufeff']);
});

test('parseFieldName: greedy prefix, optional [], anything else null', () => {
  assert.deepEqual(R.parseFieldName('issue[custom_field_values][7]'), { prefix: 'issue', fieldId: '7', multiple: false });
  assert.deepEqual(R.parseFieldName('issue[custom_field_values][7][]'), { prefix: 'issue', fieldId: '7', multiple: true });
  assert.deepEqual(R.parseFieldName('time_entry[custom_field_values][9100003]'),
    { prefix: 'time_entry', fieldId: '9100003', multiple: false });
  assert.deepEqual(R.parseFieldName('project[custom_field_values][3]').prefix, 'project');
  assert.deepEqual(R.parseFieldName('user[custom_field_values][3]').prefix, 'user');
  assert.deepEqual(R.parseFieldName('issues[7][custom_field_values][9][]'), { prefix: 'issues[7]', fieldId: '9', multiple: true });
  assert.deepEqual(R.parseFieldName('issues[7][custom_field_values][9]'), { prefix: 'issues[7]', fieldId: '9', multiple: false });
  ['[custom_field_values][7]', 'issue[custom_field_values][x]', 'issue[custom_field_values][7][][]',
    'issue[custom_field_values][7]x', 'issue[custom_field_values]', 'issue[tracker_id]', '', null, undefined, 7]
    .forEach((name) => assert.equal(R.parseFieldName(name), null, String(name)));
});

test('parseJSON never throws: absent is ok null, invalid is not ok', () => {
  assert.deepEqual(R.parseJSON(null), { ok: true, value: null });
  assert.deepEqual(R.parseJSON(undefined), { ok: true, value: null });
  assert.deepEqual(R.parseJSON(''), { ok: true, value: null });
  assert.equal(R.parseJSON('{').ok, false);
  assert.equal(R.parseJSON('{"a":').ok, false);
  assert.deepEqual(R.parseJSON('{"A":["a1"]}'), { ok: true, value: { A: ['a1'] } });
  assert.deepEqual(R.parseJSON('[]'), { ok: true, value: [] });
});

test('normalizeMap: null for absent or non-object, {} gives an empty Map (nothing allowed)', () => {
  [null, undefined, [], ['A'], 'A', 1, true].forEach((v) => assert.equal(R.normalizeMap(v), null, JSON.stringify(v)));
  const empty = R.normalizeMap({});
  assert.ok(empty instanceof Map);
  assert.equal(empty.size, 0);
});

test('normalizeMap: String() coercion, blanks and null dropped, scalar, blank key, no trimming', () => {
  const map = R.normalizeMap({ A: [21, '22', 21, null, ''], B: 'b1', '': ['x'], ' C ': [' v '], D: [], E: ['  '] });
  assert.deepEqual(set(map.get('A')), ['21', '22']);
  assert.deepEqual(set(map.get('B')), ['b1']);
  assert.equal(map.has(''), false);
  assert.deepEqual(set(map.get(' C ')), [' v ']);
  assert.equal(map.has('C'), false);
  assert.equal(map.has('D'), false);
  assert.equal(map.has('E'), false);
});

test('normalizeMap: __proto__, constructor, hasOwnProperty and toString are plain keys', () => {
  const map = R.normalizeMap(JSON.parse('{"__proto__":["p1"],"constructor":["c1"],"hasOwnProperty":["h1"],"toString":["t1"]}'));
  assert.deepEqual(set(map.get('__proto__')), ['p1']);
  assert.deepEqual(set(map.get('constructor')), ['c1']);
  assert.deepEqual(set(map.get('hasOwnProperty')), ['h1']);
  assert.deepEqual(set(map.get('toString')), ['t1']);
  assert.equal({}.polluted, undefined);
  assert.equal(Object.prototype.hasOwnProperty.call(Object.prototype, 'p1'), false);
});

test('normalizeDefaults: one value or a list, integers as strings, configured order', () => {
  const d = R.normalizeDefaults({ A: 'a2', B: ['b3', 'b1', 'b3'], C: 9200005, '': 'x', D: [null, ''] });
  assert.deepEqual(d.get('A'), ['a2']);
  assert.deepEqual(d.get('B'), ['b3', 'b1']);
  assert.deepEqual(d.get('C'), ['9200005']);
  assert.equal(d.has(''), false);
  assert.equal(d.has('D'), false);
  assert.equal(R.normalizeDefaults(null).size, 0);
  assert.equal(R.normalizeDefaults([1]).size, 0);
});

test('normalizeList: unique non-blank strings, null for a non-array', () => {
  assert.deepEqual(R.normalizeList(['A', 'A', '', null, 3, ' ']), ['A', '3']);
  assert.deepEqual(R.normalizeList([]), []);
  assert.equal(R.normalizeList(null), null);
  assert.equal(R.normalizeList('A'), null);
});

test('normalizeStored on the stored JSON of the legacy_value, issue_copy and parent_unavailable fixtures', () => {
  const stored = (file) => {
    const html = fs.readFileSync(path.join(FIXTURES, `${file}.html`), 'utf8');
    const raw = /data-dcf-stored="([^"]*)"/.exec(html)[1].replace(/&quot;/g, '"').replace(/&amp;/g, '&');
    return R.normalizeStored(JSON.parse(raw));
  };
  assert.deepEqual(stored('legacy_value'), { child: ['Bee'], parent: ['Alpha'] });
  assert.deepEqual(stored('issue_copy'), { child: ['Bee'], parent: ['Alpha'] });
  assert.deepEqual(stored('parent_unavailable'), { child: [], parent: [] });
  // An absent attribute is the new-record flag (UD-12).
  assert.equal(R.normalizeStored(null), null);
  assert.equal(R.normalizeStored('x'), null);
  assert.equal(R.normalizeStored([]), null);
  assert.deepEqual(R.normalizeStored({ child: ['b1', 'b1', ''] }), { child: ['b1'], parent: null });
});

test('allowedFor: union in parent order then map order; blanks and unknown keys add nothing', () => {
  const map = R.normalizeMap({ A: ['x', 'a1'], B: ['b1', 'x'] });
  assert.deepEqual(set(R.allowedFor(map, ['B', 'A'])), ['b1', 'x', 'a1']);
  assert.deepEqual(set(R.allowedFor(map, ['A', 'B'])), ['x', 'a1', 'b1']);
  assert.deepEqual(set(R.allowedFor(map, ['', 'Z', 'A', 'A'])), ['x', 'a1']);
  assert.deepEqual(set(R.allowedFor(map, [])), []);
  assert.deepEqual(set(R.allowedFor(null, ['A'])), []);
});

test('defaultsFor: parent order then list order, first seen, filtered by the union', () => {
  const defaults = R.normalizeDefaults({ A: ['b1', 'a1'], B: 'x' });
  assert.deepEqual(R.defaultsFor(defaults, ['A', 'B'], new Set(['a1', 'b1', 'x'])), ['b1', 'a1', 'x']);
  assert.deepEqual(R.defaultsFor(defaults, ['A'], new Set(['a1'])), ['a1']);
  assert.deepEqual(R.defaultsFor(defaults, [''], new Set(['a1'])), []);
});

test('parentKey and sameSet: JSON keys stay distinct, order, duplicates and blanks do not count', () => {
  const keys = [['[x]'], ['a]'], ['"q"'], ['a||b'], ['a', 'b'], ['a|', '|b']].map((v) => R.parentKey(v));
  assert.equal(new Set(keys).size, keys.length);
  assert.equal(R.parentKey(['C', 'A']), R.parentKey(['A', 'C', 'A']));
  assert.ok(R.sameSet(['A', 'C'], ['C', 'A']));
  assert.ok(R.sameSet(['A', 'A'], ['A']));
  assert.ok(R.sameSet([''], []));
  assert.ok(!R.sameSet(['A'], ['A', 'B']));
});

test('parentState: one assertion per row of frontend design 5.3', () => {
  const ps = (...args) => { const r = R.parentState(...args); return [r.kind, r.values]; };
  // form
  assert.deepEqual(ps('form', true, ['A'], null), ['values', ['A']]);
  assert.deepEqual(ps('form', true, [''], null), ['empty', []]);
  assert.deepEqual(ps('form', true, [], null), ['empty', []]);
  assert.deepEqual(ps('form', false, [], ['B']), ['static', ['B']]);
  assert.deepEqual(ps('form', false, [], []), ['static', []]);
  assert.deepEqual(ps('form', false, [], null), ['unfiltered', []]);
  // bulk
  assert.deepEqual(ps('bulk', true, ['A'], null), ['values', ['A']]);
  assert.deepEqual(ps('bulk', true, ['__none__', 'A'], null), ['values', ['A']]);
  assert.deepEqual(ps('bulk', true, ['__none__'], null), ['none', []]);
  assert.deepEqual(ps('bulk', true, [''], null), ['unfiltered', []]);
  assert.deepEqual(ps('bulk', true, [], null), ['unfiltered', []]);
  assert.deepEqual(ps('bulk', false, [], null), ['unfiltered', []]);
  // bulk never carries parent values
  assert.deepEqual(ps('bulk', false, [], ['B']), ['unfiltered', []]);
  // any context, data-dcf-map absent or invalid
  assert.deepEqual(ps('form', true, ['A'], null, false), ['unfiltered', []]);
  assert.deepEqual(ps('bulk', true, ['A'], null, false), ['unfiltered', []]);
});

test('parentState: the sig (kind|key) tells none, unfiltered, empty, static and values apart', () => {
  const sig = (...args) => { const r = R.parentState(...args); return `${r.kind}|${r.key}`; };
  const sigs = [sig('bulk', true, ['__none__']), sig('bulk', true, ['']), sig('form', true, ['']),
    sig('form', false, [], []), sig('form', true, ['A']), sig('form', true, ['B'])];
  assert.equal(new Set(sigs).size, sigs.length);
  assert.equal(sig('form', true, ['A', 'B']), sig('form', true, ['B', 'A']));
});

test('legacyEligible: per value, needs form context, a baseline and an unchanged parent (UD-04)', () => {
  const stored = { parent: ['A'], child: ['b1', 'a1'] };
  assert.deepEqual(set(R.legacyEligible(base({ stored }), new Set(['a1', 'a2']))), ['b1']);
  assert.deepEqual(set(R.legacyEligible(base({ stored, values: ['B'] }), new Set(['b1']))), []);
  assert.deepEqual(set(R.legacyEligible(base({ stored: null }), new Set(['a1']))), []);
  // WP-17 review: a read-only (static) parent is unchanged only on its stored
  // values, as the server's ParentState#changed?; it always counted as unchanged before.
  assert.deepEqual(set(R.legacyEligible(base({ stored, kind: 'static', values: ['A'] }), new Set())), ['b1', 'a1']);
  assert.deepEqual(set(R.legacyEligible(base({ stored, kind: 'static', values: ['Z'] }), new Set())), []);
  // A default filled in for a parent without a saved row: baseline [], so changed.
  assert.deepEqual(set(R.legacyEligible(base({ stored: { parent: [], child: ['b1'] }, kind: 'static', values: ['A'] }),
    new Set(['a1']))), []);
  assert.deepEqual(set(R.legacyEligible(base({ stored: { parent: null, child: ['b1'] }, kind: 'static', values: ['A'] }),
    new Set(['a1']))), []);
  assert.deepEqual(set(R.legacyEligible(base({ stored, ctx: 'bulk' }), new Set())), []);
  assert.deepEqual(set(R.legacyEligible(base({ stored }), null)), []);
  // A blank parent equals no stored parent value.
  assert.deepEqual(set(R.legacyEligible(base({ stored: { parent: [], child: ['b1'] }, kind: 'empty', values: [] }), new Set())), ['b1']);
});

test('decide (form, initial): keeps usable values, drops the rest, no defaults for a baseline (UD-12)', () => {
  const defaults = new Map([['A', ['a2']]]);
  assert.deepEqual(R.decide(base({ current: ['a1'], defaults })).values, ['a1']);
  // Plain new record, empty child: the per-parent default.
  assert.deepEqual(R.decide(base({ defaults })).values, ['a2']);
  // Persisted (or copied) record: no default at load.
  assert.deepEqual(R.decide(base({ defaults, stored: { parent: ['A'], child: [] } })).values, ['']);
  // WP-17 review: no usable value left after the drop (plain new record):
  // the default, as the legacy script; it stayed '' before.
  assert.deepEqual(R.decide(base({ current: ['b1'], defaults })).values, ['a2']);
  // ... but not with a baseline, and not when a usable value is left.
  assert.deepEqual(R.decide(base({ current: ['b1'], defaults, stored: { parent: ['A'], child: ['a1'] } })).values, ['']);
  assert.deepEqual(R.decide(base({ current: ['b1', 'a1'], multiple: true, defaults })).values, ['a1']);
  // Only for kind values.
  assert.deepEqual(R.decide(base({ defaults, kind: 'static', values: ['A'] })).values, ['']);
  // AJAX re-render: memory beats defaults.
  assert.deepEqual(R.decide(base({ defaults, memory: new Map([[R.parentKey(['A']), ['a1']]]) })).values, ['a1']);
});

test('decide (form, initial): stored legacy value kept and marked, a posted one dropped (F6, F6c)', () => {
  const stored = { parent: ['A'], child: ['b1'] };
  const d = R.decide(base({ current: ['b1'], stored }));
  assert.deepEqual([d.values, set(d.legacy), d.state, d.hint], [['b1'], ['b1'], 'legacy', 'legacy']);
  const c = R.decide(base({ current: ['b1'], stored: { parent: ['A'], child: ['a1'] } }));
  assert.deepEqual([c.values, set(c.legacy), c.state], [[''], [], 'ok']);
});

test('decide (form, parent change): memory, stored state, carry, defaults in that order', () => {
  const key = R.parentKey(['A']);
  const changed = (o) => base(Object.assign({ initial: false, parentChanged: true, prevValues: ['B'] }, o));
  // 1. memory, filtered by usable
  assert.deepEqual(R.decide(changed({ memory: new Map([[key, ['a2']]]) })).values, ['a2']);
  // memory filtered down to nothing is ignored; an empty pick is kept
  assert.deepEqual(R.decide(changed({ memory: new Map([[key, ['b1']]]), defaults: new Map([['A', ['a1']]]) })).values, ['a1']);
  assert.deepEqual(R.decide(changed({ memory: new Map([[key, []]]), defaults: new Map([['A', ['a1']]]) })).values, ['']);
  // 2. back on the stored parent: the stored child, legacy included
  const back = R.decide(changed({ stored: { parent: ['A'], child: ['b1'] }, defaults: new Map([['A', ['a1']]]) }));
  assert.deepEqual([back.values, back.state], [['b1'], 'legacy']);
  // 3. carry when the previous parent values were empty or a subset
  assert.deepEqual(R.decide(changed({ prevValues: [], current: ['a1'] })).values, ['a1']);
  assert.deepEqual(R.decide(changed({ prevValues: ['A'], values: ['A', 'B'], key: R.parentKey(['A', 'B']),
    allowed: new Set(['a1', 'a2', 'b1']), current: ['a1'] })).values, ['a1']);
  assert.deepEqual(R.decide(changed({ prevValues: ['B'], current: ['a1'] })).values, ['']);
  // 4. defaults
  assert.deepEqual(R.decide(changed({ defaults: new Map([['A', ['a2']]]) })).values, ['a2']);
});

test('decide (form, parent change): a multi child also gets the defaults of added parent values (F12)', () => {
  const d = R.decide(base({
    initial: false, parentChanged: true, multiple: true, hasBlank: false, prevValues: ['A'], values: ['A', 'B'],
    key: R.parentKey(['A', 'B']), allowed: new Set(['a1', 'a2', 'b1']), current: ['a1'],
    defaults: new Map([['A', ['a2']], ['B', ['b1']]])
  }));
  assert.deepEqual(d.values, ['a1', 'b1']);
});

test('decide (form): values need an option, a single child keeps one, states, hideField, rememberKey', () => {
  assert.deepEqual(R.decide(base({ current: ['a1', 'a2'], multiple: true })).values, ['a1', 'a2']);
  assert.deepEqual(R.decide(base({ current: ['a1', 'a2'] })).values, ['a1']);
  assert.deepEqual(R.decide(base({ defaults: new Map([['A', ['zz']]]), allowed: new Set(['zz']) })).values, ['']);
  assert.deepEqual(R.decide(base({ hasBlank: false })).values, []);
  const waiting = R.decide(base({ kind: 'empty', values: [], key: R.parentKey([]), allowed: new Set() }));
  assert.deepEqual([waiting.state, waiting.hint], ['waiting', 'waiting']);
  const empty = R.decide(base({ allowed: new Set(), hide: true }));
  assert.deepEqual([empty.state, empty.hint, empty.hideField], ['empty', 'empty', true]);
  const legacyEmpty = R.decide(base({ allowed: new Set(), hide: true, current: ['b1'], stored: { parent: ['A'], child: ['b1'] } }));
  assert.deepEqual([legacyEmpty.state, legacyEmpty.hideField], ['legacy', false]);
  const ok = R.decide(base({ current: ['a1'] }));
  assert.deepEqual([ok.state, ok.hint, ok.hideField, ok.rememberKey, ok.auto], ['ok', null, false, R.parentKey(['A']), false]);
  assert.deepEqual(Object.keys(ok).sort(),
    ['auto', 'eligible', 'filter', 'hideField', 'hint', 'legacy', 'rememberKey', 'state', 'values']);
});

test('decide (unfiltered): values as rendered, no filter, state unfiltered', () => {
  const d = R.decide(base({ kind: 'unfiltered', allowed: null, current: ['b1'] }));
  assert.deepEqual([d.values, d.filter, d.state, d.hint], [['b1'], null, 'unfiltered', null]);
});

test('decide (bulk, unfiltered): initial as rendered, a return restores memory[NOCHANGE] (B4)', () => {
  const initial = R.decide(bulk({ kind: 'unfiltered', key: R.NOCHANGE_KEY, allowed: null, current: [''] }));
  assert.deepEqual([initial.values, initial.state, initial.rememberKey], [[''], 'unfiltered', R.NOCHANGE_KEY]);
  const back = R.decide(bulk({ kind: 'unfiltered', key: R.NOCHANGE_KEY, allowed: null, initial: false, parentChanged: true,
    current: ['__none__'], memory: new Map([[R.NOCHANGE_KEY, ['b1']]]) }));
  assert.deepEqual(back.values, ['b1']);
});

test('decide (bulk, links): remembered pick, carry, default with hint, else (no change) (UD-09)', () => {
  const changed = (o) => bulk(Object.assign({ initial: false, parentChanged: true }, o));
  assert.deepEqual(R.decide(bulk({ current: [''] })).values, ['']);
  assert.deepEqual(R.decide(bulk({ current: ['b1'] })).values, ['']);
  assert.deepEqual(R.decide(changed({ memory: new Map([[R.parentKey(['A']), ['a2']]]) })).values, ['a2']);
  assert.deepEqual(R.decide(changed({ current: ['a1'] })).values, ['a1']);
  const d = R.decide(changed({ defaults: new Map([['A', ['a1']]]) }));
  assert.deepEqual([d.values, d.auto, d.hint, d.state], [['a1'], true, 'bulkDefault', 'ok']);
  const none = R.decide(changed({}));
  assert.deepEqual([none.values, none.auto, none.hint], [[''], false, null]);
  const multi = R.decide(changed({ multiple: true, hasBlank: false, optionValues: new Set(['__none__', 'a1', 'a2', 'b1']) }));
  assert.deepEqual(multi.values, []);
});

test('decide (bulk, nothing allowed): __none__ with bulkCleared, else (no change) with the empty hint', () => {
  const changed = (o) => bulk(Object.assign({ initial: false, parentChanged: true, allowed: new Set() }, o));
  const e = R.decide(changed({}));
  assert.deepEqual([e.values, e.state, e.hint, e.auto], [['__none__'], 'empty', 'bulkCleared', true]);
  const n = R.decide(changed({ kind: 'none', values: [], key: R.NONE_KEY }));
  assert.deepEqual([n.values, n.state, n.hint], [['__none__'], 'none', 'bulkCleared']);
  const r = R.decide(changed({ hasNone: false, optionValues: new Set(['', 'a1']) }));
  assert.deepEqual([r.values, r.state, r.hint], [[''], 'empty', 'empty']);
});

test('optionEnabled: form, bulk links and bulk nothing-allowed rows', () => {
  const form = R.decide(base({ current: ['b1'], stored: { parent: ['A'], child: ['b1'] } })).filter;
  assert.deepEqual(['', 'a1', 'a2', 'b1', 'zz'].map((v) => R.optionEnabled(form, v)), [true, true, true, true, false]);
  const links = R.decide(bulk({})).filter;
  assert.deepEqual(['', '__none__', 'a1', 'b1'].map((v) => R.optionEnabled(links, v)), [true, true, true, false]);
  const nothing = R.decide(bulk({ allowed: new Set(), initial: false, parentChanged: true })).filter;
  assert.deepEqual(['', '__none__', 'a1'].map((v) => R.optionEnabled(nothing, v)), [false, true, false]);
  const nothingNoNone = R.decide(bulk({ allowed: new Set(), hasNone: false, initial: false, parentChanged: true,
    optionValues: new Set(['', 'a1']) })).filter;
  assert.equal(R.optionEnabled(nothingNoNone, ''), true);
  assert.equal(R.optionEnabled(null, 'anything'), true);
});

test('optionEnabled: a data-dcf-required-none option only while nothing is allowed (UD-10)', () => {
  const opts = { noneRequired: true };
  const unfiltered = R.decide(bulk(Object.assign({ kind: 'unfiltered', key: R.NOCHANGE_KEY, allowed: null }, opts)));
  assert.equal(R.optionEnabled(unfiltered.filter, '__none__', true), false);
  const links = R.decide(bulk(Object.assign({ initial: false, parentChanged: true, current: ['__none__'] }, opts)));
  assert.equal(R.optionEnabled(links.filter, '__none__', true), false);
  assert.ok(!links.values.includes('__none__'), 'never a fallback while options exist');
  const remembered = R.decide(bulk(Object.assign({ initial: false, parentChanged: true,
    memory: new Map([[R.parentKey(['A']), ['__none__']]]) }, opts)));
  assert.deepEqual(remembered.values, ['']);
  const nothing = R.decide(bulk(Object.assign({ allowed: new Set(), initial: false, parentChanged: true }, opts)));
  assert.equal(R.optionEnabled(nothing.filter, '__none__', true), true);
  assert.deepEqual(nothing.values, ['__none__']);
  // In form context '' is always enabled and a plain __none__ option never.
  const form = R.decide(base({})).filter;
  assert.equal(R.optionEnabled(form, ''), true);
});

test('orderByDepth: parents first, stable, terminates on cycles and self-parents', () => {
  const out = R.orderByDepth([{ id: 1, parentId: 2 }, { id: 2, parentId: 1 }, { id: 3, parentId: 3 }, { id: 4, parentId: 1 }]);
  assert.equal(out.length, 4);
  assert.deepEqual(out.map((n) => n.id).sort(), [1, 2, 3, 4]);
  const chain = R.orderByDepth([{ id: 'c', parentId: 'b' }, { id: 'b', parentId: 'a' }, { id: 'x', parentId: 'q' }, { id: 'a', parentId: 'r' }]);
  assert.deepEqual(chain.map((n) => n.id), ['x', 'a', 'b', 'c']);
});

test('interpolate: %{name} tokens, unknown kept, inserted text not re-read, $& literal', () => {
  assert.equal(R.interpolate('%{field}: %{message}', { field: 'Child', message: 'Hint.' }), 'Child: Hint.');
  assert.equal(R.interpolate('Select %{parent} %{unknown}', { parent: 'P' }), 'Select P %{unknown}');
  assert.equal(R.interpolate('%{parent} x %{parent}', { parent: 'A $& %{values}' }), 'A $& %{values} x A $& %{values}');
  assert.equal(R.interpolate('%{toString}', {}), '%{toString}');
  assert.equal(R.interpolate(null, {}), '');
});

test('lockedRefused (UD-37 hook point): the read_only_child_carrier fixture', () => {
  const html = fs.readFileSync(path.join(FIXTURES, 'read_only_child_carrier.html'), 'utf8');
  const attr = (name) => JSON.parse(new RegExp(`${name}="([^"]*)"`).exec(html)[1].replace(/&quot;/g, '"'));
  const stored = attr('data-dcf-locked-stored');
  const allowedBy = attr('data-dcf-locked-allowed-by');
  assert.deepEqual([stored, allowedBy], [['Alpha'], [['Beta']]]);
  assert.equal(R.lockedRefused(stored, allowedBy, ['Beta']), false);
  assert.equal(R.lockedRefused(stored, allowedBy, ['Alpha']), false);
  assert.equal(R.lockedRefused(stored, allowedBy, ['Gamma']), true);
  assert.equal(R.lockedRefused(stored, allowedBy, []), true);
  assert.equal(R.lockedRefused(stored, allowedBy, ['']), true);
  assert.equal(R.lockedRefused(['A'], [['B', 'D'], ['C']], ['B']), true);
  assert.equal(R.lockedRefused(['A'], [['B', 'D'], ['C']], ['B', 'C']), false);
});

// Quality G6: wall clock only with 10x headroom. One warm-up pass, then the
// minimum of 5 runs; the filter (union, decide, optionEnabled over every
// option) is timed apart from JSON parse plus normalizeMap.
test('performance: 25,000 options and 5,000 parent keys, union, decide and filter under 100 ms (warm minimum)', () => {
  const children = L.names(25000, { trickyEvery: 97 });
  const parents = L.names(5000, { prefix: 'P' });
  const raw = JSON.stringify(L.partition(parents, children, L.sizes(25000, 5000)));
  const optionValues = new Set([''].concat(children));
  const elapsed = (fn) => { const t0 = process.hrtime.bigint(); const out = fn(); return [Number(process.hrtime.bigint() - t0) / 1e6, out]; };
  const filter = (map) => {
    const picked = [];
    let allowed = new Set();
    for (const p of parents) {
      picked.push(p);
      allowed = R.allowedFor(map, picked);
      if (allowed.size >= 5000) break;
    }
    const d = R.decide(base({ values: picked, key: R.parentKey(picked), allowed, optionValues, current: [children[1]] }));
    let count = 0;
    children.forEach((v) => { if (R.optionEnabled(d.filter, v)) count += 1; });
    return { picked, allowed, count };
  };
  const parseRuns = [];
  const filterRuns = [];
  let map = null;
  let out = null;
  for (let k = 0; k < 6; k += 1) {
    const [pm, m] = elapsed(() => R.normalizeMap(R.parseJSON(raw).value));
    const [fm, o] = elapsed(() => filter(m));
    map = m;
    out = o;
    if (k > 0) {
      parseRuns.push(pm);
      filterRuns.push(fm);
    }
  }
  const ms = Math.min(...filterRuns);
  const parseMs = Math.min(...parseRuns);
  assert.equal(map.size, 5000);
  assert.ok(out.allowed.size >= 5000);
  assert.equal(out.count, out.allowed.size);
  assert.ok(ms < 100, `filter took ${ms} ms`);
  console.log(`# perf ms=${ms.toFixed(1)} parse_ms=${parseMs.toFixed(1)} parents=${out.picked.length} allowed=${out.allowed.size}`);
});
