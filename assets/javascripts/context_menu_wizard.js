// Context-menu wizard (WP-18, frontend design 7): opens the wizard of a
// li.cf-parent entry in #cf-wizard-container (created on the first open),
// initialises it with the runtime at once and posts the form to its own
// action, same origin only (SP-15). Any save error gives a localized alert
// and keeps the wizard open. Texts come from <meta name="dcf-i18n">.
// WP-36 (UD-13 changed by the owner): the menu holds the entry only; a click
// shows a loading text at once and fetches the body from the entry's
// data-wizard-url (same origin only, GET, no-store), parses it inertly
// (DOMParser), imports its one form.cf-wizard-form without scripts or event
// handler attributes, and initialises it. A failed load shows one generic
// message. Each open fetches again; a closed or replaced wizard drops a late
// answer. Escape and the Cancel button close it and give the focus back to
// the entry.
(function () {
  'use strict';
  var FALLBACK = {
    saveFailed: 'The change could not be saved.',
    wizardLoading: 'Loading...',
    wizardLoadFailed: 'The wizard could not be loaded.'
  };
  var ENTRY_SEL = 'li.cf-parent';
  var FORM_SEL = 'form.cf-wizard-form';
  var STOPPED = ['mousedown', 'mouseup', 'click', 'contextmenu'];
  // {container, item, menu, outside, onKey, onMenuHover, stopProp, form,
  //  onSubmit, onCancel, cancel, abort}
  var current = null;

  // The text of key in the meta tag (a flat object of own strings), else the
  // English fallback (en.yml).
  function text(key) {
    var meta = document.querySelector('meta[name="dcf-i18n"]');
    var data = null;
    try {
      data = meta ? JSON.parse(meta.getAttribute('content') || '') : null;
    } catch (e) {
      data = null;
    }
    var own = data && typeof data === 'object' && !Array.isArray(data) &&
      Object.prototype.hasOwnProperty.call(data, key);
    return own && typeof data[key] === 'string' ? data[key] : FALLBACK[key];
  }

  function saveFailedText() {
    return text('saveFailed');
  }

  function ensureContainer() {
    let c = document.getElementById('cf-wizard-container');
    if (!c) {
      c = document.createElement('div');
      c.id = 'cf-wizard-container';
      c.className = 'context-menu cf-wizard';
      c.style.display = 'none';
      document.body.appendChild(c);
    }
    return c;
  }

  function setupMenu(menu) {
    if (!menu || menu.dataset.dcfInit) return;
    adjustWidth(menu);
    menu.addEventListener('click', e => {
      const a = e.target.closest('li.cf-parent > a.submenu');
      if (!a) return;
      const li = a.closest(ENTRY_SEL);
      if (!li) return;
      e.preventDefault(); e.stopPropagation();
      openWizard(menu, li);
    });
    menu.dataset.dcfInit = '1';
  }

  function adjustWidth(menu) {
    menu.classList.add('cf-has-wizard');
    menu.style.width = 'auto';
    menu.style.maxWidth = 'none';
  }

  // A status or alert line of the container (text only, no markup).
  function message(container, role, className, value) {
    const p = document.createElement('p');
    p.className = className;
    p.setAttribute('role', role);
    p.textContent = value;
    container.textContent = '';
    container.appendChild(p);
  }

  function openWizard(menu, item) {
    closeWizard(false);
    const container = ensureContainer();
    message(container, 'status', 'cf-wizard-loading', text('wizardLoading'));
    container.setAttribute('aria-busy', 'true');
    positionContainer(container, menu, item);
    container.style.display = 'block';

    const state = { container, item, menu, form: null, onSubmit: null, onCancel: null, cancel: null, abort: null };
    state.onMenuHover = e => {
      if (!item.contains(e.target)) closeWizard(false);
    };
    menu.addEventListener('mouseover', state.onMenuHover);
    state.outside = e => {
      if (!container.contains(e.target)) closeWizard(false);
    };
    document.addEventListener('mousedown', state.outside);
    state.onKey = e => {
      if (e.key !== 'Escape' && e.key !== 'Esc') return;
      e.preventDefault();
      closeWizard(true);
    };
    document.addEventListener('keydown', state.onKey);
    state.stopProp = e => e.stopPropagation();
    STOPPED.forEach(ev => container.addEventListener(ev, state.stopProp));
    current = state;

    const url = wizardUrl(item);
    if (!url) {
      failed(state);
      return;
    }
    const controller = typeof window.AbortController === 'function' ? new window.AbortController() : null;
    state.abort = controller;
    const init = {
      method: 'GET',
      credentials: 'same-origin',
      cache: 'no-store',
      headers: { 'X-Requested-With': 'XMLHttpRequest', 'Accept': 'text/html' }
    };
    if (controller) init.signal = controller.signal;
    let request;
    try {
      request = Promise.resolve(window.fetch(url, init));
    } catch (e) {
      request = Promise.reject(e);
    }
    request.then(res => {
      if (current !== state) return null;
      if (!res || !res.ok || res.redirected || !isHtml(res)) throw new Error('load');
      return res.text();
    }).then(body => {
      if (current !== state || body === null) return;
      if (!item.isConnected) {
        closeWizard(false);
        return;
      }
      const form = parseForm(body);
      if (!form) throw new Error('load');
      show(state, form);
    }).catch(() => {
      if (current === state) failed(state);
    });
  }

  function isHtml(res) {
    const headers = res.headers;
    const type = headers && typeof headers.get === 'function' ? headers.get('Content-Type') : null;
    return typeof type === 'string' && /^\s*text\/html\s*(;|$)/i.test(type);
  }

  // The one form.cf-wizard-form of body, parsed in an inert document, with
  // every script and event handler attribute removed; null when the body
  // holds no form or more than one.
  function parseForm(body) {
    if (typeof body !== 'string' || typeof window.DOMParser !== 'function') return null;
    const doc = new window.DOMParser().parseFromString(body, 'text/html');
    const forms = doc.querySelectorAll('form');
    if (forms.length !== 1 || !forms[0].matches(FORM_SEL)) return null;
    const form = forms[0];
    Array.prototype.forEach.call(form.querySelectorAll('script'), s => s.remove());
    [form].concat(Array.prototype.slice.call(form.querySelectorAll('*'))).forEach(el => {
      Array.prototype.slice.call(el.attributes).forEach(attr => {
        if (/^on/i.test(attr.name)) el.removeAttribute(attr.name);
      });
    });
    return form;
  }

  function show(state, parsed) {
    const container = state.container;
    container.textContent = '';
    container.removeAttribute('aria-busy');
    const form = document.importNode(parsed, true);
    container.appendChild(form);
    // The container is connected: the runtime filters the form at once (its
    // observer pass that follows is a no-op).
    const api = window.DependingCustomFields;
    if (api && typeof api.init === 'function') api.init(container);
    positionContainer(container, state.menu, state.item);
    container.style.display = 'block';

    state.form = form;
    state.onSubmit = e => {
      e.preventDefault();
      submitForm(form).then(saved => {
        if (saved) closeWizard(false);
      }, () => {
        window.alert(saveFailedText());
      });
    };
    form.addEventListener('submit', state.onSubmit);
    state.cancel = form.querySelector('button.cf-wizard-cancel');
    state.onCancel = e => {
      e.preventDefault();
      closeWizard(true);
    };
    if (state.cancel) state.cancel.addEventListener('click', state.onCancel);
    const first = form.querySelector('select, input:not([type="hidden"]), button');
    if (first && typeof first.focus === 'function') first.focus();
  }

  function failed(state) {
    state.container.removeAttribute('aria-busy');
    message(state.container, 'alert', 'cf-wizard-error', text('wizardLoadFailed'));
  }

  function positionContainer(container, menu, item) {
    const menuRect = menu.getBoundingClientRect();
    const itemRect = item ? item.getBoundingClientRect() : menuRect;
    container.style.position = 'absolute';
    container.style.top = (itemRect.top + window.scrollY) + 'px';
    container.style.left = (menuRect.right + window.scrollX + 2) + 'px';
  }

  // Closes the wizard, drops a pending load and removes every listener;
  // refocus gives the focus back to the entry (Escape, Cancel).
  function closeWizard(refocus) {
    if (!current) return;
    const state = current;
    current = null;
    const container = state.container;
    if (state.abort) state.abort.abort();
    container.style.display = 'none';
    container.removeAttribute('aria-busy');
    container.textContent = '';
    document.removeEventListener('mousedown', state.outside);
    document.removeEventListener('keydown', state.onKey);
    if (state.form) state.form.removeEventListener('submit', state.onSubmit);
    if (state.cancel) state.cancel.removeEventListener('click', state.onCancel);
    STOPPED.forEach(ev => container.removeEventListener(ev, state.stopProp));
    if (state.menu) state.menu.removeEventListener('mouseover', state.onMenuHover);
    if (refocus) {
      const link = state.item.querySelector('a.submenu');
      if (link && link.isConnected && typeof link.focus === 'function') link.focus();
    }
  }

  // An attribute URL resolved against the page URL, or null when it is
  // missing or blank or names another origin (SP-15). The attribute, never a
  // property: a control named action or a <base> element cannot redirect it.
  function sameOrigin(raw) {
    if (raw === null || !raw.trim()) return null;
    let url = null;
    try {
      url = new URL(raw, window.location.href);
    } catch (e) {
      return null;
    }
    const origin = window.location.origin;
    if (!origin || origin === 'null' || url.origin !== origin) return null;
    return url;
  }

  // The wizard URL of the entry with parent_id and ids[] of its selection.
  function wizardUrl(item) {
    const url = sameOrigin(item.getAttribute('data-wizard-url'));
    if (!url) return null;
    const query = new URLSearchParams();
    query.append('parent_id', item.getAttribute('data-parent-id') || '');
    (item.getAttribute('data-issue-ids') || '').split(',').filter(id => id !== '')
      .forEach(id => query.append('ids[]', id));
    url.search = query.toString();
    url.hash = '';
    return url.href;
  }

  // The form's action attribute resolved against the page URL, or null when
  // it is missing or blank or names another origin (SP-15). The attribute,
  // never the action property: a control named action or a <base> element
  // cannot redirect it.
  function actionUrl(form) {
    const url = sameOrigin(form ? form.getAttribute('action') : null);
    return url ? url.href : null;
  }

  // Resolves true after a successful save (the page reloads), false after
  // an error, which is alerted: the JSON errors of the server, else the
  // localized text with the status. A followed redirect (an expired
  // session) is no success.
  function submitForm(form) {
    const url = actionUrl(form);
    if (!url) {
      window.alert(saveFailedText());
      return Promise.resolve(false);
    }
    const body = new URLSearchParams(new FormData(form)).toString();
    return window.fetch(url, {
      method: 'POST',
      credentials: 'same-origin',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'X-Requested-With': 'XMLHttpRequest' },
      body: body
    }).then(res => {
      if (res.ok && !res.redirected) {
        window.location.reload();
        return true;
      }
      if (res.ok) {
        window.alert(saveFailedText());
        return false;
      }
      return failure(res);
    }, () => {
      window.alert(saveFailedText());
      return false;
    });
  }

  function failure(res) {
    const withStatus = () => saveFailedText() + ' (' + res.status + ')';
    const parse = typeof res.json === 'function' ? Promise.resolve().then(() => res.json()) : Promise.reject(new Error('no body'));
    return parse.then(data => {
      const errors = data && Array.isArray(data.errors) ? data.errors.filter(m => typeof m === 'string') : [];
      window.alert(errors.length ? errors.join('\n') : withStatus());
      return false;
    }, () => {
      window.alert(withStatus());
      return false;
    });
  }

  // Core fills #context-menu with .html(data): the added nodes are its
  // children, so an added node that is or holds a wizard entry binds the menu.
  function onMutations(records) {
    records.forEach(record => {
      Array.prototype.forEach.call(record.addedNodes, node => {
        if (node.nodeType !== 1) return;
        if (!node.matches(ENTRY_SEL) && !node.querySelector(ENTRY_SEL)) return;
        setupMenu(node.closest('#context-menu') || document.getElementById('context-menu'));
      });
    });
  }

  function start() {
    const menu = document.getElementById('context-menu');
    if (menu && menu.querySelector(ENTRY_SEL)) setupMenu(menu);
    if (typeof window.MutationObserver === 'function') {
      new window.MutationObserver(onMutations).observe(document.body || document.documentElement,
        { childList: true, subtree: true });
    }
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
})();
