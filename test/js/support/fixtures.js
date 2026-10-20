'use strict';
// Generated markup fixtures (spec/frontend/markup_fixtures_spec.rb, WP-16):
// test/js/fixtures/markup/<scenario>.html, or <scenario>.redmine-<x.y>.html
// when that version renders differently. tweak() edits a fixture before it is
// loaded, so row tests derive from generated markup.
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');

const DIR = path.join(__dirname, '..', 'fixtures', 'markup');
const VARIANT = /(\.redmine-\d+\.\d+)?\.html$/;

const files = () => (fs.existsSync(DIR) ? fs.readdirSync(DIR).filter((f) => f.endsWith('.html')).sort() : []);
const scenarios = () => Array.from(new Set(files().map((f) => f.replace(VARIANT, '')))).sort();

// The variant of version (x.y) when it exists, else the base file.
function file(scenario, version) {
  if (version) {
    const variant = path.join(DIR, `${scenario}.redmine-${version}.html`);
    if (fs.existsSync(variant)) return variant;
  }
  return path.join(DIR, `${scenario}.html`);
}

const read = (scenario, version) => fs.readFileSync(file(scenario, version), 'utf8');

// Parses a scenario (or markup) without running scripts, lets fn edit the
// document and returns the body markup.
function tweak(source, fn) {
  const html = source.includes('<') ? source : read(source);
  const dom = new JSDOM(`<!doctype html><html><head></head><body>${html}</body></html>`);
  fn(dom.window.document, dom.window);
  return dom.window.document.body.innerHTML;
}

// Sets the selected attributes of a select (markup level).
function selectValues(select, values) {
  const vals = [].concat(values).map(String);
  Array.from(select.options).forEach((o) => {
    if (vals.includes(o.value)) o.setAttribute('selected', 'selected');
    else o.removeAttribute('selected');
  });
}

// Sets the checked attributes of the choice inputs of a group (markup level).
function checkValues(group, values) {
  const vals = [].concat(values).map(String);
  Array.from(group.querySelectorAll('input')).filter((i) => i.type === 'radio' || i.type === 'checkbox').forEach((i) => {
    if (vals.includes(i.value)) i.setAttribute('checked', 'checked');
    else i.removeAttribute('checked');
  });
}

// The element named name in a tweak document.
const named = (doc, name) => Array.from(doc.querySelectorAll('select, input')).find((el) => el.name === name) || null;

module.exports = { DIR, files, scenarios, file, read, tweak, selectValues, checkValues, named };
