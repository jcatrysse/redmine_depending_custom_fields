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

// WP-39 (R1): a mapping is the JSON text of a <script type="application/json">
// after its control, which names its data-dcf-map-id in data-dcf-map-ref. jsonEscape mirrors
// ERB::Util.json_escape (< > & U+2028 U+2029 as \u escapes).
const JSON_ESCAPES = { '<': '\\u003c', '>': '\\u003e', '&': '\\u0026', '\u2028': '\\u2028', '\u2029': '\\u2029' };
const jsonEscape = (text) => text.replace(/[<>&\u2028\u2029]/g, (c) => JSON_ESCAPES[c]);
// The script element markup of a mapping (an object, or raw text as given).
const mapScript = (id, value) =>
  `<script type="application/json" data-dcf-map-id="${id}">${typeof value === 'string' ? value : jsonEscape(JSON.stringify(value))}</script>`;
// The mapping script a control of a tweak document names, or null.
const mapScriptOf = (doc, ctl) => {
  const ref = ctl.getAttribute('data-dcf-map-ref');
  return ref === null ? null : Array.from(doc.querySelectorAll('script')).find((s) => s.getAttribute('data-dcf-map-id') === ref) || null;
};
// Replaces the mapping text of a control in a tweak document (an object, or raw text).
const setMap = (doc, ctl, value) => {
  mapScriptOf(doc, ctl).textContent = typeof value === 'string' ? value : JSON.stringify(value);
};

module.exports = {
  DIR, files, scenarios, file, read, tweak, selectValues, checkValues, named, jsonEscape, mapScript, mapScriptOf, setMap
};
