'use strict';
// WP-18: assets/javascripts/context_menu_wizard.js with the runtime, on the
// generated wizard fixture (frontend design 3.5 and 7, rows W1..W6 and X6):
// every field opens on '(no change)' and is initialised synchronously, the
// form posts to its own action resolved against the page URL (same origin
// only, SP-15), errors give a localized alert and keep the wizard open, the
// wizard is scoped to its form, fields carry implicit labels, and the
// observer watches child lists only. fetch and alert are stubbed (jsdom has
// neither); location.reload() is reported by jsdom as a navigation error.
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

// A fetch stub: respond(url, init) gives the Promise fetch returns.
function stubs(respond) {
  const log = { fetch: [], alerts: [] };
  return {
    log,
    before(w) {
      w.fetch = (url, init) => {
        log.fetch.push({ url: String(url), init });
        return respond ? respond(url, init) : Promise.resolve({ ok: true, status: 200, redirected: false });
      };
      w.alert = (text) => { log.alerts.push(String(text)); };
    }
  };
}

async function wizardPage(opts) {
  const o = Object.assign({ body: F.read('wizard_template') }, opts || {});
  const s = stubs(o.respond);
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

function open(pg) {
  const a = pg.document.querySelector('#context-menu li.cf-parent > a.submenu');
  a.dispatchEvent(new pg.window.MouseEvent('click', { bubbles: true, cancelable: true }));
  return pg.document.getElementById('cf-wizard-container');
}

function submit(pg) {
  const form = pg.document.querySelector('#cf-wizard-container form.cf-wizard-form');
  const ev = new pg.window.Event('submit', { bubbles: true, cancelable: true });
  form.dispatchEvent(ev);
  return ev;
}

const settle = async () => { for (let i = 0; i < 5; i += 1) await D.flush(); };
const bodyPairs = (pg, call) => Array.from(new pg.window.URLSearchParams(call.init.body).entries());
const cfPairs = (pg, call) => bodyPairs(pg, call).filter(([k]) => k.includes('[custom_field_values]'));
// jsdom reports location.reload() as not implemented navigation.
const realErrors = (pg) => pg.errors.filter((e) => !/navigation/i.test(String(e && e.message)));

test('W1 every field opens on (no change), synchronously initialised, and a save without a choice posts only blanks', async () => {
  const pg = await wizardPage();
  const api = pg.window.DependingCustomFields;
  const inits = [];
  const realInit = api.init;
  api.init = (root) => { inits.push([root, root.isConnected]); return realInit(root); };
  api.requestSetup = () => { throw new Error('requestSetup called'); };
  assert.equal(pg.document.getElementById('cf-wizard-container'), null, 'the container is created on the first open');
  const timers = pg.clock.calls;

  const container = open(pg);
  const form = container.querySelector('form.cf-wizard-form');
  assert.deepEqual([D.byName(form, ROOT), D.byName(form, MIDDLE), D.byName(form, LEAF)].map((s) => s.value), ['', '', '']);
  assert.deepEqual([D.state(D.byName(form, MIDDLE)), D.state(D.byName(form, LEAF))], ['unfiltered', 'unfiltered'],
    'initialised before any timer or microtask');
  assert.equal(inits.length, 1);
  assert.equal(inits[0][0], container);
  assert.equal(inits[0][1], true, 'the container is connected when init runs');
  assert.equal(pg.clock.calls, timers, 'no timer from the wizard');
  assert.equal(container.style.display, 'block');
  const updates = pg.updates.length;
  const records = [];
  const mo = new pg.window.MutationObserver((r) => records.push(...r));
  mo.observe(container, { attributes: true, childList: true, subtree: true });
  await D.microtask();
  await D.microtask();
  mo.disconnect();
  assert.deepEqual([pg.updates.length - updates, records.length], [0, 0], 'the observer pass after the clone is a no-op');

  const ev = submit(pg);
  assert.equal(ev.defaultPrevented, true);
  await settle();
  assert.equal(pg.log.fetch.length, 1);
  const call = pg.log.fetch[0];
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
  const form = open(pg).querySelector('form');
  fire.choose(pg.window, D.byName(form, ROOT), '__none__');
  const middle = D.byName(form, MIDDLE);
  const leaf = D.byName(form, LEAF);
  assert.deepEqual([middle.value, leaf.value], ['__none__', '__none__']);
  assert.equal(D.hintText(middle), 'Cleared because the current choice for Root field allows no values for this field.');
  assert.equal(middle.classList.contains('dcf-auto-applied'), false);
  submit(pg);
  await settle();
  assert.deepEqual(cfPairs(pg, pg.log.fetch[0]), [[ROOT, '__none__'], [MIDDLE, '__none__'], [LEAF, '__none__']]);
});

test('W2 a concrete root preselects the per-parent default with its hint; back to (no change) restores (no change)', async () => {
  const pg = await wizardPage();
  const form = open(pg).querySelector('form');
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
  assert.deepEqual(cfPairs(pg, pg.log.fetch[0]), [[ROOT, ''], [MIDDLE, ''], [LEAF, '']]);
});

// WP-19 (UD-10): a required middle field carries the marked (none) the
// server renders (bulk_edit_tag through render_custom_field); the wizard
// fixture has no required field, so the option is marked here.
test('W2 a required descendant\'s marked (none) is usable only while the root allows nothing', async () => {
  const body = F.tweak('wizard_template', (doc) => {
    const select = doc.querySelector('template').content.querySelector(`select[name="${MIDDLE}"]`);
    select.querySelector('option[value="__none__"]').setAttribute('data-dcf-required-none', '1');
  });
  const pg = await wizardPage({ body });
  const form = open(pg).querySelector('form');
  const middle = D.byName(form, MIDDLE);
  const none = Array.from(middle.options).find((o) => o.value === '__none__');
  assert.deepEqual([none.disabled, none.hidden, middle.value], [true, true, '']);
  fire.choose(pg.window, D.byName(form, ROOT), 'Alpha');
  assert.deepEqual([none.disabled, none.hidden, middle.value], [true, true, '']);
  fire.choose(pg.window, D.byName(form, ROOT), '__none__');
  assert.deepEqual([none.disabled, none.hidden, middle.value], [false, false, '__none__']);
  assert.equal(D.hintText(middle), 'Cleared because the current choice for Root field allows no values for this field.');
  fire.choose(pg.window, D.byName(form, ROOT), '');
  assert.deepEqual([none.disabled, none.hidden, middle.value], [true, true, '']);
  fire.choose(pg.window, D.byName(form, ROOT), '__none__');
  submit(pg);
  await settle();
  assert.deepEqual(cfPairs(pg, pg.log.fetch[0]).filter(([k]) => k === MIDDLE), [[MIDDLE, '__none__']]);
});

test('W3 the action is resolved against the page URL: a relative URL root is kept', async () => {
  const body = F.tweak('wizard_template', (doc) => {
    doc.querySelector('template').content.querySelector('form').setAttribute('action', '/redmine/depending_custom_fields/save');
  });
  const pg = await wizardPage({ body });
  open(pg);
  submit(pg);
  await settle();
  assert.deepEqual(pg.log.fetch.map((c) => c.url), ['https://redmine.example/redmine/depending_custom_fields/save']);
});

test('W3 a control named action and a <base href> do not change the target', async () => {
  const body = F.tweak('wizard_template', (doc) => {
    const form = doc.querySelector('template').content.querySelector('form');
    form.insertAdjacentHTML('afterbegin', '<input type="hidden" name="action" value="https://evil.example/x">');
  });
  const pg = await wizardPage({ body, headHtml: '<base href="https://evil.example/">' });
  open(pg);
  submit(pg);
  await settle();
  assert.deepEqual(pg.log.fetch.map((c) => c.url), ['https://redmine.example/depending_custom_fields/save']);
});

test('W3 a cross-origin, scheme-changing, script, data, blank or missing action is refused without a request', async () => {
  const actions = ['https://evil.example/x', '//evil.example/x', 'javascript:alert(1)', 'data:text/html,x',
    'http://redmine.example/depending_custom_fields/save', 'https://redmine.example:8443/depending_custom_fields/save',
    '', '   ', null];
  for (const action of actions) {
    const body = F.tweak('wizard_template', (doc) => {
      const form = doc.querySelector('template').content.querySelector('form');
      if (action === null) form.removeAttribute('action');
      else form.setAttribute('action', action);
    });
    const pg = await wizardPage({ body });
    const container = open(pg);
    submit(pg);
    await settle();
    assert.deepEqual(pg.log.fetch, [], String(action));
    assert.deepEqual(pg.log.alerts, [SAVE_FAILED], String(action));
    assert.equal(container.style.display, 'block', String(action));
    assert.deepEqual(realErrors(pg), [], String(action));
  }
});

test('W3 about:blank (origin null) refuses even a relative action', async () => {
  const pg = await wizardPage({ url: 'about:blank' });
  open(pg);
  submit(pg);
  await settle();
  assert.deepEqual([pg.log.fetch.length, pg.log.alerts], [0, [SAVE_FAILED]]);
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
      const container = open(pg);
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
  open(pg);
  submit(pg);
  await settle();
  assert.deepEqual(pg.log.alerts, [`${DE_SAVE_FAILED} (500)`]);
  for (const meta of ['{', '[1]', '{"saveFailed":7}', '{"saveFailed":{"x":1}}']) {
    const bad = await wizardPage({ meta, body: F.tweak('wizard_template', (doc) => doc.querySelector('template').content.querySelector('form').setAttribute('action', 'https://evil.example/')) });
    open(bad);
    submit(bad);
    await settle();
    assert.deepEqual(bad.log.alerts, [SAVE_FAILED], meta);
  }
});

test('W4 a success reloads the page once and closes the wizard', async () => {
  const pg = await wizardPage();
  const container = open(pg);
  submit(pg);
  await settle();
  assert.equal(pg.log.fetch.length, 1);
  assert.deepEqual(pg.log.alerts, []);
  assert.equal(pg.errors.filter((e) => /navigation/i.test(String(e && e.message))).length, 1, 'location.reload()');
  assert.equal(container.style.display, 'none');
});

test('W5 the wizard and an issue form on the same page stay apart', async () => {
  const pg = await wizardPage({ body: `${F.read('list_single')}${F.read('wizard_template')}` });
  const issueForm = pg.document.getElementById('issue-form');
  const issueChild = D.control(issueForm, '9100002');
  const form = open(pg).querySelector('form');
  fire.choose(pg.window, D.byName(form, ROOT), 'Beta');
  assert.deepEqual([D.state(issueChild), D.selected(issueChild)], ['ok', ['Ant']]);
  fire.choose(pg.window, D.byName(issueForm, 'issue[custom_field_values][9100001]'), 'Beta');
  assert.deepEqual(D.enabled(D.byName(form, MIDDLE)), ['', '__none__', 'Bee']);
});

test('W6 each wizard field wraps its name and select in an implicit label without for or id', async () => {
  const pg = await wizardPage();
  const container = open(pg);
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
  const html = F.read('wizard_template');
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
  let inits = 0;
  api.init = (root) => { inits += 1; return realInit(root); };
  const container = open(pg);
  assert.equal(inits, 1, 'one open per click');
  assert.ok(container.querySelector('form.cf-wizard-form'));
  assert.equal(pg.document.querySelectorAll('#cf-wizard-container').length, 1);
});

// Review round 2: the head hook includes the wizard in <head>, before <body>
// exists (H1); the menu core fills later is bound and posts.
test('X6 loaded from the page head, the wizard binds a menu filled later and posts', async () => {
  const s = stubs();
  const html = F.read('wizard_template');
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
  const container = open(pg);
  const form = container.querySelector('form.cf-wizard-form');
  assert.equal(D.state(D.byName(form, MIDDLE)), 'unfiltered');
  submit(pg);
  await settle();
  assert.deepEqual(s.log.fetch.map((c) => c.url), ['https://redmine.example/depending_custom_fields/save']);
  assert.deepEqual(s.log.alerts, []);
  assert.deepEqual(pg.errors.filter((e) => !/navigation/i.test(String(e && e.message))), []);
});

test('the wizard opens and posts without the runtime (unfiltered)', async () => {
  const pg = await wizardPage({ runtime: '/* no runtime */' });
  const container = open(pg);
  assert.equal(container.querySelectorAll('[data-dcf-state]').length, 0);
  submit(pg);
  await settle();
  assert.equal(pg.log.fetch.length, 1);
  assert.deepEqual(realErrors(pg), []);
});

test('the wizard script assigns no markup from a variable and uses no ES2018 syntax', () => {
  assert.doesNotMatch(D.WIZARD, /innerHTML\s*=\s*(?!['"]['"])/);
  assert.doesNotMatch(D.WIZARD, /insertAdjacentHTML|outerHTML\s*=|document\.write/);
  assert.doesNotMatch(D.WIZARD, /\?\.|\?\?|\.\.\.[A-Za-z_]/);
  assert.doesNotMatch(D.WIZARD, /requestSetup|ContextMenuWizardConfig|DependingCustomFieldData|basePath|form\.action\b/);
});
