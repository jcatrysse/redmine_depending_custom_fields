'use strict';
// WP-30 (project design 5, UX-12): the page-mode dirty guard
// assets/javascripts/dcf_values_page.js on markup shaped like the project
// values page (toolbar with filter and sort forms, page-mode form,
// pagination, add and default forms). The request spec pins the same
// selectors on the real page. confirm is a stub fed from a queue of
// answers, and a rails-ujs stand-in (data-confirm on the bubbling document
// click, a document submit listener) is installed before the script runs.
const { test, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const acorn = require('acorn');
const D = require('./support/dom');

const SOURCE_PATH = path.join(__dirname, '..', '..', 'assets', 'javascripts', 'dcf_values_page.js');
const SOURCE = fs.existsSync(SOURCE_PATH) ? fs.readFileSync(SOURCE_PATH, 'utf8') : '';
const WARN = 'Unsaved <text> & "quotes" will be lost.';
const SORT = 'All values of this field (520) will be sorted. Continue?';

afterEach(() => D.closeAll());

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');

// sortConfirm false: the sort buttons of a shared or global field carry no
// data-confirm (WP-34, UD-23: the server panel asks).
function markup(opts) {
  const o = Object.assign({ scope: true, warn: WARN, button: false, sortConfirm: true }, opts || {});
  const attrs = (o.scope ? ' data-dcf-page-scope="1"' : '') + (o.warn === null ? '' : ` data-dcf-warn-unsaved="${esc(o.warn)}"`);
  const confirmAttr = o.sortConfirm ? ` data-confirm="${esc(SORT)}"` : '';
  const submit = (label) => (o.button
    ? `<button type="submit"${confirmAttr}><span>${label}</span></button>`
    : `<input type="submit" value="${label}"${confirmAttr}>`);
  const sortForm = (dir, label) => '<form class="button_to dcf-values-sort" method="post" ' +
    'action="/projects/p/custom_field_configuration/fields/1/values/sort"><input type="hidden" name="_method" value="patch">' +
    `${submit(label)}<input type="hidden" name="direction" value="${dir}"><input type="hidden" name="state_hash" value="h"></form>`;
  const row = (id, name, active) => `<tr data-dcf-value="${id}"><td><input type="text" name="enumerations[${id}][name]" ` +
    `value="${name}" size="30"></td><td class="dcf-active"><input type="hidden" name="enumerations[${id}][active]" value="0">` +
    `<input type="checkbox" name="enumerations[${id}][active]" value="1"${active ? ' checked' : ''}></td><td>` +
    `<a href="/projects/p/custom_field_configuration/fields/1/values?enumeration_id=${id}&amp;page=2" data-method="delete" ` +
    'data-confirm="Are you sure?" class="icon icon-del">Delete</a></td></tr>';
  return '<div id="content"><div class="dcf-values-toolbar">' +
    '<form class="dcf-values-filter" action="/projects/p/custom_field_configuration/fields/1" method="get"><fieldset>' +
    '<legend>Filters</legend><label for="dcf_values_q">Search:</label><input type="text" name="q" id="dcf_values_q" value="">' +
    '<input type="submit" value="Apply" class="small" data-disable-with="Apply">' +
    '<a class="icon icon-reload" href="/projects/p/custom_field_configuration/fields/1">Clear</a></fieldset></form>' +
    `${sortForm('asc', 'Sort A-Z')}${sortForm('desc', 'Sort Z-A')}</div>` +
    `<div class="box"><form class="dcf-enumerations-form"${attrs} ` +
    'action="/projects/p/custom_field_configuration/fields/1/enumerations" method="post">' +
    '<input type="hidden" name="_method" value="patch"><input type="hidden" name="state_hash" value="h">' +
    '<input type="hidden" name="batch_scope" value="page"><input type="hidden" name="page" value="2">' +
    `<table class="list dcf-values"><tbody>${row(26, 'N0026', true)}${row(27, 'N0027', false)}</tbody></table>` +
    '<p class="dcf-page-scope-note">Save applies to the values shown on this page only.</p>' +
    '<p class="buttons"><input type="submit" name="commit" value="Save" data-disable-with="Save"></p></form>' +
    '<span class="pagination"><ul class="pages"><li class="previous page"><a href="?page=1">Previous</a></li>' +
    '<li><a href="?page=1">1</a></li><li class="current"><span>2</span></li>' +
    '<li class="next page"><a href="?page=3"><span>Next</span></a></li></ul><span><span class="items">(26-50/520)</span> ' +
    '<span class="per-page">Per page: <span class="selected">25</span>, <a href="?per_page=50">50</a></span></span></span></div>' +
    '<fieldset class="box"><form id="dcf_default" action="/default" method="post"><select name="default_value">' +
    '<option value="">none</option><option value="26">N0026</option></select><input type="submit" value="Set"></form></fieldset>' +
    '<fieldset class="box"><form id="dcf_add" action="/add" method="post"><input type="text" name="value" id="value">' +
    '<input type="submit" value="Add"></form></fieldset></div>';
}

// The rails-ujs behaviour the guard has to live with (actionview
// rails-ujs.js: handleConfirm, stopEverything, the 13 ms disableElement on
// every document submit), reduced to counters.
function installUjs(w, log) {
  const doc = w.document;
  doc.addEventListener('click', (e) => {
    const el = e.target.closest('input[type=submit], button, a[data-confirm]');
    if (!el) return;
    const message = el.getAttribute('data-confirm');
    if (!message) return;
    log.ujsPrompts += 1;
    if (!w.confirm(message)) {
      el.dispatchEvent(new w.CustomEvent('ujs:everythingStopped', { bubbles: true }));
      e.preventDefault();
      e.stopPropagation();
      e.stopImmediatePropagation();
    }
  });
  doc.addEventListener('submit', () => { log.ujsSubmits += 1; });
  // Submits nobody stopped or prevented (the browser would send them).
  w.addEventListener('submit', (e) => { if (!e.defaultPrevented) log.sent.push(e.target.className || e.target.id); });
}

// Records 'window:<type>' and 'document:<type>' per call. jsdom's selector
// engine adds its own window listeners (click, focus, ...) on first use, so
// the assertions read document listeners and the window types it never adds.
function countListeners(target, label, log) {
  const add = target.addEventListener;
  const remove = target.removeEventListener;
  target.addEventListener = function (type, ...rest) {
    log.added.push(`${label}:${type}`);
    return add.call(this, type, ...rest);
  };
  target.removeEventListener = function (type, ...rest) {
    log.removed.push(`${label}:${type}`);
    return remove.call(this, type, ...rest);
  };
}

// opts: answers (confirm results in order; an empty queue answers true),
// ujs (default true), head, twice, scope, warn, button, body.
async function load(opts) {
  const o = Object.assign({ answers: [], ujs: true }, opts || {});
  const log = { prompts: [], ujsPrompts: 0, ujsSubmits: 0, sent: [], added: [], removed: [], before: null };
  const before = (w) => {
    w.confirm = (text) => {
      log.prompts.push(text);
      return o.answers.length ? o.answers.shift() : true;
    };
    if (o.ujs) installUjs(w, log);
    countListeners(w, 'window', log);
    countListeners(w.document, 'document', log);
    log.before = Object.keys(w).sort();
  };
  const pg = await D.page(o.body || markup(o), { runtime: SOURCE || ';', jquery: false, clock: false, head: o.head, twice: o.twice, before });
  const doc = pg.document;
  const w = pg.window;
  const q = (selector) => doc.querySelector(selector);
  const unload = () => {
    let text = null;
    const ev = new w.Event('beforeunload', { cancelable: true });
    Object.defineProperty(ev, 'returnValue', { configurable: true, get: () => text, set: (v) => { text = v; } });
    w.dispatchEvent(ev);
    return { prevented: ev.defaultPrevented, text };
  };
  const type = (el, value) => {
    el.value = value;
    el.dispatchEvent(new w.Event('input', { bubbles: true }));
  };
  const toggle = (el) => {
    el.checked = !el.checked;
    el.dispatchEvent(new w.Event('change', { bubbles: true }));
  };
  const click = (el, init) => {
    const ev = new w.MouseEvent('click', Object.assign({ bubbles: true, cancelable: true, button: 0 }, init || {}));
    el.dispatchEvent(ev);
    return ev;
  };
  const submit = (form) => {
    const ev = new w.Event('submit', { bubbles: true, cancelable: true });
    form.dispatchEvent(ev);
    return ev;
  };
  const name = () => q('input[name="enumerations[26][name]"]');
  const box = () => q('input[type="checkbox"][name="enumerations[27][active]"]');
  const pageLinks = () => Array.from(doc.querySelectorAll('span.pagination a'));
  const sortSubmit = () => q('form.dcf-values-sort [type="submit"]');
  const pageShow = (persisted) => {
    const ev = new w.Event('pageshow');
    Object.defineProperty(ev, 'persisted', { value: persisted });
    w.dispatchEvent(ev);
  };
  return Object.assign(pg, { log, q, unload, type, toggle, click, submit, name, box, pageLinks, sortSubmit, pageShow, answers: o.answers });
}

const later = () => new Promise((resolve) => setTimeout(resolve, 20));

test('the script ships and is evaluated (WP-30 asset present)', () => {
  assert.ok(SOURCE.length > 0, 'assets/javascripts/dcf_values_page.js exists');
});

test('beforeunload is prevented only while the form holds edits, through addEventListener', async () => {
  const p = await load();
  assert.equal(p.unload().prevented, false, 'clean');
  assert.equal(p.log.added.filter((t) => t === 'window:beforeunload').length, 0, 'no listener before the first edit');
  for (let i = 0; i < 10; i += 1) p.type(p.name(), `N0026 edited ${i}`);
  assert.deepEqual(p.unload(), { prevented: true, text: WARN });
  assert.equal(p.log.added.filter((t) => t === 'window:beforeunload').length, 1, 'one listener after ten inputs');
  assert.equal(p.window.onbeforeunload, null);
  p.type(p.name(), 'N0026');
  assert.equal(p.unload().prevented, false, 'reverting the edit makes the form clean');
  assert.equal(p.log.removed.filter((t) => t === 'window:beforeunload').length, 1, 'listener removed when clean');
  p.toggle(p.box());
  assert.equal(p.unload().prevented, true, 'a checkbox change makes it dirty');
  assert.deepEqual(p.log.prompts, []);
});

test('edits outside the page-mode form leave it clean', async () => {
  const p = await load();
  p.type(p.q('#dcf_values_q'), 'n002');
  p.type(p.q('#value'), 'New value');
  const select = p.q('select[name="default_value"]');
  select.value = '26';
  select.dispatchEvent(new p.window.Event('change', { bubbles: true }));
  assert.equal(p.unload().prevented, false);
  assert.equal(p.click(p.pageLinks()[0]).defaultPrevented, false);
  assert.deepEqual(p.log.prompts, []);
});

test('pagination links ask once while dirty: Cancel stays, OK leaves without a second prompt', async () => {
  const p = await load({ answers: [false, true] });
  p.type(p.name(), 'Changed');
  const next = p.q('li.next a span');
  assert.equal(p.click(next).defaultPrevented, true, 'Cancel blocks the navigation');
  assert.deepEqual(p.log.prompts, [WARN]);
  assert.equal(p.unload().prevented, true, 'still armed after Cancel');
  assert.equal(p.click(p.pageLinks()[1]).defaultPrevented, false, 'OK lets it go');
  assert.deepEqual(p.log.prompts, [WARN, WARN]);
  assert.equal(p.unload().prevented, false, 'no beforeunload prompt after OK');
  p.pageShow(true);
  assert.equal(p.unload().prevented, true, 'a bfcache restore re-arms the guard');
});

test('the per-page link asks too; modifier and middle clicks never ask', async () => {
  const p = await load({ answers: [false] });
  p.toggle(p.box());
  const perPage = p.q('span.per-page a');
  [{ ctrlKey: true }, { metaKey: true }, { shiftKey: true }, { altKey: true }, { button: 1 }].forEach((init) => {
    assert.equal(p.click(perPage, init).defaultPrevented, false, JSON.stringify(init));
  });
  assert.deepEqual(p.log.prompts, []);
  assert.equal(p.click(perPage).defaultPrevented, true);
  assert.deepEqual(p.log.prompts, [WARN]);
  assert.equal(p.unload().prevented, true);
});

test('the filter submit asks while dirty and stops rails-ujs on Cancel', async () => {
  const p = await load({ answers: [false, true] });
  const filter = p.q('form.dcf-values-filter');
  assert.equal(p.submit(filter).defaultPrevented, false, 'clean: no question');
  assert.deepEqual([p.log.prompts.length, p.log.ujsSubmits], [0, 1]);
  p.type(p.name(), 'Changed');
  assert.equal(p.submit(filter).defaultPrevented, true, 'Cancel');
  assert.deepEqual([p.log.prompts, p.log.ujsSubmits], [[WARN], 1], 'rails-ujs never sees the cancelled submit');
  assert.equal(p.unload().prevented, true);
  assert.equal(p.submit(filter).defaultPrevented, false, 'OK');
  assert.deepEqual([p.log.prompts.length, p.log.ujsSubmits], [2, 2]);
  assert.equal(p.unload().prevented, false, 'no second prompt on the way out');
});

test('the Apply button and Enter in q go through the same submit question', async () => {
  const p = await load({ answers: [false] });
  p.type(p.name(), 'Changed');
  p.q('form.dcf-values-filter input[type=submit]').click();
  assert.deepEqual(p.log.prompts, [WARN]);
  assert.equal(p.log.sent.length, 0);
});

[false, true].forEach((button) => {
  test(`a sort button asks one combined question while dirty, rails-ujs none (${button ? 'button' : 'input'})`, async () => {
    const p = await load({ button, answers: [false, true] });
    p.type(p.name(), 'Changed');
    const submitEl = p.sortSubmit();
    const target = button ? submitEl.querySelector('span') : submitEl;
    assert.equal(p.click(target).defaultPrevented, true, 'Cancel: nothing is submitted');
    assert.deepEqual(p.log.prompts, [`${WARN}\n\n${SORT}`]);
    assert.deepEqual([p.log.ujsPrompts, p.log.sent], [0, []]);
    assert.equal(submitEl.getAttribute('data-confirm'), SORT);
    assert.equal(p.unload().prevented, true, 'still armed after Cancel');

    target.click();
    assert.equal(p.log.prompts.length, 2, 'exactly one prompt for the second activation');
    assert.equal(p.log.ujsPrompts, 0, 'rails-ujs did not ask again');
    assert.deepEqual(p.log.sent, ['button_to dcf-values-sort'], 'the sort form is submitted once');
    assert.equal(p.unload().prevented, false, 'no beforeunload prompt after OK');
    await later();
    assert.equal(submitEl.getAttribute('data-confirm'), SORT, 'data-confirm is restored');
  });
});

// WP-34 (UD-23): on a shared or global field the sort buttons carry no
// data-confirm (the server panel is the only confirmation). With unsaved
// edits the guard asks the unsaved question alone, once; Cancel stops the
// click; a clean page asks nothing in the browser; no data-confirm appears.
[false, true].forEach((button) => {
  test(`a sort button without data-confirm asks only the unsaved question while dirty (${button ? 'button' : 'input'})`, async () => {
    const p = await load({ button, sortConfirm: false, answers: [false, true] });
    const submitEl = p.sortSubmit();
    assert.equal(submitEl.hasAttribute('data-confirm'), false);
    p.type(p.name(), 'Changed');
    const target = button ? submitEl.querySelector('span') : submitEl;
    assert.equal(p.click(target).defaultPrevented, true, 'Cancel: nothing is submitted');
    assert.deepEqual([p.log.prompts, p.log.ujsPrompts, p.log.sent], [[WARN], 0, []]);
    target.click();
    assert.deepEqual([p.log.prompts, p.log.ujsPrompts, p.log.sent], [[WARN, WARN], 0, ['button_to dcf-values-sort']]);
    await later();
    assert.equal(submitEl.hasAttribute('data-confirm'), false, 'no data-confirm is restored');
  });
});

test('a clean page asks nothing in the browser for a sort button without data-confirm', async () => {
  const p = await load({ sortConfirm: false });
  p.sortSubmit().click();
  assert.deepEqual([p.log.prompts, p.log.ujsPrompts, p.log.sent], [[], 0, ['button_to dcf-values-sort']]);
});

test('a clean page leaves the sort question to rails-ujs alone', async () => {
  const p = await load({ answers: [false, true] });
  p.sortSubmit().click();
  assert.deepEqual([p.log.prompts, p.log.ujsPrompts, p.log.sent], [[SORT], 1, []]);
  p.sortSubmit().click();
  assert.deepEqual([p.log.prompts, p.log.ujsPrompts, p.log.sent], [[SORT, SORT], 2, ['button_to dcf-values-sort']]);
});

test('submitting the page-mode form clears the guard; other forms do not', async () => {
  const p = await load();
  p.type(p.name(), 'Changed');
  p.submit(p.q('#dcf_add'));
  p.submit(p.q('#dcf_default'));
  assert.equal(p.unload().prevented, true, 'add and default submits keep the guard');
  p.q('form[data-dcf-page-scope] input[name="commit"]').click();
  assert.equal(p.unload().prevented, false, 'Save clears it for the navigation it starts');
  assert.deepEqual(p.log.prompts, []);
  // The Save navigation was aborted: the guard is armed again.
  assert.equal(p.click(p.pageLinks()[0]).defaultPrevented, false, 'OK');
  assert.deepEqual(p.log.prompts, [WARN], 'a later pagination click asks again');
  p.pageShow(false);
  assert.equal(p.unload().prevented, false);
  p.pageShow(true);
  assert.equal(p.unload().prevented, true, 'a bfcache restore with edits re-arms it');
});

test('an aborted navigation re-arms the guard: OK and Save quiet one beforeunload only', async () => {
  const p = await load();
  p.type(p.name(), 'Changed');
  const steps = [
    ['pagination', () => assert.equal(p.click(p.pageLinks()[0]).defaultPrevented, false)],
    ['filter', () => assert.equal(p.submit(p.q('form.dcf-values-filter')).defaultPrevented, false)],
    ['sort', () => p.sortSubmit().click()],
    ['save', () => p.q('form[data-dcf-page-scope] input[name="commit"]').click()]
  ];
  steps.forEach(([label, leave]) => {
    leave();
    assert.equal(p.unload().prevented, false, `${label}: the navigation it starts is not asked again`);
    assert.equal(p.unload().prevented, true, `${label}: aborted, closing the tab asks`);
  });
  assert.deepEqual(p.log.prompts, [WARN, WARN, `${WARN}\n\n${SORT}`]);
  assert.equal(p.log.ujsPrompts, 0);
  p.click(p.pageLinks()[0]);
  assert.equal(p.log.prompts.length, 4, 'pagination asks again after an aborted Save');
});

test('a Save of the clean form arms nothing: later edits are guarded at once', async () => {
  const p = await load({ answers: [false] });
  p.q('form[data-dcf-page-scope] input[name="commit"]').click();
  assert.equal(p.unload().prevented, false, 'clean');
  p.type(p.name(), 'Changed');
  assert.equal(p.unload().prevented, true, 'the first beforeunload after the edit asks');
  assert.equal(p.click(p.pageLinks()[0]).defaultPrevented, true, 'Cancel');
  assert.deepEqual(p.log.prompts, [WARN]);
});

test('delete links are left to rails-ujs; the browser question follows when dirty', async () => {
  const p = await load({ answers: [true] });
  p.type(p.name(), 'Changed');
  p.click(p.q('a.icon-del'));
  assert.deepEqual(p.log.prompts, ['Are you sure?']);
  assert.equal(p.unload().prevented, true);
});

[
  ['without data-dcf-page-scope', { scope: false }],
  ['without data-dcf-warn-unsaved', { warn: null }],
  ['with an empty data-dcf-warn-unsaved', { warn: '' }]
].forEach(([label, opts]) => {
  test(`no guard ${label}`, async () => {
    const p = await load(Object.assign({ answers: [true] }, opts));
    p.type(p.name(), 'Changed');
    p.toggle(p.box());
    assert.equal(p.unload().prevented, false);
    assert.equal(p.click(p.pageLinks()[0]).defaultPrevented, false);
    assert.equal(p.submit(p.q('form.dcf-values-filter')).defaultPrevented, false);
    p.sortSubmit().click();
    assert.deepEqual(p.log.prompts, [SORT], 'only the rails-ujs sort question');
    // dom.js itself adds a capturing document change listener.
    ['window:beforeunload', 'window:pageshow', 'window:submit', 'document:click', 'document:submit', 'document:input']
      .forEach((type) => {
      assert.equal(p.log.added.filter((t) => t === type).length, 0, type);
    });
  });
});

test('works when evaluated in <head> before the body exists', async () => {
  const p = await load({ head: true, answers: [false] });
  p.type(p.name(), 'Changed');
  assert.equal(p.unload().prevented, true);
  assert.equal(p.click(p.pageLinks()[0]).defaultPrevented, true);
  assert.deepEqual(p.log.prompts, [WARN]);
});

test('works when evaluated after the DOM is ready', async () => {
  const answers = [false];
  const prompts = [];
  const pg = await D.page(markup(), { runtime: ';', jquery: false, clock: false });
  pg.window.confirm = (text) => { prompts.push(text); return answers.shift(); };
  assert.notEqual(pg.document.readyState, 'loading');
  pg.window.eval(SOURCE || ';');
  const name = pg.document.querySelector('input[name="enumerations[26][name]"]');
  name.value = 'Changed';
  name.dispatchEvent(new pg.window.Event('input', { bubbles: true }));
  const ev = new pg.window.MouseEvent('click', { bubbles: true, cancelable: true, button: 0 });
  pg.document.querySelector('span.pagination a').dispatchEvent(ev);
  assert.equal(ev.defaultPrevented, true);
  assert.deepEqual(prompts, [WARN]);
});

test('a second evaluation adds no second set of listeners', async () => {
  const p = await load({ twice: true, answers: [false] });
  p.type(p.name(), 'Changed');
  p.click(p.pageLinks()[0]);
  assert.deepEqual(p.log.prompts, [WARN]);
  assert.equal(p.log.added.filter((t) => t === 'window:beforeunload').length, 1);
});

test('defines no globals and never submits a form itself', async () => {
  const calls = [];
  const p = await load({ answers: [true, true, true] });
  const proto = p.window.HTMLFormElement.prototype;
  proto.submit = () => calls.push('submit');
  proto.requestSubmit = () => calls.push('requestSubmit');
  assert.deepEqual(Object.keys(p.window).sort(), p.log.before);
  p.type(p.name(), 'Changed');
  p.click(p.pageLinks()[0]);
  p.pageShow(true);
  p.submit(p.q('form.dcf-values-filter'));
  p.pageShow(true);
  p.sortSubmit().click();
  assert.deepEqual(calls, []);
});

test('static source checks: ES2017, no HTML from strings, no eval, no onbeforeunload, no jQuery', () => {
  assert.doesNotThrow(() => acorn.parse(SOURCE, { ecmaVersion: 2017, sourceType: 'script' }));
  assert.doesNotMatch(SOURCE, /innerHTML|outerHTML|insertAdjacentHTML|document\.write|\beval\(|new Function/);
  assert.doesNotMatch(SOURCE, /onbeforeunload|\.submit\(|requestSubmit|jQuery|\$\(|CSS\.escape|console\./);
  assert.doesNotMatch(SOURCE, /setTimeout\(\s*['"`]/, 'string timers');
  assert.doesNotMatch(SOURCE, /[\u2013\u2014]/, 'dash characters');
  assert.match(SOURCE, /'use strict'/);
  assert.match(SOURCE, /addEventListener\('beforeunload'/);
  ['form[data-dcf-page-scope]', 'data-dcf-warn-unsaved', 'span.pagination a', 'form.dcf-values-filter', 'form.dcf-values-sort']
    .forEach((needle) => assert.ok(SOURCE.includes(needle), needle));
});
