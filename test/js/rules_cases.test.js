'use strict';
// WP-17: the shared rule cases (test/js/fixtures/shared/rules_cases.json, read
// by spec/lib/dependency_rules_spec.rb too) give the same allowed, default and
// D1 results in the JS rules as in DependencyRules.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const R = require('../../assets/javascripts/depending_custom_fields.js');

// JSON.parse keeps __proto__ and the integer-like keys as plain keys.
const CASES = JSON.parse(fs.readFileSync(path.join(__dirname, 'fixtures', 'shared', 'rules_cases.json'), 'utf8'));
const COUNTS = { allowed: 17, defaults: 14, d1: 22 };

test('the shared table has version 1 and the expected sections and row counts', () => {
  assert.equal(CASES.version, 1);
  Object.keys(COUNTS).forEach((section) => {
    assert.ok(Array.isArray(CASES[section]), section);
    assert.equal(CASES[section].length, COUNTS[section], `${section} rows changed: update this test`);
  });
  const ids = Object.keys(COUNTS).flatMap((s) => CASES[s].map((r) => r.id));
  assert.equal(new Set(ids).size, ids.length);
});

(CASES.allowed || []).forEach((row) => {
  test(`allowed: ${row.id}`, () => {
    assert.deepEqual(Array.from(R.allowedFor(R.normalizeMap(row.map), row.parent)), row.expected);
  });
});

(CASES.defaults || []).forEach((row) => {
  test(`defaults: ${row.id}`, () => {
    const allowed = R.allowedFor(R.normalizeMap(row.map), row.parent);
    const values = R.defaultsFor(R.normalizeDefaults(row.defaults), row.parent, allowed);
    assert.deepEqual(values, row.expected_multiple);
    assert.equal(values[0] === undefined ? null : values[0], row.expected_single);
  });
});

// The client input the server emits for a d1 row: data-dcf-stored is
// {child: child_was, parent: parent_was}; while the parent is not available
// the parent control is absent, data-dcf-parent-values is [] and the stored
// child is [] (UD-05, ClientData).
function clientInput(row) {
  const available = row.parent_available !== false;
  const stored = R.normalizeStored({ child: available ? row.child_was : [], parent: row.parent_was });
  const ps = available ? R.parentState('form', true, row.parent, null) : R.parentState('form', false, [], []);
  const map = R.normalizeMap(row.map);
  const allowed = R.allowedFor(map, ps.values);
  const input = { ctx: 'form', kind: ps.kind, values: ps.values, stored };
  return { ps, stored, allowed, eligible: R.legacyEligible(input, allowed) };
}

// Valid exactly when every child value is allowed or tolerated (each once).
function clientValid(row, c, values) {
  return Array.from(new Set(values.filter((v) => !R.isBlank(v)))).every((v) => c.allowed.has(v) || c.eligible.has(v));
}

(CASES.d1 || []).forEach((row) => {
  test(`d1: ${row.id}`, () => {
    const c = clientInput(row);
    assert.equal(clientValid(row, c, row.child), row.valid, 'the client rule equals DependencyRules');
    // The runtime decision on the rendered child never posts what the server refuses.
    const options = new Set([''].concat(row.child, row.child_was, Object.keys(row.map).flatMap((k) => [].concat(row.map[k]).map(String))));
    const d = R.decide({
      ctx: 'form', kind: c.ps.kind, key: c.ps.key, values: c.ps.values, prevValues: [], allowed: c.allowed,
      current: row.child.length ? row.child : [''], initial: true, parentChanged: false, multiple: row.multiple,
      hasBlank: true, hasNone: false, noneRequired: false, optionValues: options, defaults: new Map(),
      memory: new Map(), hide: false, stored: c.stored
    });
    const posted = d.values.filter((v) => !R.isBlank(v));
    assert.ok(clientValid(row, c, posted), `posted ${JSON.stringify(posted)}`);
    if (row.valid) assert.deepEqual(posted, Array.from(new Set(row.child.filter((v) => !R.isBlank(v)))));
  });
});
