'use strict';
// WP-17: the UMD wrapper, the public API and the wiring of the runtime
// (frontend design 5.1, 5.7, 5.9, 5.11, 5.12, 11): globals, load guard,
// listeners, events, cycles, observer, deprecated shims, i18n, rows X1..X8.
const { test, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');
const D = require('./support/dom');
const E = require('./support/entries');
const F = require('./support/fixtures');
const fire = require('./support/fire');

afterEach(D.closeAll);

const ROOT = path.join(__dirname, '..', '..');
const PARENT = 'issue[custom_field_values][9100001]';
const CHILD = 'issue[custom_field_values][9100002]';
const load = (source, opts) => D.page(source.includes('<') ? source : F.read(source), opts);
const child = (pg, id) => D.control(pg.document, id || '9100002');
const parentOf = (pg) => D.byName(pg.document, PARENT);

// Every change and dcf:updated in dispatch order, as "type:name-or-field".
function eventLog(pg) {
  const log = [];
  pg.document.addEventListener('change', (e) => log.push(`change:${e.target.name}`), true);
  pg.document.addEventListener('dcf:updated', (e) => log.push(`updated:${e.detail.fieldId}`), true);
  return log;
}

// Hand-written: two fields that name each other as parent (a DOM cycle, as
// markup rendered during a race with a cycle-creating save; stored cycles
// themselves get no parent attributes, UD-08).
const CYCLE = '<form id="issue-form">' +
  '<p><label>A</label><select name="issue[custom_field_values][1]" data-dcf-field="1" data-dcf-parent="2" data-dcf-context="form" ' +
  'data-dcf-map="{&quot;b1&quot;:[&quot;a1&quot;],&quot;b2&quot;:[&quot;a2&quot;]}"><option value=""></option><option value="a1" selected>a1</option><option value="a2">a2</option></select></p>' +
  '<p><label>B</label><select name="issue[custom_field_values][2]" data-dcf-field="2" data-dcf-parent="1" data-dcf-context="form" ' +
  'data-dcf-map="{&quot;a1&quot;:[&quot;b1&quot;,&quot;b2&quot;],&quot;a2&quot;:[&quot;b2&quot;]}"><option value=""></option><option value="b1" selected>b1</option><option value="b2">b2</option></select></p>' +
  '</form>';

test('UMD: in a window the only new global is DependingCustomFields, created at evaluation time', () => {
  const dom = new JSDOM('<!doctype html><html><head></head><body></body></html>', { runScripts: 'outside-only' });
  const w = dom.window;
  w.eval(D.JQUERY);
  const before = new Set(Object.getOwnPropertyNames(w));
  assert.equal(w.document.readyState, 'loading');
  w.eval(D.RUNTIME);
  const added = Object.getOwnPropertyNames(w).filter((k) => !before.has(k));
  assert.deepEqual(added, ['DependingCustomFields']);
  const api = w.DependingCustomFields;
  ['init', 'setup', 'requestSetup', 't'].forEach((k) => assert.equal(typeof api[k], 'function', k));
  assert.equal(api.__runtime, true);
  assert.equal(typeof api.rules.decide, 'function');
  assert.equal(api.VERSION, api.rules.VERSION);
  assert.equal(typeof w.module, 'undefined');
  w.close();
});

test('UMD: the browser branch does not depend on a page global named module', async () => {
  const pg = await load('list_single', { before(w) { w.module = { exports: {} }; } });
  assert.equal(D.state(child(pg)), 'ok');
  assert.deepEqual(pg.window.module.exports, {});
});

test('load guard: a second evaluation keeps the object and binds no second listener or observer', async () => {
  let first = null;
  const bound = [];
  let observers = 0;
  const pg = await load('list_single', {
    twice: true,
    before(w) {
      const add = w.EventTarget.prototype.addEventListener;
      w.EventTarget.prototype.addEventListener = function (type, fn, capture) {
        if (this === w.document && type === 'change' && !capture) bound.push(fn);
        return add.apply(this, arguments);
      };
      const MO = w.MutationObserver;
      w.MutationObserver = function (cb) { observers += 1; return new MO(cb); };
      w.addEventListener('DOMContentLoaded', () => { first = w.DependingCustomFields; });
    }
  });
  assert.equal(pg.window.DependingCustomFields, first);
  // The runtime's own listener and jQuery's dispatcher (one per element and type).
  assert.equal(new Set(bound).size, 2, 'one native change listener on document besides jQuery');
  assert.equal(pg.window.jQuery._data(pg.document, 'events').change.length, 1, 'one jQuery delegate');
  assert.equal(observers, 1, 'one MutationObserver');
  const log = eventLog(pg);
  fire.choose(pg.window, parentOf(pg), 'Beta');
  assert.deepEqual(log, [`change:${PARENT}`, `change:${CHILD}`, 'updated:9100002']);
});

test('start(): one native change listener plus a jQuery delegate for isTrigger events only (X4)', async () => {
  const pg = await load('list_single');
  const log = eventLog(pg);
  // WP-17 review round 2: count evaluations (a second handling of the same
  // event is a no-op without any event, so dcf:updated cannot see it).
  const rules = pg.window.DependingCustomFields.rules;
  const parentState = rules.parentState;
  let evaluations = 0;
  rules.parentState = function () { evaluations += 1; return parentState.apply(this, arguments); };
  fire.choose(pg.window, parentOf(pg), 'Beta');
  assert.equal(log.filter((l) => l === 'updated:9100002').length, 1, 'a native change is processed once');
  assert.equal(evaluations, 1, 'one evaluation for one native change');
  log.length = 0;
  evaluations = 0;
  fire.jq(pg.window, parentOf(pg), 'Alpha');
  assert.deepEqual(log.filter((l) => l.startsWith('updated')), ['updated:9100002'], 'a jQuery trigger is processed once');
  assert.equal(evaluations, 1, 'one evaluation for one jQuery trigger');
  rules.parentState = parentState;
  assert.deepEqual(D.selected(child(pg)), ['Ant']);
  const plain = await load('list_single', { jquery: false });
  fire.choose(plain.window, parentOf(plain), 'Beta');
  assert.deepEqual(D.enabled(child(plain)), ['', 'Bee']);
});

test('X4 the runtime\'s native change events reach jQuery handlers (overlays redraw); it never triggers through jQuery', async () => {
  const pg = await load('list_single');
  const seen = [];
  pg.window.jQuery(child(pg)).on('change', (e) => seen.push(e.isTrigger === undefined ? 'native' : 'jquery'));
  fire.choose(pg.window, parentOf(pg), 'Beta');
  assert.deepEqual(seen, ['native']);
  assert.equal(/\.trigger\(/.test(D.RUNTIME), false);
});

test('changes of controls whose names do not parse return at once', async () => {
  const html = F.tweak('list_single', (doc) => {
    doc.querySelector('#all_attributes').insertAdjacentHTML('afterbegin', '<p><select name="issue[tracker_id]"><option value="1">Bug</option><option value="2">Feature</option></select></p>');
  });
  const pg = await load(html);
  const u = pg.updates.length;
  fire.choose(pg.window, D.byName(pg.document, 'issue[tracker_id]'), '2');
  assert.equal(pg.updates.length, u);
});

test('X1 change only on a real value change, dcf:updated for every evaluation that is not a no-op', async () => {
  const pg = await load('list_single');
  assert.deepEqual(pg.changes, []);
  assert.equal(pg.updates.length, 1);
  const log = eventLog(pg);
  fire.choose(pg.window, parentOf(pg), 'Beta');
  assert.deepEqual(log, [`change:${PARENT}`, `change:${CHILD}`, 'updated:9100002']);
  assert.deepEqual(Array.from(pg.updates[1].values), ['']);
  assert.equal(pg.updates[1].changed, true);
  log.length = 0;
  fire.change(pg.window, parentOf(pg));
  assert.deepEqual(log, [`change:${PARENT}`], 'an unchanged parent is a no-op');
});

test('X2 a DOM cycle terminates: each control evaluated once per cascade, the user pick is kept', async () => {
  const pg = await load(CYCLE);
  const a = D.control(pg.document, '1');
  const b = D.control(pg.document, '2');
  assert.deepEqual([D.selected(a), D.selected(b)], [['a1'], ['b1']]);
  let u = pg.updates.length;
  fire.choose(pg.window, a, 'a2');
  assert.deepEqual(pg.updates.slice(u).map((x) => x.fieldId), ['2'], 'B once, A (the origin) not again');
  assert.deepEqual([D.selected(a), D.selected(b)], [['a2'], ['']]);
  u = pg.updates.length;
  fire.choose(pg.window, b, 'b2');
  assert.deepEqual(pg.updates.slice(u).map((x) => x.fieldId), ['1']);
  assert.deepEqual(D.selected(b), ['b2'], 'the pick on B is not overwritten by its own cascade');
  assert.deepEqual(pg.errors, []);
});

test('X2 stored cycle and self-parent fixtures and a self-parent child: no error, untouched', async () => {
  for (const scenario of ['stored_cycle', 'self_parent']) {
    const pg = await load(scenario);
    assert.deepEqual(pg.errors, []);
    assert.equal(pg.document.querySelectorAll('[data-dcf-state], .depending-child, em.dcf-hint').length, 0, scenario);
  }
  const self = await load('<form><p><select name="issue[custom_field_values][1]" data-dcf-field="1" data-dcf-parent="1" data-dcf-map="{}"><option value="a">a</option></select></p></form>');
  assert.equal(self.document.querySelector('select').hasAttribute('data-dcf-state'), false);
  assert.deepEqual(D.enabled(self.document.querySelector('select')), ['a']);
});

test('X3 discovery is only [data-dcf-parent]: legacy data attributes and the carrier span are ignored', async () => {
  const html = F.tweak('read_only_child_carrier', (doc) => {
    doc.querySelector('#all_attributes').insertAdjacentHTML('beforeend',
      '<p><select name="issue[custom_field_values][9100002]" id="issue_custom_field_values_9100002" data-field-id="9100002" data-depending-parent="9100001" data-value-map="{&quot;Beta&quot;:[&quot;x&quot;]}"><option value="x">x</option><option value="y">y</option></select></p>');
  });
  const pg = await load(html);
  const carrier = pg.document.querySelector('span[data-dcf-locked-parent]');
  const before = carrier.outerHTML;
  const legacy = D.byName(pg.document, CHILD);
  fire.choose(pg.window, parentOf(pg), 'Beta');
  assert.equal(legacy.hasAttribute('data-dcf-state'), false);
  assert.deepEqual(D.enabled(legacy), ['x', 'y']);
  assert.equal(carrier.outerHTML, before);
  assert.deepEqual(pg.updates, []);
});

test('UD-37 carrier: never changed, no parent option disabled, no text added, submit never prevented', async () => {
  const pg = await load('read_only_child_carrier');
  const carrier = pg.document.querySelector('span[data-dcf-locked-parent]');
  const before = carrier.outerHTML;
  const text = pg.document.body.textContent;
  for (const v of ['Gamma', '', 'Beta', 'Alpha']) {
    fire.choose(pg.window, parentOf(pg), v);
    assert.equal(carrier.outerHTML, before);
    assert.deepEqual(D.disabled(parentOf(pg)), []);
  }
  assert.equal(pg.document.body.textContent, text);
  const ev = new pg.window.Event('submit', { bubbles: true, cancelable: true });
  pg.document.forms[0].dispatchEvent(ev);
  assert.equal(ev.defaultPrevented, false);
  assert.equal(pg.window.DependingCustomFields.rules.lockedRefused(['Alpha'], [['Beta']], ['Gamma']), true);
});

test('X6 the observer is childList only and filtered: attribute and style changes and plain rows cause no init', async () => {
  const observed = [];
  const pg = await load('list_single', {
    before(w) {
      const observe = w.MutationObserver.prototype.observe;
      w.MutationObserver.prototype.observe = function (target, options) {
        observed.push([target, options]);
        return observe.apply(this, arguments);
      };
    }
  });
  assert.equal(observed.length, 1);
  assert.equal(observed[0][0], pg.document.body);
  assert.deepEqual(JSON.parse(JSON.stringify(observed[0][1])), { childList: true, subtree: true });
  const api = pg.window.DependingCustomFields;
  const original = api.init;
  const calls = [];
  api.init = function (root) { calls.push(root); return original.apply(this, arguments); };
  child(pg).setAttribute('data-x', '1');
  child(pg).style.color = 'red';
  parentOf(pg).closest('p').setAttribute('class', 'x');
  const rows = pg.document.createElement('div');
  for (let k = 0; k < 1000; k += 1) rows.appendChild(pg.document.createElement('p'));
  pg.document.body.appendChild(rows);
  fire.choose(pg.window, parentOf(pg), '');
  await D.microtask();
  assert.deepEqual(calls, [], 'hints, the live region and plain rows carry no data-dcf-parent');
});

test('X7 setup(root) is a synchronous alias of init(root)', async () => {
  const a = await load('list_single');
  const b = await load('list_single');
  [a, b].forEach((pg) => { parentOf(pg).value = 'Beta'; });
  a.window.DependingCustomFields.setup(a.document);
  b.window.DependingCustomFields.init(b.document);
  assert.equal(a.document.body.innerHTML, b.document.body.innerHTML);
  assert.deepEqual(D.enabled(child(a)), ['', 'Bee']);
});

test('X7 requestSetup(root): init debounced by 25 ms, roots collected, a detached root skipped, no console output', async () => {
  const messages = [];
  const two = F.read('list_single') + F.read('list_single').replace('id="issue-form"', 'id="other"');
  const pg = await load(two, {
    before(w) { ['log', 'info', 'warn', 'error', 'debug'].forEach((m) => { w.console[m] = (...args) => messages.push([m, args]); }); }
  });
  const [f1, f2] = Array.from(pg.document.forms);
  [f1, f2].forEach((f) => { D.byName(f, PARENT).value = 'Beta'; });
  const api = pg.window.DependingCustomFields;
  const u = pg.updates.length;
  api.requestSetup(f1);
  pg.clock.tick(10);
  api.requestSetup(f2);
  pg.clock.tick(24);
  assert.equal(pg.updates.length, u, 'nothing before the debounce ends');
  pg.clock.tick(1);
  assert.equal(pg.updates.length - u, 2, 'both roots initialised once');
  const detached = pg.document.createElement('div');
  detached.innerHTML = F.read('list_single');
  api.requestSetup(detached);
  pg.clock.tick(30);
  assert.equal(detached.querySelector('[data-dcf-state]'), null);
  api.init(detached);
  api.setup(detached.querySelector('[data-dcf-parent]'));
  assert.equal(detached.querySelector('[data-dcf-state]'), null, 'init skips a detached root');
  assert.equal(pg.clock.pending(), 0);
  api.setup();
  api.requestSetup();
  pg.clock.tick(30);
  assert.deepEqual(messages, []);
  assert.deepEqual(pg.errors, []);
});

test('init(root) is synchronous and idempotent: a second init writes nothing and dispatches nothing', async () => {
  for (const scenario of F.scenarios()) {
    const pg = await load(scenario);
    const records = [];
    const mo = new pg.window.MutationObserver((r) => records.push(...r));
    mo.observe(pg.document.body, { attributes: true, childList: true, subtree: true, characterData: true });
    const u = pg.updates.length;
    const c = pg.changes.length;
    pg.window.DependingCustomFields.init(pg.document);
    pg.window.DependingCustomFields.init();
    await D.microtask();
    mo.disconnect();
    assert.deepEqual([records.length, pg.updates.length - u, pg.changes.length - c], [0, 0, 0], scenario);
  }
});

test('init re-evaluates a control whose parent changed without an event', async () => {
  const pg = await load('list_single');
  parentOf(pg).value = 'Beta';
  const u = pg.updates.length;
  pg.window.DependingCustomFields.init(pg.document);
  assert.equal(pg.updates.length - u, 1);
  assert.deepEqual(D.enabled(child(pg)), ['', 'Bee']);
});

test('head mode: the runtime in <head> filters the page at DOMContentLoaded and observes later fields', async () => {
  const bound = [];
  const observed = [];
  const pg = await load('list_single', {
    head: true,
    before(w) {
      const add = w.document.addEventListener;
      w.document.addEventListener = function (type, fn, capture) {
        if (type === 'change' && !capture) bound.push(w.document.readyState);
        return add.apply(this, arguments);
      };
      const observe = w.MutationObserver.prototype.observe;
      w.MutationObserver.prototype.observe = function (target) {
        observed.push([w.document.readyState, target]);
        return observe.apply(this, arguments);
      };
    }
  });
  assert.equal(D.state(child(pg)), 'ok');
  // WP-17 review round 2: start() waits for DOMContentLoaded while loading.
  assert.ok(bound.length >= 1);
  assert.deepEqual(Array.from(new Set(bound)), ['interactive'], 'the change listeners are bound at DOMContentLoaded');
  assert.deepEqual(observed.map(([rs, target]) => [rs, target === pg.document.body]), [['interactive', true]]);
  const p = pg.document.createElement('div');
  p.innerHTML = F.read('legacy_value').replace(/9100002/g, '9100005');
  pg.document.body.appendChild(p);
  await D.microtask();
  assert.equal(D.state(D.control(pg.document, '9100005')), 'legacy');
});

test('head mode: an init call while the page is still loading does not stop the full init at DOMContentLoaded', async () => {
  const second = F.read('legacy_value').replace(/9100002/g, '9100005').replace('id="issue-form"', 'id="second"');
  const body = `${F.read('list_single')}<script>window.DependingCustomFields.init(document);</script>${second}`;
  const pg = await load(body, { head: true });
  assert.equal(D.state(child(pg)), 'ok');
  assert.equal(D.state(D.control(pg.document, '9100005')), 'legacy');
  assert.deepEqual(pg.errors, []);
});

test('X8 the runtime never reads window.DependingCustomFieldData or window.ContextMenuWizardConfig', async () => {
  const thrower = (w, name) => Object.defineProperty(w, name, { configurable: true, get() { throw new Error(`read ${name}`); } });
  const pg = await load('legacy_value', { before(w) { thrower(w, 'DependingCustomFieldData'); thrower(w, 'ContextMenuWizardConfig'); } });
  fire.choose(pg.window, parentOf(pg), 'Gamma');
  fire.choose(pg.window, parentOf(pg), 'Alpha');
  assert.deepEqual([D.state(child(pg)), pg.errors], ['legacy', []]);
  const conflicting = await load('list_single', { before(w) { w.DependingCustomFieldData = { 9100002: { parent_id: '9100001', map: { Alpha: ['Bee'] } } }; } });
  const plain = await load('list_single');
  fire.choose(conflicting.window, parentOf(conflicting), 'Beta');
  fire.choose(plain.window, parentOf(plain), 'Beta');
  assert.equal(conflicting.document.body.innerHTML, plain.document.body.innerHTML);
});

test('data-dcf-context: missing, "form", "edit" or unknown reads as form; only "bulk" is bulk', async () => {
  for (const value of [null, 'form', 'edit', 'other']) {
    const html = F.tweak('legacy_value', (doc) => {
      const s = F.named(doc, CHILD);
      if (value === null) s.removeAttribute('data-dcf-context');
      else s.setAttribute('data-dcf-context', value);
    });
    const pg = await load(html);
    assert.equal(D.state(child(pg)), 'legacy', String(value));
  }
  const bulk = await load(F.tweak('legacy_value', (doc) => F.named(doc, CHILD).setAttribute('data-dcf-context', 'bulk')));
  assert.equal(D.state(child(bulk)), 'ok', 'bulk ignores data-dcf-stored');
});

test('i18n: English fallbacks without a meta tag, the meta texts when given, fallbacks for invalid content', async () => {
  const plain = await load('list_single');
  const t = plain.window.DependingCustomFields.t;
  assert.equal(t('noOptionsGeneric'), 'No values are available for this field.');
  assert.equal(t('saveFailed'), 'The change could not be saved.');
  assert.equal(t('selectParent', { parent: 'P' }), 'Select a value for P first.');
  assert.equal(t('unknownKey'), '');
  const de = 'Wählen Sie zuerst einen Wert für %{parent} aus.';
  const meta = await load('list_single', { meta: { selectParent: de, noOptions: 7 } });
  fire.choose(meta.window, parentOf(meta), '');
  assert.equal(D.hintText(child(meta)), 'Wählen Sie zuerst einen Wert für Parent field aus.');
  fire.choose(meta.window, parentOf(meta), 'Gamma');
  assert.equal(D.hintText(child(meta)), 'No values are available for the selected Parent field.', 'a non-string value falls back');
  for (const content of ['{', '[1]', '"x"', 'null']) {
    const bad = await load('list_single', { meta: content });
    fire.choose(bad.window, parentOf(bad), '');
    assert.equal(D.hintText(child(bad)), 'Select a value for Parent field first.', content);
    assert.deepEqual(bad.errors, []);
  }
  const nested = await load('list_single', { meta: { i18n: { selectParent: 'nested' } } });
  fire.choose(nested.window, parentOf(nested), '');
  assert.equal(D.hintText(child(nested)), 'Select a value for Parent field first.', 'only the flat dcf-i18n object counts');
});

test('i18n: the 10 English fallbacks equal the en texts of the registry and en.yml error_save_failed', async () => {
  const keys = {
    selectParent: 'text_dcf_hint_select_parent', noOptions: 'text_dcf_hint_no_options',
    noOptionsGeneric: 'text_dcf_hint_no_options_generic', legacy: 'text_dcf_hint_legacy',
    legacyLocked: 'text_dcf_hint_legacy_locked', legacyGeneric: 'text_dcf_hint_legacy_generic',
    bulkDefault: 'text_dcf_hint_bulk_default', bulkCleared: 'text_dcf_hint_bulk_cleared',
    liveMessage: 'text_dcf_live_message'
  };
  const registry = fs.readFileSync(path.join(ROOT, 'docs', 'specs', 'large_lists_i18n_registry.md'), 'utf8');
  const en = {};
  registry.split('\n').forEach((line) => {
    const cells = line.split('|').map((c) => c.trim());
    const m = /^`(text_dcf_[a-z_]+)`$/.exec(cells[1] || '');
    if (m) en[m[1]] = cells[5];
  });
  const yml = fs.readFileSync(path.join(ROOT, 'config', 'locales', 'en.yml'), 'utf8');
  const saveFailed = /^\s*error_save_failed:\s*"?(.*?)"?\s*$/m.exec(yml)[1];
  const pg = await load('list_single');
  const t = pg.window.DependingCustomFields.t;
  Object.keys(keys).forEach((k) => assert.equal(t(k), en[keys[k]], k));
  assert.equal(t('saveFailed'), saveFailed);
});

test('own events: a listener that re-dispatches each runtime change (same values) is no pick and the page settles as without it', async () => {
  const run = async (redispatch) => {
    const pg = await load('chain_of_three');
    if (redispatch) {
      const mine = new WeakSet();
      pg.document.addEventListener('change', (e) => {
        if (mine.has(e) || e.target.name !== CHILD) return;
        const ev = new pg.window.Event('change', { bubbles: true });
        mine.add(ev);
        e.target.dispatchEvent(ev);
      });
    }
    fire.choose(pg.window, parentOf(pg), 'Beta');
    fire.choose(pg.window, parentOf(pg), '');
    fire.choose(pg.window, parentOf(pg), 'Alpha');
    return { html: pg.document.body.innerHTML, updates: pg.updates.length };
  };
  const plain = await run(false);
  const noisy = await run(true);
  assert.equal(noisy.html, plain.html);
  assert.equal(noisy.updates, plain.updates);
  const cyc = await load(CYCLE);
  const mine = new WeakSet();
  cyc.document.addEventListener('change', (e) => {
    if (mine.has(e)) return;
    const ev = new cyc.window.Event('change', { bubbles: true });
    mine.add(ev);
    e.target.dispatchEvent(ev);
  });
  const u = cyc.updates.length;
  fire.choose(cyc.window, D.control(cyc.document, '1'), 'a2');
  assert.ok(cyc.updates.length - u < 10);
  assert.deepEqual(cyc.errors, []);
});

test('point 2: no select, group or parent option is ever disabled and no submit listener is added, on every fixture', async () => {
  for (const scenario of F.scenarios()) {
    const types = [];
    const pg = await load(scenario, {
      before(w) {
        const add = w.EventTarget.prototype.addEventListener;
        w.EventTarget.prototype.addEventListener = function (type) { types.push(type); return add.apply(this, arguments); };
      }
    });
    const parents = Array.from(pg.document.querySelectorAll('select:not([data-dcf-parent])'));
    const before = parents.map((s) => Array.from(s.options).map((o) => o.disabled));
    pg.document.querySelectorAll('select:not([data-dcf-parent])').forEach((s) => {
      const values = Array.from(s.options).map((o) => o.value).filter((v) => v !== '' && v !== '__none__');
      if (values.length) fire.choose(pg.window, s, s.multiple ? [values[values.length - 1]] : values[values.length - 1]);
    });
    pg.document.querySelectorAll('select').forEach((s) => assert.equal(s.disabled, false, `${scenario} ${s.name}`));
    pg.document.querySelectorAll('.check_box_group').forEach((g) => assert.equal(g.hasAttribute('disabled'), false));
    assert.deepEqual(parents.map((s) => Array.from(s.options).map((o) => o.disabled)), before, scenario);
    assert.equal(types.includes('submit'), false, scenario);
    Array.from(pg.document.forms).forEach((f) => assert.deepEqual(E.entries(f), E.serialized(pg.window, f), scenario));
  }
});

test('a child disabled by a third party stays disabled; its options are still filtered', async () => {
  const pg = await load(F.tweak('list_single', (doc) => F.named(doc, CHILD).setAttribute('disabled', 'disabled')));
  const c = child(pg);
  assert.equal(c.disabled, true);
  assert.deepEqual(D.disabled(c), ['Bee']);
});

test('an option pre-hidden by the server (hidden plus inline display:none) is reset when enabled', async () => {
  const pg = await load(F.tweak('list_single', (doc) => {
    const bee = F.named(doc, CHILD).querySelector('option[value="Bee"]');
    bee.setAttribute('hidden', 'hidden');
    bee.setAttribute('style', 'display:none');
  }));
  const bee = Array.from(child(pg).options).find((o) => o.value === 'Bee');
  fire.choose(pg.window, parentOf(pg), 'Beta');
  assert.deepEqual([bee.disabled, bee.hidden, bee.style.display], [false, false, '']);
  // WP-17 review round 2: the runtime never writes an inline style itself.
  const ant = Array.from(child(pg).options).find((o) => o.value === 'Ant');
  assert.deepEqual([ant.hidden, ant.disabled], [true, true]);
  assert.deepEqual(Array.from(child(pg).options).filter((o) => o.hasAttribute('style')).map((o) => o.value), ['Bee']);
  fire.choose(pg.window, parentOf(pg), 'Gamma');
  assert.deepEqual(Array.from(child(pg).options).filter((o) => o.hasAttribute('style')).map((o) => o.value), ['Bee']);
  assert.equal(pg.document.querySelectorAll('[style]').length, 1);
});

// Hand-written: a required single select without a blank option. Core omits
// it for a required field with a default value, which a depending field holds
// only when saved before the clear-on-save rule (depending_format_methods.rb).
// Nothing is posted, so the server keeps the stored (or core default) value
// and refuses it as 'is invalid' after the parent change; the WP-19 open
// input from WP-17 covers the fix.
test('single select without a blank option: no option stays selected and disabled when nothing is usable', async () => {
  const html = '<form><p><label>P</label><select name="issue[custom_field_values][1]"><option value="A" selected>A</option><option value="C">C</option></select></p>' +
    '<p><label>C</label><select name="issue[custom_field_values][2]" data-dcf-field="2" data-dcf-parent="1" data-dcf-context="form" ' +
    'data-dcf-map="{&quot;A&quot;:[&quot;Ant&quot;,&quot;Ape&quot;]}" data-dcf-stored="{&quot;child&quot;:[&quot;Ant&quot;],&quot;parent&quot;:[&quot;A&quot;]}">' +
    '<option value="Ant" selected>Ant</option><option value="Ape">Ape</option></select></p></form>';
  const pg = await load(html);
  const c = D.control(pg.document, '2');
  assert.deepEqual(D.selected(c), ['Ant']);
  fire.choose(pg.window, D.byName(pg.document, 'issue[custom_field_values][1]'), 'C');
  assert.equal(c.selectedIndex, -1);
  assert.deepEqual(E.list(pg.document.forms[0], 'issue[custom_field_values][2]'), []);
  assert.deepEqual(E.serialized(pg.window, pg.document.forms[0]).filter(([k]) => k.endsWith('[2]')), []);
  fire.choose(pg.window, D.byName(pg.document, 'issue[custom_field_values][1]'), 'A');
  assert.deepEqual(D.selected(c), ['Ant']);
});

test('writes only what changed: an option whose state stays the same gets no attribute write', async () => {
  const pg = await load('list_single');
  const blank = child(pg).querySelector('option[value=""]');
  const records = [];
  const mo = new pg.window.MutationObserver((r) => records.push(...r));
  mo.observe(blank, { attributes: true });
  fire.choose(pg.window, parentOf(pg), 'Beta');
  fire.choose(pg.window, parentOf(pg), 'Gamma');
  await D.microtask();
  mo.disconnect();
  assert.deepEqual(records.map((r) => r.attributeName), []);
});

// jsdom resets a single select on every parsed option (quadratic parse), so
// the select is parsed as multiple and made single before the runtime runs.
test('a 25,000-option child initialises in jsdom (5,000 allowed)', async () => {
  const values = Array.from({ length: 25000 }, (_, i) => `v${i}`);
  const map = { A: values.slice(0, 5000), B: values.slice(5000, 6000) };
  const esc = (s) => s.replace(/&/g, '&amp;').replace(/"/g, '&quot;');
  const html = '<form><p><select name="issue[custom_field_values][1]"><option value="A" selected>A</option><option value="B">B</option></select></p>' +
    `<p><select multiple name="issue[custom_field_values][2]" data-dcf-field="2" data-dcf-parent="1" data-dcf-context="form" data-dcf-map="${esc(JSON.stringify(map))}">` +
    `<option value=""></option>${values.map((v) => `<option value="${v}">${v}</option>`).join('')}</select></p></form>`;
  const pg = await load(html, { before(w) { w.document.querySelector('[data-dcf-field="2"]').removeAttribute('multiple'); } });
  const c = D.control(pg.document, '2');
  assert.equal(c.multiple, false);
  assert.deepEqual(D.selected(c), ['']);
  assert.equal(D.enabled(c).length, 5001);
  fire.choose(pg.window, D.byName(pg.document, 'issue[custom_field_values][1]'), 'B');
  assert.equal(D.enabled(c).length, 1001);
});

// Hand-written: data keys that are Object.prototype names.
test('prototype-named keys are plain keys: choosing __proto__ enables only its value, nothing is polluted', async () => {
  const html = '<form><p><select name="issue[custom_field_values][1]"><option value="toString" selected>toString</option><option value="__proto__">__proto__</option></select></p>' +
    '<p><select name="issue[custom_field_values][2]" data-dcf-field="2" data-dcf-parent="1" data-dcf-context="form" ' +
    'data-dcf-map="{&quot;__proto__&quot;:[&quot;Ant&quot;],&quot;toString&quot;:[&quot;Ape&quot;]}" data-dcf-defaults="{&quot;constructor&quot;:&quot;Ant&quot;}">' +
    '<option value=""></option><option value="Ant">Ant</option><option value="Ape">Ape</option></select></p></form>';
  const pg = await load(html);
  const c = D.control(pg.document, '2');
  assert.deepEqual(D.enabled(c), ['', 'Ape']);
  fire.choose(pg.window, D.byName(pg.document, 'issue[custom_field_values][1]'), '__proto__');
  assert.deepEqual(D.enabled(c), ['', 'Ant']);
  assert.equal(pg.window.eval('({}).Ant'), undefined);
  assert.equal(({}).Ant, undefined);
});

test('parent names with quotes, backslashes and brackets match; a name with a newline is ignored; nothing throws', async () => {
  const esc = (s) => s.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/\n/g, '&#10;');
  const page = (prefix) => `<form><p><select name="${esc(`${prefix}[custom_field_values][1]`)}"><option value="A" selected>A</option><option value="B">B</option></select></p>` +
    `<p><select name="${esc(`${prefix}[custom_field_values][2]`)}" data-dcf-field="2" data-dcf-parent="1" data-dcf-context="form" ` +
    `data-dcf-parent-name="${esc(`${prefix}[custom_field_values][1]`)}" data-dcf-map="{&quot;A&quot;:[&quot;a1&quot;],&quot;B&quot;:[&quot;b1&quot;]}">` +
    '<option value=""></option><option value="a1">a1</option><option value="b1">b1</option></select></p></form>';
  const pg = await load(page('x"y\\z]'));
  const [p, c] = Array.from(pg.document.querySelectorAll('select'));
  assert.equal(p.name, 'x"y\\z][custom_field_values][1]');
  assert.deepEqual(D.enabled(c), ['', 'a1']);
  fire.choose(pg.window, p, 'B');
  assert.deepEqual(D.enabled(c), ['', 'b1']);
  assert.deepEqual(pg.errors, []);
  // Like the server pattern (no newline in a name), such a field is left alone.
  const nl = await load(page('x\ny'));
  const [np, nc] = Array.from(nl.document.querySelectorAll('select'));
  fire.choose(nl.window, np, 'B');
  assert.deepEqual([nc.hasAttribute('data-dcf-state'), D.enabled(nc)], [false, ['', 'a1', 'b1']]);
  assert.deepEqual(nl.errors, []);
});

test('radio parent: changes come from its inputs; "(none)" checked makes the child wait', async () => {
  const html = '<form><p><label>Parent</label><span class="check_box_group"><label><input type="radio" name="issue[custom_field_values][1]" value=""> (none)</label>' +
    '<label><input type="radio" name="issue[custom_field_values][1]" value="A" checked> A</label><label><input type="radio" name="issue[custom_field_values][1]" value="B"> B</label></span></p>' +
    '<p><label>Child</label><select name="issue[custom_field_values][2]" data-dcf-field="2" data-dcf-parent="1" data-dcf-context="form" ' +
    'data-dcf-map="{&quot;A&quot;:[&quot;a1&quot;],&quot;B&quot;:[&quot;b1&quot;]}"><option value=""></option><option value="a1">a1</option><option value="b1">b1</option></select></p></form>';
  const pg = await load(html);
  const c = D.control(pg.document, '2');
  assert.deepEqual(D.enabled(c), ['', 'a1']);
  fire.choose(pg.window, pg.document.querySelector('input[value="B"]'), 'B');
  assert.deepEqual(D.enabled(c), ['', 'b1']);
  fire.choose(pg.window, pg.document.querySelector('input[value=""]'), '');
  assert.deepEqual([D.state(c), D.hintText(c)], ['waiting', 'Select a value for Parent first.']);
});

test('entries.js: a selected disabled option is not submitted (jsdom FormData wrongly keeps it)', async () => {
  const pg = await load('<form><select name="a"><option value="x" selected disabled>x</option><option value="y">y</option></select>' +
    '<fieldset disabled><input name="b" value="1"></fieldset><input type="radio" name="c" value="r"><input type="hidden" name="d" value=""></form>');
  const form = pg.document.forms[0];
  assert.deepEqual(E.entries(form), [['d', '']]);
  assert.deepEqual(E.serialized(pg.window, form), [['d', '']]);
  assert.ok(Array.from(new pg.window.FormData(form).entries()).some(([k]) => k === 'a'), 'the jsdom quirk this helper avoids');
});

test('static source checks: no HTML from strings, no legacy mechanisms, ES2017 runtime APIs only, no logging', () => {
  const src = D.RUNTIME;
  ['innerHTML', 'outerHTML', 'insertAdjacentHTML', 'document.write', 'eval(', 'new Function', 'localStorage', 'sessionStorage',
    'DependingCustomFieldData', 'ContextMenuWizardConfig', 'ajaxComplete', 'depending_cf_', 'dataset', 'data-hidden-for',
    'valueMap', 'data-depending', 'preventDefault', 'console.', '.flat(', 'flatMap', 'fromEntries', 'matchAll', 'replaceAll',
    'globalThis', 'structuredClone', 'replaceChildren', 'CSS.escape', '.at(', '?.', '??',
    // WP-17 resume: more ES2018+ built-ins (acorn checks syntax only) and core globals.
    '.finally(', 'trimStart', 'trimEnd', 'Object.hasOwn', 'findLast', 'toSorted', 'toReversed', 'allSettled',
    'queueMicrotask', 'Symbol.asyncIterator', 'for await', '$(', 'updateIssueFrom', 'replaceIssueFormWith',
    'warnLeavingUnsaved', 'createSVGIcon', 'document.cookie', 'data-dcf-parent^=', 'data-dcf-parent*=', 'data-dcf-parent$=',
    'data-dcf-parent|=', 'data-dcf-parent~=']
    .forEach((needle) => assert.equal(src.includes(needle), false, needle));
  assert.equal(/setTimeout\(\s*['"`]/.test(src), false, 'string timers');
  assert.equal(/catch\s*\{/.test(src), false, 'optional catch binding');
  assert.equal(/[\u2013\u2014]/.test(src), false, 'dash characters');
  assert.equal(/\bnormalizes\b/.test(src), false);
});

// WP-17 resume: the gates and environment the suites rely on.
test('npm run check gate: acorn ecmaVersion 2017 rejects ES2018+ syntax', () => {
  const acorn = require('acorn');
  ['a?.b', 'a ?? b', '({...a})', 'try {} catch {}', '/(?<=a)b/', 'async function f() { for await (const x of y); }', 'a ||= b']
    .forEach((code) => assert.throws(() => acorn.parse(code, { ecmaVersion: 2017, sourceType: 'script' }), SyntaxError, code));
  assert.doesNotThrow(() => acorn.parse(D.RUNTIME, { ecmaVersion: 2017, sourceType: 'script' }));
});

test('the jsdom suites run the locked jQuery 3.7.1', async () => {
  const pg = await load('list_single');
  assert.equal(pg.window.jQuery.fn.jquery, '3.7.1');
});

test('own events with jQuery: a listener answering each native change with a jQuery trigger settles on a DOM cycle', async () => {
  const cyc = await load(CYCLE);
  const $ = cyc.window.jQuery;
  $(cyc.document).on('change', 'select', function (e) { if (!e.isTrigger) $(this).trigger('change'); });
  const u = cyc.updates.length;
  fire.choose(cyc.window, D.control(cyc.document, '1'), 'a2');
  assert.ok(cyc.updates.length - u < 10);
  assert.deepEqual([D.selected(D.control(cyc.document, '1')), D.selected(D.control(cyc.document, '2'))], [['a2'], ['']]);
  assert.deepEqual(cyc.errors, []);
});

test('a control removed by a dcf:updated listener of an earlier control gets no event', async () => {
  const pg = await load('chain_of_three');
  const leaf = child(pg, '9100003');
  pg.document.addEventListener('dcf:updated', (e) => {
    if (e.detail.fieldId === '9100002' && leaf.isConnected) leaf.closest('p').remove();
  });
  const log = eventLog(pg);
  fire.choose(pg.window, parentOf(pg), 'Beta');
  assert.deepEqual(log, [`change:${PARENT}`, `change:${CHILD}`, 'updated:9100002']);
  assert.deepEqual(pg.errors, []);
});

test('without a body at start the observer watches the document element', async () => {
  const dom = new JSDOM('<!doctype html><html><head></head><body></body></html>', { runScripts: 'outside-only' });
  const w = dom.window;
  await new Promise((resolve) => w.addEventListener('DOMContentLoaded', () => resolve(), { once: true }));
  w.document.body.remove();
  assert.equal(w.document.body, null);
  assert.notEqual(w.document.readyState, 'loading');
  w.eval(D.RUNTIME);
  const body = w.document.createElement('body');
  body.innerHTML = F.read('list_single');
  w.document.documentElement.appendChild(body);
  await D.microtask();
  assert.equal(D.state(D.control(w.document, '9100002')), 'ok');
  w.close();
});

test('data-dcf-map: absent or invalid leaves the child unfiltered; ids above MAX_SAFE_INTEGER compare as strings', async () => {
  for (const raw of [null, '{', '[1]', '"x"']) {
    const pg = await load(F.tweak('list_single', (doc) => {
      const s = F.named(doc, CHILD);
      if (raw === null) s.removeAttribute('data-dcf-map');
      else s.setAttribute('data-dcf-map', raw);
    }));
    assert.deepEqual([D.state(child(pg)), D.disabled(child(pg))], ['unfiltered', []], String(raw));
  }
  const big = '9007199254740993';
  const html = '<form><p><select name="issue[custom_field_values][1]"><option value="7" selected>7</option></select></p>' +
    '<p><select name="issue[custom_field_values][2]" data-dcf-field="2" data-dcf-parent="1" data-dcf-context="form" ' +
    `data-dcf-map="{&quot;7&quot;:[&quot;${big}&quot;,12]}"><option value=""></option><option value="${big}">big</option><option value="12">12</option><option value="13">13</option></select></p></form>`;
  const pg = await load(html);
  assert.deepEqual(D.enabled(D.control(pg.document, '2')), ['', big, '12']);
});

test('meta texts with markup characters are written as text, never as markup', async () => {
  const meta = { selectParent: '<img src=x onerror=alert(1)> %{parent} &amp; $&', liveMessage: '<b>%{field}</b>: %{message}' };
  const pg = await load('list_single', { meta });
  fire.choose(pg.window, parentOf(pg), '');
  const hint = D.hint(child(pg));
  assert.equal(hint.textContent, '<img src=x onerror=alert(1)> Parent field &amp; $&');
  assert.equal(hint.children.length, 0);
  pg.clock.tick(400);
  const live = pg.document.getElementById('dcf-live');
  assert.equal(live.textContent, '<b>Child field</b>: <img src=x onerror=alert(1)> Parent field &amp; $&');
  assert.equal(live.children.length, 0);
  assert.equal(pg.document.querySelectorAll('img, b').length, 0);
});

test('X9 a page without managed fields: nothing written, no live region, no error, with or without the meta', async () => {
  for (const opts of [{}, { meta: { selectParent: 'x' } }, { jquery: false }]) {
    for (const body of ['<p>x</p>', F.read('role_invisible_parent')]) {
      const pg = await load(body, opts);
      const before = F.tweak(body, () => {});
      pg.document.querySelectorAll('select').forEach((s) => fire.choose(pg.window, s, s.options[0].value));
      pg.clock.tick(1000);
      assert.equal(pg.document.body.innerHTML, before);
      assert.equal(pg.document.getElementById('dcf-live'), null);
      assert.deepEqual([pg.errors, pg.updates, pg.clock.pending()], [[], [], 0]);
    }
  }
});

test('without jQuery the runtime ends in the same state (F1, F2, B2): native changes cascade', async () => {
  const run = async (scenario, steps, jquery) => {
    const pg = await load(scenario, { jquery });
    steps.forEach((v) => fire.choose(pg.window, parentOf(pg), v));
    return pg.document.body.innerHTML;
  };
  for (const [scenario, steps] of [['new_issue', ['', 'Alpha', 'Beta']], ['bulk_single', ['Beta', 'Alpha', '__none__', '']]]) {
    assert.equal(await run(scenario, steps, false), await run(scenario, steps, true), scenario);
  }
});

// FD-14: the runtime's own change events are never picks. A listener that
// changes another control without an event of its own before the runtime
// dispatches that control's change stays unseen (it needs its own event).
test('own events are ignored (WeakSet): a control changed silently before its own change is dispatched is no pick', async () => {
  const html = F.tweak('list_single', (doc) => {
    const p = F.named(doc, CHILD).closest('p');
    const copy = p.cloneNode(true);
    const s = copy.querySelector('select');
    s.setAttribute('name', 'issue[custom_field_values][9100003]');
    s.setAttribute('data-dcf-field', '9100003');
    s.removeAttribute('id');
    s.setAttribute('data-dcf-defaults', JSON.stringify({ Beta: 'Bee' }));
    s.setAttribute('data-dcf-stored', JSON.stringify({ child: [], parent: ['Alpha'] }));
    F.selectValues(s, ['']);
    p.after(copy);
  });
  const pg = await load(html);
  const c2 = child(pg, '9100003');
  let armed = true;
  child(pg).addEventListener('change', () => { if (armed) { armed = false; c2.value = ''; } });
  fire.choose(pg.window, parentOf(pg), 'Beta');
  assert.deepEqual([D.selected(child(pg)), D.selected(c2)], [[''], ['']], 'the listener cleared c2 after the runtime set Bee');
  fire.choose(pg.window, parentOf(pg), 'Alpha');
  fire.choose(pg.window, parentOf(pg), 'Beta');
  assert.deepEqual(D.selected(c2), ['Bee'], 'memory holds the runtime value, not the silent change');
});

// WP-17 review round 2: a change event is checked against the values the
// dependents were last evaluated against, so a pick after a silent change
// that init(document) acted on cascades again (it was dropped as a
// re-dispatch, leaving the leaf filtered for the silent value).
test('a pick of the old value after a silent change and init(document) cascades to the dependents again', async () => {
  for (const mode of ['native', 'jquery']) {
    const pg = await load('chain_of_three');
    const middle = child(pg, '9100002');
    const leaf = child(pg, '9100003');
    middle.value = 'Ape';
    pg.window.DependingCustomFields.init(pg.document);
    assert.deepEqual([D.enabled(leaf), D.selected(leaf), D.state(leaf)], [[''], [''], 'empty'], mode);
    if (mode === 'native') fire.choose(pg.window, middle, 'Ant');
    else fire.jq(pg.window, middle, 'Ant');
    assert.deepEqual([D.enabled(leaf), D.selected(leaf), D.state(leaf)], [['', 'Cub', 'Calf'], ['Cub'], 'ok'], mode);
    assert.deepEqual(pg.errors, []);
  }
  // The observer path: a silent change, the leaf re-rendered, then the pick.
  const pg = await load('chain_of_three');
  const middle = child(pg, '9100002');
  middle.value = 'Ape';
  const p = child(pg, '9100003').closest('p');
  p.replaceWith(p.cloneNode(true));
  await D.microtask();
  const leaf = child(pg, '9100003');
  assert.equal(D.state(leaf), 'empty');
  fire.choose(pg.window, middle, 'Ant');
  assert.deepEqual([D.enabled(leaf), D.state(leaf)], [['', 'Cub', 'Calf'], 'ok']);
  // A re-dispatch with the values the runtime left still starts no cascade.
  const u = pg.updates.length;
  fire.change(pg.window, middle);
  assert.equal(pg.updates.length, u);
});

// Accepted limit (WP-18 README): options a third party adds to a child stay
// as added until the next change of its parent; init is a no-op meanwhile.
test('pinned limit: an option added to a child after an evaluation is filtered at the next parent change only', async () => {
  const pg = await load('chain_of_three');
  const leaf = child(pg, '9100003');
  const extra = pg.document.createElement('option');
  extra.value = 'Colt2';
  extra.textContent = 'Colt2';
  leaf.appendChild(extra);
  pg.window.DependingCustomFields.init(pg.document.forms[0]);
  pg.window.DependingCustomFields.init(pg.document);
  await D.microtask();
  assert.deepEqual(D.enabled(leaf), ['', 'Cub', 'Calf', 'Colt2']);
  fire.choose(pg.window, parentOf(pg), 'Beta');
  assert.deepEqual(D.enabled(leaf), ['']);
  fire.choose(pg.window, parentOf(pg), 'Alpha');
  assert.deepEqual([D.enabled(leaf), D.selected(leaf)], [['', 'Cub', 'Calf'], ['Cub']]);
});

// WP-17 review round 2: the pick check and the cascade check are separate,
// so an init call in a change listener that runs before the runtime's (it
// re-evaluates the dependents first) does not swallow the user's pick.
test('a third-party init inside an earlier change listener keeps the user pick remembered', async () => {
  const pg = await load('chain_of_three');
  const middle = child(pg, '9100002');
  const leaf = child(pg, '9100003');
  middle.addEventListener('change', () => pg.window.DependingCustomFields.init(pg.document));
  fire.choose(pg.window, middle, 'Ape');
  assert.deepEqual([D.selected(leaf), D.state(leaf)], [[''], 'empty']);
  fire.choose(pg.window, parentOf(pg), 'Beta');
  fire.choose(pg.window, parentOf(pg), 'Alpha');
  assert.deepEqual(D.selected(middle), ['Ape'], 'the pick under Alpha comes back');
  assert.deepEqual(pg.errors, []);
});
