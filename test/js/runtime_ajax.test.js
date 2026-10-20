'use strict';
// WP-17: AJAX re-renders (frontend design 5.10, 5.11 and 6, row F15, gap 13):
// core's updateIssueFrom and replaceIssueFormWith (core-7.0
// app/assets/javascripts/application-legacy.js:713-737, identical in core-5.1
// public/javascripts/application.js:606-630) run verbatim with jQuery 3.7.1.
const { test, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const D = require('./support/dom');
const E = require('./support/entries');
const F = require('./support/fixtures');
const fire = require('./support/fire');

afterEach(D.closeAll);

const PARENT = 'issue[custom_field_values][9100001]';
const CHILD = 'issue[custom_field_values][9100002]';

const CORE = `
function updateIssueFrom(url, el) {
  $('#all_attributes input, #all_attributes textarea, #all_attributes select').each(function(){
    $(this).data('valuebeforeupdate', $(this).val());
  });
  if (el) {
    $("#form_update_triggered_by").val($(el).attr('id'));
  }
  return $.ajax({
    url: url,
    type: 'post',
    data: $('#issue-form').serialize()
  });
}

function replaceIssueFormWith(html){
  var replacement = $(html);
  $('#all_attributes input, #all_attributes textarea, #all_attributes select').each(function(){
    var object_id = $(this).attr('id');
    if (object_id && $(this).data('valuebeforeupdate')!=$(this).val()) {
      replacement.find('#'+object_id).val($(this).val());
    }
  });
  $('#all_attributes').empty();
  $('#all_attributes').prepend(replacement);
}`;

// The inside of #all_attributes of a scenario (optionally tweaked).
function attributes(source) {
  const html = source.includes('<') ? source : F.read(source);
  const holder = F.tweak(html, () => {});
  const m = /<div id="all_attributes">([\s\S]*)<\/div>\s*(<fieldset|<\/form>)/.exec(holder);
  return m[1];
}

// Shaped like core's issues/_form: hidden trigger input, div#attributes with
// the custom field paragraphs, the carrier slot and a script.
const coreForm = (inner) => `\n<input type="hidden" name="form_update_triggered_by" id="form_update_triggered_by" value="">\n` +
  `<div id="attributes" class="attributes">${inner}</div>\n<span hidden></span>\n<script>window.ran = 1;</script>\n`;

async function load(source) {
  const pg = await D.page(source.includes('<') ? source : F.read(source), {
    before(window) {
      window.eval(CORE);
      window.ajaxCalls = [];
      window.jQuery.ajax = (o) => { window.ajaxCalls.push(o); return window.jQuery.Deferred().promise(); };
    }
  });
  // Spy on the public init: the observer must go through it.
  const api = pg.window.DependingCustomFields;
  const original = api.init;
  pg.inits = [];
  api.init = function (root) { pg.inits.push(root); return original.apply(this, arguments); };
  return pg;
}

const child = (pg) => D.control(pg.document, '9100002');
const parentOf = (pg) => D.byName(pg.document, PARENT);

test('F15 updateIssueFrom serializes exactly the spec entry list (no disabled control, no selected disabled option)', async () => {
  for (const scenario of ['list_single', 'legacy_value', 'new_issue', 'legacy_value_multi', 'multi_checkbox', 'radio', 'tricky_values', 'issue_time_entry_prefixes']) {
    const pg = await load(scenario);
    fire.choose(pg.window, parentOf(pg), scenario === 'tricky_values' ? 'comma, value' : 'Gamma');
    pg.window.updateIssueFrom('/issues/new.js', parentOf(pg));
    const posted = Array.from(new pg.window.URLSearchParams(pg.window.ajaxCalls[0].data).entries());
    assert.deepEqual(posted, E.entries(pg.document.getElementById('issue-form')), scenario);
  }
});

test('gap 13: one replaceIssueFormWith insertion inits once per added root, filtered before the next task, no timer', async () => {
  const pg = await load('list_single');
  const before = pg.clock.calls;
  pg.window.updateIssueFrom('/issues/1/edit.js', parentOf(pg));
  const inner = attributes(F.tweak('list_single', (doc) => F.selectValues(F.named(doc, CHILD), ['Ape'])));
  pg.window.replaceIssueFormWith(coreForm(inner));
  await D.microtask();
  assert.equal(pg.inits.length, 1);
  assert.equal(pg.inits[0].id, 'attributes');
  const c = child(pg);
  assert.equal(D.state(c), 'ok');
  assert.deepEqual([D.selected(c), Array.from(c.options).find((o) => o.value === 'Bee').disabled], [['Ape'], true]);
  assert.equal(pg.clock.calls, before, 'no setTimeout');
  assert.equal(pg.clock.pending(), 0);
});

test('gap 13: a fragment with two roots and nested children gives exactly two inits, none for a nested root', async () => {
  const pg = await load('list_single');
  const inner = attributes('list_single');
  const two = `<div id="r1"><div class="nested">${inner}</div></div><div id="r2">${attributes('chain_of_three')}</div><div id="plain"><p>x</p></div>`;
  pg.window.replaceIssueFormWith(two);
  await D.microtask();
  assert.deepEqual(pg.inits.map((r) => r.id), ['r1', 'r2']);
  assert.equal(pg.clock.pending(), 0);
});

test('gap 13: nested and removed roots of one task are coalesced; unrelated mutations cause no init', async () => {
  const pg = await load('list_single');
  const doc = pg.document;
  const make = (id) => {
    const div = doc.createElement('div');
    div.id = id;
    const tmp = doc.createElement('div');
    tmp.innerHTML = attributes('list_single');
    while (tmp.firstChild) div.appendChild(tmp.firstChild);
    return div;
  };
  const a = make('a');
  const b = make('b');
  doc.body.appendChild(a);
  a.appendChild(b);
  doc.body.removeChild(a);
  doc.body.appendChild(a);
  const gone = make('gone');
  doc.body.appendChild(gone);
  doc.body.removeChild(gone);
  doc.body.setAttribute('data-x', '1');
  doc.body.style.color = 'red';
  const plain = doc.createElement('div');
  for (let k = 0; k < 1000; k += 1) plain.appendChild(doc.createElement('p'));
  doc.body.appendChild(plain);
  await D.microtask();
  assert.deepEqual(pg.inits.map((r) => r.id), ['a']);
  pg.inits.length = 0;
  doc.body.setAttribute('data-y', '1');
  await D.microtask();
  assert.deepEqual(pg.inits, []);
});

test('gap 13: a chain split across two roots of one callback ends consistent', async () => {
  const pg = await load('<form id="issue-form"><div id="all_attributes"></div></form>');
  const html = F.tweak('chain_of_three', (doc) => F.selectValues(F.named(doc, CHILD), ['Bee']));
  const tmp = pg.document.createElement('div');
  tmp.innerHTML = html;
  const ps = Array.from(tmp.querySelectorAll('#all_attributes > p'));
  const root1 = pg.document.createElement('div');
  root1.appendChild(ps[0]);
  root1.appendChild(ps[2]);
  const root2 = pg.document.createElement('div');
  root2.appendChild(ps[1]);
  const target = pg.document.getElementById('all_attributes');
  target.appendChild(root1);
  target.appendChild(root2);
  await D.microtask();
  const middle = D.control(pg.document, '9100002');
  const leaf = D.control(pg.document, '9100003');
  assert.deepEqual([D.selected(middle), D.state(middle)], [[''], 'ok']);
  assert.deepEqual([D.selected(leaf), D.state(leaf)], [[''], 'waiting']);
});

test('F15 memory survives updateIssueFrom: the pick under Alpha comes back after a re-render (UN-07)', async () => {
  const pg = await load('list_single');
  fire.choose(pg.window, child(pg), 'Ape');
  fire.choose(pg.window, parentOf(pg), 'Beta');
  pg.window.updateIssueFrom('/issues/1/edit.js', parentOf(pg));
  const rerender = F.tweak('list_single', (doc) => {
    F.selectValues(F.named(doc, PARENT), ['Beta']);
    F.selectValues(F.named(doc, CHILD), ['']);
  });
  pg.window.replaceIssueFormWith(coreForm(attributes(rerender)));
  await D.microtask();
  assert.deepEqual(D.selected(child(pg)), ['']);
  fire.choose(pg.window, parentOf(pg), 'Alpha');
  assert.deepEqual(D.selected(child(pg)), ['Ape']);
});

test('F15 values copied in flight are classified by data-dcf-stored: a disallowed copied value is dropped', async () => {
  const pg = await load('list_single');
  pg.window.updateIssueFrom('/issues/1/edit.js', parentOf(pg));
  fire.choose(pg.window, child(pg), 'Ape');
  const rerender = F.tweak('list_single', (doc) => F.selectValues(F.named(doc, PARENT), ['Beta']));
  pg.window.replaceIssueFormWith(coreForm(attributes(rerender)));
  await D.microtask();
  const c = child(pg);
  assert.deepEqual([D.selected(c), D.enabled(c)], [[''], ['', 'Bee']]);
  assert.deepEqual(E.list(pg.document.forms[0], CHILD), [`${CHILD}=`]);
});

test('F15 a stored value under the unchanged parent stays legacy after a re-render', async () => {
  const pg = await load('legacy_value');
  pg.window.updateIssueFrom('/issues/1/edit.js', parentOf(pg));
  pg.window.replaceIssueFormWith(coreForm(attributes('legacy_value')));
  await D.microtask();
  assert.deepEqual([D.selected(child(pg)), D.state(child(pg))], [['Bee'], 'legacy']);
});

test('F13b tracker change removing the parent drops the value; switching back restores it through memory', async () => {
  const pg = await load('legacy_value');
  pg.window.updateIssueFrom('/issues/1/edit.js', parentOf(pg));
  pg.window.replaceIssueFormWith(coreForm(attributes('parent_unavailable')));
  await D.microtask();
  let c = child(pg);
  assert.deepEqual([D.selected(c), D.state(c), D.hintText(c)], [[''], 'empty', 'No values are available for this field.']);
  pg.window.updateIssueFrom('/issues/1/edit.js', null);
  const back = F.tweak('legacy_value', (doc) => F.selectValues(F.named(doc, CHILD), ['']));
  pg.window.replaceIssueFormWith(coreForm(attributes(back)));
  await D.microtask();
  c = child(pg);
  assert.deepEqual([D.selected(c), D.state(c)], [['Bee'], 'legacy']);
});

test('F13b pinned: a page opened with the parent unavailable does not get the value back when the parent returns', async () => {
  const pg = await load('parent_unavailable');
  pg.window.updateIssueFrom('/issues/1/edit.js', null);
  const back = F.tweak('legacy_value', (doc) => F.selectValues(F.named(doc, CHILD), ['']));
  pg.window.replaceIssueFormWith(coreForm(attributes(back)));
  await D.microtask();
  const c = child(pg);
  assert.deepEqual([D.selected(c), D.state(c)], [[''], 'ok']);
  assert.ok(D.enabled(c).includes('Bee'), 'still eligible under the stored parent');
  fire.choose(pg.window, c, 'Bee');
  assert.deepEqual(E.list(pg.document.forms[0], CHILD), [`${CHILD}=Bee`]);
});
