'use strict';
// WP-23 (quality 5.6, R3, QA-02): the payload goldens test/js/fixtures/payload/*.json
// are the exact text the editor puts in the hidden input, written by the real
// model serialize() from fixed inputs. npm test compares them byte for byte;
// DCF_WRITE_JS_FIXTURES=1 node --test test/js/payload_golden.test.js writes them.
// spec/requests/dependency_payload_contract_spec.rb posts each one to the admin
// form (and, from WP-27, to the project page) with fields holding the same
// lists, so these lists and that spec change together. WP-26 regenerates
// import_*.json with the real import.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const M = require('../../assets/javascripts/dcf_dependency_editor_model.js');
const L = require('./support/large_list');

const DIR = path.join(__dirname, 'fixtures', 'payload');
const WRITE = process.env.DCF_WRITE_JS_FIXTURES === '1';
const HINT = 'run DCF_WRITE_JS_FIXTURES=1 node --test test/js/payload_golden.test.js and review the diff';
// The one placeholder base; the contract spec replaces it by the stored digest.
const BASE = '0123456789abcdef'.repeat(4);
// DependencyPayload.digest({}, {}): a placeholder equal to it would pass the stale guard.
const EMPTY_DIGEST = '643d5437104296e21d906ecb15b2c96ad278f20cfc4af53b12bb6069bd853726';
const NAMES = ['clear', 'enumeration_save', 'import_merge', 'import_replace', 'list_save', 'tricky_values'];

const wire = (keys) => keys.map((key) => ({ key }));
const COUNTRIES = ['Belgium', 'France', 'Germany', 'Netherlands'];
const CITIES = ['Antwerp', 'Brussels', 'Ghent', 'Lyon', 'Paris', 'Berlin', 'Utrecht'];
const REGIONS = [{ key: '9200001', label: 'North' }, { key: '9200002', label: 'South' },
  { key: '9200003', label: 'Old region', active: false }];
const PRODUCTS = [{ key: '9200004', label: 'Alpha' }, { key: '9200005', label: 'Beta' }, { key: '9200006', label: 'Gamma' },
  { key: '9200007', label: 'Retired', active: false }];
const NAMED = ['__proto__', 'constructor', 'toString', 'hasOwnProperty', 'valueOf', 'toJSON'];
const TRICKY_PARENTS = L.TRICKY.concat(NAMED, ['Foo [x]', '[b', '"><script>alert(1)</script>', '</script>', '&',
  'a/b', '12345678901234567890', '007', '10', '2', '\u00e9', 'e\u0301', 'line\u2028sep', 'back\\slash',
  '\ud83d\ude00 smile']);
const TRICKY_CHILDREN = ['__proto__', 'constructor', 'toString', 'hasOwnProperty', 'toJSON', 'b', '[x]', 'a]',
  '<b>x</b>', '&amp;', '1.0', 'null', 'a/b/c', '9007199254740993', '\u00dcn\u00efc\u00f8d\u00e9 \u00f1', 'tab\tin'];

// Links are added in the given order, or reversed: the text must not depend on it.
function linked(pairs, reversed) {
  const state = new M.State(null);
  (reversed ? pairs.slice().reverse() : pairs).forEach(([p, c]) => state.link(p, c, true));
  return state;
}

// Stand-in for the WP-26 apply: merge adds the pairs, replace keeps only
// them and drops the defaults whose link went; source and import are set.
function applyPairs(state, pairs, mode) {
  if (mode === 'replace') {
    const defaults = state.defaults;
    state.links = new Map();
    state.defaults = new Map();
    pairs.forEach(([p, c]) => state.link(p, c, true));
    defaults.forEach((keys, p) => state.setDefaults(p, keys));
  } else {
    pairs.forEach(([p, c]) => state.link(p, c, true));
  }
  state.source = 'import';
  state.importMeta = { mode, rows: pairs.length };
}

const BUILDERS = {
  list_save(reversed) {
    const state = linked([['France', 'Paris'], ['Belgium', 'Ghent'], ['Belgium', 'Brussels'], ['Germany', 'Berlin'],
      ['France', 'Lyon'], ['Belgium', 'Antwerp'], ['Gone', 'Paris'], ['Belgium', 'Atlantis']], reversed);
    state.setDefaults('Belgium', ['Ghent', 'Brussels']);
    state.setDefaults('Germany', ['Berlin']);
    state.setDefaults('Gone', ['Paris']);
    return M.serialize(state, M.ValueList.fromWire(wire(COUNTRIES)), M.ValueList.fromWire(wire(CITIES)),
                       { multiple: false, base: BASE });
  },
  enumeration_save(reversed) {
    const state = linked([['9200001', '9200007'], ['9200001', '9200004'], ['9200002', '9200006'],
      ['9200001', '9200005'], ['9200003', '9200004'], ['9200002', '9200099']], reversed);
    state.setDefaults('9200001', ['9200007', '9200005']);
    state.setDefaults('9200003', ['9200004']);
    return M.serialize(state, M.ValueList.fromWire(REGIONS), M.ValueList.fromWire(PRODUCTS),
                       { kind: 'enumeration', multiple: true, base: BASE });
  },
  clear(reversed) {
    const pairs = [['Belgium', 'Ghent'], ['France', 'Paris']];
    const state = linked(pairs, reversed);
    state.setDefaults('Belgium', ['Ghent']);
    pairs.forEach(([p, c]) => state.link(p, c, false));
    return M.serialize(state, M.ValueList.fromWire(wire(COUNTRIES)), M.ValueList.fromWire(wire(CITIES)),
                       { multiple: false, base: BASE });
  },
  import_merge(reversed) {
    const state = new M.State({ value_dependencies: { Belgium: ['Brussels'] }, default_value_dependencies: { Belgium: 'Brussels' } });
    const pairs = [['Belgium', 'Ghent'], ['France', 'Paris'], ['Netherlands', 'Utrecht'], ['Belgium', 'Brussels']];
    applyPairs(state, reversed ? pairs.slice().reverse() : pairs, 'merge');
    return M.serialize(state, M.ValueList.fromWire(wire(COUNTRIES)), M.ValueList.fromWire(wire(CITIES)),
                       { multiple: false, base: BASE });
  },
  import_replace(reversed) {
    const state = new M.State({ value_dependencies: { Belgium: ['Brussels', 'Ghent'], France: ['Paris'] },
                                default_value_dependencies: { Belgium: ['Ghent'], France: ['Paris'] } });
    const pairs = [['Belgium', 'Antwerp'], ['Belgium', 'Ghent'], ['Germany', 'Berlin'], ['Netherlands', 'Utrecht'],
      ['France', 'Lyon']];
    applyPairs(state, reversed ? pairs.slice().reverse() : pairs, 'replace');
    return M.serialize(state, M.ValueList.fromWire(wire(COUNTRIES)), M.ValueList.fromWire(wire(CITIES)),
                       { multiple: true, base: BASE });
  },
  tricky_values(reversed) {
    const pairs = [['__proto__', '__proto__'], ['constructor', 'b'], ['hasOwnProperty', 'b'], ['toString', 'toString'],
      ['toString', 'b'], ['valueOf', 'constructor'], ['toJSON', 'toJSON']];
    TRICKY_PARENTS.forEach((p, i) => {
      if (NAMED.includes(p)) return;
      pairs.push([p, TRICKY_CHILDREN[i % TRICKY_CHILDREN.length]]);
      pairs.push([p, TRICKY_CHILDREN[(i * 7 + 3) % TRICKY_CHILDREN.length]]);
    });
    const state = linked(pairs, reversed);
    state.setDefaults('__proto__', ['__proto__']);
    state.setDefaults('toJSON', ['toJSON']);
    TRICKY_PARENTS.forEach((p, i) => {
      if (i % 3 === 0 && !NAMED.includes(p)) state.setDefaults(p, [TRICKY_CHILDREN[(i * 7 + 3) % TRICKY_CHILDREN.length]]);
    });
    return M.serialize(state, M.ValueList.fromWire(wire(TRICKY_PARENTS)), M.ValueList.fromWire(wire(TRICKY_CHILDREN)),
                       { multiple: false, base: BASE });
  }
};

const golden = (name, reversed) => M.stringify(BUILDERS[name](reversed));
const fileOf = (name) => path.join(DIR, name + '.json');

// Strings replaced by "": what JSON.stringify wrote outside them.
const outside = (text) => text.replace(/"(?:[^"\\]|\\.)*"/g, '""');

function wellFormed(s) {
  for (let i = 0; i < s.length; i += 1) {
    const c = s.charCodeAt(i);
    if (c >= 0xd800 && c <= 0xdbff) {
      const d = s.charCodeAt(i + 1);
      if (!(d >= 0xdc00 && d <= 0xdfff)) return false;
      i += 1;
    } else if (c >= 0xdc00 && c <= 0xdfff) {
      return false;
    }
  }
  return true;
}

// A value core possible_values= stores unchanged (no surrounding white
// space, no CR or LF, not blank) and PostgreSQL accepts (no NUL).
function storable(v) {
  return typeof v === 'string' && !M.isBlank(v) && !/[\r\n\u0000]/.test(v) && v === v.replace(/^[\t\n\v\f\r ]+|[\t\n\v\f\r ]+$/g, '') &&
    wellFormed(v) && !/[\u2013\u2014]/.test(v);
}

if (WRITE) {
  fs.mkdirSync(DIR, { recursive: true });
  NAMES.forEach((name) => fs.writeFileSync(fileOf(name), golden(name, false)));
}

NAMES.forEach((name) => {
  test(`${name}.json is the committed serialize() output`, () => {
    const text = golden(name, false);
    assert.ok(fs.existsSync(fileOf(name)), `${fileOf(name)} is missing: ${HINT}`);
    const committed = fs.readFileSync(fileOf(name), 'utf8');
    assert.ok(committed === text, `${name}.json differs from serialize(): ${HINT}`);
  });

  test(`${name}: the same text whatever the link insertion order`, () => {
    assert.equal(golden(name, true), golden(name, false));
  });

  test(`${name}: only what DependencyPayload accepts and core can store`, () => {
    const text = golden(name, false);
    const numbers = [];
    const data = JSON.parse(text, function reviver(key, value) {
      assert.notEqual(value, null);
      assert.notEqual(typeof value, 'boolean');
      if (typeof value === 'number') {
        assert.ok(Number.isSafeInteger(value) && (value > 0 || key === 'rows'), `number ${value}`);
        numbers.push([key, value]);
      }
      return value;
    });
    assert.deepEqual(Object.keys(data).filter((k) => !['import', 'base'].includes(k)),
                     ['version', 'source', 'value_dependencies', 'default_value_dependencies']);
    assert.equal(data.version, 1);
    assert.equal(data.base, BASE);
    assert.notEqual(data.base, EMPTY_DIGEST);
    assert.equal(/^[0-9a-f]{64}$/.test(data.base), true);
    assert.equal(text.split(BASE).length, 2, 'the placeholder occurs once');
    assert.equal(/\/|[0-9]{20}/.test(outside(text)), false);
    assert.equal(/\\u[dD][89abAB]|\\u[dD][c-fC-F]/.test(text), false, 'escaped lone surrogate');
    assert.equal(/[\u2013\u2014\r\n]/.test(text), false);
    if (name.startsWith('import_')) {
      assert.equal(data.source, 'import');
      assert.deepEqual(Object.keys(data.import), ['mode', 'rows']);
      assert.equal(data.import.mode, name === 'import_merge' ? 'merge' : 'replace');
    } else {
      assert.equal(data.source, 'editor');
      assert.equal('import' in data, false);
    }
    const vd = data.value_dependencies;
    const dd = data.default_value_dependencies;
    Object.keys(vd).forEach((p) => {
      assert.equal(storable(p), true, JSON.stringify(p));
      assert.ok(Array.isArray(vd[p]) && vd[p].length > 0);
      assert.equal(new Set(vd[p]).size, vd[p].length);
      vd[p].forEach((c) => assert.equal(typeof c === 'number' || storable(c), true, JSON.stringify(c)));
    });
    Object.keys(dd).forEach((p) => {
      assert.ok(Object.prototype.hasOwnProperty.call(vd, p), `default without links: ${p}`);
      [].concat(dd[p]).forEach((c) => assert.ok(vd[p].includes(c), `default not linked: ${p}`));
    });
    if (name === 'enumeration_save') {
      numbers.filter(([k]) => k !== 'version').forEach(([, n]) => assert.ok(n >= 9200001 && n <= 9299999, String(n)));
      Object.keys(vd).forEach((p) => assert.ok(/^92[0-9]{5}$/.test(p)));
    }
  });
});

test('the payload directory holds exactly the six goldens', () => {
  assert.deepEqual(fs.readdirSync(DIR).sort(), NAMES.map((n) => n + '.json'));
});

test('the goldens cover both default shapes, an inactive link, the clear case and the tricky names', () => {
  const data = Object.fromEntries(NAMES.map((n) => [n, JSON.parse(golden(n, false))]));
  assert.equal(golden('clear', false).endsWith('"value_dependencies":{},"default_value_dependencies":{}}'), true);
  assert.equal(typeof data.list_save.default_value_dependencies.Belgium, 'string');
  assert.ok(Array.isArray(data.import_replace.default_value_dependencies.Belgium));
  assert.deepEqual(data.enumeration_save.value_dependencies['9200001'], [9200004, 9200005, 9200007]);
  assert.deepEqual(data.enumeration_save.default_value_dependencies['9200001'], [9200005, 9200007]);
  assert.deepEqual(data.enumeration_save.value_dependencies['9200003'], [9200004]);
  const tricky = golden('tricky_values', false);
  ['"__proto__":["__proto__"]', '"constructor":["b"]', '"hasOwnProperty":["b"]', '"toJSON":["toJSON"]'].forEach((s) => {
    assert.ok(tricky.includes(s), s);
  });
  const trickyDefaults = data.tricky_values.default_value_dependencies;
  assert.ok(Object.prototype.hasOwnProperty.call(trickyDefaults, '__proto__'));
  assert.equal(trickyDefaults.__proto__, '__proto__');
  assert.ok(tricky.split('"default_value_dependencies":')[1].includes('"__proto__":"__proto__"'));
  const keys = Object.keys(data.tricky_values.value_dependencies);
  TRICKY_PARENTS.forEach((p) => assert.ok(keys.includes(p), JSON.stringify(p)));
  assert.equal(keys.length, TRICKY_PARENTS.length);
  assert.equal(data.import_merge.import.rows, 4);
  assert.equal(data.import_replace.import.rows, 5);
});
