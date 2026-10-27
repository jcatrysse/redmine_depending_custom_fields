/* Redmine Depending Custom Fields: dependency editor DOM layer (editor
 * design 5.4 to 5.11, WP-25). Builds the editor inside [data-dcf-editor-app]
 * from the data-dcf-editor-* attributes of the shared partial, with every
 * ValueList and State made by window.DcfDependencyEditorModel (WP-23). The
 * hidden input is the only named control; text goes in through textContent
 * and createTextNode, attributes through setAttribute, never as markup. No
 * plain object is keyed by values (Map, Set, WeakMap). A bad attribute leaves
 * the editor inert (QA-24): no write, no multipart switch, no submit gate.
 * window.DcfDependencyEditor = {init(root), get(root)}. ES2017, no build. */
(function (window) {
  'use strict';
  if (!window || !window.document || window.DcfDependencyEditor) return;

  var doc = window.document;
  var instances = new WeakMap();
  var live = new Set();
  var warnedModel = false;
  var SECTION_PAGE = 100;
  var ROW_PAGE = 200;
  var UNLINKED_PAGE = 200;
  var FILTER_MS = 150;
  var REVOKE_MS = 1000;
  var WRITE_MS = 150;
  var VALUES_MS = 300;
  var LIVE_MS = 400;
  var RATIO = new Map([['list', 1.2], ['enumeration', 1.6]]);
  var VIEWS = [['all', 'show_all'], ['linked', 'show_linked'], ['not_linked', 'show_not_linked'],
    ['unlinked', 'show_unlinked']];
  // Only when data-dcf-editor-i18n itself cannot be read.
  var FALLBACK_UNAVAILABLE = 'The dependency editor could not be started. Reload the page.';
  var INT_RE = /^(0|[1-9][0-9]{0,15})$/;
  var STRIP_RE = /^[\u0000\t\n\v\f\r ]+|[\u0000\t\n\v\f\r ]+$/g;
  var hasOwn = Object.prototype.hasOwnProperty;

  // ---------------------------------------------------------------- helpers
  function isPlain(o) {
    return o !== null && typeof o === 'object' && !Array.isArray(o);
  }

  function el(tag, cls, text) {
    var node = doc.createElement(tag);
    if (cls) node.className = cls;
    if (text !== undefined && text !== null) node.textContent = text;
    return node;
  }

  function button(marker, text) {
    var node = el('button', null, text);
    node.type = 'button';
    node.setAttribute(marker, '');
    return node;
  }

  // A label wrapping its control (the label text before or after it).
  function wrap(text, control, after) {
    var label = el('label');
    if (after) {
      label.appendChild(control);
      label.appendChild(doc.createTextNode(' ' + text));
    } else {
      label.appendChild(doc.createTextNode(text + ' '));
      label.appendChild(control);
    }
    return label;
  }

  function info(text) {
    var p = el('p', 'dcf-dep-editor__info');
    p.appendChild(el('em', 'info', text));
    return p;
  }

  function badge(text) {
    return el('span', 'badge badge-status-locked', text);
  }

  // %{name} in one pass with a replacer function, so '$&' or '%{count}'
  // inside a value stay literal.
  function interpolate(text, vars) {
    return String(text).replace(/%\{([a-z_]+)\}/g, function (match, name) {
      return vars && hasOwn.call(vars, name) ? String(vars[name]) : match;
    });
  }

  function numberFormat() {
    var lang = doc.documentElement && doc.documentElement.getAttribute('lang');
    try {
      return new Intl.NumberFormat(lang || undefined);
    } catch (e) {
      return new Intl.NumberFormat();
    }
  }

  function integer(raw, name) {
    if (typeof raw !== 'string' || !INT_RE.test(raw)) throw new TypeError('DcfDependencyEditor: ' + name);
    return Number(raw);
  }

  function json(root, name, check) {
    var value = JSON.parse(root.getAttribute('data-dcf-editor-' + name));
    if (check && !check(value)) throw new TypeError('DcfDependencyEditor: ' + name);
    return value;
  }

  // div.flash.<type>; the warning sprite where core offers createSVGIcon
  // and its icon source (6.1, 7.0), else the class background (UX-10).
  function flash(type, text, alert) {
    var box = el('div', 'flash ' + type);
    if (alert) box.setAttribute('role', 'alert');
    if (typeof window.createSVGIcon === 'function' && doc.querySelector('#icon-copy-source svg')) {
      try {
        box.appendChild(window.createSVGIcon('warning'));
      } catch (e) {
        // the class background stays
      }
    }
    if (text) box.appendChild(doc.createTextNode(text));
    return box;
  }

  // Possible values as core stores them (duplicates kept), for the
  // possible-values storage estimate.
  function storedValues(text) {
    var M = window.DcfDependencyEditorModel;
    return String(text || '').split(/[\n\r]+/).map(function (line) { return line.replace(STRIP_RE, ''); })
      .filter(function (v) { return !M.isBlank(v); });
  }

  // RFC 4180 with a BOM and CRLF (conflict export; WP-26 owns the full CSV
  // builder).
  function csvCell(value, sep) {
    var s = String(value);
    if (s.indexOf(sep) >= 0 || /["\r\n]/.test(s)) return '"' + s.replace(/"/g, '""') + '"';
    return s;
  }

  function csvText(rows, sep) {
    return '\ufeff' + rows.map(function (row) {
      return row.map(function (cell) { return csvCell(cell, sep); }).join(sep);
    }).join('\r\n') + '\r\n';
  }

  function download(text, name) {
    var URLs = window.URL;
    if (!URLs || typeof URLs.createObjectURL !== 'function' || typeof window.Blob !== 'function') return false;
    var url = URLs.createObjectURL(new window.Blob([text], { type: 'text/csv;charset=utf-8' }));
    var link = el('a');
    link.setAttribute('href', url);
    link.setAttribute('download', name);
    link.hidden = true;
    (doc.body || doc.documentElement).appendChild(link);
    link.click();
    // Some engines start the download after click() returns.
    window.setTimeout(function () {
      link.remove();
      if (typeof URLs.revokeObjectURL === 'function') URLs.revokeObjectURL(url);
    }, REVOKE_MS);
    return true;
  }

  // One debounce timer per section child filter.
  function childTimer(entry) {
    return 'child_filter:' + entry.item.key;
  }

  function utf8(text) {
    return window.DcfDependencyEditorModel.utf8Bytes(text);
  }

  function urlencodedLength(text) {
    try {
      return encodeURIComponent(text).length;
    } catch (e) {
      return utf8(text) * 3;
    }
  }

  // The successful controls of +form+ (enabled, named, checked, selected,
  // the submitter), as [name, value] pairs.
  function entries(form, submitter) {
    var out = [];
    Array.prototype.forEach.call(form.elements, function (control) {
      var name = control.name;
      if (!name || control.disabled) return;
      var tag = control.tagName;
      var type = (control.type || '').toLowerCase();
      if (tag === 'SELECT') {
        Array.prototype.forEach.call(control.options, function (o) { if (o.selected) out.push([name, o.value]); });
        return;
      }
      if (tag === 'BUTTON' || ['submit', 'image', 'reset', 'button'].indexOf(type) >= 0) {
        if (control === submitter) out.push([name, control.value || '']);
        return;
      }
      if ((type === 'checkbox' || type === 'radio') && !control.checked) return;
      if (type === 'file') {
        out.push([name, '']);
        return;
      }
      out.push([name, tag === 'TEXTAREA' ? String(control.value).replace(/\r?\n/g, '\r\n') : control.value]);
    });
    return out;
  }

  // Request body estimate for the encoding the form uses (editor design 5.9).
  function formBytes(form, encoding, submitter) {
    return entries(form, submitter).reduce(function (sum, pair) {
      if (encoding === 'multipart') return sum + utf8(pair[0]) + utf8(pair[1]) + 100;
      return sum + urlencodedLength(pair[0]) + urlencodedLength(pair[1]) + 2;
    }, 0);
  }

  // ---------------------------------------------------------------- config
  // Every attribute parsed and shape-checked; any failure throws (inert).
  function readConfig(root, M) {
    var attr = function (name) { return root.getAttribute('data-dcf-editor-' + name); };
    var has = function (name) { return root.hasAttribute('data-dcf-editor-' + name); };
    var mode = attr('mode');
    var kind = attr('kind');
    if (mode !== 'admin' && mode !== 'project') throw new TypeError('DcfDependencyEditor: mode');
    if (kind !== 'list' && kind !== 'enumeration') throw new TypeError('DcfDependencyEditor: kind');
    var form = root.closest('form');
    var scope = form || doc;
    var find = function (name) {
      var selector = attr(name + '-source');
      return selector ? scope.querySelector(selector) : null;
    };
    var maxForm = json(root, 'max-form-bytes', isPlain);
    var cfg = {
      mode: mode,
      kind: kind,
      form: form,
      i18n: json(root, 'i18n', isPlain),
      maxPayload: integer(attr('max-payload-bytes'), 'max-payload-bytes'),
      maxForm: { multipart: integer(String(maxForm.multipart), 'multipart'),
                 urlencoded: integer(String(maxForm.urlencoded), 'urlencoded') },
      parents: M.ValueList.fromWire(json(root, 'parent-values')),
      children: has('child-values') ? M.ValueList.fromWire(json(root, 'child-values')) : null,
      mapping: json(root, 'mapping', isPlain),
      conflict: has('conflict-mapping') ? json(root, 'conflict-mapping', isPlain) : null,
      base: null,
      fieldId: attr('field-id') || '',
      fieldType: attr('field-type') || '',
      fieldName: attr('field-name') || '',
      parentId: attr('parent-id') || '',
      parentName: attr('parent-name') || '',
      dirty: attr('dirty') === '1',
      multiple: attr('multiple') === '1',
      required: attr('required') === '1',
      valuesUrl: attr('values-url'),
      separator: attr('csv-separator') || ',',
      warnUnsaved: attr('warn-unsaved') === '1',
      alwaysSubmit: attr('always-submit') === '1',
      storageLimit: has('storage-limit') ? integer(attr('storage-limit'), 'storage-limit') : null,
      storageBase: has('storage-base') ? integer(attr('storage-base'), 'storage-base') : 0,
      valuesLimit: has('values-limit') ? integer(attr('values-limit'), 'values-limit') : null,
      storageWarn: has('storage-warn') ? integer(attr('storage-warn'), 'storage-warn') : 90,
      parentSource: null,
      valuesSource: null,
      multipleSource: null,
      requiredSource: null,
      formatSource: null,
      defaultRow: null
    };
    if (cfg.maxPayload < 1) throw new TypeError('DcfDependencyEditor: max-payload-bytes');
    if (mode === 'admin') {
      if (has('base')) {
        cfg.base = attr('base');
        if (!M.isDigest(cfg.base)) throw new TypeError('DcfDependencyEditor: base');
      }
      cfg.parentSource = find('parent');
      cfg.valuesSource = find('values');
      cfg.multipleSource = find('multiple');
      cfg.requiredSource = find('required');
      cfg.formatSource = find('format');
      var row = attr('default-value-row');
      cfg.defaultRow = row ? scope.querySelector(row) : null;
    }
    return cfg;
  }

  // ---------------------------------------------------------------- editor
  function Editor(root, M) {
    this.root = root;
    this.model = M;
    this.inert = false;
    this.dirty = false;
    this.submitting = false;
    this.timers = new Map();
    this.notes = new Map();
    this.sectionUi = new Map();
    this.sectionOf = new WeakMap();
    this.sectionLimit = SECTION_PAGE;
    this.parentQuery = [];
    this.onlyUnlinked = false;
    this.loading = false;
    this.request = 0;
    this.mine = null;
    this.input = root.querySelector('[data-dcf-editor-input]');
    this.app = root.querySelector('[data-dcf-editor-app]');
  }

  Editor.prototype.t = function (key, vars) {
    var text = this.config && hasOwn.call(this.config.i18n, key) ? this.config.i18n[key] : '';
    return vars ? interpolate(text, vars) : String(text);
  };

  Editor.prototype.n = function (value) {
    return this.numbers.format(value);
  };

  Editor.prototype.start = function () {
    var M = this.model;
    var cfg = readConfig(this.root, M);
    if (!this.input || !this.app) throw new TypeError('DcfDependencyEditor: markup');
    this.config = cfg;
    this.numbers = numberFormat();
    this.form = cfg.form;
    this.mode = cfg.mode;
    this.kind = cfg.kind;
    this.state = new M.State(cfg.mapping);
    this.mine = cfg.conflict ? new M.State(cfg.conflict) : null;
    this.renderedParents = cfg.parents;
    this.parents = cfg.parents;
    this.parentId = cfg.parentId;
    this.blank = this.mode === 'admin' && !cfg.parentId;
    this.multiple = cfg.multipleSource ? cfg.multipleSource.checked === true : cfg.multiple;
    this.required = cfg.requiredSource ? cfg.requiredSource.checked === true : cfg.required;
    this.children = cfg.children || this.childrenFromText();
    this.newEnumeration = this.mode === 'admin' && this.kind === 'enumeration' && !cfg.fieldId;
    this.format = cfg.formatSource ? cfg.formatSource.value : null;
    var warning = this.root.querySelector('[data-dcf-editor-required-warning]');
    this.requiredEl = warning;
    // The server hides the warning without an effective parent (stored
    // cycle); while that parent is selected the editor keeps it hidden.
    this.requiredSuppressed = !!warning && warning.classList.contains('dcf-hidden') &&
      this.requiredRule(cfg.required);
    this.build();
    this.dirty = cfg.dirty && !this.newEnumeration;
    this.app.hidden = false;
    this.orphans();
    if (this.mine) this.conflictPanel();
    this.listen();
    if (this.mode === 'admin' && this.form) this.form.enctype = 'multipart/form-data';
    if (this.mode === 'project' && this.form) {
      Array.prototype.forEach.call(this.form.querySelectorAll('[data-dcf-editor-submit]'), function (b) {
        b.disabled = false;
      });
    }
    this.write();
    this.storage();
    var selected = cfg.parentSource ? cfg.parentSource.value : cfg.parentId;
    if (this.mode === 'admin' && cfg.parentSource && selected !== cfg.parentId) this.parentChanged();
    else this.updateRequired();
  };

  Editor.prototype.childrenFromText = function () {
    var M = this.model;
    var source = this.config.valuesSource;
    return M.ValueList.fromWire(source ? M.listValuesFromText(source.value) : []);
  };

  // ---------------------------------------------------------------- notices
  // One keyed notice per id; text null removes it.
  Editor.prototype.notice = function (id, type, text, alert) {
    var old = this.notes.get(id);
    if (old) old.remove();
    this.notes.delete(id);
    if (text === null || text === undefined) return null;
    var box = flash(type, text, alert);
    box.setAttribute('data-dcf-ed-notice', id);
    this.noticesEl.appendChild(box);
    this.notes.set(id, box);
    return box;
  };

  Editor.prototype.hint = function (id, text) {
    var old = this.notes.get(id);
    if (old) old.remove();
    var p = info(text);
    p.setAttribute('data-dcf-ed-notice', id);
    this.noticesEl.appendChild(p);
    this.notes.set(id, p);
  };

  Editor.prototype.announce = function (text) {
    var region = this.liveEl;
    this.later('live', LIVE_MS, function () { region.textContent = text; });
  };

  Editor.prototype.later = function (name, ms, fn) {
    var old = this.timers.get(name);
    if (old) window.clearTimeout(old.handle);
    var self = this;
    var entry = { fn: fn, handle: null };
    entry.handle = window.setTimeout(function () {
      if (self.timers.get(name) === entry) self.timers.delete(name);
      fn();
    }, ms);
    this.timers.set(name, entry);
  };

  Editor.prototype.flushTimer = function (name) {
    var entry = this.timers.get(name);
    if (!entry) return;
    window.clearTimeout(entry.handle);
    this.timers.delete(name);
    entry.fn();
  };

  // ---------------------------------------------------------------- skeleton
  Editor.prototype.build = function () {
    var app = this.app;
    this.noticesEl = el('div', 'dcf-dep-editor__notices');
    app.appendChild(this.noticesEl);
    this.conflictEl = null;
    this.bodyEl = el('div', 'dcf-dep-editor__body');
    var toolbar = el('div', 'dcf-dep-editor__toolbar');
    this.parentFilter = el('input');
    this.parentFilter.type = 'search';
    this.parentFilter.setAttribute('data-dcf-ed-parent-filter', '');
    this.parentFilter.setAttribute('autocomplete', 'off');
    toolbar.appendChild(wrap(this.t('filter_parents'), this.parentFilter));
    this.onlyBox = el('input');
    this.onlyBox.type = 'checkbox';
    this.onlyBox.setAttribute('data-dcf-ed-only-unlinked', '');
    toolbar.appendChild(wrap(this.t('only_parents_without_links'), this.onlyBox, true));
    toolbar.appendChild(button('data-dcf-ed-collapse-all', this.t('collapse_all')));
    this.toolbarEl = toolbar;
    this.statusEl = el('p', 'dcf-dep-editor__status');
    this.liveEl = el('p', 'hidden-for-sighted');
    this.liveEl.setAttribute('role', 'status');
    this.liveEl.setAttribute('aria-live', 'polite');
    this.sectionsEl = el('div', 'dcf-dep-editor__sections');
    this.moreSections = button('data-dcf-ed-more-sections', '');
    this.unlinkedEl = el('details', 'dcf-dep-editor__unlinked');
    this.unlinkedSummary = el('summary');
    this.unlinkedEl.appendChild(this.unlinkedSummary);
    [toolbar, this.statusEl, this.sectionsEl, this.moreSections, this.unlinkedEl].forEach(function (node) {
      this.bodyEl.appendChild(node);
    }, this);
    app.appendChild(this.liveEl);
    app.appendChild(this.bodyEl);
    if (this.newEnumeration) this.hint('save_first', this.t('enumeration_save_first'));
    else if (this.mode === 'admin' && this.kind === 'enumeration') this.hint('enumeration_hint', this.t('enumeration_hint'));
    this.render();
  };

  Editor.prototype.ready = function () {
    return !this.blank && !this.loading && this.parents !== null && !this.newEnumeration;
  };

  // Parents for serialize: null while not loaded (the server prunes).
  Editor.prototype.serialParents = function () {
    return this.loading || this.blank ? null : this.parents;
  };

  Editor.prototype.render = function () {
    var placeholder = this.root.querySelector('[data-dcf-editor-placeholder]');
    if (placeholder) placeholder.classList.toggle('dcf-hidden', !this.blank);
    if (this.config.defaultRow) this.config.defaultRow.classList.toggle('dcf-hidden', !this.blank);
    this.bodyEl.hidden = !this.ready();
    if (!this.ready()) return;
    var empty = this.parents.items.length === 0 ? 'no_parent_values'
      : (this.children.items.length === 0 ? 'no_child_values' : null);
    this.toolbarEl.hidden = !!empty;
    this.statusEl.hidden = !!empty;
    this.unlinkedEl.hidden = !!empty;
    this.sectionsEl.textContent = '';
    this.moreSections.hidden = true;
    if (empty) {
      this.sectionsEl.appendChild(info(this.t(empty)));
      return;
    }
    this.renderSections();
    this.renderStatus();
    this.renderUnlinked();
  };

  // ---------------------------------------------------------------- sections
  Editor.prototype.filteredParents = function () {
    var M = this.model;
    var toks = this.parentQuery;
    var self = this;
    return this.parents.items.filter(function (item) {
      if (!M.matchesTokens(item.folded, toks)) return false;
      return !self.onlyUnlinked || self.state.linkedCount(item.key, self.children) === 0;
    });
  };

  Editor.prototype.renderSections = function () {
    this.sectionsEl.textContent = '';
    this.shown = this.filteredParents();
    this.rendered = 0;
    if (this.shown.length === 0) {
      this.sectionsEl.appendChild(info(this.t('no_matches')));
      this.moreSections.hidden = true;
      return;
    }
    this.appendSections(this.sectionLimit);
  };

  Editor.prototype.appendSections = function (limit) {
    var end = Math.min(limit, this.shown.length);
    var first = null;
    for (var i = this.rendered; i < end; i++) {
      var details = this.section(this.shown[i]);
      if (!first) first = details;
      this.sectionsEl.appendChild(details);
    }
    this.rendered = end;
    var rest = this.shown.length - end;
    this.moreSections.hidden = rest <= 0;
    this.moreSections.textContent = this.t('show_more', { count: this.n(rest) });
    return first;
  };

  Editor.prototype.section = function (item) {
    var details = el('details', 'dcf-dep-section');
    details.setAttribute('data-dcf-ed-section', item.key);
    var summary = el('summary');
    details.appendChild(summary);
    var entry = { item: item, details: details, summary: summary, body: null };
    this.sectionOf.set(details, entry);
    this.summary(entry);
    var ui = this.sectionUi.get(item.key);
    if (ui && ui.open) {
      details.open = true;
      this.openBody(entry);
    }
    return details;
  };

  Editor.prototype.ui = function (key) {
    var ui = this.sectionUi.get(key);
    if (!ui) {
      ui = { open: false, query: [], text: '', view: 'all', limit: ROW_PAGE };
      this.sectionUi.set(key, ui);
    }
    return ui;
  };

  Editor.prototype.summary = function (entry) {
    var summary = entry.summary;
    var item = entry.item;
    var linked = this.state.linkedCount(item.key, this.children);
    summary.textContent = '';
    summary.appendChild(el('span', 'dcf-dep-section__label', item.label));
    if (!item.active) summary.appendChild(badge(this.t('inactive')));
    var counts = el('span', 'dcf-dep-section__counts' + (linked === 0 ? ' dcf-dep-section__counts--none' : ''),
      this.t('linked_count', { linked: this.n(linked), total: this.n(this.children.items.length) }));
    summary.appendChild(counts);
    var defaults = this.defaultItems(item.key);
    if (defaults.length) {
      var value = defaults.map(function (d) { return d.label; }).join(', ');
      summary.appendChild(el('span', 'dcf-dep-section__default', this.t('default_summary', { value: value })));
    }
  };

  // Current default children of pk in child order (the first one only for a
  // single-value field).
  Editor.prototype.defaultItems = function (pk) {
    var chosen = new Set(this.state.defaultsOf(pk));
    if (!chosen.size) return [];
    var self = this;
    var items = this.children.items.filter(function (c) { return chosen.has(c.key) && self.state.isLinked(pk, c.key); });
    return this.multiple ? items : items.slice(0, 1);
  };

  Editor.prototype.toggled = function (details) {
    if (details === this.unlinkedEl) {
      this.renderUnlinked();
      return;
    }
    var entry = this.sectionOf.get(details);
    if (!entry) return;
    this.ui(entry.item.key).open = details.open;
    if (details.open) this.openBody(entry);
    else this.closeBody(entry);
  };

  Editor.prototype.closeBody = function (entry) {
    if (entry.body) entry.body.remove();
    entry.body = null;
  };

  Editor.prototype.openBody = function (entry) {
    if (entry.body) return;
    var ui = this.ui(entry.item.key);
    ui.open = true;
    var body = el('div', 'dcf-dep-section__body');
    var tools = el('div', 'dcf-dep-section__tools');
    var filter = el('input');
    filter.type = 'search';
    filter.setAttribute('data-dcf-ed-child-filter', '');
    filter.setAttribute('autocomplete', 'off');
    filter.value = ui.text;
    tools.appendChild(wrap(this.t('filter_children'), filter));
    var view = el('select');
    view.setAttribute('data-dcf-ed-child-view', '');
    VIEWS.forEach(function (pair) {
      var option = el('option', null, this.t(pair[1]));
      option.value = pair[0];
      view.appendChild(option);
    }, this);
    view.value = ui.view;
    tools.appendChild(wrap(this.t('show'), view));
    entry.check = button('data-dcf-ed-check-shown', '');
    entry.uncheck = button('data-dcf-ed-uncheck-shown', '');
    tools.appendChild(entry.check);
    tools.appendChild(entry.uncheck);
    body.appendChild(tools);
    entry.defaultRow = el('p', 'dcf-dep-section__default-row');
    body.appendChild(entry.defaultRow);
    entry.rows = el('ul', 'dcf-dep-section__rows');
    body.appendChild(entry.rows);
    entry.more = button('data-dcf-ed-more-rows', '');
    body.appendChild(entry.more);
    entry.body = body;
    entry.details.appendChild(body);
    this.sectionOf.set(body, entry);
    this.defaultControl(entry);
    this.renderRows(entry);
  };

  // Children of the section matching its filter and view (rendered or not).
  Editor.prototype.matches = function (entry) {
    var M = this.model;
    var ui = this.ui(entry.item.key);
    var pk = entry.item.key;
    var state = this.state;
    var counts = ui.view === 'unlinked' ? state.childLinkCounts(this.parents, this.children) : null;
    return this.children.items.filter(function (c) {
      if (!M.matchesTokens(c.folded, ui.query)) return false;
      if (ui.view === 'linked') return state.isLinked(pk, c.key);
      if (ui.view === 'not_linked') return !state.isLinked(pk, c.key);
      if (ui.view === 'unlinked') return !counts.has(c.key);
      return true;
    });
  };

  Editor.prototype.renderRows = function (entry) {
    entry.list = this.matches(entry);
    entry.count = 0;
    entry.rows.textContent = '';
    if (entry.list.length === 0) entry.rows.appendChild(el('li', 'dcf-dep-section__empty', this.t('no_matches')));
    this.appendRows(entry, this.ui(entry.item.key).limit);
    this.shownButtons(entry);
  };

  Editor.prototype.appendRows = function (entry, limit) {
    var end = Math.min(limit, entry.list.length);
    var first = null;
    var pk = entry.item.key;
    for (var i = entry.count; i < end; i++) {
      var child = entry.list[i];
      var box = el('input');
      box.type = 'checkbox';
      box.setAttribute('data-dcf-ed-child-key', child.key);
      box.checked = this.state.isLinked(pk, child.key);
      var li = el('li');
      var label = wrap(child.label, box, true);
      if (!child.active) label.appendChild(badge(this.t('inactive')));
      li.appendChild(label);
      entry.rows.appendChild(li);
      if (!first) first = box;
    }
    entry.count = end;
    var rest = entry.list.length - end;
    entry.more.hidden = rest <= 0;
    entry.more.textContent = this.t('show_more', { count: this.n(rest) });
    return first;
  };

  // The counts of the current matches (the rendered rows stay as rendered
  // until the filter or view changes).
  Editor.prototype.shownButtons = function (entry) {
    var total = this.matches(entry).length;
    var count = this.n(total);
    entry.check.textContent = this.t('check_shown', { count: count });
    entry.uncheck.textContent = this.t('uncheck_shown', { count: count });
    entry.check.disabled = total === 0;
    entry.uncheck.disabled = total === 0;
  };

  // Single: '(no default)' plus the linked children; multiple: a list box
  // of the linked children plus Clear. Disabled while nothing is linked.
  Editor.prototype.defaultControl = function (entry) {
    var row = entry.defaultRow;
    var pk = entry.item.key;
    var state = this.state;
    row.textContent = '';
    var select = el('select');
    select.setAttribute('data-dcf-ed-default', '');
    var linked = this.children.items.filter(function (c) { return state.isLinked(pk, c.key); });
    var chosen = new Set(this.defaultItems(pk).map(function (c) { return c.key; }));
    if (this.multiple) {
      select.multiple = true;
      select.size = 5;
    } else {
      var none = el('option', null, this.t('no_default'));
      none.value = '';
      select.appendChild(none);
    }
    linked.forEach(function (c) {
      var option = el('option', null, c.label);
      option.value = c.key;
      option.selected = chosen.has(c.key);
      select.appendChild(option);
    });
    select.disabled = linked.length === 0;
    row.appendChild(wrap(this.t('default_value'), select));
    if (this.multiple) {
      var clear = button('data-dcf-ed-clear-default', this.t('clear'));
      clear.disabled = linked.length === 0;
      row.appendChild(clear);
    }
  };

  // Refreshes a section after its links changed (summary, defaults,
  // checkboxes, button counts).
  Editor.prototype.refreshSection = function (entry, rows) {
    this.summary(entry);
    if (!entry.body) return;
    this.defaultControl(entry);
    if (rows) {
      var state = this.state;
      var pk = entry.item.key;
      Array.prototype.forEach.call(entry.rows.querySelectorAll('input[data-dcf-ed-child-key]'), function (box) {
        box.checked = state.isLinked(pk, box.getAttribute('data-dcf-ed-child-key'));
      });
    }
    this.shownButtons(entry);
  };

  Editor.prototype.entryFor = function (node) {
    var details = node.closest('details.dcf-dep-section');
    return details ? this.sectionOf.get(details) : null;
  };

  Editor.prototype.renderStatus = function () {
    var total = this.parents.items.length;
    var shown = this.shown ? this.shown.length : total;
    this.statusEl.textContent = [
      this.t('status_sections', { shown: this.n(shown), total: this.n(total) }),
      this.t('status_parents_without_links', { count: this.n(this.state.parentsWithoutLinks(this.parents, this.children)) }),
      this.t('status_unlinked_children', { count: this.n(this.state.unlinkedChildren(this.parents, this.children).length) })
    ].join(' ');
  };

  Editor.prototype.renderUnlinked = function () {
    var list = this.state.unlinkedChildren(this.parents, this.children);
    this.unlinkedSummary.textContent = this.t('unlinked_list', { count: this.n(list.length) });
    var old = this.unlinkedEl.querySelector('ul');
    if (old) old.remove();
    if (!this.unlinkedEl.open) return;
    var ul = el('ul');
    list.slice(0, UNLINKED_PAGE).forEach(function (c) {
      var li = el('li', null, c.label);
      if (!c.active) li.appendChild(badge(this.t('inactive')));
      ul.appendChild(li);
    }, this);
    this.unlinkedEl.appendChild(ul);
  };

  Editor.prototype.statusText = function () {
    return this.statusEl.textContent;
  };

  // After a link or default change: summary, status, warning, payload.
  Editor.prototype.changed = function () {
    this.renderStatus();
    this.renderUnlinked();
    this.updateRequired();
    this.markDirty();
  };

  // ---------------------------------------------------------------- payload
  Editor.prototype.markDirty = function () {
    if (this.newEnumeration) return;
    this.dirty = true;
    var self = this;
    this.later('write', WRITE_MS, function () {
      self.write();
      self.storage();
    });
  };

  Editor.prototype.payload = function () {
    var M = this.model;
    var opts = { multiple: this.multiple === true, kind: this.kind };
    if (this.mode === 'admin' && this.config.base) opts.base = this.config.base;
    return M.serialize(this.state, this.serialParents(), this.children, opts);
  };

  Editor.prototype.value = function () {
    if (this.inert) return null;
    if (this.mode === 'project') return this.model.stringify(this.payload());
    if (this.newEnumeration || this.blank || !this.dirty) return '';
    return this.model.stringify(this.payload());
  };

  Editor.prototype.write = function () {
    var value = this.value();
    if (value !== null) this.input.value = value;
  };

  Editor.prototype.flush = function () {
    this.flushTimer('values');
    this.flushTimer('write');
    this.write();
  };

  // Client storage estimate (limits design 4.10): advisory only.
  Editor.prototype.storage = function () {
    var cfg = this.config;
    var M = this.model;
    if (cfg.storageLimit !== null && !this.newEnumeration && !this.blank) {
      var p = this.payload();
      var bytes = M.utf8Bytes(JSON.stringify({ value_dependencies: p.value_dependencies,
                                               default_value_dependencies: p.default_value_dependencies }));
      this.estimate('storage_mapping', 'label_value_dependencies',
        cfg.storageBase + Math.ceil(bytes * RATIO.get(this.kind)), cfg.storageLimit);
    } else {
      this.notice('storage_mapping', null);
    }
    if (cfg.valuesLimit !== null && this.kind === 'list' && cfg.valuesSource) {
      var size = storedValues(cfg.valuesSource.value).reduce(function (sum, v) { return sum + M.utf8Bytes(v) + 3; }, 4);
      this.estimate('storage_values', 'label_possible_values', size, cfg.valuesLimit);
    }
  };

  Editor.prototype.estimate = function (id, label, size, limit) {
    if (limit > 0 && size * 100 >= limit * this.config.storageWarn) {
      this.notice(id, 'warning', this.t('storageEstimate', { label: this.t(label), size: this.n(size),
        limit: this.n(limit), percent: Math.floor(size * 100 / limit) }));
    } else {
      this.notice(id, null);
    }
  };

  // ---------------------------------------------------------------- orphans
  Editor.prototype.orphans = function () {
    if (this.newEnumeration || this.blank) return;
    var count = this.state.orphanCount(this.parents, this.children);
    this.orphanCount = count;
    if (count > 0) {
      this.root.setAttribute('data-dcf-ed-orphans', String(count));
      this.notice('orphans', 'warning', this.t('orphans', { count: this.n(count) }));
    }
  };

  // ---------------------------------------------------------------- conflict
  Editor.prototype.conflictPanel = function () {
    var M = this.model;
    var counts = M.conflictCounts(this.mine, this.state, this.parents, this.children);
    var panel = flash('warning', '', true);
    panel.classList.add('dcf-dep-editor__conflict');
    panel.appendChild(el('p', null, this.t('conflict', { only_mine: this.n(counts.onlyMine),
                                                         only_current: this.n(counts.onlyCurrent) })));
    var actions = el('p', 'dcf-dep-editor__conflict-actions');
    actions.appendChild(button('data-dcf-ed-use-mine', this.t('use_mine')));
    actions.appendChild(doc.createTextNode(' '));
    actions.appendChild(button('data-dcf-ed-keep-current', this.t('keep_current')));
    actions.appendChild(doc.createTextNode(' '));
    actions.appendChild(button('data-dcf-ed-export-mine', this.t('export_mine')));
    panel.appendChild(actions);
    this.conflictEl = panel;
    this.app.insertBefore(panel, this.noticesEl.nextSibling);
  };

  Editor.prototype.closeConflict = function () {
    if (this.conflictEl) this.conflictEl.remove();
    this.conflictEl = null;
  };

  Editor.prototype.useMine = function () {
    if (!this.mine) return;
    this.state = this.mine;
    this.mine = null;
    this.closeConflict();
    this.notice('mine_loaded', 'notice', this.t('mine_loaded'));
    this.render();
    this.updateRequired();
    this.markDirty();
    this.announce(this.t('mine_loaded'));
  };

  Editor.prototype.keepCurrent = function () {
    this.mine = null;
    this.closeConflict();
    this.announce(this.statusText());
  };

  // CSV of the refused version over the current lists (header, then one
  // row per link in parent then child order).
  Editor.prototype.exportMine = function () {
    var mine = this.mine;
    if (!mine) return false;
    var children = this.children;
    var rows = [[this.config.parentName || 'parent', this.config.fieldName || 'child']];
    (this.parents ? this.parents.items : []).forEach(function (p) {
      children.items.forEach(function (c) {
        if (mine.isLinked(p.key, c.key)) rows.push([p.label, c.label]);
      });
    });
    return download(csvText(rows, this.config.separator), 'dependency-mapping.csv');
  };

  // ---------------------------------------------------------------- required
  Editor.prototype.requiredRule = function (required) {
    if (!required || this.blank || this.loading || !this.parents) return false;
    var state = this.state;
    var children = this.children;
    return this.parents.items.some(function (p) { return p.active && state.linkedCount(p.key, children) === 0; });
  };

  Editor.prototype.updateRequired = function () {
    if (!this.requiredEl) return;
    var show = this.requiredRule(this.required) &&
      !(this.requiredSuppressed && this.parentId === this.config.parentId);
    this.requiredEl.classList.toggle('dcf-hidden', !show);
  };

  // ---------------------------------------------------------------- parent
  Editor.prototype.valuesUrl = function (parentId) {
    var raw = this.config.valuesUrl;
    if (!raw) return null;
    var url;
    try {
      url = new window.URL(raw, doc.baseURI);
    } catch (e) {
      return null;
    }
    if (url.origin !== window.location.origin || url.origin === 'null') return null;
    url.search = new window.URLSearchParams({ custom_field_id: parentId, type: this.config.fieldType,
                                              kind: this.kind }).toString();
    url.hash = '';
    return url.toString();
  };

  // Also at init for a restored select that differs from the rendered parent.
  Editor.prototype.parentChanged = function () {
    var id = this.config.parentSource ? this.config.parentSource.value : '';
    this.parentId = id;
    this.request += 1;
    this.notice('load_failed', null);
    this.notice('parent_changed', null);
    this.notice('orphans', null);
    this.setLoading(false);
    this.sectionUi.clear();
    this.sectionLimit = SECTION_PAGE;
    this.markDirty();
    if (!id) {
      this.blank = true;
      this.parents = null;
      this.render();
      this.updateRequired();
      this.write();
      return;
    }
    this.blank = false;
    if (id === this.config.parentId) {
      this.parents = this.renderedParents;
      this.loaded();
      if (this.orphanCount > 0) this.notice('orphans', 'warning', this.t('orphans', { count: this.n(this.orphanCount) }));
      return;
    }
    if (this.newEnumeration) {
      this.render();
      return;
    }
    this.fetchValues(id);
  };

  Editor.prototype.setLoading = function (on) {
    this.loading = on;
    if (on) {
      this.root.setAttribute('aria-busy', 'true');
      this.notice('loading', 'notice', this.t('loading'));
    } else {
      this.root.removeAttribute('aria-busy');
      this.notice('loading', null);
    }
  };

  Editor.prototype.fetchValues = function (id) {
    var token = this.request;
    var self = this;
    var url = this.valuesUrl(id);
    this.parents = null;
    if (!url || typeof window.fetch !== 'function') {
      this.loadFailed();
      return;
    }
    this.setLoading(true);
    this.render();
    var M = this.model;
    window.fetch(url, { method: 'GET', credentials: 'same-origin',
                        headers: { 'X-Requested-With': 'XMLHttpRequest', Accept: 'application/json' } })
      .then(function (response) {
        if (!response || !response.ok) throw new Error('DcfDependencyEditor: status');
        return response.json();
      })
      .then(function (body) {
        if (token !== self.request) return;
        if (!isPlain(body) || String(body.id) !== id) throw new Error('DcfDependencyEditor: body');
        var list = M.ValueList.fromWire(body.values);
        self.setLoading(false);
        self.parents = list;
        self.loaded();
      })
      .catch(function () {
        if (token !== self.request) return;
        self.setLoading(false);
        self.loadFailed();
      });
  };

  Editor.prototype.loadFailed = function () {
    this.parents = null;
    this.notice('load_failed', 'error', this.t('load_failed'), true);
    this.render();
    this.updateRequired();
    this.write();
    this.announce(this.t('load_failed'));
  };

  // New parent values rendered; the dropped count is derived state shown
  // only while the parent differs from the rendered one.
  Editor.prototype.loaded = function () {
    if (this.parentId !== this.config.parentId) {
      this.notice('parent_changed', 'warning',
        this.t('parent_changed', { count: this.n(this.state.orphanCount(this.parents, this.children)) }));
    }
    this.render();
    this.updateRequired();
    this.write();
    this.storage();
    this.announce(this.statusText());
  };

  // ---------------------------------------------------------------- sources
  Editor.prototype.valuesInput = function () {
    var self = this;
    this.later('values', VALUES_MS, function () {
      self.children = self.childrenFromText();
      self.render();
      self.updateRequired();
      if (self.dirty) self.write();
      self.storage();
    });
  };

  Editor.prototype.multipleChanged = function () {
    this.multiple = this.config.multipleSource.checked === true;
    var self = this;
    this.eachSection(function (entry) {
      self.summary(entry);
      if (entry.body) self.defaultControl(entry);
    });
    this.markDirty();
  };

  Editor.prototype.eachSection = function (fn) {
    var self = this;
    Array.prototype.forEach.call(this.sectionsEl.querySelectorAll('details.dcf-dep-section'), function (d) {
      var entry = self.sectionOf.get(d);
      if (entry) fn(entry);
    });
  };

  // ---------------------------------------------------------------- events
  Editor.prototype.listen = function () {
    var self = this;
    var root = this.root;
    var cfg = this.config;
    root.addEventListener('toggle', function (e) {
      if (e.target && e.target.tagName === 'DETAILS') self.toggled(e.target);
    }, true);
    root.addEventListener('click', function (e) { self.click(e); });
    root.addEventListener('change', function (e) { self.change(e); });
    root.addEventListener('input', function (e) { self.input_(e); });
    root.addEventListener('keydown', function (e) { self.keydown(e); });
    if (cfg.parentSource) cfg.parentSource.addEventListener('change', function () { self.parentChanged(); });
    if (cfg.valuesSource && this.kind === 'list' && !cfg.children) {
      cfg.valuesSource.addEventListener('input', function () { self.valuesInput(); });
    }
    if (cfg.multipleSource) cfg.multipleSource.addEventListener('change', function () { self.multipleChanged(); });
    if (cfg.requiredSource) {
      cfg.requiredSource.addEventListener('change', function () {
        self.required = cfg.requiredSource.checked === true;
        self.updateRequired();
      });
    }
    if (this.form) this.form.addEventListener('submit', function (e) { self.submit(e); });
  };

  Editor.prototype.click = function (e) {
    var target = e.target && e.target.closest ? e.target.closest('button') : null;
    if (!target || !this.root.contains(target)) return;
    if (target.hasAttribute('data-dcf-ed-collapse-all')) this.collapseAll();
    else if (target.hasAttribute('data-dcf-ed-more-sections')) this.moreSectionsClicked();
    else if (target.hasAttribute('data-dcf-ed-more-rows')) this.moreRows(this.entryFor(target));
    else if (target.hasAttribute('data-dcf-ed-check-shown')) this.checkShown(this.entryFor(target), true);
    else if (target.hasAttribute('data-dcf-ed-uncheck-shown')) this.checkShown(this.entryFor(target), false);
    else if (target.hasAttribute('data-dcf-ed-clear-default')) this.clearDefault(this.entryFor(target));
    else if (target.hasAttribute('data-dcf-ed-use-mine')) this.useMine();
    else if (target.hasAttribute('data-dcf-ed-keep-current')) this.keepCurrent();
    else if (target.hasAttribute('data-dcf-ed-export-mine')) this.exportMine();
  };

  Editor.prototype.change = function (e) {
    var target = e.target;
    if (target.hasAttribute('data-dcf-ed-child-key')) {
      var entry = this.entryFor(target);
      if (!entry) return;
      this.state.link(entry.item.key, target.getAttribute('data-dcf-ed-child-key'), target.checked);
      this.refreshSection(entry, false);
      this.changed();
    } else if (target.hasAttribute('data-dcf-ed-default')) {
      var section = this.entryFor(target);
      if (!section) return;
      var keys = Array.prototype.filter.call(target.options, function (o) { return o.selected && o.value !== ''; })
        .map(function (o) { return o.value; });
      this.state.setDefaults(section.item.key, keys);
      this.summary(section);
      this.markDirty();
    } else if (target.hasAttribute('data-dcf-ed-child-view')) {
      var viewed = this.entryFor(target);
      if (!viewed) return;
      this.flushTimer(childTimer(viewed));
      var ui = this.ui(viewed.item.key);
      ui.view = target.value;
      ui.limit = ROW_PAGE;
      this.renderRows(viewed);
      this.announce(viewed.check.textContent);
    } else if (target.hasAttribute('data-dcf-ed-only-unlinked')) {
      this.onlyUnlinked = target.checked;
      this.filterParents();
    }
  };

  Editor.prototype.input_ = function (e) {
    var target = e.target;
    var self = this;
    if (target.hasAttribute('data-dcf-ed-parent-filter')) {
      this.later('parent_filter', FILTER_MS, function () { self.filterParents(); });
    } else if (target.hasAttribute('data-dcf-ed-child-filter')) {
      var entry = this.entryFor(target);
      if (entry) this.later(childTimer(entry), FILTER_MS, function () { self.filterChildren(entry, target); });
    }
  };

  Editor.prototype.keydown = function (e) {
    var target = e.target;
    if (!target || target.tagName !== 'INPUT') return;
    var type = (target.type || '').toLowerCase();
    if (type !== 'search' && type !== 'text') return;
    if (e.key === 'Enter') {
      e.preventDefault();
    } else if ((e.key === 'Escape' || e.key === 'Esc') && target.value !== '') {
      e.preventDefault();
      target.value = '';
      if (target.hasAttribute('data-dcf-ed-parent-filter')) this.filterParents();
      else if (target.hasAttribute('data-dcf-ed-child-filter')) {
        var entry = this.entryFor(target);
        if (entry) this.filterChildren(entry, target);
      }
    }
  };

  Editor.prototype.filterParents = function () {
    var timer = this.timers.get('parent_filter');
    if (timer) {
      window.clearTimeout(timer.handle);
      this.timers.delete('parent_filter');
    }
    this.parentQuery = this.model.tokens(this.parentFilter.value);
    this.onlyUnlinked = this.onlyBox.checked;
    this.sectionLimit = SECTION_PAGE;
    if (!this.ready()) return;
    this.renderSections();
    this.renderStatus();
    this.announce(this.statusText());
  };

  Editor.prototype.filterChildren = function (entry, input) {
    var timer = this.timers.get(childTimer(entry));
    if (timer) {
      window.clearTimeout(timer.handle);
      this.timers.delete(childTimer(entry));
    }
    var ui = this.ui(entry.item.key);
    ui.text = input.value;
    ui.query = this.model.tokens(input.value);
    ui.limit = ROW_PAGE;
    this.renderRows(entry);
    this.announce(entry.check.textContent);
  };

  Editor.prototype.collapseAll = function () {
    var self = this;
    this.eachSection(function (entry) {
      self.ui(entry.item.key).open = false;
      entry.details.open = false;
      self.closeBody(entry);
    });
  };

  Editor.prototype.moreSectionsClicked = function () {
    this.sectionLimit += SECTION_PAGE;
    var first = this.appendSections(this.sectionLimit);
    if (first) first.querySelector('summary').focus();
  };

  Editor.prototype.moreRows = function (entry) {
    if (!entry) return;
    this.flushTimer(childTimer(entry));
    var ui = this.ui(entry.item.key);
    ui.limit += ROW_PAGE;
    var first = this.appendRows(entry, ui.limit);
    if (first) first.focus();
  };

  // Acts on every match of the section filter and view, rendered or not.
  Editor.prototype.checkShown = function (entry, on) {
    if (!entry) return;
    this.flushTimer(childTimer(entry));
    var pk = entry.item.key;
    var state = this.state;
    this.matches(entry).forEach(function (c) { state.link(pk, c.key, on); });
    this.refreshSection(entry, true);
    this.changed();
    this.announce(this.t('linked_count', { linked: this.n(state.linkedCount(pk, this.children)),
                                           total: this.n(this.children.items.length) }));
  };

  Editor.prototype.clearDefault = function (entry) {
    if (!entry) return;
    this.state.setDefaults(entry.item.key, []);
    this.summary(entry);
    this.defaultControl(entry);
    this.markDirty();
  };

  // ---------------------------------------------------------------- submit
  Editor.prototype.submit = function (e) {
    if (this.inert) return;
    this.flush();
    this.notice('too_large', null);
    this.notice('form_too_large', null);
    var cfg = this.config;
    var bytes = this.model.utf8Bytes(this.input.value);
    if (bytes > cfg.maxPayload) {
      this.block(e, 'too_large', this.t('too_large_to_send', { size: this.n(bytes), limit: this.n(cfg.maxPayload) }));
      return;
    }
    var type = String(this.form.enctype || this.form.getAttribute('enctype') || '').toLowerCase();
    var encoding = type.indexOf('multipart') >= 0 ? 'multipart' : 'urlencoded';
    var size = formBytes(this.form, encoding, e.submitter || null);
    if (size > cfg.maxForm[encoding]) {
      this.block(e, 'form_too_large', this.t('form_too_large', { size: this.n(size), limit: this.n(cfg.maxForm[encoding]) }));
      return;
    }
    this.submitting = true;
  };

  // A blocked submit stops here, so rails-ujs does not disable the buttons.
  Editor.prototype.block = function (e, id, text) {
    e.preventDefault();
    e.stopPropagation();
    this.submitting = false;
    var box = this.notice(id, 'error', text, true);
    box.setAttribute('tabindex', '-1');
    if (typeof box.focus === 'function') box.focus();
  };

  Editor.prototype.wantsWarning = function () {
    return !this.inert && this.dirty && !this.submitting && this.config.warnUnsaved && this.root.isConnected;
  };

  // ---------------------------------------------------------------- inert
  function inert(root, i18n) {
    var editor = { root: root, inert: true, dirty: false };
    var text = isPlain(i18n) && typeof i18n.unavailable === 'string' ? i18n.unavailable : FALLBACK_UNAVAILABLE;
    var box = flash('error', text, true);
    box.setAttribute('data-dcf-ed-notice', 'unavailable');
    var app = root.querySelector('[data-dcf-editor-app]');
    if (app && app.parentNode === root) root.insertBefore(box, app);
    else root.appendChild(box);
    root.setAttribute('data-dcf-ed-inert', '1');
    return editor;
  }

  function readI18n(root) {
    try {
      return JSON.parse(root.getAttribute('data-dcf-editor-i18n'));
    } catch (e) {
      return null;
    }
  }

  function create(root) {
    var M = window.DcfDependencyEditorModel;
    if (!M || typeof M.serialize !== 'function') {
      if (!warnedModel && window.console && typeof window.console.warn === 'function') {
        window.console.warn('DcfDependencyEditor: window.DcfDependencyEditorModel is missing; the editor stays inert.');
      }
      warnedModel = true;
      return inert(root, readI18n(root));
    }
    var editor = new Editor(root, M);
    try {
      editor.start();
    } catch (e) {
      Array.prototype.forEach.call(root.querySelectorAll('[data-dcf-editor-app]'), function (app) {
        app.textContent = '';
        app.hidden = true;
      });
      return inert(root, readI18n(root));
    }
    live.add(editor);
    return editor;
  }

  function initOne(root) {
    if (instances.has(root)) return instances.get(root);
    var editor = create(root);
    instances.set(root, editor);
    return editor;
  }

  // Inits every [data-dcf-editor] at or below +root+ (idempotent).
  function init(root) {
    var scope = root || doc;
    var result;
    if (scope.nodeType === 1 && scope.matches('[data-dcf-editor]')) result = initOne(scope);
    if (scope.querySelectorAll) {
      Array.prototype.forEach.call(scope.querySelectorAll('[data-dcf-editor]'), function (node) { initOne(node); });
    }
    return result;
  }

  function get(root) {
    return instances.get(root) || null;
  }

  function connected() {
    var out = [];
    live.forEach(function (editor) {
      if (editor.root.isConnected) out.push(editor);
      else live.delete(editor);
    });
    return out;
  }

  // ---------------------------------------------------------------- global
  // One beforeunload listener for every editor (never window.onbeforeunload,
  // which core assigns for its textareas).
  window.addEventListener('beforeunload', function (e) {
    var dirty = connected().filter(function (editor) { return editor.wantsWarning(); });
    if (!dirty.length) return undefined;
    var text = dirty[0].t('unsaved');
    e.preventDefault();
    e.returnValue = text;
    return text;
  });

  window.addEventListener('pageshow', function (e) {
    if (e.persisted) connected().forEach(function (editor) { editor.submitting = false; });
  });

  // Format switch on /new (UX-11): runs in the capture phase on document,
  // before core's jQuery handler on the select.
  doc.addEventListener('change', function (e) {
    var target = e.target;
    connected().forEach(function (editor) {
      if (e.cancelBubble || editor.config.formatSource !== target) return;
      if (editor.dirty && !window.confirm(editor.t('format_change_confirm'))) {
        e.stopImmediatePropagation();
        if (editor.format !== null) target.value = editor.format;
        return;
      }
      editor.format = target.value;
      editor.input.value = '';
    });
  }, true);

  function observe() {
    var target = doc.body || doc.documentElement;
    if (!target || typeof window.MutationObserver !== 'function') return;
    new window.MutationObserver(function (records) {
      records.forEach(function (record) {
        Array.prototype.forEach.call(record.addedNodes, function (node) {
          if (node.nodeType === 1) init(node);
        });
      });
    }).observe(target, { childList: true, subtree: true });
  }

  function boot() {
    init(doc);
    observe();
  }

  window.DcfDependencyEditor = { init: init, get: get };
  if (doc.readyState === 'loading') doc.addEventListener('DOMContentLoaded', boot);
  else boot();
}(typeof window !== 'undefined' ? window : null));
