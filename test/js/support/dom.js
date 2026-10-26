'use strict';
// WP-17 runtime pages: JSDOM with runScripts 'outside-only', the runtime
// (assets/javascripts/depending_custom_fields.js) evaluated after the markup,
// optional jQuery 3.7.1 and an optional <meta name="dcf-i18n">. page()
// resolves after DOMContentLoaded, when the runtime ran its start(). With
// head: true jQuery and the runtime sit in <head> (runScripts 'dangerously',
// the real page order) and page() resolves after load. WP-18: scripts (more
// sources, evaluated after the runtime in this order, as the head hook
// includes context_menu_wizard.js) and url (the page URL; jsdom's default
// about:blank has the origin 'null').
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM, VirtualConsole } = require('jsdom');

const RUNTIME_PATH = path.join(__dirname, '..', '..', '..', 'assets', 'javascripts', 'depending_custom_fields.js');
const RUNTIME = fs.readFileSync(RUNTIME_PATH, 'utf8');
const WIZARD_PATH = path.join(__dirname, '..', '..', '..', 'assets', 'javascripts', 'context_menu_wizard.js');
const WIZARD = fs.readFileSync(WIZARD_PATH, 'utf8');
const JQUERY = fs.readFileSync(require.resolve('jquery/dist/jquery.js'), 'utf8');
const OPEN = [];

const escAttr = (s) => String(s).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');

// meta: an object (written as its JSON) or a raw content string.
function metaTag(meta) {
  if (meta === undefined || meta === null) return '';
  const content = typeof meta === 'string' ? meta : JSON.stringify(meta);
  return `<meta name="dcf-i18n" content="${escAttr(content)}">`;
}

// Deterministic per-window clock: replaces window.setTimeout/clearTimeout.
// calls counts every setTimeout made through it.
function installClock(window) {
  let now = 0;
  let seq = 0;
  const timers = new Map();
  const clock = {
    calls: 0,
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
  window.setTimeout = (fn, ms) => {
    clock.calls += 1;
    seq += 1;
    timers.set(seq, { fn, at: now + (Number(ms) || 0) });
    return seq;
  };
  window.clearTimeout = (handle) => { timers.delete(handle); };
  return clock;
}

function virtualConsole(errors) {
  const vc = new VirtualConsole();
  vc.on('jsdomError', (e) => errors.push(e.cause || e));
  return vc;
}

// Capture-phase collectors: every change event (name of the target) and
// every dcf:updated detail (with its target).
function collect(window) {
  const changes = [];
  const updates = [];
  window.document.addEventListener('change', (e) => changes.push(e.target.name || e.target.id || e.target.tagName), true);
  window.document.addEventListener('dcf:updated', (e) => updates.push(Object.assign({ target: e.target }, e.detail)), true);
  return { changes, updates };
}

function ready(window, event) {
  return new Promise((resolve) => {
    const done = event === 'load' ? window.document.readyState === 'complete' : window.document.readyState !== 'loading';
    if (done) resolve();
    else window.addEventListener(event, () => resolve(), { once: true });
  });
}

function result(window, clock, errors, c) {
  OPEN.push(window);
  return { window, document: window.document, clock, errors, changes: c.changes, updates: c.updates };
}

// opts: jquery (default true), clock (default true), meta, before(window)
// (runs before the runtime is evaluated), twice (evaluate the runtime twice),
// runtime (source to evaluate instead of the asset), head, scripts, url,
// headHtml (raw head markup instead of the meta tag, for the head fixtures).
function page(body, opts) {
  const o = Object.assign({ jquery: true, clock: true, scripts: [] }, opts || {});
  const source = o.runtime || RUNTIME;
  const errors = [];
  const urlOption = o.url ? { url: o.url } : {};
  const headStart = o.headHtml !== undefined ? o.headHtml : metaTag(o.meta);
  if (o.head) {
    let clock = null;
    let c = null;
    const head = headStart + (o.jquery ? `<script>${JQUERY}</script>` : '') + `<script>${source}</script>` +
      o.scripts.map((s) => `<script>${s}</script>`).join('');
    const dom = new JSDOM(`<!doctype html><html><head>${head}</head><body>${body}</body></html>`, {
      ...urlOption,
      runScripts: 'dangerously',
      virtualConsole: virtualConsole(errors),
      beforeParse(window) {
        if (o.clock) clock = installClock(window);
        c = collect(window);
        if (o.before) o.before(window);
      }
    });
    return ready(dom.window, 'load').then(() => result(dom.window, clock, errors, c));
  }
  const dom = new JSDOM(`<!doctype html><html><head>${headStart}</head><body>${body}</body></html>`,
    { ...urlOption, runScripts: 'outside-only', virtualConsole: virtualConsole(errors) });
  const window = dom.window;
  const clock = o.clock ? installClock(window) : null;
  if (o.jquery) window.eval(JQUERY);
  if (o.before) o.before(window);
  const c = collect(window);
  window.eval(source);
  if (o.twice) window.eval(source);
  o.scripts.forEach((s) => window.eval(s));
  return ready(window, 'DOMContentLoaded').then(() => result(window, clock, errors, c));
}

// Closes every window opened by page() (node:test afterEach).
function closeAll() {
  while (OPEN.length) OPEN.pop().close();
}

// One microtask turn: MutationObserver callbacks queued so far have run.
const microtask = () => Promise.resolve();
// One macrotask turn.
const flush = () => new Promise((resolve) => setImmediate(resolve));

// The control carrying data-dcf-field="<id>" (optionally within root or with
// a name prefix).
function control(root, fieldId, prefix) {
  const list = Array.from(root.querySelectorAll(`[data-dcf-field="${fieldId}"]`));
  if (!prefix) return list[0] || null;
  return list.find((el) => {
    const input = el.tagName === 'SELECT' ? el : el.querySelector('input[name]');
    return input && input.name.startsWith(`${prefix}[`);
  }) || null;
}

// The select or input named exactly name (or name plus []), never hidden.
function byName(root, name) {
  return Array.from(root.querySelectorAll('select, input'))
    .find((el) => (el.name === name || el.name === `${name}[]`) && el.type !== 'hidden') || null;
}

const choices = (ctl) => Array.from(ctl.querySelectorAll('input')).filter((i) => i.type === 'radio' || i.type === 'checkbox');
// slice, not Array.from: jsdom iterates a live options collection slowly.
const options = (select) => Array.prototype.slice.call(select.options);
const items = (ctl) => (ctl.tagName === 'SELECT' ? options(ctl) : choices(ctl));
const selected = (ctl) => items(ctl).filter((o) => (ctl.tagName === 'SELECT' ? o.selected : o.checked)).map((o) => o.value);
const enabled = (ctl) => items(ctl).filter((o) => !o.disabled).map((o) => o.value);
const disabled = (ctl) => items(ctl).filter((o) => o.disabled).map((o) => o.value);
// Values whose option (select) or wrapping label (group) carries [hidden].
const hiddenValues = (ctl) => items(ctl).filter((o) => (ctl.tagName === 'SELECT' ? o : (o.closest('label') || o)).hidden).map((o) => o.value);
const state = (ctl) => ctl.getAttribute('data-dcf-state');

// The visible hint of a control (em.dcf-hint referenced by aria-describedby), or null.
function hint(ctl) {
  const target = ctl.tagName === 'SELECT' ? ctl : choices(ctl)[0];
  const ids = (target.getAttribute('aria-describedby') || '').split(/\s+/).filter(Boolean);
  const doc = ctl.ownerDocument;
  for (const id of ids) {
    const el = doc.getElementById(id);
    if (el && el.classList.contains('dcf-hint')) return el;
  }
  return null;
}
// Every hint element in the box of a control, visible or not.
const hintElements = (ctl) => Array.from((ctl.closest('p, .cf-wizard-field') || ctl.parentNode).querySelectorAll('em.dcf-hint'));
const hintText = (ctl) => { const h = hint(ctl); return h && !h.hidden ? h.textContent : null; };

module.exports = {
  RUNTIME, RUNTIME_PATH, WIZARD, WIZARD_PATH, JQUERY, metaTag, installClock, page, closeAll, microtask, flush,
  control, byName, choices, items, selected, enabled, disabled, hiddenValues, state, hint, hintElements, hintText
};
