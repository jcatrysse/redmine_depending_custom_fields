/*
 * Dirty guard of the page-mode values form (WP-30, project design 5): a
 * filtered or paginated Key/Value list page saves only the rows it shows,
 * so leaving it with unsaved edits asks first. Active only on
 * form[data-dcf-page-scope] carrying data-dcf-warn-unsaved (absent when the
 * user turned the warning off). Plain DOM, no globals, no library.
 *
 * - beforeunload: a listener added while the form holds edits (the window
 *   property belongs to core's warnLeavingUnsaved).
 * - span.pagination a and form.dcf-values-filter: one confirm; Cancel stops
 *   the event before rails-ujs sees it, OK leaves without a second prompt.
 * - form.dcf-values-sort: rails-ujs asks data-confirm on the bubbling click,
 *   so the guard asks one combined question in the capture phase and hides
 *   data-confirm from rails-ujs for that click.
 * - Submitting the page form itself clears the guard; other forms do not.
 *   OK and that submit quiet one beforeunload only, so an aborted
 *   navigation keeps the guard.
 */
(function () {
  'use strict';

  var MARK = Symbol.for('dcf.valuesPage');
  var LINKS = 'span.pagination a';
  var FILTER = 'form.dcf-values-filter';
  var SORT_SUBMIT = 'form.dcf-values-sort [type=submit], form.dcf-values-sort button:not([type])';

  // Edited controls differ from their markup defaults, so reverting an edit
  // or a value the browser restored counts as what it is.
  function changed(form) {
    var elements = form.elements;
    for (var i = 0; i < elements.length; i += 1) {
      var el = elements[i];
      if (el.type === 'checkbox' || el.type === 'radio') {
        if (el.checked !== el.defaultChecked) return true;
      } else if (el.type === 'text' || el.tagName === 'TEXTAREA') {
        if (el.value !== el.defaultValue) return true;
      }
    }
    return false;
  }

  function guard(form, text) {
    var doc = form.ownerDocument;
    var win = doc.defaultView;
    var leaving = false;
    var listening = false;

    function armed() {
      return !leaving && form.isConnected && changed(form);
    }

    // The leaving flag quiets the one beforeunload of the navigation it
    // allowed (set only while the listener exists); an aborted navigation
    // leaves the guard armed.
    function onBeforeUnload(e) {
      if (leaving) {
        leaving = false;
        return undefined;
      }
      if (!armed()) return undefined;
      e.preventDefault();
      e.returnValue = text;
      return text;
    }

    // The listener exists only while the form holds edits (bfcache).
    function sync() {
      var dirty = changed(form);
      if (dirty && !listening) win.addEventListener('beforeunload', onBeforeUnload);
      if (!dirty && listening) win.removeEventListener('beforeunload', onBeforeUnload);
      listening = dirty;
    }

    function ask(e, message) {
      if (win.confirm(message)) {
        leaving = listening;
        return true;
      }
      e.preventDefault();
      e.stopPropagation();
      return false;
    }

    function onClick(e) {
      var target = e.target;
      if (e.defaultPrevented || !target || typeof target.closest !== 'function') return;
      var link = target.closest(LINKS);
      if (link) {
        // A new tab or window leaves the page as it is.
        if (e.button !== 0 || e.ctrlKey || e.metaKey || e.shiftKey || e.altKey) return;
        if (armed()) ask(e, text);
        return;
      }
      var button = target.closest(SORT_SUBMIT);
      if (!button || !armed()) return;
      var sortText = button.getAttribute('data-confirm');
      if (!ask(e, sortText ? text + '\n\n' + sortText : text) || !sortText) return;
      button.removeAttribute('data-confirm');
      win.setTimeout(function () { button.setAttribute('data-confirm', sortText); }, 0);
    }

    function onSubmit(e) {
      var target = e.target;
      if (!target || typeof target.matches !== 'function' || !target.matches(FILTER)) return;
      if (armed()) ask(e, text);
    }

    form.addEventListener('input', sync);
    form.addEventListener('change', sync);
    form.addEventListener('submit', function () { leaving = listening; });
    // Capture phase on document: before rails-ujs's bubbling listeners.
    doc.addEventListener('click', onClick, true);
    doc.addEventListener('submit', onSubmit, true);
    win.addEventListener('pageshow', function (e) {
      if (!e.persisted) return;
      leaving = false;
      sync();
    });
    sync();
  }

  function start() {
    var form = document.querySelector('form[data-dcf-page-scope]');
    if (!form || form[MARK]) return;
    var text = form.getAttribute('data-dcf-warn-unsaved');
    if (!text) return;
    form[MARK] = true;
    guard(form, text);
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
})();
