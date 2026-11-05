'use strict';
// WP-18: assets/javascripts/context_menu_wizard.js with the runtime, on the
// generated wizard fixture (frontend design 3.5 and 7, rows W1..W6 and X6):
// every field opens on '(no change)' and is initialised synchronously, the
// form posts to its own action resolved against the page URL (same origin
// only, SP-15), errors give a localized alert and keep the wizard open, the
// wizard is scoped to its form, fields carry implicit labels, and the
// observer watches child lists only. fetch and alert are stubbed (jsdom has
// neither); location.reload() is reported by jsdom as a navigation error.
// WP-36 (UD-13 changed by the owner): the menu holds the entry only
// (fixture wizard_entry); a click fetches the body (fixture wizard_body, the
// GET wizard response) and shows it. The fetch stub answers that GET first
// and the save POST after it (saves() keeps the POSTs); the W and X rows
// open through the fetch (open() awaits it). The L rows pin the loading
// state, the request, the parsing, the failures, the races and the closes.
const { test, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const D = require('./support/dom');
const F = require('./support/fixtures');
const fire = require('./support/fire');

afterEach(D.closeAll);

const URL_ = 'https://redmine.example/redmine/issues';
const ROOT = 'issue[custom_field_values][9100001]';
const MIDDLE = 'issue[custom_field_values][9100002]';
const LEAF = 'issue[custom_field_values][9100003]';
const SAVE_FAILED = 'The change could not be saved.';
const DE_SAVE_FAILED = 'Die Änderung konnte nicht gespeichert werden.';
const LOADING = 'Loading...';
const LOAD_FAILED = 'The wizard could not be loaded. Click the entry again to try again.';
const WIZARD_URL = 'https://redmine.example/depending_custom_fields/wizard?parent_id=9100001&ids%5B%5D=9300001';

// A Response-like object of the wizard GET: an HTML body by default.
function htmlResponse(text, extra) {
  return Object.assign({
    ok: true,
    status: 200,
    redirected: false,
    headers: { get: (name) => (/^content-type$/i.test(name) ? 'text/html; charset=utf-8' : null) },
    text: () => Promise.resolve(text)
  }, extra || {});
}

// A fetch stub: load(url, init) answers the wizard GET (default: the
// wizard_body fixture, or form), respond(url, init) the save POST.
function stubs(respond, load, form) {
  const log = { fetch: [], alerts: [] };
  const body = form === undefined ? F.read('wizard_body') : form;
  return {
    log,
    before(w) {
      w.fetch = (url, init) => {
        log.fetch.push({ url: String(url), init });
        if (!init || init.method !== 'POST') return load ? load(url, init) : Promise.resolve(htmlResponse(body));
        return respond ? respond(url, init) : Promise.resolve({ ok: true, status: 200, redirected: false });
      };
      w.alert = (text) => { log.alerts.push(String(text)); };
    }
  };
}

const saves = (pg) => pg.log.fetch.filter((c) => c.init && c.init.method === 'POST');

async function wizardPage(opts) {
  const o = Object.assign({ body: F.read('wizard_entry') }, opts || {});
  const s = stubs(o.respond, o.load, o.form);
  const pg = await D.page(o.body, {
    url: o.url || URL_,
    meta: o.meta,
    headHtml: o.headHtml,
    scripts: o.withoutWizard ? [] : [D.WIZARD],
    runtime: o.runtime,
    before(w) {
      s.before(w);
      if (o.before) o.before(w);
    }
  });
  pg.log = s.log;
  return pg;
}

// Clicks the entry (the first, or the one of parentId) and returns the
// container at once, while the body loads.
function click(pg, parentId) {
  const sel = parentId ? `#context-menu li.cf-parent[data-parent-id="${parentId}"] > a.submenu` : '#context-menu li.cf-parent > a.submenu';
  const a = pg.document.querySelector(sel);
  a.dispatchEvent(new pg.window.MouseEvent('click', { bubbles: true, cancelable: true }));
  return pg.document.getElementById('cf-wizard-container');
}

const settle = async () => { for (let i = 0; i < 5; i += 1) await D.flush(); };

// Changed by WP-36: opens and waits for the fetched body; was synchronous.
async function open(pg, parentId) {
  const container = click(pg, parentId);
  await settle();
  return container;
}

function submit(pg) {
  const form = pg.document.querySelector('#cf-wizard-container form.cf-wizard-form');
  const ev = new pg.window.Event('submit', { bubbles: true, cancelable: true });
  form.dispatchEvent(ev);
  return ev;
}

const bodyPairs = (pg, call) => Array.from(new pg.window.URLSearchParams(call.init.body).entries());
const cfPairs = (pg, call) => bodyPairs(pg, call).filter(([k]) => k.includes('[custom_field_values]'));
// jsdom reports location.reload() as not implemented navigation.
const realErrors = (pg) => pg.errors.filter((e) => !/navigation/i.test(String(e && e.message)));

// Changed by WP-36: the body arrives through the fetch, so the checks run
// inside the init wrapper, right when the wizard calls init(container) after
// inserting the body (the runtime's own observer pass follows and calls the
// public init for the added form); was right after the synchronous clone.
test('W1 every field opens on (no change), synchronously initialised, and a save without a choice posts only blanks', async () => {
  const pg = await wizardPage();
  const api = pg.window.DependingCustomFields;
  const inits = [];
  const realInit = api.init;
  let atInit = null;
  const records = [];
  let mo = null;
  api.init = (root) => {
    inits.push([root, root.isConnected]);
    const out = realInit(root);
    if (inits.length === 1) {
      const f = root.querySelector('form.cf-wizard-form');
      atInit = {
        values: [D.byName(f, ROOT), D.byName(f, MIDDLE), D.byName(f, LEAF)].map((sel) => sel.value),
        states: [D.state(D.byName(f, MIDDLE)), D.state(D.byName(f, LEAF))],
        updates: pg.updates.length
      };
      mo = new pg.window.MutationObserver((r) => records.push(...r));
      mo.observe(root, { attributes: true, childList: true, subtree: true });
    }
    return out;
  };
  api.requestSetup = () => { throw new Error('requestSetup called'); };
  assert.equal(pg.document.getElementById('cf-wizard-container'), null, 'the container is created on the first open');
  const timers = pg.clock.calls;

  const container = await open(pg);
  mo.disconnect();
  assert.deepEqual(atInit.values, ['', '', '']);
  assert.deepEqual(atInit.states, ['unfiltered', 'unfiltered'], 'initialised before any timer or microtask');
  assert.equal(inits[0][0], container);
  assert.equal(inits[0][1], true, 'the container is connected when init runs');
  assert.equal(inits.filter(([root]) => root === container).length, 1, 'the wizard initialises once');
  assert.equal(pg.clock.calls, timers, 'no timer from the wizard');
  assert.equal(container.style.display, 'block');
  assert.deepEqual([pg.updates.length - atInit.updates, records.length], [0, 0], 'the observer pass after the insertion is a no-op');

  const ev = submit(pg);
  assert.equal(ev.defaultPrevented, true);
  await settle();
  // WP-36: the GET of the body first, the save second.
  assert.deepEqual(pg.log.fetch.map((c) => c.init.method), ['GET', 'POST']);
  assert.equal(saves(pg).length, 1);
  const call = saves(pg)[0];
  assert.equal(call.url, 'https://redmine.example/depending_custom_fields/save');
  assert.equal(call.init.method, 'POST');
  assert.equal(call.init.credentials, 'same-origin');
  assert.equal(call.init.headers['Content-Type'], 'application/x-www-form-urlencoded');
  assert.equal(call.init.headers['X-Requested-With'], 'XMLHttpRequest', 'an expired session answers 401');
  assert.deepEqual(cfPairs(pg, call), [[ROOT, ''], [MIDDLE, ''], [LEAF, '']]);
  const names = bodyPairs(pg, call).map(([k]) => k);
  assert.ok(names.includes('authenticity_token') && names.includes('ids[]') && names.includes('issue_ids'));
  assert.deepEqual(pg.log.alerts, []);
});

test('W2 root (none) sets every descendant to __none__ with the cleared hint, and each field is posted once', async () => {
  const pg = await wizardPage();
  const form = (await open(pg)).querySelector('form');
  fire.choose(pg.window, D.byName(form, ROOT), '__none__');
  const middle = D.byName(form, MIDDLE);
  const leaf = D.byName(form, LEAF);
  assert.deepEqual([middle.value, leaf.value], ['__none__', '__none__']);
  assert.equal(D.hintText(middle), 'Cleared because the current choice for Root field allows no values for this field.');
  assert.equal(middle.classList.contains('dcf-auto-applied'), false);
  submit(pg);
  await settle();
  assert.deepEqual(cfPairs(pg, saves(pg)[0]), [[ROOT, '__none__'], [MIDDLE, '__none__'], [LEAF, '__none__']]);
});

test('W2 a concrete root preselects the per-parent default with its hint; back to (no change) restores (no change)', async () => {
  const pg = await wizardPage();
  const form = (await open(pg)).querySelector('form');
  const middle = D.byName(form, MIDDLE);
  const leaf = D.byName(form, LEAF);
  fire.choose(pg.window, D.byName(form, ROOT), 'Alpha');
  fire.choose(pg.window, middle, 'Ant');
  assert.deepEqual(D.selected(leaf), ['Calf']);
  assert.equal(leaf.classList.contains('dcf-auto-applied'), true);
  assert.equal(D.hintText(leaf), 'Set to the default for the selected Middle field. Choose (No change) to keep the current values.');
  fire.choose(pg.window, D.byName(form, ROOT), '');
  assert.deepEqual([middle.value, D.state(middle)], ['', 'unfiltered']);
  // Review round 2: the leaf held the applied default; it goes back to its
  // value before the cascade, so a save changes nothing (UD-11, UN-15).
  assert.deepEqual([leaf.value, D.state(leaf), leaf.classList.contains('dcf-auto-applied'), D.hintText(leaf)],
    ['', 'unfiltered', false, null]);
  submit(pg);
  await settle();
  assert.deepEqual(cfPairs(pg, saves(pg)[0]), [[ROOT, ''], [MIDDLE, ''], [LEAF, '']]);
});

// Flipped by WP-34 (UD-10 changed by the owner on 2026-11-02): a required
// middle field gets core's select without (none) (bulk_edit_tag through
// render_custom_field); the wizard fixture has no required field, so its
// (none) is removed here. Root (none) leaves it on '' with the empty hint, the
// leaf reads it as (no change) and stays unfiltered (the clear stops at a
// required field), and the save posts '' for both; was the marked (none)
// enabled and selected while the root allowed nothing (WP-19).
test('W2 a required descendant without (none) stays on (no change) with the empty hint; the clear stops there', async () => {
  const form0 = F.tweak('wizard_body', (doc) => {
    const select = doc.querySelector(`select[name="${MIDDLE}"]`);
    select.querySelector('option[value="__none__"]').remove();
  });
  const pg = await wizardPage({ form: form0 });
  const form = (await open(pg)).querySelector('form');
  const middle = D.byName(form, MIDDLE);
  const leaf = D.byName(form, LEAF);
  assert.deepEqual(Array.from(middle.options).map((o) => o.value).includes('__none__'), false);
  assert.equal(form.querySelectorAll('[data-dcf-required-none]').length, 0);
  fire.choose(pg.window, D.byName(form, ROOT), 'Alpha');
  assert.deepEqual([middle.value, D.state(middle)], ['', 'ok']);
  fire.choose(pg.window, D.byName(form, ROOT), '__none__');
  assert.deepEqual([middle.value, D.state(middle), D.selected(middle)], ['', 'none', ['']]);
  assert.equal(D.hintText(middle), 'No values are available for the selected Root field.');
  assert.equal(middle.classList.contains('dcf-auto-applied'), false);
  assert.deepEqual([leaf.value, D.state(leaf), D.disabled(leaf)], ['', 'unfiltered', []]);
  submit(pg);
  await settle();
  assert.deepEqual(cfPairs(pg, saves(pg)[0]), [[ROOT, '__none__'], [MIDDLE, ''], [LEAF, '']]);
});

test('W3 the action is resolved against the page URL: a relative URL root is kept', async () => {
  const form = F.tweak('wizard_body', (doc) => {
    doc.querySelector('form').setAttribute('action', '/redmine/depending_custom_fields/save');
  });
  const pg = await wizardPage({ form });
  await open(pg);
  submit(pg);
  await settle();
  assert.deepEqual(saves(pg).map((c) => c.url), ['https://redmine.example/redmine/depending_custom_fields/save']);
});

test('W3 a control named action and a <base href> do not change the target', async () => {
  const form = F.tweak('wizard_body', (doc) => {
    doc.querySelector('form').insertAdjacentHTML('afterbegin', '<input type="hidden" name="action" value="https://evil.example/x">');
  });
  // WP-36: the entry's wizard URL is relative too; the <base> does not move
  // it either.
  const pg = await wizardPage({ form, headHtml: '<base href="https://evil.example/">' });
  await open(pg);
  submit(pg);
  await settle();
  assert.deepEqual(pg.log.fetch.map((c) => c.url), [WIZARD_URL, 'https://redmine.example/depending_custom_fields/save']);
});

test('W3 a cross-origin, scheme-changing, script, data, blank or missing action is refused without a request', async () => {
  const actions = ['https://evil.example/x', '//evil.example/x', 'javascript:alert(1)', 'data:text/html,x',
    'http://redmine.example/depending_custom_fields/save', 'https://redmine.example:8443/depending_custom_fields/save',
    '', '   ', null];
  for (const action of actions) {
    const form = F.tweak('wizard_body', (doc) => {
      const f = doc.querySelector('form');
      if (action === null) f.removeAttribute('action');
      else f.setAttribute('action', action);
    });
    const pg = await wizardPage({ form });
    const container = await open(pg);
    submit(pg);
    await settle();
    assert.deepEqual(saves(pg), [], String(action));
    assert.deepEqual(pg.log.alerts, [SAVE_FAILED], String(action));
    assert.equal(container.style.display, 'block', String(action));
    assert.deepEqual(realErrors(pg), [], String(action));
  }
});

// Changed by WP-36: on about:blank the wizard URL is refused as well, so
// no body is fetched and no form can be submitted (L3); was a refused save.
test('W3 about:blank (origin null) refuses even a relative wizard URL', async () => {
  const pg = await wizardPage({ url: 'about:blank' });
  const container = await open(pg);
  assert.deepEqual([pg.log.fetch.length, container.querySelector('form'), container.textContent], [0, null, LOAD_FAILED]);
});

test('W4 errors: JSON errors joined, non-JSON and network failures localized, a redirect is no success; the wizard stays open', async () => {
  const unhandled = [];
  const onUnhandled = (reason) => unhandled.push(reason);
  process.on('unhandledRejection', onUnhandled);
  const notJson = () => Promise.reject(new SyntaxError('Unexpected token <'));
  const cases = [
    [{ ok: false, status: 422, redirected: false, json: () => Promise.resolve({ errors: ['A is invalid', 'B is invalid'] }) },
      'A is invalid\nB is invalid'],
    [{ ok: false, status: 422, redirected: false, json: () => Promise.resolve({ other: 1 }) }, `${SAVE_FAILED} (422)`],
    // Review round 2: only string errors are joined.
    [{ ok: false, status: 422, redirected: false, json: () => Promise.resolve({ errors: ['A is invalid', 7, { x: 1 }] }) },
      'A is invalid'],
    [{ ok: false, status: 422, redirected: false, json: () => Promise.resolve({ errors: [5] }) }, `${SAVE_FAILED} (422)`],
    [{ ok: false, status: 403, redirected: false, json: notJson }, `${SAVE_FAILED} (403)`],
    [{ ok: false, status: 500, redirected: false, json: notJson, text: () => Promise.resolve('PG::Error SELECT') },
      `${SAVE_FAILED} (500)`],
    [{ ok: true, status: 200, redirected: true, json: notJson }, SAVE_FAILED],
    ['reject', SAVE_FAILED]
  ];
  try {
    for (const [response, expected] of cases) {
      const pg = await wizardPage({
        respond: () => (response === 'reject' ? Promise.reject(new TypeError('Failed to fetch')) : Promise.resolve(response))
      });
      const container = await open(pg);
      const form = container.querySelector('form');
      fire.choose(pg.window, D.byName(form, ROOT), 'Alpha');
      submit(pg);
      await settle();
      assert.deepEqual(pg.log.alerts, [expected], String(expected));
      assert.equal(container.style.display, 'block');
      assert.equal(pg.document.getElementById('cf-wizard-container').querySelector('form'), form, 'still open');
      assert.equal(D.byName(form, ROOT).value, 'Alpha', 'the choice is kept');
      assert.deepEqual(pg.errors, [], 'no reload and no error');
    }
    await settle();
    assert.deepEqual(unhandled, []);
  } finally {
    process.removeListener('unhandledRejection', onUnhandled);
  }
});

test('W4 the alert uses the saveFailed text of the dcf-i18n meta tag', async () => {
  const pg = await wizardPage({
    meta: { saveFailed: DE_SAVE_FAILED },
    respond: () => Promise.resolve({ ok: false, status: 500, redirected: false, json: () => Promise.reject(new SyntaxError('x')) })
  });
  await open(pg);
  submit(pg);
  await settle();
  assert.deepEqual(pg.log.alerts, [`${DE_SAVE_FAILED} (500)`]);
  for (const meta of ['{', '[1]', '{"saveFailed":7}', '{"saveFailed":{"x":1}}']) {
    const bad = await wizardPage({ meta, form: F.tweak('wizard_body', (doc) => doc.querySelector('form').setAttribute('action', 'https://evil.example/')) });
    await open(bad);
    submit(bad);
    await settle();
    assert.deepEqual(bad.log.alerts, [SAVE_FAILED], meta);
  }
});

test('W4 a success reloads the page once and closes the wizard', async () => {
  const pg = await wizardPage();
  const container = await open(pg);
  submit(pg);
  await settle();
  assert.equal(saves(pg).length, 1);
  assert.deepEqual(pg.log.alerts, []);
  assert.equal(pg.errors.filter((e) => /navigation/i.test(String(e && e.message))).length, 1, 'location.reload()');
  assert.equal(container.style.display, 'none');
});

test('W5 the wizard and an issue form on the same page stay apart', async () => {
  const pg = await wizardPage({ body: `${F.read('list_single')}${F.read('wizard_entry')}` });
  const issueForm = pg.document.getElementById('issue-form');
  const issueChild = D.control(issueForm, '9100002');
  const form = (await open(pg)).querySelector('form');
  fire.choose(pg.window, D.byName(form, ROOT), 'Beta');
  assert.deepEqual([D.state(issueChild), D.selected(issueChild)], ['ok', ['Ant']]);
  fire.choose(pg.window, D.byName(issueForm, 'issue[custom_field_values][9100001]'), 'Beta');
  assert.deepEqual(D.enabled(D.byName(form, MIDDLE)), ['', '__none__', 'Bee']);
});

test('W6 each wizard field wraps its name and select in an implicit label without for or id', async () => {
  const pg = await wizardPage();
  const container = await open(pg);
  const fields = Array.from(container.querySelectorAll('div.cf-wizard-field'));
  assert.deepEqual(fields.map((f) => f.getAttribute('data-dcf-wizard-field')), ['9100001', '9100002', '9100003']);
  fields.forEach((field) => {
    const label = field.querySelector(':scope > label.cf-wizard-label');
    assert.ok(label);
    assert.equal(label.hasAttribute('for'), false);
    assert.equal(label.firstElementChild.className, 'field-description');
    assert.ok(label.querySelector(':scope > select'));
  });
  assert.equal(container.querySelectorAll('[data-field-id]').length, 0);
  fire.choose(pg.window, D.byName(container, ROOT), 'Alpha');
  fire.choose(pg.window, D.byName(container, MIDDLE), 'Ant');
  const leaf = D.byName(container, LEAF);
  assert.equal(D.hint(leaf).parentNode, leaf.closest('.cf-wizard-field'), 'the hint sits outside the label');
});

test('X6 observers watch child lists only; a menu filled later is bound once; nothing without a wizard entry', async () => {
  const observed = [];
  const html = F.read('wizard_entry');
  const inner = html.replace(/^<div id="context-menu">/, '').replace(/<\/div>\s*$/, '');
  const pg = await wizardPage({
    body: '<div id="content"></div>',
    before(w) {
      const observe = w.MutationObserver.prototype.observe;
      w.MutationObserver.prototype.observe = function (target, options) {
        observed.push(options);
        return observe.call(this, target, options);
      };
    }
  });
  assert.deepEqual(JSON.parse(JSON.stringify(observed)), [{ childList: true, subtree: true }, { childList: true, subtree: true }]);
  const menu = pg.document.createElement('div');
  menu.id = 'context-menu';
  const clicks = [];
  const add = menu.addEventListener;
  menu.addEventListener = function (type, fn, o) {
    if (type === 'click') clicks.push(fn);
    return add.call(this, type, fn, o);
  };
  pg.document.body.appendChild(menu);
  menu.innerHTML = '<ul><li><a href="#">Status</a></li></ul>';
  await D.microtask();
  assert.equal(menu.dataset.dcfInit, undefined, 'no wizard entry, no binding');
  pg.document.body.setAttribute('style', 'color: red');
  menu.setAttribute('style', 'left: 10px');
  await D.microtask();
  assert.equal(menu.dataset.dcfInit, undefined);
  menu.innerHTML = inner;
  await D.microtask();
  assert.equal(menu.dataset.dcfInit, '1');
  menu.innerHTML = inner;
  await D.microtask();
  assert.equal(clicks.length, 1, 'one click listener after both fills');
  const api = pg.window.DependingCustomFields;
  const realInit = api.init;
  const inits = [];
  api.init = (root) => { inits.push(root); return realInit(root); };
  const container = await open(pg);
  // Changed by WP-36: the wizard's own init(container) once per click (the
  // runtime observer's pass for the added form follows); was any init.
  assert.equal(inits.filter((root) => root === container).length, 1, 'one open per click');
  assert.ok(container.querySelector('form.cf-wizard-form'));
  assert.equal(pg.document.querySelectorAll('#cf-wizard-container').length, 1);
});

// Review round 2: the head hook includes the wizard in <head>, before <body>
// exists (H1); the menu core fills later is bound and posts.
test('X6 loaded from the page head, the wizard binds a menu filled later and posts', async () => {
  const s = stubs();
  const html = F.read('wizard_entry');
  const inner = html.replace(/^<div id="context-menu">/, '').replace(/<\/div>\s*$/, '');
  const pg = await D.page('<div id="content"></div>', {
    head: true,
    url: URL_,
    scripts: ['window.dcfHeadBody = String(document.body);', D.WIZARD],
    before: s.before
  });
  assert.equal(pg.window.dcfHeadBody, 'null', 'no <body> while the head scripts run');
  const menu = pg.document.createElement('div');
  menu.id = 'context-menu';
  pg.document.body.appendChild(menu);
  menu.innerHTML = inner;
  await D.microtask();
  assert.equal(menu.dataset.dcfInit, '1');
  const container = await open(pg);
  const form = container.querySelector('form.cf-wizard-form');
  assert.equal(D.state(D.byName(form, MIDDLE)), 'unfiltered');
  submit(pg);
  await settle();
  assert.deepEqual(s.log.fetch.map((c) => c.url), [WIZARD_URL, 'https://redmine.example/depending_custom_fields/save']);
  assert.deepEqual(s.log.alerts, []);
  assert.deepEqual(pg.errors.filter((e) => !/navigation/i.test(String(e && e.message))), []);
});

test('the wizard opens and posts without the runtime (unfiltered)', async () => {
  const pg = await wizardPage({ runtime: '/* no runtime */' });
  const container = await open(pg);
  assert.equal(container.querySelectorAll('[data-dcf-state]').length, 0);
  submit(pg);
  await settle();
  assert.equal(saves(pg).length, 1);
  assert.deepEqual(realErrors(pg), []);
});

test('the wizard script assigns no markup from a variable and uses no ES2018 syntax', () => {
  assert.doesNotMatch(D.WIZARD, /innerHTML\s*=\s*(?!['"]['"])/);
  assert.doesNotMatch(D.WIZARD, /insertAdjacentHTML|outerHTML\s*=|document\.write|createContextualFragment|\beval\(|new Function/);
  assert.doesNotMatch(D.WIZARD, /\?\.|\?\?|\.\.\.[A-Za-z_]/);
  assert.doesNotMatch(D.WIZARD, /requestSetup|ContextMenuWizardConfig|DependingCustomFieldData|basePath|form\.action\b/);
  // WP-36: the entry no longer names a template.
  assert.doesNotMatch(D.WIZARD, /templateId|template-id|\.content\.cloneNode/);
});

// ---- WP-36: the body is fetched when the wizard opens --------------------

// A promise that the test settles itself.
function deferred() {
  const d = {};
  d.promise = new Promise((resolve, reject) => { d.resolve = resolve; d.reject = reject; });
  return d;
}

// A load stub whose answers the test settles: calls[i].resolve(response).
function controlled() {
  const calls = [];
  return { calls, load: (url, init) => { const d = deferred(); d.url = String(url); d.init = init; calls.push(d); return d.promise; } };
}

const ENTRY_B = F.tweak('wizard_entry', (doc) => {
  const li = doc.querySelector('li.cf-parent');
  const b = li.cloneNode(true);
  b.setAttribute('data-parent-id', '9100004');
  b.querySelector('a').textContent = 'Second root';
  li.parentNode.appendChild(b);
});
const FORM_B = F.tweak('wizard_body', (doc) => doc.querySelector('form').setAttribute('data-parent-id', '9100004'));

function keydown(pg, key) {
  const ev = new pg.window.KeyboardEvent('keydown', { key, bubbles: true, cancelable: true });
  pg.document.dispatchEvent(ev);
  return ev;
}

function mousedownOutside(pg) {
  pg.document.body.dispatchEvent(new pg.window.MouseEvent('mousedown', { bubbles: true, cancelable: true }));
}

const closed = (container) => [container.style.display, container.childNodes.length];

test('L1 a click fetches the body once: GET, same origin, X-Requested-With, Accept text/html, no-store, no body', async () => {
  const pg = await wizardPage();
  const container = await open(pg);
  assert.equal(pg.log.fetch.length, 1);
  const call = pg.log.fetch[0];
  assert.equal(call.url, WIZARD_URL);
  assert.equal(call.init.method, 'GET');
  assert.equal(call.init.credentials, 'same-origin');
  assert.equal(call.init.cache, 'no-store');
  assert.equal(call.init.headers['X-Requested-With'], 'XMLHttpRequest');
  assert.equal(call.init.headers.Accept, 'text/html');
  assert.equal(call.init.body, undefined);
  assert.equal(container.querySelectorAll('form.cf-wizard-form').length, 1);
  const multi = await wizardPage({
    body: F.tweak('wizard_entry', (doc) => doc.querySelector('li').setAttribute('data-issue-ids', '9300001,9300002')),
    url: 'https://redmine.example/redmine/projects/x/issues'
  });
  await open(multi);
  assert.equal(multi.log.fetch[0].url,
    'https://redmine.example/depending_custom_fields/wizard?parent_id=9100001&ids%5B%5D=9300001&ids%5B%5D=9300002');
  const rooted = await wizardPage({
    body: F.tweak('wizard_entry', (doc) => doc.querySelector('li').setAttribute('data-wizard-url', '/redmine/depending_custom_fields/wizard'))
  });
  await open(rooted);
  assert.equal(rooted.log.fetch[0].url, WIZARD_URL.replace('/depending_custom_fields', '/redmine/depending_custom_fields'));
});

test('L2 the container shows an announced loading text at once, without a form or a field name', async () => {
  const c = controlled();
  const pg = await wizardPage({ load: c.load });
  const container = click(pg);
  assert.equal(container.style.display, 'block');
  assert.equal(container.getAttribute('aria-busy'), 'true');
  const status = container.querySelector('[role="status"]');
  assert.ok(status, 'a status element');
  assert.equal(status.textContent, LOADING);
  assert.equal(container.textContent, LOADING);
  assert.equal(container.querySelector('form'), null);
  c.calls[0].resolve(htmlResponse(F.read('wizard_body')));
  await settle();
  assert.equal(container.querySelectorAll('form.cf-wizard-form').length, 1);
  assert.equal(container.hasAttribute('aria-busy'), false);
  assert.equal(container.querySelector('[role="status"]'), null);
  assert.equal(container.style.display, 'block');
  assert.equal(pg.document.activeElement, D.byName(container, ROOT), 'focus moves to the first field');
  assert.deepEqual(realErrors(pg), []);
});

test('L2 the loading and failure texts come from the dcf-i18n meta tag, else English', async () => {
  const meta = { wizardLoading: 'Lade...', wizardLoadFailed: 'Der Assistent konnte nicht geladen werden.' };
  const c = controlled();
  const pg = await wizardPage({ meta, load: c.load });
  const container = click(pg);
  assert.equal(container.textContent, meta.wizardLoading);
  c.calls[0].resolve(htmlResponse('', { ok: false, status: 500 }));
  await settle();
  assert.equal(container.textContent, meta.wizardLoadFailed);
  for (const bad of ['{', '[1]', '{"wizardLoading":7,"wizardLoadFailed":{"x":1}}']) {
    const d = controlled();
    const other = await wizardPage({ meta: bad, load: d.load });
    const box = click(other);
    assert.equal(box.textContent, LOADING, bad);
    d.calls[0].reject(new TypeError('x'));
    await settle();
    assert.equal(box.textContent, LOAD_FAILED, bad);
  }
});

test('L3 a cross-origin, script, data, blank or missing wizard URL is refused without a request', async () => {
  const urls = ['https://evil.example/x', '//evil.example/x', 'javascript:alert(1)', 'data:text/html,x',
    'http://redmine.example/depending_custom_fields/wizard', 'https://redmine.example:8443/depending_custom_fields/wizard',
    '', '   ', null];
  for (const url of urls) {
    const body = F.tweak('wizard_entry', (doc) => {
      const li = doc.querySelector('li');
      if (url === null) li.removeAttribute('data-wizard-url');
      else li.setAttribute('data-wizard-url', url);
    });
    const pg = await wizardPage({ body });
    const container = await open(pg);
    assert.deepEqual(pg.log.fetch, [], String(url));
    assert.equal(container.style.display, 'block', String(url));
    assert.equal(container.querySelector('[role="alert"]').textContent, LOAD_FAILED, String(url));
    assert.equal(container.textContent, LOAD_FAILED, String(url));
    assert.equal(container.querySelector('form'), null, String(url));
    assert.deepEqual(realErrors(pg), [], String(url));
  }
});

test('L4 every failed load shows one generic message, never server text, and a later click retries', async () => {
  const leak = '<p>HiddenFieldName zz-secret</p><form class="cf-wizard-form"><select name="x"><option>HiddenValue</option></select></form>';
  const body = F.read('wizard_body');
  const cases = {
    reject: () => Promise.reject(new TypeError('Failed to fetch HiddenFieldName')),
    401: () => Promise.resolve(htmlResponse(leak, { ok: false, status: 401, statusText: 'HiddenFieldName' })),
    403: () => Promise.resolve(htmlResponse(leak, { ok: false, status: 403 })),
    404: () => Promise.resolve(htmlResponse(leak, { ok: false, status: 404 })),
    422: () => Promise.resolve(htmlResponse(leak, { ok: false, status: 422 })),
    500: () => Promise.resolve(htmlResponse(leak, { ok: false, status: 500 })),
    redirected: () => Promise.resolve(htmlResponse(body, { redirected: true })),
    json: () => Promise.resolve(htmlResponse(body, { headers: { get: () => 'application/json' } })),
    noType: () => Promise.resolve(htmlResponse(body, { headers: { get: () => null } })),
    noHeaders: () => Promise.resolve(htmlResponse(body, { headers: undefined })),
    empty: () => Promise.resolve(htmlResponse('')),
    twoForms: () => Promise.resolve(htmlResponse(body + body)),
    noForm: () => Promise.resolve(htmlResponse('<p>HiddenFieldName</p>')),
    otherForm: () => Promise.resolve(htmlResponse('<form id="login-form"><input name="username"></form>')),
    textRejects: () => Promise.resolve(htmlResponse(body, { text: () => Promise.reject(new Error('HiddenFieldName')) })),
    aborted: () => Promise.reject(Object.assign(new Error('The operation was aborted.'), { name: 'AbortError' }))
  };
  for (const [name, failure] of Object.entries(cases)) {
    let calls = 0;
    const logged = [];
    const pg = await wizardPage({
      load: () => { calls += 1; return calls === 1 ? failure() : Promise.resolve(htmlResponse(body)); },
      before(w) { ['log', 'warn', 'error', 'info', 'debug'].forEach((k) => { w.console[k] = (...a) => logged.push(a.join(' ')); }); }
    });
    const container = await open(pg);
    assert.equal(container.textContent, LOAD_FAILED, name);
    assert.equal(container.querySelectorAll('[role="alert"]').length, 1, name);
    assert.equal(container.querySelector('form'), null, name);
    assert.equal(container.style.display, 'block', name);
    assert.doesNotMatch(pg.document.body.textContent, /HiddenFieldName|HiddenValue|zz-secret/, name);
    assert.deepEqual(pg.log.alerts, [], name);
    const again = await open(pg);
    assert.equal(calls, 2, `${name}: a new request`);
    assert.equal(again.querySelectorAll('form.cf-wizard-form').length, 1, name);
    assert.equal(again.querySelector('[role="alert"]'), null, name);
    assert.deepEqual(logged.filter((l) => /HiddenFieldName|zz-secret/.test(l)), [], name);
    assert.deepEqual(realErrors(pg), [], name);
  }
});

test('L5 scripts and event handler attributes of the body never run and are not kept', async () => {
  const form = F.tweak('wizard_body', (doc) => {
    const f = doc.querySelector('form');
    const script = doc.createElement('script');
    script.textContent = 'window.dcfPwned = 1;';
    f.appendChild(script);
    const img = doc.createElement('img');
    img.setAttribute('src', 'data:,x');
    img.setAttribute('onerror', 'window.dcfPwned2 = 1');
    img.setAttribute('onload', 'window.dcfPwned3 = 1');
    f.appendChild(img);
    D.byName(f, ROOT).setAttribute('onchange', 'window.dcfPwned4 = 1');
  });
  const outside = '<script>window.dcfPwned5 = 1;</script>';
  const s = stubs(null, () => Promise.resolve(htmlResponse(outside + form)));
  const pg = await D.page(F.read('wizard_entry'), { head: true, url: URL_, scripts: [D.WIZARD], before: s.before });
  pg.log = s.log;
  const container = await open(pg);
  fire.choose(pg.window, D.byName(container, ROOT), 'Alpha');
  await settle();
  assert.equal(container.querySelectorAll('form.cf-wizard-form').length, 1);
  assert.equal(container.querySelectorAll('script').length, 0);
  assert.equal(container.querySelectorAll('[onerror], [onload], [onchange]').length, 0);
  ['dcfPwned', 'dcfPwned2', 'dcfPwned3', 'dcfPwned4', 'dcfPwned5'].forEach((k) => assert.equal(pg.window[k], undefined, k));
});

test('L6 a second click while loading or after the body is shown gives one form and one submit handler', async () => {
  const c = controlled();
  const pg = await wizardPage({ load: c.load });
  const container = click(pg);
  click(pg);
  assert.equal(c.calls.length, 2, 'the second click asks again');
  if (c.calls[0].init.signal) assert.equal(c.calls[0].init.signal.aborted, true, 'the first request is aborted');
  c.calls[1].resolve(htmlResponse(F.read('wizard_body')));
  c.calls[0].resolve(htmlResponse(F.read('wizard_body')));
  await settle();
  assert.equal(container.querySelectorAll('form').length, 1);
  click(pg);
  c.calls[2].resolve(htmlResponse(F.read('wizard_body')));
  await settle();
  assert.equal(container.querySelectorAll('form').length, 1);
  assert.equal(pg.document.querySelectorAll('#cf-wizard-container').length, 1);
  submit(pg);
  await settle();
  assert.equal(saves(pg).length, 1, 'one submit handler');
});

test('L6 a late answer for another entry, a closed wizard or a rebuilt menu is dropped', async () => {
  const c = controlled();
  const pg = await wizardPage({ body: ENTRY_B, load: c.load });
  const container = click(pg, '9100001');
  click(pg, '9100004');
  c.calls[1].resolve(htmlResponse(FORM_B));
  await settle();
  c.calls[0].resolve(htmlResponse(F.read('wizard_body')));
  await settle();
  assert.deepEqual(Array.from(container.querySelectorAll('form')).map((f) => f.getAttribute('data-parent-id')), ['9100004']);
  assert.ok(c.calls[1].url.includes('parent_id=9100004'));

  click(pg, '9100001');
  keydown(pg, 'Escape');
  c.calls[2].resolve(htmlResponse(F.read('wizard_body')));
  await settle();
  assert.deepEqual(closed(container), ['none', 0], 'Escape while loading');

  click(pg, '9100001');
  mousedownOutside(pg);
  c.calls[3].resolve(htmlResponse(F.read('wizard_body')));
  await settle();
  assert.deepEqual(closed(container), ['none', 0], 'outside mousedown while loading');

  click(pg, '9100001');
  const menu = pg.document.getElementById('context-menu');
  menu.textContent = '';
  c.calls[4].resolve(htmlResponse(F.read('wizard_body')));
  await settle();
  assert.equal(container.querySelector('form'), null, 'menu rebuilt by core');
  assert.deepEqual(realErrors(pg), []);
});

test('L6 every open fetches again: nothing is reused between opens', async () => {
  const pg = await wizardPage();
  const first = await open(pg);
  const token1 = first.querySelector('input[name="authenticity_token"]');
  keydown(pg, 'Escape');
  const second = await open(pg);
  assert.equal(pg.log.fetch.length, 2);
  assert.notEqual(second.querySelector('input[name="authenticity_token"]'), token1);
  assert.equal(second.querySelectorAll('form').length, 1);
});

test('L7 Escape closes while loading and when shown, focus returns to the entry, and the listener goes', async () => {
  const pg = await wizardPage();
  const entry = pg.document.querySelector('#context-menu li.cf-parent > a.submenu');
  const container = await open(pg);
  assert.equal(pg.document.activeElement, D.byName(container, ROOT));
  const ev = keydown(pg, 'Escape');
  assert.equal(ev.defaultPrevented, true);
  assert.deepEqual(closed(container), ['none', 0]);
  assert.equal(pg.document.activeElement, entry, 'focus back on the entry');
  assert.equal(keydown(pg, 'Escape').defaultPrevented, false, 'no listener after close');
  await open(pg);
  keydown(pg, 'Enter');
  assert.equal(container.style.display, 'block', 'other keys do nothing');
  assert.deepEqual(saves(pg), []);
  assert.deepEqual(realErrors(pg), []);
});

test('L7 the Cancel button closes without a request and returns the focus to the entry', async () => {
  const pg = await wizardPage();
  const entry = pg.document.querySelector('#context-menu li.cf-parent > a.submenu');
  const container = await open(pg);
  const cancel = container.querySelector('form.cf-wizard-form button.cf-wizard-cancel');
  assert.equal(cancel.getAttribute('type'), 'button');
  assert.equal(cancel.textContent, 'Cancel');
  fire.choose(pg.window, D.byName(container, ROOT), 'Alpha');
  cancel.dispatchEvent(new pg.window.MouseEvent('click', { bubbles: true, cancelable: true }));
  await settle();
  assert.deepEqual(closed(container), ['none', 0]);
  assert.equal(pg.document.activeElement, entry);
  assert.deepEqual(saves(pg), []);
  assert.equal(pg.log.fetch.length, 1);
});

test('L7 every listener added while loading or shown is removed on close', async () => {
  const counts = {};
  const track = (target, label) => {
    const add = target.addEventListener;
    const remove = target.removeEventListener;
    target.addEventListener = function (type, fn, o) { counts[`${label}:${type}`] = (counts[`${label}:${type}`] || 0) + 1; return add.call(this, type, fn, o); };
    target.removeEventListener = function (type, fn, o) { counts[`${label}:${type}`] = (counts[`${label}:${type}`] || 0) - 1; return remove.call(this, type, fn, o); };
  };
  const c = controlled();
  const pg = await wizardPage({ load: c.load });
  track(pg.document, 'doc');
  const menu = pg.document.getElementById('context-menu');
  track(menu, 'menu');
  const container = click(pg);
  keydown(pg, 'Escape');
  click(pg);
  c.calls[1].resolve(htmlResponse(F.read('wizard_body')));
  await settle();
  mousedownOutside(pg);
  click(pg);
  c.calls[2].resolve(htmlResponse('', { ok: false, status: 404 }));
  await settle();
  keydown(pg, 'Escape');
  assert.deepEqual(closed(container), ['none', 0]);
  Object.keys(counts).forEach((k) => assert.equal(counts[k], 0, k));
  assert.ok(Object.keys(counts).includes('doc:keydown') && Object.keys(counts).includes('doc:mousedown'));
});
