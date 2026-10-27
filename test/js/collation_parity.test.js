'use strict';
// WP-23 (project design 2.7): the editor model's fold() on the shared
// collation fixture, test/js/fixtures/shared/collation_cases.json, which
// ValueCollation (WP-28, spec/lib/dcf_value_collation_spec.rb) reads with
// encoding 'UTF-8' and must fold to the same keys.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const M = require('../../assets/javascripts/dcf_dependency_editor_model.js');

const FILE = path.join(__dirname, 'fixtures', 'shared', 'collation_cases.json');
const CASES = JSON.parse(fs.readFileSync(FILE, 'utf8'));

test('the shared fixture holds 20 [input, expected] pairs of Strings', () => {
  assert.equal(CASES.length, 20, 'case count changed: update WP-28 and this test');
  CASES.forEach((pair) => {
    assert.equal(pair.length, 2);
    pair.forEach((s) => assert.equal(typeof s, 'string'));
  });
  assert.equal(new Set(CASES.map((pair) => pair[0])).size, 20);
});

test('the fixture is UTF-8 without BOM, en dash or em dash, and ends with a newline', () => {
  const bytes = fs.readFileSync(FILE);
  assert.notDeepEqual([...bytes.subarray(0, 3)], [0xef, 0xbb, 0xbf]);
  const text = bytes.toString('utf8');
  assert.equal(Buffer.from(text, 'utf8').equals(bytes), true);
  assert.equal(/[\u2013\u2014\r]/.test(text), false);
  assert.equal(text.endsWith(']\n'), true);
});

CASES.forEach(([input, expected]) => {
  test(`fold(${JSON.stringify(input)}) is ${JSON.stringify(expected)}`, () => {
    assert.equal(M.fold(input), expected);
  });
});

// Not in the 20 shared cases: the white space class (Ruby [[:space:]], not
// JS \s) and the final sigma. WP-28 asserts the same keys in Ruby.
const EXTRA = [
  ['a\ufeffb', 'a\ufeffb'],
  ['\ufeff x \ufeff', '\ufeff x \ufeff'],
  ['a\u2028b', 'a b'],
  ['a\u2029b', 'a b'],
  ['a\u1680b', 'a b'],
  ['a\u0085b', 'a b'],
  ['a\u3000b', 'a b'],
  ['a\u00a0\u202f\u205fb', 'a b'],
  ['\u0000x', '\u0000x'],
  ['x\u0000', 'x\u0000'],
  ['a\u200bb', 'a\u200bb'],
  ['\t\n\v\f\r x \u3000', 'x'],
  ['\u039f\u0394\u039f\u03a3', '\u03bf\u03b4\u03bf\u03c3'],
  ['\u03bf\u03b4\u03bf\u03c2', '\u03bf\u03b4\u03bf\u03c3'],
  ['A\u03a3 B', 'a\u03c3 b'],
  ['\u1e9e', 'ss']
];

EXTRA.forEach(([input, expected]) => {
  test(`fold(${JSON.stringify(input)}) is ${JSON.stringify(expected)} (white space and sigma rule)`, () => {
    assert.equal(M.fold(input), expected);
  });
});
