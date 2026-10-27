'use strict';
// WP-25: jsdom pages for the dependency editor DOM layer
// (assets/javascripts/dcf_dependency_editor.js) on the generated editor
// fixtures (test/js/fixtures/editor/, WP-24). The admin scenarios are wrapped
// in a core-like form#custom_field_form with the source controls the root
// names (-parent-source, -values-source, -multiple-source,
// -required-source, -format-source, -default-value-row); the project
// scenarios in a multipart form with a disabled [data-dcf-editor-submit]
// button. window.fetch and window.confirm are stubs; the page URL is
// http://redmine.test so the same-origin check has a real origin.
const fs = require('node:fs');
const path = require('node:path');
const { page, closeAll, flush, microtask } = require('./dom');

const ASSETS = path.join(__dirname, '..', '..', '..', 'assets', 'javascripts');
const MODEL = fs.readFileSync(path.join(ASSETS, 'dcf_dependency_editor_model.js'), 'utf8');
const EDITOR_PATH = path.join(ASSETS, 'dcf_dependency_editor.js');
const FIXTURES = path.join(__dirname, '..', 'fixtures', 'editor');
const ORIGIN = 'http://redmine.test';
const LIST_VALUES = ['Antwerp', 'Brussels', 'Paris', 'Lyon'];

// Read per page: a missing asset gives failing tests, not a load error.
const editorSource = () => (fs.existsSync(EDITOR_PATH) ? fs.readFileSync(EDITOR_PATH, 'utf8') : '');

function fixture(name, variant) {
  return fs.readFileSync(path.join(FIXTURES, `${name}${variant ? '.redmine-5.1' : ''}.html`), 'utf8');
}

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;');

// The admin form around +html+ (the editor fieldset), in the order of the
// admin partials (UX-11). o: values (textarea lines, list kind only),
// parents ([[id, name]]), parent (selected id, '' for none), multiple,
// required, format, formatEnabled.
function adminForm(html, o) {
  const parents = [['', '']].concat(o.parents)
    .map(([id, name]) => `<option value="${esc(id)}"${id === o.parent ? ' selected' : ''}>${esc(name)}</option>`).join('');
  const values = o.values === null ? '' :
    `<p><textarea name="custom_field[possible_values]" id="custom_field_possible_values">${esc(o.values.join('\n'))}</textarea></p>`;
  return `<div id="content"><form id="custom_field_form" action="/custom_fields/9100002" method="post" accept-charset="UTF-8">
<input type="hidden" name="_method" value="put"><input type="hidden" name="authenticity_token" value="token-1">
<div class="box tabular">
<p><select name="custom_field[field_format]" id="custom_field_field_format"${o.formatEnabled ? '' : ' disabled'}>
<option value="${esc(o.format)}" selected>Format</option><option value="string">Text</option></select></p>
<p><input type="text" name="custom_field[name]" id="custom_field_name" value="City"></p>
<p><input type="hidden" name="custom_field[multiple]" value="0"><input type="checkbox" name="custom_field[multiple]" id="custom_field_multiple" value="1"${o.multiple ? ' checked' : ''}></p>
${values}
<p data-dcf-default-value-row class="${o.parent ? 'dcf-hidden' : ''}"><input type="text" name="custom_field[default_value]" id="custom_field_default_value" value=""></p>
<p><select name="custom_field[parent_custom_field_id]" id="custom_field_parent_custom_field_id">${parents}</select></p>
<p><input type="hidden" name="custom_field[hide_when_disabled]" value="0"><input type="checkbox" name="custom_field[hide_when_disabled]" value="1"></p>
${html}
</div>
<p><input type="hidden" name="custom_field[is_required]" value="0"><input type="checkbox" name="custom_field[is_required]" id="custom_field_is_required" value="1"${o.required ? ' checked' : ''}></p>
<p class="mobile-hide"><input type="submit" name="commit" value="Save" data-disable-with="Save"></p>
</form></div>`;
}

function projectForm(html) {
  return `<div id="content"><form id="dcf_dependencies_form" action="/projects/p/custom_field_configuration/9100002/dependencies" method="post" enctype="multipart/form-data">
<input type="hidden" name="_method" value="patch"><input type="hidden" name="authenticity_token" value="token-1">
${html}
<p><input type="submit" name="commit" value="Save" data-dcf-editor-submit disabled></p>
</form></div>`;
}

function defaults(name, html) {
  const parentId = (html.match(/data-dcf-editor-parent-id="(\d+)"/) || [])[1] || '';
  const enumeration = /data-dcf-editor-kind="enumeration"/.test(html);
  return {
    values: enumeration ? null : (name === 'admin_new' ? ['One', 'Two'] : LIST_VALUES.slice()),
    parents: parentId ? [[parentId, 'Country'], ['9100050', 'Other']] : [['9100001', 'Country'], ['9100050', 'Other']],
    parent: parentId,
    multiple: /data-dcf-editor-multiple="1"/.test(html),
    required: /data-dcf-editor-required="1"/.test(html),
    format: enumeration ? 'depending_enumeration' : 'depending_list',
    formatEnabled: !/data-dcf-editor-field-id=/.test(html)
  };
}

// opts: variant (the .redmine-5.1 file), bare (no form), form (overrides
// for adminForm), tweak(root, document, window) before the editor runs,
// fetch(url, init) returning a Promise, confirm, noModel, noEditor, twice,
// lang (default 'en'), before(window).
async function load(name, opts) {
  const o = opts || {};
  const html = o.html || fixture(name, o.variant);
  const mode = (html.match(/data-dcf-editor-mode="(\w+)"/) || [])[1];
  let body = html;
  if (!o.bare) body = mode === 'project' ? projectForm(html) : adminForm(html, Object.assign(defaults(name, html), o.form || {}));
  const fetchCalls = [];
  const warns = [];
  const source = editorSource();
  const scripts = o.noEditor ? [] : (o.twice ? [source, source] : [source]);
  const res = await page(body, {
    jquery: true,
    clock: true,
    url: `${ORIGIN}/custom_fields/9100002/edit`,
    runtime: o.noModel ? '/* no model */' : MODEL,
    scripts,
    before(window) {
      window.document.documentElement.setAttribute('lang', o.lang || 'en');
      window.fetch = (url, init) => {
        fetchCalls.push({ url: String(url), init });
        return o.fetch ? o.fetch(String(url), init) : new Promise(() => {});
      };
      window.confirm = o.confirm || (() => true);
      window.console.warn = (...args) => warns.push(args.join(' '));
      window.HTMLAnchorElement.prototype.click = function () { window.__dcfClicked = this.getAttribute('download'); };
      const root = window.document.querySelector('[data-dcf-editor]');
      if (o.tweak) o.tweak(root, window.document, window);
      if (o.before) o.before(window);
    }
  });
  const { window, document } = res;
  const root = document.querySelector('[data-dcf-editor]');
  const form = document.querySelector('form');
  const input = root.querySelector('[data-dcf-editor-input]');
  let i18n = {};
  try {
    i18n = JSON.parse(root.getAttribute('data-dcf-editor-i18n'));
  } catch (e) {
    // the inert tests break the attribute on purpose
  }
  const t = (key, vars) => String(i18n[key] === undefined ? `[${key}]` : i18n[key])
    .replace(/%\{([a-z_]+)\}/g, (m, k) => (vars && k in vars ? String(vars[k]) : m));
  const fire = (el, type, init) => {
    const ev = new window.Event(type, Object.assign({ bubbles: true, cancelable: true }, init || {}));
    el.dispatchEvent(ev);
    return ev;
  };
  const key = (el, k) => {
    const ev = new window.KeyboardEvent('keydown', { key: k, bubbles: true, cancelable: true });
    el.dispatchEvent(ev);
    return ev;
  };
  return Object.assign(res, {
    root,
    form,
    input,
    i18n,
    t,
    fire,
    key,
    fetchCalls,
    warns,
    editor: () => (window.DcfDependencyEditor ? window.DcfDependencyEditor.get(root) : null),
    sections: () => Array.from(root.querySelectorAll('details.dcf-dep-section')),
    section: (k) => Array.from(root.querySelectorAll('details.dcf-dep-section'))
      .find((d) => d.getAttribute('data-dcf-ed-section') === k) || null,
    open(details) {
      details.open = true;
      details.dispatchEvent(new window.Event('toggle'));
      return details;
    },
    close(details) {
      details.open = false;
      details.dispatchEvent(new window.Event('toggle'));
    },
    rows: (details) => Array.from(details.querySelectorAll('input[data-dcf-ed-child-key]')),
    box: (details, k) => Array.from(details.querySelectorAll('input[data-dcf-ed-child-key]'))
      .find((b) => b.getAttribute('data-dcf-ed-child-key') === k) || null,
    tick(details, k, on) {
      const box = Array.from(details.querySelectorAll('input[data-dcf-ed-child-key]'))
        .find((b) => b.getAttribute('data-dcf-ed-child-key') === k);
      box.checked = on !== false;
      fire(box, 'change');
      return box;
    },
    payload: () => JSON.parse(input.value),
    notice: (id) => root.querySelector(`[data-dcf-ed-notice="${id}"]`),
    alerts: () => Array.from(root.querySelectorAll('[role=alert]')),
    submit() {
      return fire(form, 'submit');
    },
    named: () => Array.from(form.elements).filter((e) => e.name).map((e) => e.name)
  });
}

// A fetch Response stand-in.
function response(status, body) {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: () => (body === undefined ? Promise.reject(new SyntaxError('empty')) : Promise.resolve(body))
  };
}

function deferred() {
  let resolve;
  const promise = new Promise((r) => { resolve = r; });
  return { promise, resolve };
}

module.exports = { load, fixture, response, deferred, closeAll, flush, microtask, editorSource, MODEL, EDITOR_PATH, ORIGIN, LIST_VALUES };
