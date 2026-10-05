'use strict';
// Must match spec/support/dcf_large_list.rb (pinned in spec/quality/dcf_large_list_spec.rb).
const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const L = require('./support/large_list');

const sha16 = (text) => crypto.createHash('sha256').update(text, 'utf8').digest('hex').slice(0, 16);

test('names(5570, trickyEvery 97) is byte-identical to the Ruby generator', () => {
  assert.equal(sha16(L.names(5570, { trickyEvery: 97 }).join('\n')), '233acf899217e962');
});

test('the 27 x 5,570 partition is byte-identical to the Ruby generator', () => {
  const parents = L.names(27, { prefix: 'P' });
  const children = L.names(5570, { trickyEvery: 97 });
  assert.equal(sha16(JSON.stringify(L.partition(parents, children))), '466b240daca61be9');
});

test('sizes() matches the Ruby generator', () => {
  assert.equal(sha16(L.sizes(25000, 5000).join(',')), '63b3c3c03829ed24');
  assert.equal(sha16(L.sizes(1000, 7).join(',')), '3cf77e9fea249ba6');
});
