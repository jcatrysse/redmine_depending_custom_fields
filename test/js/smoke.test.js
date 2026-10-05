'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');
test('current runtime loads in jsdom without throwing', () => {
  const dom = new JSDOM('<!doctype html><html><body></body></html>', { runScripts: 'outside-only' });
  dom.window.eval(fs.readFileSync(require.resolve('jquery/dist/jquery.js'), 'utf8'));
  dom.window.eval(fs.readFileSync(path.join(__dirname, '..', '..', 'assets', 'javascripts', 'depending_custom_fields.js'), 'utf8'));
  assert.equal(typeof dom.window.DependingCustomFields, 'object');
});
