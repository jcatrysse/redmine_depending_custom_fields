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

// WP-26: the import and export functions and strip join the API list.
test('loads under CommonJS without a DOM and exports the model API', () => {
  assert.equal(typeof globalThis.window, 'undefined');
  assert.equal(typeof globalThis.DcfDependencyEditorModel, 'undefined');
  ['fold', 'tokens', 'matchesTokens', 'isBlank', 'isDigest', 'listValuesFromText', 'State', 'serialize',
    'stringify', 'utf8Bytes', 'conflictCounts', 'strip', 'parseRecords', 'planImport', 'applyImport',
    'buildCsv'].forEach((name) => assert.equal(typeof M[name], 'function', name));
  assert.equal(typeof M.ValueList.prototype.match, 'function');
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

// ---------------------------------------------------------------- WP-26 import and export
// Editor design 6.1 to 6.7, UD-18, UD-19, QA-11, SP-13, SP-14. Cells are
// [line, cells] pairs, errors [line, code] pairs unless the test needs more.

const recs = (parsed) => parsed.records.map((r) => [r.line, r.cells]);
const codes = (list) => list.map((e) => [e.line, e.code]);
const COUNTRY = list(['Belgium', 'France', 'Germany']);
const CITY = list(['Antwerp', 'Brussels', 'Paris', 'Lyon']);
const NAMES = { parentName: 'Country', childName: 'City' };
const plan = (text, state, P, C, opts) => M.planImport(text, state || new M.State(null), P || COUNTRY, C || CITY,
  Object.assign({ separator: ';' }, NAMES, opts || {}));
const snapshotState = (state) => JSON.stringify([[...state.links].map(([k, s]) => [k, [...s]]), [...state.defaults],
  state.source, state.importMeta]);

test('strip is Ruby strip (NUL and ASCII white space) and linear; listValuesFromText keeps its behaviour', () => {
  assert.equal(M.strip(' \t\u0000a b\r\n\v\f '), 'a b');
  assert.equal(M.strip('\u00a0a\u3000'), '\u00a0a\u3000');
  assert.equal(M.strip(''), '');
  assert.deepEqual(M.listValuesFromText(' A \n\u0000B\u0000\r\n\u00a0C\u00a0\n\n'), [{ key: 'A' }, { key: 'B' }, { key: '\u00a0C\u00a0' }]);
  const big = 'a' + ' '.repeat(1000000) + 'b';
  const [ms1, keys] = elapsed(() => M.listValuesFromText(big));
  assert.deepEqual(keys, [{ key: big }]);
  const [ms2, parsed] = elapsed(() => M.parseRecords('x;' + big, ';'));
  assert.deepEqual(recs(parsed), [[1, ['x', big]]]);
  console.log(`# perf strip_list_ms=${ms1.toFixed(1)} strip_parse_ms=${ms2.toFixed(1)}`);
  assert.ok(ms1 < 1000 && ms2 < 1000, `${ms1} ${ms2}`);
});

test('parseRecords: RFC 4180 cells, quotes and start lines', () => {
  const cases = [
    ['"a;b";c', [[1, ['a;b', 'c']]]],
    ['"say ""hi""";x', [[1, ['say "hi"', 'x']]]],
    ['say "hi";x', [[1, ['say "hi"', 'x']]]],
    ['"a""";x', [[1, ['a"', 'x']]]],
    ['"multi\r\nline";c\r\nd;e', [[1, ['multi\r\nline', 'c']], [3, ['d', 'e']]]],
    ['a;b\rc;d\ne;f\r\ng;h', [[1, ['a', 'b']], [2, ['c', 'd']], [3, ['e', 'f']], [4, ['g', 'h']]]],
    ['a;b\n\rc;d', [[1, ['a', 'b']], [3, ['c', 'd']]]],
    ['\ufeffa;b', [[1, ['a', 'b']]]],
    ['\ufeff\ufeffa;b', [[1, ['\ufeffa', 'b']]]],
    ['  "a"  ;b', [[1, ['a', 'b']]]],
    ['\t"a";b', [[1, ['a', 'b']]]],
    [' a ; b ', [[1, ['a', 'b']]]],
    ['" a ";b', [[1, [' a ', 'b']]]],
    ['\n\na;b\n\n', [[3, ['a', 'b']]]]
  ];
  cases.forEach(([text, expected]) => {
    const parsed = M.parseRecords(text, ';');
    assert.deepEqual(recs(parsed), expected, JSON.stringify(text));
    assert.deepEqual(parsed.errors, [], JSON.stringify(text));
    assert.equal(parsed.separator, ';');
  });
  assert.deepEqual(recs(M.parseRecords('a,"b\nc"\nd,e', ',')), [[1, ['a', 'b\nc']], [3, ['d', 'e']]]);
  assert.deepEqual(recs(M.parseRecords('a\t"b\tc"\n', '\t')), [[1, ['a', 'b\tc']]]);
});

test('parseRecords: unterminated and bad quotes, recovery in one pass', () => {
  let parsed = M.parseRecords('x,y\na,"b', ',');
  assert.deepEqual(recs(parsed), [[1, ['x', 'y']]]);
  assert.deepEqual(codes(parsed.errors), [[2, 'unterminated_quote']]);
  parsed = M.parseRecords('"a"x,b\nc,d', ',');
  assert.deepEqual(codes(parsed.errors), [[1, 'bad_quote']]);
  assert.deepEqual(recs(parsed), [[2, ['c', 'd']]]);
  assert.deepEqual([parsed.first.cells, parsed.first.code], [['a'], 'bad_quote'], 'the bad-quoted cell is kept for the header warning');
  parsed = M.parseRecords('"open\n' + 'a;b\n'.repeat(1000), ';');
  assert.deepEqual(codes(parsed.errors), [[1, 'unterminated_quote']]);
  assert.deepEqual(parsed.records, []);
  parsed = M.parseRecords('"a"x;"b\nc";d', ';');
  assert.deepEqual(codes(parsed.errors), [[1, 'bad_quote']]);
  assert.deepEqual(recs(parsed), [[2, ['c"', 'd']]]);
  parsed = M.parseRecords('"a\nb"x;c\nd;e', ';');
  assert.deepEqual(codes(parsed.errors), [[2, 'bad_quote']]);
  assert.deepEqual(recs(parsed), [[3, ['d', 'e']]]);
  const [ms, many] = elapsed(() => M.parseRecords('"a"x;b\n'.repeat(100000), ';'));
  assert.equal(many.errors.length, 200);
  assert.equal(many.errorCount, 100000);
  assert.deepEqual(codes(many.errors.slice(0, 2)), [[1, 'bad_quote'], [2, 'bad_quote']]);
  console.log(`# perf bad_quote_100k_ms=${ms.toFixed(1)}`);
  assert.ok(ms < 2000, `${ms} ms`);
});

test('parseRecords: trailing empty cells, blank lines, column counts and blank values', () => {
  const one = (text) => {
    const parsed = M.parseRecords(text, ';');
    return [recs(parsed), parsed.errors.map((e) => [e.line, e.code, e.count])];
  };
  assert.deepEqual(one('a;b;;'), [[[1, ['a', 'b']]], []]);
  assert.deepEqual(one('a;;b'), [[], [[1, 'columns', 3]]]);
  assert.deepEqual(one(';a;b'), [[], [[1, 'columns', 3]]]);
  assert.deepEqual(one('a;""'), [[], [[1, 'columns', 1]]]);
  assert.deepEqual(one('a;b;c'), [[], [[1, 'columns', 3]]]);
  assert.deepEqual(one('x'), [[], [[1, 'columns', 1]]]);
  assert.deepEqual(one(';;\n  ;  \n\t'), [[], []]);
  assert.equal(M.parseRecords(';;\n  ;  ', ';').lines, 0);
  assert.deepEqual(one('"\u3000";b'), [[], [[1, 'blank_value', undefined]]]);
  assert.deepEqual(one(' ;b'), [[], [[1, 'blank_value', undefined]]]);
  assert.deepEqual(one('"";b'), [[], [[1, 'blank_value', undefined]]]);
  assert.equal(M.parseRecords('a;b\nc;d;e\n\nf;g', ';').lines, 3);
});

test('parseRecords: separator auto detection on the first 64 KB and 20 records, tie order tab ; ,', () => {
  const sep = (text, fallback) => M.parseRecords(text, 'auto', fallback === undefined ? {} : { fallback }).separator;
  assert.equal(sep('a\tsemi;colon\nd\tcomma, value'), '\t');
  assert.equal(sep('"a;b",c\n'.repeat(20)), ',');
  assert.equal(sep('a;b,c'), ';');
  assert.equal(sep('x\ty;z,w'), '\t');
  assert.equal(sep('"a;b";"c;d"\n"e;f";"g;h"'), ';');
  assert.equal(sep('Paris,"Nord;Ost"\nLyon,"Sud;Est"'), ',', 'a quote inside an unquoted cell breaks the tie');
  // Review fix: such a record still scores (design 6.1), the quote only breaks ties.
  assert.equal(sep('x" a\tb\n'.repeat(3)), '\t');
  assert.equal(sep('x" a;b\n'.repeat(3), ','), ';');
  assert.equal(sep('12" pipe\tPlumbing\n', ','), '\t');
  assert.equal(sep('12" pipe\tPlumbing\n', ';'), '\t');
  const inch = M.parseRecords('3/4" valve;Plumbing\n3/4" valve;Heating', 'auto', { fallback: ',' });
  assert.deepEqual([inch.separator, inch.errors, recs(inch)],
    [';', [], [[1, ['3/4" valve', 'Plumbing']], [2, ['3/4" valve', 'Heating']]]]);
  assert.equal(sep('abc\ndef'), ',');
  assert.equal(sep('abc\ndef', ';'), ';');
  assert.equal(sep('abc\ndef', '.'), ',');
  const long = M.parseRecords('"' + 'x'.repeat(100000) + '",y\na,b', 'auto');
  assert.equal(long.separator, ',');
  assert.deepEqual(long.errors, []);
  assert.deepEqual(long.records.map((r) => r.line), [1, 2]);
  // Only the first 20 records count (review round 2: each input flips one
  // record above or below the limit).
  assert.equal(sep('c;d\n'.repeat(10) + 'a,b\n'.repeat(11)), ';', 'the 21st record is not read');
  assert.equal(sep('a,b\n'.repeat(10) + 'c;d\n'.repeat(10) + 'e,f\n'), ';', 'the 20th record is read');
  // Only the first 65,536 characters count: a record ending exactly at the
  // boundary is read, one ending a character later is cut.
  assert.equal(sep('p,q\na;b\n' + 'x'.repeat(65536 - 11) + ',y\ntail\n'), ',', 'ends at character 65,536');
  assert.equal(sep('p;q\na,b\n' + 'x'.repeat(65537 - 11) + ',y\ntail\n'), ';', 'ends at character 65,537');
  assert.equal(M.parseRecords('a;b', ';').separator, ';');
  assert.equal(M.parseRecords('a\tb', '\t').separator, '\t');
});

test('parseRecords: 10,000,000 characters and 200,000 records caps, 200 kept errors', () => {
  let parsed = M.parseRecords('x'.repeat(10000001), ';');
  assert.deepEqual(parsed.errors, [{ line: null, code: 'too_large', max: 10000000 }]);
  assert.deepEqual(parsed.records, []);
  parsed = M.parseRecords('\ufeff' + 'x'.repeat(10000000), ';');
  assert.deepEqual(parsed.errors, [{ line: null, code: 'too_large', max: 10000000 }], 'the BOM counts');
  parsed = M.parseRecords('"' + 'x'.repeat(9999998) + '"', ';');
  assert.deepEqual(parsed.errors.map((e) => [e.code, e.count]), [['columns', 1]]);
  parsed = M.parseRecords('P1;C1\n'.repeat(200000), ';');
  assert.equal(parsed.records.length, 200000);
  assert.deepEqual(parsed.errors, []);
  parsed = M.parseRecords('P1;C1\n'.repeat(200001), ';');
  assert.deepEqual(parsed.errors, [{ line: null, code: 'too_many_lines', max: 200000 }]);
  assert.equal(parsed.errorCount, 1);
  assert.deepEqual(parsed.records, []);
  parsed = M.parseRecords('a;b;c\n'.repeat(250), ';');
  assert.equal(parsed.errors.length, 200);
  assert.equal(parsed.errorCount, 250);
  assert.equal(parsed.errors[199].line, 200);
});

test('parseRecords is linear on adversarial input of 10,000,000 characters (G6)', () => {
  const shapes = [
    ['quoted_cell', '"' + 'x'.repeat(9999998) + '"', (p) => assert.equal(p.errors[0].code, 'columns')],
    ['escaped_quotes', '"' + '""'.repeat(4999999) + '"', (p) => assert.equal(p.errors[0].count, 1)],
    ['newlines', '\n'.repeat(10000000), (p) => assert.deepEqual([p.records.length, p.errors.length, p.lines], [0, 0, 0])],
    ['separators', ';'.repeat(10000000), (p) => assert.deepEqual([p.records.length, p.errors.length], [0, 0])],
    ['filled_separators', 'x' + ';'.repeat(9999998) + 'y', (p) => assert.deepEqual(p.errors.map((e) => e.count), [9999999])],
    ['quote_newline', '"\n'.repeat(5000000), (p) => assert.equal(p.errors[0].code, 'too_many_lines')]
  ];
  const report = [];
  shapes.forEach(([name, text, check]) => {
    const [ms, parsed] = elapsed(() => M.parseRecords(text, ';'));
    check(parsed);
    report.push(`${name}_ms=${ms.toFixed(1)}`);
    // single cold runs: 10x the 555 ms measured at most (G6); a quadratic parser takes minutes
    assert.ok(ms < 6000, `${name}: ${ms} ms`);
  });
  console.log(`# perf parse ${report.join(' ')}`);
});

test('ValueList.match: exact, exact NFC, unique NFC lowercase; accents and special letters significant', () => {
  const L1 = list(['Paris', 'PARIS', 'Montr\u00e9al', 'Caf\u00e9', 'Stra\u00dfe', 'Ghent']);
  const keys = (cell) => L1.match(cell).map((i) => i.key);
  assert.deepEqual(keys('Paris'), ['Paris']);
  assert.deepEqual(keys('PARIS'), ['PARIS']);
  assert.deepEqual(keys('paris'), ['Paris', 'PARIS']);
  assert.deepEqual(keys('Montre\u0301al'), ['Montr\u00e9al']);
  assert.deepEqual(keys('MONTR\u00c9AL'), ['Montr\u00e9al']);
  assert.deepEqual(keys('MONTRE\u0301AL'), ['Montr\u00e9al']);
  assert.deepEqual(keys('cafe'), []);
  assert.deepEqual(keys('STRASSE'), []);
  assert.deepEqual(keys('stra\u00dfe'), ['Stra\u00dfe']);
  assert.deepEqual(keys('Gh\u00e8nt'), []);
  const twins = list(['\u00e9', 'e\u0301']);
  assert.deepEqual(twins.match('\u00e9').map((i) => i.key), ['\u00e9']);
  assert.deepEqual(twins.match('e\u0301').map((i) => i.key), ['e\u0301']);
  assert.deepEqual(twins.match('\u00c9').map((i) => i.key), ['\u00e9', 'e\u0301']);
  const plain = list(['a']);
  ['constructor', '__proto__', 'toString', 'hasOwnProperty', 'valueOf'].forEach((n) => assert.deepEqual(plain.match(n), [], n));
  assert.deepEqual(list(['__proto__', 'constructor']).match('constructor').map((i) => i.key), ['constructor']);
  const enums = M.ValueList.fromWire([{ key: '1', label: 'A' }, { key: '2', label: 'A', active: false }, { key: '3', label: 'B' }]);
  assert.deepEqual(enums.match('A').map((i) => i.key), ['1', '2']);
  assert.deepEqual(enums.match('b').map((i) => i.key), ['3']);
  assert.deepEqual(enums.match('3'), []);
  // the lookup lives on the list, not on its items (serialize compares the items)
  assert.equal(JSON.stringify(enums.items), JSON.stringify(M.ValueList.fromWire([{ key: '1', label: 'A' },
    { key: '2', label: 'A', active: false }, { key: '3', label: 'B' }]).items));
});

const REGIONS = M.ValueList.fromWire([{ key: '9200001', label: 'North' }, { key: '9200002', label: 'South' },
  { key: '9200003', label: 'Old', active: false }]);
const PRODUCTS = (extra) => M.ValueList.fromWire([{ key: '9200004', label: 'Alpha' }, { key: '9200005', label: 'Beta' },
  { key: '9200006', label: 'Gamma' }, { key: '9200007', label: 'Retired', active: false }].concat(extra || []));

test('planImport: enumerations by name only, inactive included, duplicates ambiguous, no #id syntax (UD-19)', () => {
  const C = PRODUCTS([{ key: '9200008', label: 'Alpha', active: false }, { key: '9200009', label: 'Beta' },
    { key: '9200010', label: '12' }, { key: '12', label: 'Twelve' }]);
  const opts = { kind: 'enumeration', parentName: 'Region', childName: 'Product', header: 'no' };
  const run = (text, extra) => plan(text, null, REGIONS, C, Object.assign({}, opts, extra || {}));
  let p = run('North;Alpha');
  assert.deepEqual(p.errors, [{ line: 1, code: 'ambiguous_child', value: 'Alpha' }]);
  assert.equal(p.ok, false);
  p = run('North;beta');
  assert.deepEqual(codes(p.errors), [[1, 'ambiguous_child']]);
  p = run('North;Retired\nOld;Gamma');
  assert.deepEqual(p.errors, []);
  assert.deepEqual(p.warnings, [{ line: 1, code: 'inactive', value: 'Retired' }, { line: 2, code: 'inactive', value: 'Old' }]);
  assert.deepEqual(p.pairs.map((x) => [x.parent, x.child]), [['9200001', '9200007'], ['9200003', '9200006']]);
  assert.equal(p.ok, true);
  p = run('North;#9200004\nNorth;9200004\nnorth;GAMMA');
  assert.deepEqual(p.errors, [{ line: 1, code: 'unknown_child', value: '#9200004' },
    { line: 2, code: 'unknown_child', value: '9200004' }]);
  assert.deepEqual(Object.keys(p.errors[0]).sort(), ['code', 'line', 'value']);
  p = run('North;12');
  assert.deepEqual(p.pairs.map((x) => x.child), ['9200010']);
  p = run('North;Zeta', { addMissing: true });
  assert.deepEqual(codes(p.errors), [[1, 'unknown_child']]);
  assert.deepEqual(p.newValues, []);
  // the same rule on the parent side: an active and an inactive North are ambiguous
  const twins = M.ValueList.fromWire([{ key: '9200001', label: 'North' }, { key: '9200011', label: 'North', active: false },
    { key: '9200002', label: 'South' }]);
  p = plan('North;Alpha\nnorth;Alpha\nSouth;Alpha', null, twins, PRODUCTS(), opts);
  assert.deepEqual(p.errors, [{ line: 1, code: 'ambiguous_parent', value: 'North' },
    { line: 2, code: 'ambiguous_parent', value: 'north' }]);
  assert.equal(p.ok, false);
  assert.deepEqual(p.pairs.map((x) => [x.parent, x.child]), [['9200002', '9200004']]);
});

test('planImport: header auto, yes and no; the skipped cells are reported', () => {
  let p = plan('Country;City\nBelgium;Paris', null, null, null, { header: 'auto' });
  assert.deepEqual([p.headerSkipped, p.headerCells, p.pairs.length, p.lines, p.errors], [true, ['Country', 'City'], 1, 1, []]);
  p = plan('country;CITY\nBelgium;Paris');
  assert.equal(p.headerSkipped, true);
  p = plan('parent;child\nBelgium;Paris');
  assert.equal(p.headerSkipped, true);
  p = plan('Belgium;Brussels\nFrance;Paris');
  assert.deepEqual([p.headerSkipped, p.pairs.length, p.headerCells], [false, 2, []]);
  p = plan('Belgum;Brusels\nFrance;Paris');
  assert.deepEqual([p.headerSkipped, p.headerCells, p.errors], [true, ['Belgum', 'Brusels'], []]);
  p = plan('Belgium;Brusels\nFrance;Paris');
  assert.deepEqual([p.headerSkipped, codes(p.errors)], [false, [[1, 'unknown_child']]]);
  p = plan('Country;City;Extra\nBelgium;Paris');
  assert.deepEqual([p.headerSkipped, p.headerCells, p.errors, p.errorCount], [true, ['Country', 'City', 'Extra'], [], 0]);
  p = plan('Belgium;Brussels\nFrance;Paris', null, null, null, { header: 'yes' });
  assert.deepEqual([p.headerSkipped, p.pairs.length, p.lines], [true, 1, 1]);
  p = plan('Country;City\nBelgium;Paris', null, null, null, { header: 'no' });
  assert.deepEqual(codes(p.errors), [[1, 'unknown_parent'], [1, 'unknown_child']]);
  p = plan('Country;City\nBelgium;Paris', null, list(['Country', 'Belgium']), list(['City', 'Paris']));
  assert.deepEqual([p.headerSkipped, p.pairs.length], [false, 2]);
  // unprotect runs before the header rule
  const towns = list(['City', 'Paris']);
  p = plan("'=Country;City\nBelgium;Paris", null, null, towns, { parentName: '=Country', childName: 'Town', unprotect: true });
  assert.equal(p.headerSkipped, true);
  p = plan("'=Country;City\nBelgium;Paris", null, null, towns, { parentName: '=Country', childName: 'Town' });
  assert.deepEqual([p.headerSkipped, codes(p.errors)], [false, [[1, 'unknown_parent']]]);
  // the first record after blank lines is row 1
  p = plan('\n\nCountry;City\nBelgium;Paris');
  assert.deepEqual([p.headerSkipped, p.pairs[0].line], [true, 4]);
  // each auto rule on its own, the other cell being a known value
  for (const text of ['parent;Paris', 'Belgium;CHILD', 'Belgium;city', 'COUNTRY;Paris']) {
    p = plan(`${text}\nBelgium;Antwerp`);
    assert.deepEqual([p.headerSkipped, p.errors, p.pairs.length], [true, [], 1], text);
  }
  // 'both unknown' needs two non-blank cells: a one-cell or blank-cell first
  // record keeps its error (review round 2), the name rules still skip it
  const linked = () => new M.State({ value_dependencies: { Belgium: ['Brussels', 'Antwerp'], France: ['Paris'] } });
  p = plan('Belgum', linked(), null, null, { mode: 'replace' });
  assert.deepEqual([p.headerSkipped, p.errors, p.ok], [false, [{ line: 1, code: 'columns', count: 1 }], false]);
  p = plan(';;', linked(), null, null, { separator: 'auto', defaultSeparator: ',', mode: 'replace' });
  assert.deepEqual([p.headerSkipped, p.separator, codes(p.errors), p.ok], [false, ',', [[1, 'columns']], false]);
  p = plan('Belgum\nBelgium;Antwerp');
  assert.deepEqual([p.headerSkipped, codes(p.errors), p.ok], [false, [[1, 'columns']], false]);
  p = plan(' ,Typo\nBelgium,Antwerp', null, null, null, { separator: ',' });
  assert.deepEqual([p.headerSkipped, codes(p.errors), p.ok], [false, [[1, 'blank_value']], false]);
  p = plan('Typo;　\nBelgium;Antwerp');
  assert.deepEqual([p.headerSkipped, codes(p.errors)], [false, [[1, 'blank_value']]]);
  p = plan('Country\nBelgium;Antwerp');
  assert.deepEqual([p.headerSkipped, p.headerCells, p.errors, p.pairs.length], [true, ['Country'], [], 1]);
  p = plan(' ;City\nBelgium;Antwerp');
  assert.deepEqual([p.headerSkipped, p.headerCells, p.errors, p.pairs.length], [true, ['', 'City'], [], 1]);
  // auto never reads a quote error as a header
  p = plan('"a"x;b\nBelgium;Paris');
  assert.deepEqual([p.headerSkipped, codes(p.errors), p.ok], [false, [[1, 'bad_quote']], false]);
  p = plan('"open;b');
  assert.deepEqual([p.headerSkipped, codes(p.errors), p.ok], [false, [[1, 'unterminated_quote']], false]);
  // yes skips a first record with a bad quote (its error goes, matched on the
  // line of the quote), not an unterminated one (it holds the rest of the input)
  const yes = { header: 'yes' };
  p = plan('"Country"x;City\nBelgium;Lyon', null, null, null, yes);
  assert.deepEqual([p.headerSkipped, p.errors, p.errorCount, p.pairs.length, p.lines, p.ok], [true, [], 0, 1, 1, true]);
  // the warning names the cells read up to and including the bad-quoted one
  assert.deepEqual(p.headerCells, ['Country']);
  p = plan('"Country"x,City\nBelgium,Paris', null, null, null, { separator: ',', header: 'yes' });
  assert.deepEqual([p.headerSkipped, p.headerCells, p.errors], [true, ['Country'], []]);
  p = plan('Country,"City"x\nBelgium,Paris', null, null, null, { separator: ',', header: 'yes' });
  assert.deepEqual([p.headerSkipped, p.headerCells, p.errors], [true, ['Country', 'City'], []]);
  p = plan('"Coun\ntry"x;City\nBelgium;Lyon\n"a"x;b', null, null, null, yes);
  assert.deepEqual([p.headerSkipped, codes(p.errors), p.errorCount, p.pairs.map((x) => x.line)],
    [true, [[4, 'bad_quote']], 1, [3]]);
  p = plan('"open;b\nBelgium;Lyon', null, null, null, yes);
  assert.deepEqual([p.headerSkipped, codes(p.errors), p.ok], [false, [[1, 'unterminated_quote']], false]);
});

test('planImport: matching order, NFD input against NFC values, unique case-insensitive, ambiguous', () => {
  const P = list(['Belgium']);
  const C = list(['Paris', 'PARIS', 'Montr\u00e9al', 'Li\u00e8ge']);
  const p = plan('Belgium;Paris\nBelgium;paris\nBelgium;Montre\u0301al\nBELGIUM;li\u00e8ge\nBelgium;Liege', null, P, C,
    { header: 'no' });
  assert.deepEqual(p.errors, [{ line: 2, code: 'ambiguous_child', value: 'paris' },
    { line: 5, code: 'unknown_child', value: 'Liege' }]);
  assert.deepEqual(p.pairs.map((x) => x.child), ['Paris', 'Montr\u00e9al', 'Li\u00e8ge']);
  // separator auto with nothing found: the locale separator (defaultSeparator) when given, else ','
  const local = plan('a;b;c', null, list(['a']), list(['b']), { separator: 'auto', defaultSeparator: ';', header: 'no' });
  assert.deepEqual([local.separator, local.errors], [';', [{ line: 1, code: 'columns', count: 3 }]]);
  const none = plan('a;b;c', null, list(['a']), list(['b']), { separator: 'auto', header: 'no' });
  assert.deepEqual([none.separator, none.errors], [',', [{ line: 1, code: 'columns', count: 1 }]]);
});

test('planImport: merge and replace counts; the plan changes neither the state nor the lists', () => {
  // Gone is no current child: its links are never counted as removed
  const state = new M.State({ value_dependencies: { Belgium: ['Antwerp', 'Brussels', 'Gone'], France: ['Paris'],
                                                    Atlantis: ['Gone'] },
                              default_value_dependencies: { Belgium: 'Brussels' } });
  const before = snapshotState(state);
  const lists = JSON.stringify([COUNTRY.items, CITY.items]);
  const text = 'Belgium;Paris\nBelgium;Antwerp\nGermany;Lyon\nBelgium;Paris';
  const merge = plan(text, state, null, null, { header: 'no' });
  assert.deepEqual([merge.ok, merge.mode, merge.added, merge.existing, merge.removed, merge.duplicates, merge.pairs.length,
    merge.lines], [true, 'merge', 2, 1, 0, 1, 3, 4]);
  assert.deepEqual(merge.pairs.map((x) => [x.line, x.parent, x.child, x.existing]),
    [[1, 'Belgium', 'Paris', false], [2, 'Belgium', 'Antwerp', true], [3, 'Germany', 'Lyon', false]]);
  const replace = plan(text, state, null, null, { header: 'no', mode: 'replace' });
  assert.deepEqual([replace.ok, replace.mode, replace.added, replace.existing, replace.removed, replace.duplicates],
    [true, 'replace', 2, 1, 2, 1]);
  const headerOnly = plan('Country;City', state, null, null, { mode: 'replace' });
  assert.deepEqual([headerOnly.ok, headerOnly.pairs.length, headerOnly.removed, headerOnly.headerSkipped], [true, 0, 3, true]);
  assert.equal(plan('', state, null, null, { mode: 'replace' }).ok, false, 'an empty input never clears the links');
  assert.equal(plan('Country;City', state, null, null, {}).ok, false, 'merge needs a pair');
  assert.equal(snapshotState(state), before);
  assert.equal(JSON.stringify([COUNTRY.items, CITY.items]), lists);
  assert.throws(() => M.planImport('a;b', {}, COUNTRY, CITY, {}), TypeError);
  assert.throws(() => M.planImport('a;b', state, null, CITY, {}), TypeError);
});

test('applyImport: merge adds, replace keeps exactly the pairs (orphans and lost defaults go); source and import set', () => {
  const mapping = { value_dependencies: { Belgium: ['Antwerp', 'Brussels'], France: ['Paris'], Atlantis: ['Gone'] },
                    default_value_dependencies: { Belgium: 'Brussels', France: 'Paris' } };
  const text = 'Belgium;Paris\nBelgium;Antwerp\nGermany;Lyon\nFrance;Paris';
  const opts = { multiple: false, base: BASE };
  const merged = new M.State(mapping);
  const snapshot = merged.clone();
  const preText = M.stringify(M.serialize(merged, COUNTRY, CITY, opts));
  M.applyImport(merged, plan(text, merged, null, null, { header: 'no' }));
  let out = J(M.serialize(merged, COUNTRY, CITY, opts));
  assert.deepEqual(out.value_dependencies, { Belgium: ['Antwerp', 'Brussels', 'Paris'], France: ['Paris'], Germany: ['Lyon'] });
  assert.deepEqual(out.default_value_dependencies, { Belgium: 'Brussels', France: 'Paris' });
  assert.deepEqual([out.source, out.import], ['import', { mode: 'merge', rows: 4 }]);
  assert.ok(merged.isLinked('Atlantis', 'Gone'));
  // undo: the clone taken before gives the pre-import payload byte for byte
  assert.equal(M.stringify(M.serialize(snapshot, COUNTRY, CITY, opts)), preText);

  const replaced = new M.State(mapping);
  M.applyImport(replaced, plan(text, replaced, null, null, { header: 'no', mode: 'replace' }));
  out = J(M.serialize(replaced, COUNTRY, CITY, opts));
  assert.deepEqual(out.value_dependencies, { Belgium: ['Antwerp', 'Paris'], France: ['Paris'], Germany: ['Lyon'] });
  assert.deepEqual(out.default_value_dependencies, { France: 'Paris' });
  assert.deepEqual(out.import, { mode: 'replace', rows: 4 });
  assert.equal(replaced.isLinked('Atlantis', 'Gone'), false);
  assert.deepEqual(replaced.importMeta, { mode: 'replace', rows: 4 });
  const clone = replaced.clone();
  assert.deepEqual([clone.source, clone.importMeta], ['import', { mode: 'replace', rows: 4 }]);

  const cleared = new M.State(mapping);
  M.applyImport(cleared, plan('Country;City', cleared, null, null, { mode: 'replace' }));
  assert.deepEqual([cleared.links.size, cleared.defaults.size, cleared.importMeta], [0, 0, { mode: 'replace', rows: 0 }]);
  // rows counts the distinct pairs: not the skipped header, not the duplicate line
  const x = new M.State(null);
  const dup = plan('Country;City\nBelgium;Paris\nBelgium;Paris\nBelgium;Antwerp', x);
  M.applyImport(x, dup);
  assert.deepEqual([dup.lines, dup.duplicates, x.importMeta], [3, 1, { mode: 'merge', rows: 2 }]);
  assert.throws(() => M.applyImport({}, { pairs: [], mode: 'merge' }), TypeError);
});

test('planImport: add missing child values (list children only)', () => {
  const P = list(['Belgium']);
  const C = list(['Antwerp', 'Brussels']);
  const opts = { header: 'no', addMissing: true, kind: 'list' };
  const text = ['Belgium;Zurich', 'Belgium;zurich', 'Belgium;" Zurich "', 'Belgium;Zu\u0308rich', 'Belgium;Z\u00fcrich',
    'Belgium;" Brussels "', 'Belgium;"\tTab\u0000"'].join('\n');
  let p = plan(text, null, P, C, opts);
  assert.deepEqual(p.errors, []);
  assert.deepEqual(p.newValues, ['Zurich', 'Z\u00fcrich', 'Tab']);
  assert.deepEqual(p.pairs.map((x) => [x.child, x.existing]), [['Zurich', false], ['Z\u00fcrich', false], ['Brussels', false],
    ['Tab', false]]);
  assert.equal(p.duplicates, 3);
  p = plan('Belgium;Zurich\nBelgium;"New\nLine"\nBelgium;"New\rLine"', null, P, C, opts);
  assert.deepEqual(p.errors, [{ line: 2, code: 'multiline_value', value: 'New\nLine' },
    { line: 4, code: 'multiline_value', value: 'New\rLine' }]);
  p = plan('Belgium;" \u0000 "', null, P, C, opts);
  assert.deepEqual(codes(p.errors), [[1, 'blank_value']]);
  p = plan('Belgium;\ud800x', null, P, C, opts);
  assert.deepEqual(p.newValues, ['\ufffdx']);
  assert.deepEqual(M.listValuesFromText('Antwerp\nBrussels\n' + p.newValues.join('\n')).map((v) => v.key),
    ['Antwerp', 'Brussels', '\ufffdx']);
  p = plan('Belgium;Zurich', null, P, C, { header: 'no' });
  assert.deepEqual([codes(p.errors), p.newValues], [[[1, 'unknown_child']], []]);
  // a NUL inside a new value is refused (HTML would turn it into U+FFFD)
  p = plan('Belgium;"new\u0000val"\nBelgium;new\u0000val\nBelgium;\u0000Zurich\u0000', null, P, C, opts);
  assert.deepEqual([p.errors, p.newValues, p.ok], [[{ line: 1, code: 'nul_value', value: 'new\u0000val' },
    { line: 2, code: 'nul_value', value: 'new\u0000val' }], ['Zurich'], false]);
  // the match after strip and NFC can be ambiguous too
  p = plan('Belgium;" paris "', null, P, list(['Paris', 'PARIS']), opts);
  assert.deepEqual([codes(p.errors), p.newValues], [[[1, 'ambiguous_child']], []]);
  // the estimate counts the extended children
  p = plan('Belgium;Zurich', null, P, C, Object.assign({ multiple: false, base: BASE }, opts));
  const state = new M.State(null);
  M.applyImport(state, p);
  const extended = list(['Antwerp', 'Brussels', 'Zurich']);
  const text2 = M.stringify(M.serialize(state, P, extended, { multiple: false, base: BASE }));
  assert.equal(p.estimatedPayloadBytes, M.utf8Bytes(text2));
  assert.ok(text2.includes('"Belgium":["Zurich"]'));
});

test('planImport: errors in line order (parent before child), 200 kept and the rest counted; warnings capped', () => {
  const lines = [];
  for (let k = 0; k < 150; k += 1) lines.push('"a"x;b', 'Nowhere;Antwerp');
  let p = plan(lines.join('\n'), null, null, null, { header: 'no' });
  assert.equal(p.errors.length, 200);
  assert.equal(p.errorCount, 300);
  assert.deepEqual(p.errors.map((e) => e.line), Array.from({ length: 200 }, (_, k) => k + 1));
  assert.deepEqual(codes(p.errors.slice(0, 2)), [[1, 'bad_quote'], [2, 'unknown_parent']]);
  p = plan('Nowhere;Nothing', null, null, null, { header: 'no' });
  assert.deepEqual(codes(p.errors), [[1, 'unknown_parent'], [1, 'unknown_child']]);
  p = plan('Country;City\nnope;x;y', null, null, null, { header: 'auto' });
  assert.deepEqual(p.errors.map((e) => [e.line, e.code, e.count]), [[2, 'columns', 3]]);
  // a skipped header's columns error does not cost one of the 200 kept errors
  p = plan('Country;City;Extra\n' + 'a;b;c\n'.repeat(250));
  assert.deepEqual([p.headerSkipped, p.errors.length, p.errorCount, p.errors[0].line, p.errors[199].line], [true, 200, 250, 2, 201]);
  const C = PRODUCTS();
  p = plan('North;Retired\n'.repeat(1000), null, REGIONS, C, { header: 'no', kind: 'enumeration' });
  assert.equal(p.warnings.length, 200);
  assert.equal(p.warningCount, 1000);
  assert.equal(p.duplicates, 999);
  assert.equal(p.ok, true);
});

test('planImport: estimatedPayloadBytes is the serialized result; above maxPayloadBytes the plan is not ok', () => {
  const state = new M.State({ value_dependencies: { Belgium: ['Antwerp'] }, default_value_dependencies: { Belgium: 'Antwerp' } });
  const opts = { header: 'no', multiple: true, base: BASE };
  const p = plan('France;Paris\nGermany;Lyon', state, null, null, opts);
  const applied = state.clone();
  M.applyImport(applied, p);
  const bytes = M.utf8Bytes(M.stringify(M.serialize(applied, COUNTRY, CITY, { multiple: true, base: BASE })));
  assert.equal(p.estimatedPayloadBytes, bytes);
  assert.equal(plan('France;Paris\nGermany;Lyon', state, null, null, Object.assign({ maxPayloadBytes: bytes }, opts)).ok, true);
  const over = plan('France;Paris\nGermany;Lyon', state, null, null, Object.assign({ maxPayloadBytes: bytes - 1 }, opts));
  assert.deepEqual([over.ok, over.tooLarge, over.errorCount], [false, true, 0]);
  const enumPlan = plan('North;Alpha', null, REGIONS, PRODUCTS(), { header: 'no', kind: 'enumeration', multiple: true });
  const enumState = new M.State(null);
  M.applyImport(enumState, enumPlan);
  assert.equal(enumPlan.estimatedPayloadBytes,
    M.utf8Bytes(M.stringify(M.serialize(enumState, REGIONS, PRODUCTS(), { kind: 'enumeration', multiple: true }))));
  assert.ok(M.stringify(M.serialize(enumState, REGIONS, PRODUCTS(), { kind: 'enumeration' })).includes('[9200004]'));
});

test('planImport, applyImport and buildCsv: Object.prototype names behave like other values; no prototype changes', () => {
  const before = Object.getOwnPropertyNames(Object.prototype).sort();
  const P = list(['__proto__', 'constructor', 'a|b', 'a', 'toJSON']);
  const C = list(['toString', 'hasOwnProperty', 'c', 'b|c', 'prototype', '__defineGetter__']);
  const p = plan('constructor;toString\n__proto__;hasOwnProperty\na|b;c\na;b|c\ntoJSON;__defineGetter__\n__proto__;prototype',
    null, P, C, { header: 'no' });
  assert.deepEqual([p.errors, p.duplicates, p.pairs.length], [[], 0, 6]);
  const q = plan('valueOf;c\na;constructor\nprototype;c', null, P, C, { header: 'no' });
  assert.deepEqual(codes(q.errors), [[1, 'unknown_parent'], [2, 'unknown_child'], [3, 'unknown_parent']]);
  const state = new M.State(null);
  M.applyImport(state, p);
  const out = J(M.serialize(state, P, C, {}));
  assert.deepEqual(out.value_dependencies.__proto__, ['hasOwnProperty', 'prototype']);
  assert.deepEqual(out.value_dependencies.constructor, ['toString']);
  const csv = M.buildCsv(state, P, C, { separator: ',' });
  assert.ok(csv.includes('\r\n__proto__,hasOwnProperty\r\n__proto__,prototype\r\nconstructor,toString\r\n'), csv);
  assert.deepEqual(Object.getOwnPropertyNames(Object.prototype).sort(), before);
  assert.equal({}.toString, Object.prototype.toString);
  assert.equal(typeof Object.prototype.prototype, 'undefined');
});

test('buildCsv: one BOM, CRLF, header names, quoting, labels, orphans and defaults left out', () => {
  const C = list(['Antwerp', 'semi;colon', 'say "hi"', ' lead', 'trail\t', 'a\nb', 'c,d', 'tab\tin']);
  const state = new M.State({ value_dependencies: { Belgium: ['semi;colon', 'Antwerp'],
                                                    France: ['a\nb', 'say "hi"', ' lead', 'trail\t', 'c,d', 'tab\tin'],
                                                    Atlantis: ['Gone'], Germany: ['Gone'] },
                              default_value_dependencies: { Belgium: 'Antwerp' } });
  const csv = M.buildCsv(state, COUNTRY, C, { separator: ',', parentName: 'Country', childName: 'City' });
  assert.equal(csv, '\ufeffCountry,City\r\nBelgium,Antwerp\r\nBelgium,"semi;colon"\r\nFrance,"say ""hi"""\r\n' +
    'France," lead"\r\nFrance,"trail\t"\r\nFrance,"a\nb"\r\nFrance,"c,d"\r\nFrance,"tab\tin"\r\n');
  assert.equal(csv.split('\ufeff').length, 2);
  assert.equal(M.buildCsv(state, COUNTRY, C, { separator: '.' }).split('\r\n')[0], '\ufeffparent,child');
  assert.equal(M.buildCsv(state, COUNTRY, C, { separator: ';', parentName: 'Country', childName: 'City' }).split('\r\n')[2],
    'Belgium;"semi;colon"');
  assert.equal(M.buildCsv(state, COUNTRY, C, { separator: '\t' }).split('\r\n')[1], 'Belgium\tAntwerp');
  assert.equal(M.buildCsv(state, null, C, { separator: ',', parentName: 'Country', childName: 'City' }), '\ufeffCountry,City\r\n');
  const enumState = new M.State({ value_dependencies: { 9200001: ['9200004', '9200007'] } });
  assert.equal(M.buildCsv(enumState, REGIONS, PRODUCTS(), { separator: ',', parentName: 'Region', childName: 'Product' }),
    '\ufeffRegion,Product\r\nNorth,Alpha\r\nNorth,Retired\r\n');
  const before = snapshotState(state);
  M.buildCsv(state, COUNTRY, C, { separator: ',', protect: true });
  assert.equal(snapshotState(state), before);
  assert.throws(() => M.buildCsv({}, COUNTRY, C, {}), TypeError);
  // cost follows the links, not parents x children
  const many = list(L.names(5000, { prefix: 'P' }));
  const kids = list(L.names(2000, { prefix: 'C', offset: 9000 }));
  const sparse = new M.State(null);
  for (let k = 0; k < 10; k += 1) sparse.link(many.items[k * 400].key, kids.items[k * 150].key, true);
  const [ms, out] = warmMinimum(() => M.buildCsv(sparse, many, kids, { separator: ',' }));
  assert.equal(out.split('\r\n').length, 12);
  assert.ok(ms < 100, `${ms} ms`);
});

test('buildCsv formula protection: each trigger in both columns and the header, any separator; off by default (UD-18)', () => {
  const values = ['=1+1', '+x', '-5', '@SUM(A1)', '\tz', '\rq', "'=x", "''-a", 'a=b', ' =x', "'x", '\uff1dx', 'plain'];
  const P = list(['=P']);
  const C = list(values);
  const state = new M.State(null);
  values.forEach((v) => state.link('=P', v, true));
  [',', ';', '\t'].forEach((sep) => {
    const quote = (s) => (/[,;\t"\r\n]/.test(s) || /^[\u0000\t\v\f ]|[\u0000\t\v\f ]$/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s);
    const row = (a, b) => quote(a) + sep + quote(b);
    const on = M.buildCsv(state, P, C, { separator: sep, parentName: '=Field', childName: 'City', protect: true });
    const protectedValues = ["'=1+1", "'+x", "'-5", "'@SUM(A1)", "'\tz", "'\rq", "''=x", "'''-a", 'a=b', ' =x', "'x", '\uff1dx',
      'plain'];
    assert.equal(on, '\ufeff' + [row("'=Field", 'City')].concat(protectedValues.map((v) => row("'=P", v))).join('\r\n') + '\r\n', sep);
    const off = M.buildCsv(state, P, C, { separator: sep, parentName: '=Field', childName: 'City' });
    assert.equal(off, '\ufeff' + [row('=Field', 'City')].concat(values.map((v) => row('=P', v))).join('\r\n') + '\r\n', sep);
  });
});

test('protect and unprotect are symmetric; unprotect off keeps the apostrophe (UD-18)', () => {
  const values = ['=x', "'=x", "''=x", "'x", '-1', "'-1", '@', "'", '\tz', 'a', '=SUM(1)', '+1', '@x', "'@"];
  const P = list(['P']);
  const C = list(values);
  const state = new M.State(null);
  values.forEach((v) => state.link('P', v, true));
  const csv = M.buildCsv(state, P, C, { separator: ',', parentName: 'Country', childName: 'City', protect: true });
  const p = plan(csv, null, P, C, { separator: 'auto', mode: 'replace', unprotect: true });
  assert.deepEqual(p.errors, []);
  assert.deepEqual(p.pairs.map((x) => x.child), values);
  const lone = plan("P,'=x\nP,'x\nP,''=x", null, P, C, { separator: ',', header: 'no', unprotect: true });
  assert.deepEqual(lone.pairs.map((x) => x.child), ['=x', "'x", "'=x"]);
  const kept = plan("P,'=x\nP,=x", null, P, C, { separator: ',', header: 'no' });
  assert.deepEqual(kept.pairs.map((x) => x.child), ["'=x", '=x']);
  const brussels = list(['=Brussels']);
  assert.deepEqual(plan("P;'=Brussels", null, P, brussels, { header: 'no', unprotect: true }).pairs.map((x) => x.child), ['=Brussels']);
  assert.deepEqual(codes(plan("P;'=Brussels", null, P, brussels, { header: 'no' }).errors), [[1, 'unknown_child']]);
});

const TRICKY_P = L.TRICKY.concat(['__proto__', 'constructor', 'toString', 'hasOwnProperty', 'valueOf', 'toJSON',
  '"><script>alert(1)</script>', '</script>', '&', 'a/b', '007', '10', '\u00e9', 'e\u0301', 'line\u2028sep', '\ud83d\ude00 smile',
  '=SUM(1)', '+1', '-1', '@x', "'=x", "''=x", "'x", '-', "'", 'Nord;Ost', 'semi;colon,comma\ttab']);
const TRICKY_C = ['__proto__', 'constructor', 'b', '[x]', 'a]', '<b>x</b>', '&amp;', '1.0', 'null', 'tab\tin', '=x', '@',
  '\u00dcn\u00efc\u00f8d\u00e9 \u00f1', 'say "hi"', 'Sud;Est', 'x,y'];

test('export then import round-trips: each separator, protection off and on, tricky values and field names', () => {
  const scenarios = [];
  const parentKeys = L.names(27, { prefix: 'P' });
  const childKeys = L.names(5570, { trickyEvery: 97 });
  scenarios.push(['S1', list(parentKeys), list(childKeys), new M.State({ value_dependencies: L.partition(parentKeys, childKeys) }),
    {}]);
  const trickyState = new M.State(null);
  TRICKY_P.forEach((p, i) => {
    trickyState.link(p, TRICKY_C[i % TRICKY_C.length], true);
    trickyState.link(p, TRICKY_C[(i * 7 + 3) % TRICKY_C.length], true);
  });
  scenarios.push(['tricky', list(TRICKY_P), list(TRICKY_C), trickyState, {}]);
  const enumP = M.ValueList.fromWire([{ key: '1', label: ' lead ' }, { key: '2', label: '=Formula' },
    { key: '3', label: 'Old', active: false }]);
  const enumC = M.ValueList.fromWire([{ key: '4', label: 'Alpha' }, { key: '5', label: 'trail\t' }, { key: '6', label: '+1' },
    { key: '7', label: 'Retired', active: false }]);
  const enumState = new M.State({ value_dependencies: { 1: ['4', '5'], 2: ['6', '7'], 3: ['4'] } });
  scenarios.push(['enumeration', enumP, enumC, enumState, { kind: 'enumeration' }]);
  scenarios.forEach(([name, P, C, state, extra]) => {
    const expected = JSON.stringify(J(M.serialize(state, P, C, extra)).value_dependencies);
    [',', ';', '\t'].forEach((sep) => {
      [false, true].forEach((protect) => {
        [['Country', 'City'], ['Land;Region', 'Stad, Ort'], ['=Field', 'tab\there']].forEach(([parentName, childName]) => {
          const label = `${name} ${JSON.stringify(sep)} protect=${protect} ${parentName}`;
          const csv = M.buildCsv(state, P, C, { separator: sep, parentName, childName, protect });
          const p = M.planImport(csv, new M.State(null), P, C, Object.assign({ separator: 'auto', header: 'auto', mode: 'replace',
            unprotect: protect, parentName, childName }, extra));
          assert.equal(p.errorCount, 0, `${label}: ${JSON.stringify(p.errors.slice(0, 3))}`);
          assert.equal(p.separator, sep, label);
          assert.equal(p.headerSkipped, true, label);
          const fresh = new M.State(null);
          M.applyImport(fresh, p);
          assert.equal(JSON.stringify(J(M.serialize(fresh, P, C, extra)).value_dependencies), expected, label);
        });
      });
    });
  });
});

test('scale: parse + plan + apply + serialize for 27 x 5,570 under 500 ms, S1-full under 4,500 ms; buildCsv under 2,000 ms (G6)', () => {
  const parentKeys = L.names(27, { prefix: 'P' });
  const childKeys = L.names(5570, { trickyEvery: 97 });
  const P = list(parentKeys);
  const C = list(childKeys);
  const s1 = new M.State({ value_dependencies: L.partition(parentKeys, childKeys) });
  const csv = M.buildCsv(s1, P, C, { separator: ';', parentName: 'Country', childName: 'City' });
  const expected = M.stringify(M.serialize(s1, P, C, { multiple: false, base: BASE }));
  const run = (text) => {
    const state = new M.State(null);
    const p = M.planImport(text, state, P, C, { separator: 'auto', mode: 'merge', parentName: 'Country', childName: 'City',
                                               multiple: false, base: BASE });
    M.applyImport(state, p);
    return [p, M.stringify(M.serialize(state, P, C, { multiple: false, base: BASE }))];
  };
  const [s1Ms, [s1Plan, s1Text]] = warmMinimum(() => run(csv));
  assert.equal(s1Plan.pairs.length, 5570);
  assert.equal(JSON.stringify(JSON.parse(s1Text).value_dependencies), JSON.stringify(JSON.parse(expected).value_dependencies));

  const full = new M.State(null);
  parentKeys.forEach((pk) => childKeys.forEach((ck) => full.link(pk, ck, true)));
  const [csvMs, fullCsv] = warmMinimum(() => M.buildCsv(full, P, C, { separator: ',', parentName: 'Country', childName: 'City' }));
  assert.equal(fullCsv.split('\r\n').length, 150392);
  const [fullMs, [fullPlan]] = warmMinimum(() => run(fullCsv));
  assert.equal(fullPlan.pairs.length, 150390);
  assert.ok(fullPlan.estimatedPayloadBytes <= 4194304);
  console.log(`# perf import_ms=${s1Ms.toFixed(1)} import_full_ms=${fullMs.toFixed(1)} build_csv_full_ms=${csvMs.toFixed(1)} ` +
              `full_csv_chars=${fullCsv.length}`);
  assert.ok(s1Ms < 500, `S1 ${s1Ms} ms`);
  assert.ok(fullMs < 4500, `S1-full ${fullMs} ms`);
  assert.ok(csvMs < 2000, `buildCsv ${csvMs} ms`);
});
