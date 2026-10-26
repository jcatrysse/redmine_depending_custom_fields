// Context-menu wizard (WP-18, frontend design 7): opens the wizard template of
// a li.cf-parent entry in #cf-wizard-container (created on the first open),
// initialises it with the runtime at once and posts the form to its own
// action, same origin only (SP-15). Any error gives a localized alert and
// keeps the wizard open. Texts come from <meta name="dcf-i18n">.
(function () {
  'use strict';
  var SAVE_FAILED = 'The change could not be saved.';
  var ENTRY_SEL = 'li.cf-parent';
  var current = null; // {container, outside, onSubmit, form, stopProp, menu, onMenuHover, item}

  // The saveFailed text of the meta tag (a flat object of own strings), else
  // the English fallback (en.yml error_save_failed).
  function saveFailedText() {
    var meta = document.querySelector('meta[name="dcf-i18n"]');
    var data = null;
    try {
      data = meta ? JSON.parse(meta.getAttribute('content') || '') : null;
    } catch (e) {
      data = null;
    }
    var own = data && typeof data === 'object' && !Array.isArray(data) &&
      Object.prototype.hasOwnProperty.call(data, 'saveFailed');
    return own && typeof data.saveFailed === 'string' ? data.saveFailed : SAVE_FAILED;
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
      const tId = li ? li.dataset.templateId : null;
      if (!tId) return;
      e.preventDefault(); e.stopPropagation();
      const tmpl = document.getElementById(tId);
      if (!tmpl) return;
      openWizard(menu, tmpl, li);
    });
    menu.dataset.dcfInit = '1';
  }

  function adjustWidth(menu) {
    menu.classList.add('cf-has-wizard');
    menu.style.width = 'auto';
    menu.style.maxWidth = 'none';
  }

  function openWizard(menu, tmpl, item) {
    closeWizard();
    const container = ensureContainer();
    container.textContent = '';
    container.appendChild(tmpl.content.cloneNode(true));
    // The container is connected: the runtime filters the clone at once
    // (its observer pass that follows is a no-op).
    const api = window.DependingCustomFields;
    if (api && typeof api.init === 'function') api.init(container);
    positionContainer(container, menu, item);
    container.style.display = 'block';

    const form = container.querySelector('form');
    const onMenuHover = e => {
      if (!item.contains(e.target)) closeWizard();
    };
    menu.addEventListener('mouseover', onMenuHover);

    const outside = e => {
      if (!container.contains(e.target)) {
        closeWizard();
      }
    };
    document.addEventListener('mousedown', outside);

    const stopProp = e => e.stopPropagation();
    ['mousedown', 'mouseup', 'click', 'contextmenu']
      .forEach(ev => container.addEventListener(ev, stopProp));

    const onSubmit = e => {
      e.preventDefault();
      submitForm(form).then(saved => {
        if (saved) closeWizard();
      }, () => {
        window.alert(saveFailedText());
      });
    };
    if (form) form.addEventListener('submit', onSubmit);

    current = { container, outside, onSubmit, form, stopProp, menu, onMenuHover, item };
  }

  function positionContainer(container, menu, item) {
    const menuRect = menu.getBoundingClientRect();
    const itemRect = item ? item.getBoundingClientRect() : menuRect;
    container.style.position = 'absolute';
    container.style.top = (itemRect.top + window.scrollY) + 'px';
    container.style.left = (menuRect.right + window.scrollX + 2) + 'px';
  }

  function closeWizard() {
    if (!current) return;
    const { container, outside, onSubmit, form, stopProp, menu, onMenuHover } = current;
    container.style.display = 'none';
    container.textContent = '';
    document.removeEventListener('mousedown', outside);
    if (form) form.removeEventListener('submit', onSubmit);
    ['mousedown', 'mouseup', 'click', 'contextmenu']
      .forEach(ev => container.removeEventListener(ev, stopProp));
    if (menu) menu.removeEventListener('mouseover', onMenuHover);
    current = null;
  }

  // The form's action attribute resolved against the page URL, or null when
  // it is missing or blank or names another origin (SP-15). The attribute,
  // never the action property: a control named action or a <base> element
  // cannot redirect it.
  function actionUrl(form) {
    const raw = form ? form.getAttribute('action') : null;
    if (raw === null || !raw.trim()) return null;
    let url = null;
    try {
      url = new URL(raw, window.location.href);
    } catch (e) {
      return null;
    }
    const origin = window.location.origin;
    if (!origin || origin === 'null' || url.origin !== origin) return null;
    return url.href;
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
