'use strict';
// Fixtures for test/js/legacy_characterization.test.js: core-like markup
// (Redmine 7.0 lib/redmine/field_format.rb List#edit_tag / #bulk_edit_tag,
// app/helpers/custom_fields_helper.rb) and JSDOM pages that load the legacy
// runtime. Deleted by WP-18 together with the characterization file.
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM, VirtualConsole } = require('jsdom');

const ASSETS = path.join(__dirname, '..', '..', '..', 'assets', 'javascripts');
const SCRIPT = fs.readFileSync(path.join(ASSETS, 'depending_custom_fields.js'), 'utf8');
const WIZARD = fs.readFileSync(path.join(ASSETS, 'context_menu_wizard.js'), 'utf8');
const JQUERY = fs.readFileSync(require.resolve('jquery/dist/jquery.js'), 'utf8');

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');
// ActionView sanitize_to_id: drop "]", every other non [-a-zA-Z0-9:.] becomes "_".
const sanitizeToId = (name) => String(name).replace(/\]/g, '').replace(/[^-a-zA-Z0-9:.]/g, '_');
const tagName = (prefix, id, multiple) => `${prefix}[custom_field_values][${id}]${multiple ? '[]' : ''}`;
const tagId = (prefix, id) => `${prefix}_custom_field_values_${id}`;
const attrs = (o) => Object.keys(o || {}).map((k) => ` ${k}="${esc(o[k])}"`).join('');
const options = (pairs, selected) => pairs.map(([label, value]) => {
  const sel = selected.includes(value) ? ' selected="selected"' : '';
  return `<option value="${esc(value)}"${sel}>${label}</option>`;
}).join('');

// List#select_edit_tag. Single, not required: blank "&nbsp;" option. Single,
// required, no default: "--- Please select ---". Multiple: no blank option and
// a hidden_field_tag(tag_name, '') after the select (its id is sanitize_to_id).
function editSelect(prefix, id, values, opts) {
  const o = opts || {};
  const name = o.name || tagName(prefix, id, o.multiple);
  const selected = [].concat(o.selected || []);
  let blank = '';
  if (!o.multiple) {
    if (!o.required) blank = '<option value="">&nbsp;</option>';
    else if (!o.hasDefault) blank = '<option value="">--- Please select ---</option>';
  }
  const idAttr = o.id === null ? '' : ` id="${esc(o.id || tagId(prefix, id))}"`;
  let html = `<select name="${esc(name)}"${idAttr}${o.multiple ? ' multiple="multiple"' : ''}${attrs(o.attrs)}>` +
    blank + options(values.map((v) => [v, v]), selected) + '</select>';
  if (o.multiple) {
    html += `<input type="hidden" name="${esc(name)}" id="${sanitizeToId(name)}" value="" autocomplete="off" />`;
  }
  return html;
}

// List#check_box_edit_tag. Multiple: check boxes plus a trailing hidden ''.
// Single: radios, with a "(none)" '' radio unless required. No ids.
function editCheckBoxes(prefix, id, values, opts) {
  const o = opts || {};
  const name = tagName(prefix, id, o.multiple);
  const checked = [].concat(o.checked || []);
  const pairs = (!o.multiple && !o.required ? [['(none)', '']] : []).concat(values.map((v) => [v, v]));
  const type = o.multiple ? 'checkbox' : 'radio';
  let html = pairs.map(([label, value]) => {
    const chk = checked.includes(value) ? ' checked="checked"' : '';
    return `<label><input type="${type}" name="${esc(name)}" value="${esc(value)}"${chk} /> ${label}</label>`;
  }).join('');
  if (o.multiple) html += `<input type="hidden" name="${esc(name)}" value="" autocomplete="off" />`;
  return `<span class="check_box_group">${html}</span>`;
}

// List#bulk_edit_tag: select_tag(tag_name, ...) without an explicit id, so the
// id is sanitize_to_id(tag_name) ("..._2_" for a multiple field). Options:
// "(No change)" '' unless multiple, "none" __none__ unless required, values.
function bulkSelect(prefix, id, values, opts) {
  const o = opts || {};
  const name = tagName(prefix, id, o.multiple);
  const pairs = [];
  if (!o.multiple) pairs.push(['(No change)', '']);
  if (!o.required) pairs.push(['none', '__none__']);
  values.forEach((v) => pairs.push([v, v]));
  const extra = o.dataFieldId ? ` data-field-id='${esc(o.dataFieldId)}'` : '';
  return `<select${extra} name="${esc(name)}" id="${sanitizeToId(name)}"${o.multiple ? ' multiple="multiple"' : ''}>` +
    options(pairs, [].concat(o.selected || [])) + '</select>';
}

const field = (label, html, pAttrs) => `<p${attrs(pAttrs)}><label>${label}</label>${html}</p>`;

// Deterministic per-window clock: replaces window.setTimeout/clearTimeout (the
// legacy script resolves the bare identifiers against the window).
function installClock(window) {
  let now = 0;
  let seq = 0;
  const timers = new Map();
  window.setTimeout = (fn, ms) => {
    seq += 1;
    timers.set(seq, { fn, at: now + (Number(ms) || 0) });
    return seq;
  };
  window.clearTimeout = (handle) => { timers.delete(handle); };
  return {
    pending: () => timers.size,
    tick(ms) {
      const end = now + ms;
      for (;;) {
        let next = null;
        timers.forEach((t, k) => { if (t.at <= end && (!next || t.at < next[1].at)) next = [k, t]; });
        if (!next) break;
        timers.delete(next[0]);
        now = next[1].at;
        next[1].fn();
      }
      now = end;
    }
  };
}

function collectors(window) {
  const changes = [];
  window.document.addEventListener('change', (e) => {
    const t = e.target;
    changes.push(t.id || t.name || t.tagName);
  }, true);
  return changes;
}

function virtualConsole(errors) {
  const vc = new VirtualConsole();
  vc.on('jsdomError', (e) => errors.push(e.cause || e));
  return vc;
}

// Existing convention: runScripts 'outside-only', eval after parsing, then an
// explicit setup(). Pass mapping: undefined to leave the global unset.
function legacyPage(body, opts) {
  const o = Object.assign({ setup: true, clock: true }, opts || {});
  const errors = [];
  const dom = new JSDOM(`<!doctype html><html><head></head><body>${body}</body></html>`,
    { runScripts: 'outside-only', virtualConsole: virtualConsole(errors) });
  const window = dom.window;
  const clock = o.clock ? installClock(window) : null;
  if (o.jquery) window.eval(JQUERY);
  if (o.mapping !== undefined) window.DependingCustomFieldData = o.mapping;
  const changes = collectors(window);
  window.eval(SCRIPT);
  if (o.wizard) window.eval(WIZARD);
  if (o.setup) window.DependingCustomFields.setup();
  return { window, document: window.document, clock, changes, errors };
}

// Real page order: the head hook emits <script src=legacy>, an inline script
// that defines the globals, then <script src=wizard>; all run while the body
// does not exist yet. The scripts are inlined (runScripts 'dangerously').
// Resolves after the load event, so the script already ran its own
// DOMContentLoaded setup(). wizardConfig: false omits ContextMenuWizardConfig.
function headPage(body, opts) {
  const o = opts || {};
  const errors = [];
  let clock = null;
  let changes = null;
  let globals = '';
  if (o.mapping !== undefined) globals += `window.DependingCustomFieldData = ${JSON.stringify(o.mapping)};\n`;
  if (o.wizardConfig !== false) {
    globals += `window.ContextMenuWizardConfig = ${JSON.stringify({ basePath: o.basePath || '' })};\n`;
  }
  const head = (o.jquery ? `<script>${JQUERY}</script>` : '') +
    `<script>window.bodyAtLoad = !!document.body;\n${SCRIPT}</script>` +
    `<script>${globals}</script>` + (o.wizard ? `<script>${WIZARD}</script>` : '');
  const dom = new JSDOM(`<!doctype html><html><head>${head}</head><body>${body}</body></html>`, {
    runScripts: 'dangerously',
    virtualConsole: virtualConsole(errors),
    beforeParse(window) {
      if (o.clock !== false) clock = installClock(window);
      changes = collectors(window);
    }
  });
  const window = dom.window;
  return loaded(window).then(() => ({ window, document: window.document, clock, changes, errors }));
}

// Resolves once the document fired load (DOMContentLoaded already ran).
function loaded(window) {
  return new Promise((resolve) => {
    if (window.document.readyState === 'complete') resolve();
    else window.addEventListener('load', () => resolve());
  });
}

// One macrotask turn: every pending microtask (MutationObserver records) ran.
const flush = () => new Promise((resolve) => setImmediate(resolve));

// FormData entries of a form as "name=value", optionally filtered by a name prefix.
function entries(window, form, keyPrefix) {
  const f = form || window.document.forms[0];
  return Array.from(new window.FormData(f).entries())
    .filter(([key]) => !keyPrefix || key.startsWith(keyPrefix))
    .map(([key, value]) => `${key}=${value}`);
}

// Select the given value(s) (select) or check them (check box / radio group)
// and fire a bubbling change, as a user would.
function choose(window, el, value) {
  const vals = [].concat(value).map(String);
  if (el.tagName === 'SELECT') {
    if (el.multiple) Array.from(el.options).forEach((opt) => { opt.selected = vals.includes(opt.value); });
    else el.value = vals[0] || '';
    el.dispatchEvent(new window.Event('change', { bubbles: true }));
    return;
  }
  const inputs = Array.from(el.querySelectorAll('input[type="checkbox"], input[type="radio"]'));
  inputs.forEach((input) => { input.checked = vals.includes(input.value); });
  (inputs.find((i) => i.checked) || inputs[0]).dispatchEvent(new window.Event('change', { bubbles: true }));
}

const visibleOptions = (select) => Array.from(select.options).filter((o) => !o.hidden).map((o) => o.value);
const hiddenOptions = (select) => Array.from(select.options).filter((o) => o.hidden).map((o) => o.value);
const selectedValues = (select) => Array.from(select.options).filter((o) => o.selected).map((o) => o.value);

module.exports = {
  SCRIPT, WIZARD, JQUERY, sanitizeToId, tagName, tagId,
  editSelect, editCheckBoxes, bulkSelect, field,
  installClock, legacyPage, headPage, loaded, flush, entries, choose,
  visibleOptions, hiddenOptions, selectedValues
};
