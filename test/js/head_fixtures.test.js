'use strict';
// WP-18: the generated head fixtures (spec/frontend/head_fixtures_spec.rb,
// test/js/fixtures/head/<locale>.html): the head hook output in en, de, fr
// and nl. The page order is meta, runtime, wizard script, stylesheet; the
// runtime and the wizard read their texts from the meta tag, whose keys are
// exactly the runtime's English fallback keys.
const { test, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');
const acorn = require('acorn');
const D = require('./support/dom');
const F = require('./support/fixtures');

afterEach(D.closeAll);

const DIR = path.join(__dirname, 'fixtures', 'head');
const LOCALES = ['de', 'en', 'fr', 'nl'];
const read = (locale) => fs.readFileSync(path.join(DIR, `${locale}.html`), 'utf8');

function parsed(locale) {
  const doc = new JSDOM(`<!doctype html><html><head>${read(locale)}</head><body></body></html>`).window.document;
  const meta = doc.querySelector('meta[name="dcf-i18n"]');
  return { doc, payload: JSON.parse(meta.getAttribute('content')) };
}

// The property names of the runtime's `var I18N = {...}` (its English
// fallbacks), read from the parsed source.
function runtimeFallbackKeys() {
  const found = [];
  (function walk(node) {
    if (!node || typeof node.type !== 'string') return;
    if (node.type === 'VariableDeclarator' && node.id.name === 'I18N' && node.init && node.init.type === 'ObjectExpression') {
      found.push(node.init.properties.map((p) => p.key.name || p.key.value));
    }
    Object.keys(node).forEach((k) => {
      const v = node[k];
      if (Array.isArray(v)) v.forEach(walk);
      else if (v && typeof v === 'object') walk(v);
    });
  })(acorn.parse(D.RUNTIME, { ecmaVersion: 2017 }));
  assert.equal(found.length, 1, 'one I18N object in the runtime');
  return found[0];
}

test('one head fixture per locale and no other', () => {
  assert.deepEqual(fs.readdirSync(DIR).sort(), LOCALES.map((l) => `${l}.html`));
});

test('the head order is meta, runtime, wizard script, stylesheet, with nothing inline', () => {
  LOCALES.forEach((locale) => {
    const { doc } = parsed(locale);
    const nodes = Array.from(doc.head.children);
    assert.deepEqual(nodes.map((n) => n.tagName), ['META', 'SCRIPT', 'SCRIPT', 'LINK'], locale);
    assert.match(nodes[1].getAttribute('src'), /\/depending_custom_fields\.js$/);
    assert.match(nodes[2].getAttribute('src'), /\/context_menu_wizard\.js$/);
    assert.match(nodes[3].getAttribute('href'), /\/depending_custom_fields\.css$/);
    assert.equal(doc.querySelectorAll('script:not([src])').length, 0);
    assert.doesNotMatch(read(locale), /depending_custom_fields_legacy|DependingCustomFieldData|ContextMenuWizardConfig/);
  });
});

test('every locale has the same flat key set of own strings, and it equals the runtime fallback keys', async () => {
  const en = parsed('en').payload;
  const keys = Object.keys(en);
  // Review round 2: both directions, so a runtime key without a server text
  // (English in every locale) fails too.
  assert.deepEqual(runtimeFallbackKeys().slice().sort(), keys.slice().sort());
  const plain = await D.page(F.read('list_single'));
  const t = plain.window.DependingCustomFields.t;
  keys.forEach((k) => assert.notEqual(t(k), '', `fallback for ${k}`));
  assert.equal(t('noSuchKey'), '');
  LOCALES.forEach((locale) => {
    const payload = parsed(locale).payload;
    assert.deepEqual(Object.keys(payload), keys, locale);
    Object.keys(payload).forEach((k) => assert.equal(typeof payload[k], 'string', `${locale}.${k}`));
    if (locale !== 'en') {
      const same = keys.filter((k) => payload[k] === en[k]);
      assert.deepEqual(same, locale === 'fr' ? [] : ['liveMessage'], locale);
    }
  });
});

test('the runtime and the wizard read the texts of the head they are loaded after', async () => {
  for (const locale of LOCALES) {
    const head = read(locale);
    const payload = parsed(locale).payload;
    const alerts = [];
    const body = F.tweak('wizard_template', (doc) => {
      doc.querySelector('template').content.querySelector('form').setAttribute('action', 'https://evil.example/');
    });
    const pg = await D.page(`${F.read('list_single')}${body}`, {
      headHtml: head,
      url: 'https://redmine.example/issues/1',
      scripts: [D.WIZARD],
      before(w) {
        w.alert = (text) => alerts.push(text);
        w.fetch = () => { throw new Error('no request expected'); };
      }
    });
    const t = pg.window.DependingCustomFields.t;
    Object.keys(payload).forEach((k) => {
      if (!payload[k].includes('%{')) assert.equal(t(k), payload[k], `${locale}.${k}`);
    });
    const parent = D.byName(pg.document.getElementById('issue-form'), 'issue[custom_field_values][9100001]');
    parent.value = '';
    parent.dispatchEvent(new pg.window.Event('change', { bubbles: true }));
    const hint = D.hintText(D.control(pg.document.getElementById('issue-form'), '9100002'));
    assert.equal(hint, payload.selectParent.replace('%{parent}', 'Parent field'), locale);
    pg.document.querySelector('#context-menu li.cf-parent > a.submenu')
      .dispatchEvent(new pg.window.MouseEvent('click', { bubbles: true, cancelable: true }));
    pg.document.querySelector('#cf-wizard-container form')
      .dispatchEvent(new pg.window.Event('submit', { bubbles: true, cancelable: true }));
    await D.flush();
    assert.deepEqual(alerts, [payload.saveFailed], locale);
    assert.deepEqual(pg.errors, [], locale);
  }
});
