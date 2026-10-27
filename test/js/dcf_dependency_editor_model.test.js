'use strict';
// WP-23 (editor design 5.5 and 5.6, QA-11): the pure editor model
// assets/javascripts/dcf_dependency_editor_model.js under plain node --test
// (no DOM). Null-prototype dictionaries are not deepStrictEqual to object
// literals, so payloads are compared through their JSON text (J below).
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const L = require('./support/large_list');

const MODEL_PATH = path.join(__dirname, '..', '..', 'assets', 'javascripts', 'dcf_dependency_editor_model.js');
const M = require(MODEL_PATH);

const J = (x) => JSON.parse(JSON.stringify(x));
const wire = (keys) => keys.map((key) => ({ key }));
const list = (keys) => M.ValueList.fromWire(wire(keys));
const BASE = 'ab'.repeat(32);
const elapsed = (fn) => {
  const t0 = process.hrtime.bigint();
  const out = fn();
  return [Number(process.hrtime.bigint() - t0) / 1e6, out];
};
// One warm-up run, then the minimum of 5 (quality G6: wall clock with 10x headroom).
const warmMinimum = (fn) => {
  let out = null;
  const runs = [];
  for (let k = 0; k < 6; k += 1) {
    const [ms, o] = elapsed(fn);
    out = o;
    if (k > 0) runs.push(ms);
  }
  return [Math.min(...runs), out];
};

// ---------------------------------------------------------------- module

test('loads under CommonJS without a DOM and exports the model API', () => {
  assert.equal(typeof globalThis.window, 'undefined');
  assert.equal(typeof globalThis.DcfDependencyEditorModel, 'undefined');
  ['fold', 'tokens', 'matchesTokens', 'isBlank', 'isDigest', 'listValuesFromText', 'State', 'serialize',
    'stringify', 'utf8Bytes', 'conflictCounts'].forEach((name) => assert.equal(typeof M[name], 'function', name));
  assert.equal(typeof M.ValueList.fromWire, 'function');
  assert.equal(M.VERSION, 1);
});

test('defines only window.DcfDependencyEditorModel in a browser window and leaves the DOM alone', () => {
  const { JSDOM } = require('jsdom');
  const dom = new JSDOM('<!doctype html><html><body><p>x</p></body></html>', { runScripts: 'outside-only' });
  const before = new Set(Object.getOwnPropertyNames(dom.window));
  dom.window.eval(fs.readFileSync(MODEL_PATH, 'utf8'));
  const added = Object.getOwnPropertyNames(dom.window).filter((n) => !before.has(n));
  assert.deepEqual(added, ['DcfDependencyEditorModel']);
  const W = dom.window.DcfDependencyEditorModel;
  assert.equal(W.fold('\u0141\u00f3d\u017a'), 'lodz');
  assert.equal(typeof W.ValueList.fromWire, 'function');
  assert.equal(dom.window.document.body.innerHTML, '<p>x</p>');
  // A copy loaded later is ignored: objects built from the first still serialize.
  const state = new W.State(null);
  const children = W.ValueList.fromWire([]);
  dom.window.eval(fs.readFileSync(MODEL_PATH, 'utf8'));
  const kept = dom.window.DcfDependencyEditorModel;
  assert.equal(kept, W);
  assert.equal(kept.stringify(kept.serialize(state, null, children, {})),
               '{"version":1,"source":"editor","value_dependencies":{},"default_value_dependencies":{}}');
});

test('the source is ASCII, ES2017 in its built-ins, and has no DOM, console, for-in or own hasOwnProperty call', () => {
  const src = fs.readFileSync(MODEL_PATH, 'utf8');
  assert.equal(/[^\x00-\x7f]/.test(src), false, 'non-ASCII character: use \\u escapes');
  const later = /\b(fromEntries|flatMap|trimStart|trimEnd|matchAll|replaceAll|hasOwn\(|globalThis|structuredClone|toWellFormed|isWellFormed)\b|\.flat\(|\.at\(|\.finally\(/;
  assert.equal(later.test(src), false, `ES2018+ built-in: ${(src.match(later) || [])[0]}`);
  assert.equal(/\bdocument\b|innerHTML|\bconsole\b|\brequire\(/.test(src), false);
  assert.equal(/for\s*\([^)]*\bin\b/.test(src), false);
  assert.equal(/\.hasOwnProperty\(/.test(src), false);
});

test('logs nothing while loading and working', () => {
  const calls = [];
  const saved = {};
  ['log', 'warn', 'error', 'info', 'debug'].forEach((m) => { saved[m] = console[m]; console[m] = () => calls.push(m); });
  try {
    delete require.cache[require.resolve(MODEL_PATH)];
    const fresh = require(MODEL_PATH);
    const state = new fresh.State(JSON.parse('{"value_dependencies":{"A":["a"],"Gone":["a"]}}'));
    const one = (k) => fresh.ValueList.fromWire([{ key: k }]);
    fresh.stringify(fresh.serialize(state, one('A'), one('a'), { multiple: false }));
    assert.throws(() => fresh.ValueList.fromWire('x'), TypeError);
  } finally {
    Object.keys(saved).forEach((m) => { console[m] = saved[m]; });
  }
  assert.deepEqual(calls, []);
});

// ---------------------------------------------------------------- fold and search

test('fold maps the special letters, strips accents and lowercases', () => {
  assert.equal(M.fold('Stra\u00dfe'), 'strasse');
  assert.equal(M.fold('\u0141\u00f3d\u017a'), 'lodz');
  assert.equal(M.fold('\u00c6ble \u0152uvre \u00d8re \u0110uro \u00deing \u0131i'), 'aeble oeuvre ore duro thing ii');
  assert.equal(M.fold('\u00c9MILE'), 'emile');
  assert.equal(M.fold('E\u0301mile'), M.fold('\u00c9mile'));
  assert.equal(M.fold('\ufb01nal \u2163'), 'final iv');
});

test('fold of null, undefined, a number, a lone combining mark and white space only', () => {
  assert.equal(M.fold(null), '');
  assert.equal(M.fold(undefined), '');
  assert.equal(M.fold(12), '12');
  assert.equal(M.fold('\u0301'), '');
  assert.equal(M.fold('\u0301\u0300'), '');
  assert.equal(M.fold(' \t\u3000 '), '');
});

test('fold collapses white space runs to one space and trims them', () => {
  assert.equal(M.fold('  Rio\tde   Janeiro '), 'rio de janeiro');
  assert.equal(M.fold('S\u00e3o\u00a0\u00a0Paulo'), 'sao paulo');
});

test('fold strips each COMBINING range at both ends and keeps the marks outside them', () => {
  [0x300, 0x36f, 0x1ab0, 0x1aff, 0x1dc0, 0x1dff, 0x20d0, 0x20ff, 0xfe20, 0xfe2f].forEach((cp) => {
    assert.equal(M.fold('a' + String.fromCharCode(cp)), 'a', cp.toString(16));
  });
  // Outside the ranges (Hebrew point, Devanagari sign): kept, as in ValueCollation.
  assert.equal(M.fold('a\u05b0b'), 'a\u05b0b');
  assert.equal(M.fold('a\u093fb'), 'a\u093fb');
});

test('fold handles the Turkish dotted and dotless I without locale rules', () => {
  assert.equal(M.fold('I'), 'i');
  assert.equal(M.fold('\u0130stanbul'), 'istanbul');
  assert.equal(M.fold('I\u011fd\u0131r'), 'igdir');
  const script = `const M = require(${JSON.stringify(MODEL_PATH)});` +
    "process.stdout.write(JSON.stringify([M.fold('I'), M.fold('\\u0130stanbul'), M.fold('I\\u011fd\\u0131r')]));";
  const out = execFileSync(process.execPath, ['-e', script],
                           { env: Object.assign({}, process.env, { LANG: 'tr_TR.UTF-8', LC_ALL: 'tr_TR.UTF-8' }) });
  assert.deepEqual(JSON.parse(out.toString()), ['i', 'istanbul', 'igdir']);
});

test('tokens folds the query and splits it; an empty or mark-only query is unfiltered', () => {
  assert.deepEqual(M.tokens(' Sao  PAULO '), ['sao', 'paulo']);
  assert.deepEqual(M.tokens(''), []);
  assert.deepEqual(M.tokens('   '), []);
  assert.deepEqual(M.tokens('\u0301'), []);
  assert.deepEqual(M.tokens(null), []);
});

test('matchesTokens needs every token as a substring of the folded label (AND)', () => {
  const folded = M.fold('S\u00e3o Paulo do Norte');
  assert.equal(M.matchesTokens(folded, M.tokens('s\u00e3o paulo')), true);
  assert.equal(M.matchesTokens(folded, M.tokens('norte sao')), true);
  assert.equal(M.matchesTokens(folded, M.tokens('paulo sul')), false);
  assert.equal(M.matchesTokens(folded, []), true);
  assert.equal(M.matchesTokens(M.fold('\u0141\u00f3d\u017a'), M.tokens('lodz')), true);
  assert.equal(M.matchesTokens(M.fold('\u039f\u0394\u039f\u03a3\u03a4\u03a1\u03a9\u039c\u0391'),
                               M.tokens('\u039f\u0394\u039f\u03a3')), true);
});

test('isBlank follows Ruby blank? ([[:space:]], U+FEFF is not blank)', () => {
  ['', ' ', '\t\n\v\f\r', '\u00a0', '\u3000\u2028', '\u0085', null, undefined].forEach((v) => {
    assert.equal(M.isBlank(v), true, JSON.stringify(v));
  });
  ['x', '\ufeff', '\u200b', '\u0000', '0'].forEach((v) => assert.equal(M.isBlank(v), false, JSON.stringify(v)));
});

test('isDigest accepts 64 lowercase hex characters only', () => {
  assert.equal(M.isDigest(BASE), true);
  ['', 'abc', BASE.toUpperCase(), BASE + '0', null, undefined, 1].forEach((v) => assert.equal(M.isDigest(v), false));
});

// ---------------------------------------------------------------- ValueList

test('fromWire: label defaults to the key only when absent; an explicit label, even empty, stays a String', () => {
  const values = M.ValueList.fromWire([{ key: '11', label: 'Red' }, { key: '12', label: 'Old', active: false },
                                       { key: 'B' }, { key: 'B', label: 'dup' }, { key: 'x', label: '' },
                                       { key: 'n', label: null }, { key: 7 }]);
  assert.deepEqual(values.items.map((i) => i.label), ['Red', 'Old', 'B', '', 'null', '7']);
  assert.deepEqual(values.items.map((i) => i.key), ['11', '12', 'B', 'x', 'n', '7']);
  assert.equal(values.byKey.get('B').label, 'B');
  assert.ok(values.byKey instanceof Map);
});

test('fromWire: only active === false is inactive', () => {
  const values = M.ValueList.fromWire([{ key: 'a', active: false }, { key: 'b', active: 0 }, { key: 'c', active: null },
                                       { key: 'd', active: 'false' }, { key: 'e' }, { key: 'f', active: true }]);
  assert.deepEqual(values.items.map((i) => i.active), [false, true, true, true, true, true]);
});

test('fromWire: duplicates keep the first, blank keys are skipped, index and folded are set', () => {
  const values = M.ValueList.fromWire([{ key: '11' }, { key: '' }, { key: ' \u00a0' }, { key: '9200001', label: '\u00c9mile' },
                                       { key: '11', label: 'dup' }]);
  assert.deepEqual(values.items.map((i) => [i.key, i.index]), [['11', 0], ['9200001', 1]]);
  assert.equal(values.byKey.get('9200001').folded, 'emile');
  assert.equal(values.byKey.get('11').folded, '11');
  assert.deepEqual(values.keys(), ['11', '9200001']);
  assert.equal(values.has('11'), true);
  assert.equal(values.has(11), true);
  assert.equal(values.has('x'), false);
  assert.equal(values.get('9200001').label, '\u00c9mile');
});

test('fromWire: keys such as __proto__ and hasOwnProperty are ordinary keys and the input is not changed', () => {
  const input = JSON.parse('[{"key":"__proto__","label":"P"},{"key":"a","hasOwnProperty":1,"label":"x"},' +
                           '{"key":"constructor"},{"key":"toString","active":false}]');
  const copy = JSON.stringify(input);
  const values = M.ValueList.fromWire(input);
  assert.equal(values.byKey.get('__proto__').label, 'P');
  assert.equal(values.byKey.get('a').label, 'x');
  assert.equal(values.byKey.get('constructor').label, 'constructor');
  assert.equal(values.byKey.get('toString').active, false);
  assert.equal(values.has('valueOf'), false);
  assert.equal(JSON.stringify(input), copy);
});

test('fromWire refuses anything but an Array of {key} objects (TypeError, no value in the message)', () => {
  [null, undefined, 'x', {}, { length: 1, 0: { key: 'a' } }].forEach((bad) => {
    assert.throws(() => M.ValueList.fromWire(bad), TypeError);
  });
  [[null], ['a'], [['a']], [{}], [{ label: 'a' }], [{ key: null }], [{ key: {} }], [{ key: true }], [{ key: NaN }]]
    .forEach((bad) => {
      assert.throws(() => M.ValueList.fromWire(bad), (e) => e instanceof TypeError && !/label/.test(e.message));
    });
  assert.throws(() => M.ValueList.fromWire([{ key: 'secret<b>' }, 5]),
                (e) => e instanceof TypeError && !e.message.includes('secret'));
});

test('listValuesFromText splits like core possible_values=: CR/LF, strip, no blanks, first one kept', () => {
  const text = 'Ghent\r\n  Brussels \n\n\rGhent\n\u00a0\n\u00a0Liege\u00a0\n\ttab\tin\t\n\u0000nul\u0000';
  assert.deepEqual(M.listValuesFromText(text).map((v) => v.key),
                   ['Ghent', 'Brussels', '\u00a0Liege\u00a0', 'tab\tin', 'nul']);
  assert.deepEqual(M.listValuesFromText(''), []);
  assert.deepEqual(M.listValuesFromText(null), []);
  assert.deepEqual(M.listValuesFromText('a'), [{ key: 'a' }]);
});

test('listValuesFromText replaces a lone surrogate by U+FFFD, as the form submission does', () => {
  assert.deepEqual(M.listValuesFromText('a\ud800b\n\udc00\nok \ud83d\ude00').map((v) => v.key),
                   ['a\ufffdb', '\ufffd', 'ok \ud83d\ude00']);
});

// ---------------------------------------------------------------- State

test('State coerces keys and values to String, drops blanks and items that are not ids', () => {
  const state = new M.State(JSON.parse('{"value_dependencies":{"A":[9200001,{},null,true,1.5,-3,0,"x"," ","",' +
    '"x",[1]],"":["a"],"B":"b","C":[]},"default_value_dependencies":{"A":["x",9200001,"zz",null],"B":"b"}}'));
  assert.deepEqual([...state.links.keys()], ['A', 'B']);
  assert.deepEqual([...state.links.get('A')], ['9200001', 'x']);
  assert.deepEqual([...state.links.get('B')], ['b']);
  assert.deepEqual(state.defaultsOf('A'), ['x', '9200001']);
  assert.deepEqual(state.defaultsOf('B'), ['b']);
  assert.equal(state.isLinked('A', '9200001'), true);
  assert.equal(state.isLinked('A', 9200001), true);
  assert.equal(state.source, 'editor');
  assert.equal(state.importMeta, null);
});

test('State from a missing or malformed mapping is empty', () => {
  [undefined, null, 'x', 5, [], { value_dependencies: [] }, { value_dependencies: 'A' }].forEach((m) => {
    const state = new M.State(m);
    assert.equal(state.links.size, 0);
    assert.equal(state.defaults.size, 0);
    assert.equal(state.source, 'editor');
  });
});

test('State keeps keys unknown to the current lists (superset)', () => {
  const state = new M.State({ value_dependencies: { Gone: ['x'], A: ['a', 'zz'] } });
  assert.deepEqual([...state.links.keys()], ['Gone', 'A']);
  assert.deepEqual([...state.links.get('A')], ['a', 'zz']);
});

test('State holds only linked defaults; unlinking a child removes it from that parent\'s defaults', () => {
  const state = new M.State({ value_dependencies: { A: ['a', 'b'] }, default_value_dependencies: { A: ['b', 'c', 'a'] } });
  assert.deepEqual(state.defaultsOf('A'), ['b', 'a']);
  state.defaultsOf('A').push('zz');
  assert.deepEqual(state.defaultsOf('A'), ['b', 'a']);
  assert.equal(state.link('A', 'b', false), true);
  assert.deepEqual(state.defaultsOf('A'), ['a']);
  assert.equal(state.link('A', 'b', false), false);
  assert.equal(state.link('A', 'a', false), true);
  assert.equal(state.links.has('A'), false);
  assert.equal(state.defaults.has('A'), false);
  assert.deepEqual(state.defaultsOf('A'), []);
  assert.equal(state.link('A', 'a', true), true);
  assert.equal(state.link('A', 'a', true), false);
  assert.equal(state.link('', 'a', true), false);
  assert.equal(state.link('A', ' ', true), false);
  state.setDefaults('A', ['q', 'a', 'a']);
  assert.deepEqual(state.defaultsOf('A'), ['a']);
  state.setDefaults('A', []);
  assert.equal(state.defaults.has('A'), false);
});

test('State reads source and import from a conflict mapping; clone copies everything', () => {
  const state = new M.State({ value_dependencies: { A: ['a'] }, default_value_dependencies: { A: 'a' }, source: 'import',
                              import: { mode: 'replace', rows: 3, extra: 1 } });
  assert.equal(state.source, 'import');
  assert.deepEqual(state.importMeta, { mode: 'replace', rows: 3 });
  const copy = state.clone();
  assert.deepEqual([...copy.links.get('A')], ['a']);
  assert.deepEqual(copy.defaultsOf('A'), ['a']);
  assert.equal(copy.source, 'import');
  assert.deepEqual(copy.importMeta, { mode: 'replace', rows: 3 });
  copy.link('A', 'b', true);
  copy.setDefaults('A', ['b']);
  copy.importMeta.rows = 9;
  copy.source = 'editor';
  assert.deepEqual([...state.links.get('A')], ['a']);
  assert.deepEqual(state.defaultsOf('A'), ['a']);
  assert.deepEqual(state.importMeta, { mode: 'replace', rows: 3 });
  assert.equal(state.source, 'import');
  [{ source: 'other' }, { source: 'import', import: { mode: 'x', rows: 1 } }, { source: 'import', import: { mode: 'merge', rows: -1 } },
    { source: 'import', import: { mode: 'merge', rows: 1.5 } }, { source: 'import', import: { mode: 'merge', rows: 10000001 } }]
    .forEach((m) => {
      const s = new M.State(m);
      assert.equal(s.importMeta, null, JSON.stringify(m));
    });
  assert.equal(new M.State({ source: 'other' }).source, 'editor');
});

test('State built from a JSON.parse mapping keeps __proto__, constructor and hasOwnProperty', () => {
  const state = new M.State(JSON.parse('{"value_dependencies":{"__proto__":["__proto__"],"constructor":["b"],' +
    '"hasOwnProperty":["b"]},"default_value_dependencies":{"__proto__":"__proto__","hasOwnProperty":["b"]}}'));
  assert.deepEqual([...state.links.keys()], ['__proto__', 'constructor', 'hasOwnProperty']);
  assert.deepEqual(state.defaultsOf('__proto__'), ['__proto__']);
  assert.deepEqual(state.defaultsOf('hasOwnProperty'), ['b']);
  assert.equal(state.isLinked('toString', 'b'), false);
});

// ---------------------------------------------------------------- serialize

test('an empty state serializes as version 1, source editor and two empty objects', () => {
  const out = M.serialize(new M.State(null), list(['A']), list(['a']), { multiple: false });
  assert.equal(M.stringify(out),
               '{"version":1,"source":"editor","value_dependencies":{},"default_value_dependencies":{}}');
  assert.equal(Object.getPrototypeOf(out.value_dependencies), null);
  assert.equal(Object.getPrototypeOf(out.default_value_dependencies), null);
});

test('base is written only for a non-empty String and import only with source import', () => {
  const state = new M.State({ value_dependencies: { A: ['a'] } });
  const P = list(['A']);
  const C = list(['a']);
  assert.equal(J(M.serialize(state, P, C, { base: BASE })).base, BASE);
  [undefined, null, '', 0, 1, true, {}, [BASE]].forEach((base) => {
    assert.equal(Object.keys(J(M.serialize(state, P, C, { base }))).includes('base'), false, JSON.stringify(base));
  });
  const meta = { mode: 'merge', rows: 3 };
  assert.equal(Object.keys(J(M.serialize(state, P, C, { importMeta: meta }))).includes('import'), false);
  state.importMeta = meta;
  assert.equal(Object.keys(J(M.serialize(state, P, C, {}))).includes('import'), false);
  state.source = 'import';
  assert.deepEqual(Object.keys(J(M.serialize(state, P, C, { base: BASE }))),
                   ['version', 'source', 'import', 'base', 'value_dependencies', 'default_value_dependencies']);
  assert.deepEqual(J(M.serialize(state, P, C, {})).import, meta);
  assert.deepEqual(J(M.serialize(state, P, C, { importMeta: { mode: 'replace', rows: 0 } })).import,
                   { mode: 'replace', rows: 0 });
  state.importMeta = null;
  const bare = J(M.serialize(state, P, C, {}));
  assert.equal(bare.source, 'import');
  assert.equal(Object.keys(bare).includes('import'), false);
  state.importMeta = { mode: 'merge', rows: 2, extra: 'x' };
  assert.deepEqual(J(M.serialize(state, P, C, {})).import, { mode: 'merge', rows: 2 });
  state.source = 'nonsense';
  assert.equal(J(M.serialize(state, P, C, {})).source, 'editor');
});

test('the payload holds no null, boolean or fraction outside strings', () => {
  const state = new M.State({ value_dependencies: { A: ['a', 'b'] }, default_value_dependencies: { A: 'b' },
                              source: 'import', import: { mode: 'merge', rows: 2 } });
  const text = M.stringify(M.serialize(state, list(['A']), list(['a', 'b']), { base: BASE }));
  const outside = text.replace(/"(?:[^"\\]|\\.)*"/g, '""');
  assert.equal(/null|true|false|\d\.\d|-\d/.test(outside), false, outside);
});

test('keys follow parent order and values child order, whatever the insertion order', () => {
  const P = list(['Zeta', 'Belgium', 'France', 'Alpha']);
  const C = list(['Brussels', 'Ghent', 'Paris', 'Lyon']);
  const one = new M.State({ value_dependencies: { Alpha: ['Lyon', 'Brussels'], France: ['Lyon', 'Paris'],
                                                   Belgium: ['Ghent', 'Brussels'], Zeta: ['Ghent'] } });
  const two = new M.State(null);
  [['Belgium', 'Brussels'], ['Zeta', 'Ghent'], ['France', 'Paris'], ['Alpha', 'Brussels'], ['Belgium', 'Ghent'],
    ['Alpha', 'Lyon'], ['France', 'Lyon']].forEach(([p, c]) => two.link(p, c, true));
  const a = M.stringify(M.serialize(one, P, C, {}));
  assert.equal(a, M.stringify(M.serialize(two, P, C, {})));
  assert.equal(a, '{"version":1,"source":"editor","value_dependencies":{"Zeta":["Ghent"],"Belgium":["Brussels","Ghent"],' +
                  '"France":["Paris","Lyon"],"Alpha":["Brussels","Lyon"]},"default_value_dependencies":{}}');
});

test('array-index-like keys come first in ascending numeric order in the JSON text (engine rule)', () => {
  const state = new M.State({ value_dependencies: { Belgium: ['x'], 10: ['x'], 2: ['x'] } });
  const text = M.stringify(M.serialize(state, list(['Belgium', '10', '2']), list(['x']), {}));
  assert.equal(text.indexOf('"2"') < text.indexOf('"10"'), true);
  assert.equal(text.indexOf('"10"') < text.indexOf('"Belgium"'), true);
});

test('orphans stay in the state, are not posted and come back when the values reappear', () => {
  const state = new M.State({ value_dependencies: { France: ['Paris', 'Atlantis'], Gone: ['Paris'] },
                              default_value_dependencies: { France: 'Atlantis', Gone: 'Paris' } });
  const P = list(['France']);
  const out = J(M.serialize(state, P, list(['Paris']), { multiple: false }));
  assert.deepEqual(out.value_dependencies, { France: ['Paris'] });
  assert.deepEqual(out.default_value_dependencies, {});
  assert.deepEqual([...state.links.get('France')], ['Paris', 'Atlantis']);
  assert.deepEqual([...state.links.get('Gone')], ['Paris']);
  assert.deepEqual(state.defaultsOf('France'), ['Atlantis']);
  const back = J(M.serialize(state, list(['France', 'Gone']), list(['Atlantis', 'Paris']), { multiple: false }));
  assert.deepEqual(back.value_dependencies, { France: ['Atlantis', 'Paris'], Gone: ['Paris'] });
  assert.deepEqual(back.default_value_dependencies, { France: 'Atlantis', Gone: 'Paris' });
});

test('default shape: a String (first in child order) unless multiple === true; unlinked defaults dropped', () => {
  const C = list(['a1', 'a2', 'b1']);
  const P = list(['A', 'B', 'N']);
  const mapping = { value_dependencies: { A: ['a2', 'a1'], B: ['b1'], N: [] },
                    default_value_dependencies: { A: ['a2', 'a1'], B: ['b1'], N: ['a1'] } };
  const single = J(M.serialize(new M.State(mapping), P, C, { multiple: false }));
  assert.deepEqual(single.default_value_dependencies, { A: 'a1', B: 'b1' });
  const multiple = J(M.serialize(new M.State(mapping), P, C, { multiple: true }));
  assert.deepEqual(multiple.default_value_dependencies, { A: ['a1', 'a2'], B: ['b1'] });
  ['1', 1, 'true', {}].forEach((m) => {
    assert.deepEqual(J(M.serialize(new M.State(mapping), P, C, { multiple: m })).default_value_dependencies,
                     { A: 'a1', B: 'b1' }, String(m));
  });
  assert.deepEqual(J(M.serialize(new M.State(mapping), P, C)).default_value_dependencies, { A: 'a1', B: 'b1' });
  const state = new M.State(mapping);
  state.defaults.set('A', ['zz', 'a2']);
  state.defaults.set('Z', ['a1']);
  assert.deepEqual(J(M.serialize(state, P, C, { multiple: true })).default_value_dependencies, { A: ['a2'], B: ['b1'] });
  state.link('B', 'b1', false);
  const out = J(M.serialize(state, P, C, { multiple: true }));
  assert.deepEqual(Object.keys(out.value_dependencies), ['A']);
  assert.deepEqual(Object.keys(out.default_value_dependencies), ['A']);
});

test('parents null keeps every state parent key in state order and still intersects the children', () => {
  const state = new M.State(JSON.parse('{"value_dependencies":{"Gone":["b1","zz"],"__proto__":["a1"],' +
    '"Belgium":["zz"],"France":["a1","b1"]},"default_value_dependencies":{"Gone":"zz","France":["b1"]}}'));
  state.links.set(' ', new Set(['a1']));
  const text = M.stringify(M.serialize(state, null, list(['a1', 'b1']), { multiple: false }));
  assert.equal(text, '{"version":1,"source":"editor","value_dependencies":{"Gone":["b1"],"__proto__":["a1"],' +
                     '"France":["a1","b1"]},"default_value_dependencies":{"France":"b1"}}');
});

test('enumeration children are written as JSON integers when canonical and safe; list values never', () => {
  const keys = ['9200001', '9007199254740991', '9007199254740993', '0', '01', '+1', '1e3', ' 1', '-1',
    '12345678901234567890', '1.0', 'x'];
  const state = new M.State({ value_dependencies: { 9200009: keys, P: keys }, default_value_dependencies: { P: keys } });
  const P = list(['9200009', 'P']);
  const C = list(keys);
  const enumText = M.stringify(M.serialize(state, P, C, { kind: 'enumeration', multiple: true }));
  const expected = '[9200001,9007199254740991,"9007199254740993","0","01","+1","1e3"," 1","-1",' +
                   '"12345678901234567890","1.0","x"]';
  assert.equal(enumText, '{"version":1,"source":"editor","value_dependencies":{"9200009":' + expected + ',"P":' +
                         expected + '},"default_value_dependencies":{"P":' + expected + '}}');
  const single = J(M.serialize(state, P, C, { kind: 'enumeration', multiple: false }));
  assert.equal(single.default_value_dependencies.P, 9200001);
  const listText = M.stringify(M.serialize(state, P, C, { kind: 'list', multiple: true }));
  assert.equal(listText.includes('[9200001'), false);
  assert.equal(listText.includes('["9200001","9007199254740991"'), true);
  assert.equal(M.stringify(M.serialize(state, P, C, { multiple: true })), listText);
});

test('serialize copies keys byte for byte (no trim, no normalization, no labels)', () => {
  const nfc = '\u00e9';
  const nfd = 'e\u0301';
  const state = new M.State(null);
  [[nfc, 'a b'], [nfd, ' x'], ['9200001', 'a b']].forEach(([p, c]) => state.link(p, c, true));
  const P = M.ValueList.fromWire([{ key: nfc }, { key: nfd }, { key: '9200001', label: 'Hidden label' }]);
  const C = M.ValueList.fromWire([{ key: 'a b', label: 'Label A' }, { key: ' x', label: 'Label X' }]);
  const text = M.stringify(M.serialize(state, P, C, {}));
  assert.deepEqual(Object.keys(JSON.parse(text).value_dependencies), ['9200001', nfc, nfd]);
  assert.equal(text.includes('"a b"') && text.includes('" x"'), true);
  assert.equal(/Label|Hidden/.test(text), false);
});

test('links and defaults to inactive values are posted like active ones', () => {
  const P = M.ValueList.fromWire([{ key: '9200001', label: 'N' }, { key: '9200002', label: 'Old', active: false }]);
  const C = M.ValueList.fromWire([{ key: '9200003', label: 'a' }, { key: '9200005', label: 'r', active: false }]);
  const state = new M.State({ value_dependencies: { 9200002: ['9200005'], 9200001: ['9200005', '9200003'] },
                              default_value_dependencies: { 9200002: '9200005' } });
  const out = J(M.serialize(state, P, C, { kind: 'enumeration', multiple: true }));
  assert.deepEqual(out.value_dependencies, { 9200001: [9200003, 9200005], 9200002: [9200005] });
  assert.deepEqual(out.default_value_dependencies, { 9200002: [9200005] });
});

test('__proto__, constructor, toString, hasOwnProperty, toJSON and the like survive as parent, child and default', () => {
  const names = ['__proto__', 'constructor', 'toString', 'hasOwnProperty', 'toJSON', 'valueOf', '__defineGetter__',
    'prototype'];
  const kids = ['__proto__', 'constructor', 'b', 'toJSON', 'prototype', '__defineGetter__'];
  const raw = '{"value_dependencies":{"__proto__":["__proto__","toJSON"],"constructor":["b"],"hasOwnProperty":["b"],' +
              '"toString":["b"],"toJSON":["b"],"valueOf":["constructor"],"__defineGetter__":["prototype"],' +
              '"prototype":["__defineGetter__"]},"default_value_dependencies":{"__proto__":"__proto__","toJSON":"b",' +
              '"valueOf":"constructor","prototype":"__defineGetter__"}}';
  const state = new M.State(JSON.parse(raw));
  const out = M.serialize(state, list(names), list(kids), { multiple: false });
  const text = M.stringify(out);
  assert.equal(text, '{"version":1,"source":"editor","value_dependencies":{"__proto__":["__proto__","toJSON"],' +
                     '"constructor":["b"],"toString":["b"],"hasOwnProperty":["b"],"toJSON":["b"],' +
                     '"valueOf":["constructor"],"__defineGetter__":["prototype"],"prototype":["__defineGetter__"]},' +
                     '"default_value_dependencies":{"__proto__":"__proto__","toJSON":"b","valueOf":"constructor",' +
                     '"prototype":"__defineGetter__"}}');
  const back = JSON.parse(text);
  assert.deepEqual(Object.keys(back.value_dependencies), names);
  assert.equal(Object.prototype.hasOwnProperty.call(back.value_dependencies, '__proto__'), true);
  assert.equal(Array.isArray(back.value_dependencies.__proto__), true);
  assert.equal(M.stringify(M.serialize(new M.State(back), list(names), list(kids), { multiple: false })), text);
});

test('serialize changes neither the state nor the lists and returns fresh arrays', () => {
  const state = new M.State({ value_dependencies: { France: ['Paris', 'Gone'], Gone: ['Paris'] },
                              default_value_dependencies: { France: ['Paris'] }, source: 'import',
                              import: { mode: 'merge', rows: 1 } });
  const P = list(['France']);
  const C = list(['Lyon', 'Paris']);
  const before = JSON.stringify([[...state.links].map(([k, s]) => [k, [...s]]), [...state.defaults], state.source,
                                 state.importMeta, P.items, C.items]);
  const first = M.serialize(state, P, C, { multiple: true, base: BASE });
  const text = M.stringify(first);
  first.value_dependencies.France.push('x');
  first.default_value_dependencies.France.push('y');
  first.import.rows = 99;
  assert.equal(M.stringify(M.serialize(state, P, C, { multiple: true, base: BASE })), text);
  assert.equal(JSON.stringify([[...state.links].map(([k, s]) => [k, [...s]]), [...state.defaults], state.source,
                               state.importMeta, P.items, C.items]), before);
});

test('serialize refuses a state, parents or children of the wrong type', () => {
  const C = list(['a']);
  assert.throws(() => M.serialize({ links: new Map(), defaults: new Map() }, null, C, {}), TypeError);
  assert.throws(() => M.serialize(new M.State(null), null, null, {}), TypeError);
  assert.throws(() => M.serialize(new M.State(null), null, [{ key: 'a' }], {}), TypeError);
  assert.throws(() => M.serialize(new M.State(null), [], C, {}), TypeError);
  assert.throws(() => M.serialize(new M.State(null), undefined, C, {}), TypeError);
});

test('no prototype is changed and no object is polluted by the model', () => {
  const protos = [Object.prototype, Array.prototype, String.prototype, Map.prototype, Set.prototype, Function.prototype];
  const snapshot = () => protos.map((p) => Object.getOwnPropertyNames(p).sort().map((n) => {
    const d = Object.getOwnPropertyDescriptor(p, n);
    return [n, d.value, d.get, d.set, d.writable, d.enumerable];
  }));
  const before = snapshot();
  delete require.cache[require.resolve(MODEL_PATH)];
  const fresh = require(MODEL_PATH);
  const raw = '{"value_dependencies":{"__proto__":["polluted"],"constructor":["prototype"],"prototype":["x"]},' +
              '"default_value_dependencies":{"__proto__":["polluted"]}}';
  const values = fresh.ValueList.fromWire(JSON.parse('[{"key":"__proto__"},{"key":"constructor"},{"key":"prototype"}]'));
  const children = fresh.ValueList.fromWire(JSON.parse('[{"key":"polluted"},{"key":"prototype"},{"key":"x"}]'));
  const state = new fresh.State(JSON.parse(raw));
  const text = fresh.stringify(fresh.serialize(state, values, children, { multiple: true }));
  new fresh.State(JSON.parse(text));
  fresh.serialize(state.clone(), null, children, { multiple: false });
  assert.deepEqual(snapshot(), before);
  assert.equal({}.polluted, undefined);
  assert.equal(Object.getPrototypeOf({}), Object.prototype);
  assert.equal(typeof Object.prototype.prototype, 'undefined');
});

// ---------------------------------------------------------------- counters

test('counters: linked per parent, parents without links, unlinked children, orphans', () => {
  const P = list(['A', 'B', 'C']);
  const C = list(['a1', 'a2', 'b1']);
  const state = new M.State({ value_dependencies: { A: ['a1', 'zz'], Gone: ['a1'], B: ['zz'] } });
  assert.equal(state.linkedCount('A', C), 1);
  assert.equal(state.linkedCount('C', C), 0);
  assert.equal(state.parentsWithoutLinks(P, C), 2);
  assert.deepEqual(state.unlinkedChildren(P, C).map((i) => i.key), ['a2', 'b1']);
  assert.equal(state.orphanCount(P, C), 3);
  assert.deepEqual([...state.childLinkCounts(P, C)], [['a1', 1]]);
  assert.equal(state.orphanCount(null, C), 2);
  assert.equal(state.parentsWithoutLinks(null, C), 0);
  assert.deepEqual([...state.childLinkCounts(null, C)], [['a1', 2]]);
  assert.deepEqual(state.unlinkedChildren(null, C).map((i) => i.key), ['a2', 'b1']);
  // A parent change drops the links the new parent's values do not cover.
  assert.equal(state.orphanCount(list(['B']), C), 4);
});

test('conflictCounts compares link pairs on the current lists only', () => {
  const P = list(['A', 'B', 'C']);
  const C = list(['a1', 'a2', 'b1']);
  const mine = new M.State({ value_dependencies: { A: ['a1', 'a2'], B: ['b1'], Gone: ['a1'], C: ['zz'] } });
  const current = new M.State({ value_dependencies: { A: ['a1'], C: ['b1'] } });
  assert.deepEqual(M.conflictCounts(mine, current, P, C), { onlyMine: 2, onlyCurrent: 1 });
  assert.deepEqual(M.conflictCounts(current, current, P, C), { onlyMine: 0, onlyCurrent: 0 });
  // parents null (values not loaded): Gone counts as current.
  assert.deepEqual(M.conflictCounts(mine, current, null, C), { onlyMine: 3, onlyCurrent: 1 });
});

test('utf8Bytes counts UTF-8 bytes as TextEncoder does', () => {
  ['', 'abc', '\u00e9', '\u20ac', '\ud83d\ude00', 'a\ud800b', '\udc00', '\u2028'].forEach((s) => {
    assert.equal(M.utf8Bytes(s), new TextEncoder().encode(s).length, JSON.stringify(s));
  });
});

// ---------------------------------------------------------------- scale (G6)

test('scale: serialize 27 x 5,570 under 500 ms (S1, S1-full single and multiple, S2), shared generator', () => {
  const parentKeys = L.names(27, { prefix: 'P' });
  const childKeys = L.names(5570, { trickyEvery: 97 });
  const P = list(parentKeys);
  const C = list(childKeys);
  const run = (state, parents, children, opts) => {
    const text = M.stringify(M.serialize(state, parents, children, opts));
    return text;
  };
  const report = [];

  const s1 = new M.State({ value_dependencies: L.partition(parentKeys, childKeys) });
  const [s1Ms, s1Text] = warmMinimum(() => run(s1, P, C, { multiple: false, base: BASE }));
  const s1Out = JSON.parse(s1Text);
  assert.equal(Object.keys(s1Out.value_dependencies).length, 27);
  assert.equal(Object.values(s1Out.value_dependencies).reduce((n, v) => n + v.length, 0), 5570);
  assert.equal(s1Out.value_dependencies[parentKeys[0]][0], childKeys[0]);
  assert.equal(s1Out.value_dependencies[parentKeys[26]][0], childKeys[5569]);
  report.push(`s1_ms=${s1Ms.toFixed(1)} s1_bytes=${M.utf8Bytes(s1Text)}`);

  const full = new M.State(null);
  parentKeys.forEach((pk) => childKeys.forEach((ck) => full.link(pk, ck, true)));
  parentKeys.forEach((pk, k) => full.setDefaults(pk, [childKeys[k * 7]]));
  const [fullMs, fullText] = warmMinimum(() => run(full, P, C, { multiple: false, base: BASE }));
  const fullOut = JSON.parse(fullText);
  assert.equal(Object.values(fullOut.value_dependencies).reduce((n, v) => n + v.length, 0), 150390);
  parentKeys.forEach((pk, k) => {
    assert.equal(fullOut.value_dependencies[pk][0], childKeys[0]);
    assert.equal(fullOut.value_dependencies[pk][5569], childKeys[5569]);
    assert.equal(fullOut.default_value_dependencies[pk], childKeys[k * 7]);
  });
  const fullBytes = M.utf8Bytes(fullText);
  assert.equal(fullBytes, Buffer.byteLength(fullText, 'utf8'));
  assert.ok(fullBytes <= 4194304, `S1-full is ${fullBytes} bytes`);
  report.push(`full_ms=${fullMs.toFixed(1)} full_bytes=${fullBytes}`);

  const all = full.clone();
  parentKeys.forEach((pk) => all.setDefaults(pk, childKeys.slice().reverse()));
  const [allMs, allText] = warmMinimum(() => run(all, P, C, { multiple: true, base: BASE }));
  const allOut = JSON.parse(allText);
  assert.equal(allOut.default_value_dependencies[parentKeys[3]].length, 5570);
  assert.equal(allOut.default_value_dependencies[parentKeys[3]][0], childKeys[0]);
  report.push(`full_all_defaults_ms=${allMs.toFixed(1)} full_all_defaults_bytes=${M.utf8Bytes(allText)}`);

  const parentIds = parentKeys.map((_, k) => String(9200001 + k));
  const childIds = childKeys.map((_, k) => String(9200028 + k));
  const s2 = new M.State({ value_dependencies: L.partition(parentIds, childIds) });
  const [s2Ms, s2Text] = warmMinimum(() => run(s2, list(parentIds), list(childIds), { kind: 'enumeration', multiple: false }));
  const s2Out = JSON.parse(s2Text);
  assert.equal(s2Out.value_dependencies['9200001'][0], 9200028);
  assert.equal(Object.values(s2Out.value_dependencies).reduce((n, v) => n + v.length, 0), 5570);
  report.push(`s2_ms=${s2Ms.toFixed(1)} s2_bytes=${M.utf8Bytes(s2Text)}`);

  [s1Ms, fullMs, allMs, s2Ms].forEach((ms) => assert.ok(ms < 500, `serialize took ${ms} ms`));
  console.log(`# perf ${report.join(' ')}`);
});
