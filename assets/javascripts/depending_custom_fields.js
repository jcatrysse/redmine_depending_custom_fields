/* Redmine Depending Custom Fields: issue-form runtime (frontend design 4 and 5).
 * One UMD file: under CommonJS the pure rules are module.exports and no DOM
 * runtime starts; in a browser the runtime reads the per-field data-dcf-*
 * attributes and exposes window.DependingCustomFields (rules at .rules).
 * ES2017 only (npm run check); names are compared as strings, never through
 * a CSS escape helper (jsdom has none). */
(function () {
  'use strict';

  // ---------------------------------------------------------------- rules
  function buildRules() {
    var NONE = '__none__';
    var BLANK = '';
    // Memory keys outside the JSON array strings parentKey() returns.
    var NOCHANGE_KEY = '\u0000nochange';
    var NONE_KEY = '\u0000none';
    var VERSION = '1';
    var NAME_RE = /^(.+)\[custom_field_values\]\[(\d+)\](\[\])?$/;
    var hasOwn = Object.prototype.hasOwnProperty;

    function str(v) { return v === null || v === undefined ? '' : String(v); }
    // Ruby blank?: nil, '' and [[:space:]] only (U+0085 is blank, U+FEFF is not).
    var BLANK_RE = /^[\t\n\v\f\r \u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]*$/;
    function isBlank(v) { return v === null || v === undefined || BLANK_RE.test(String(v)); }
    function uniq(values) {
      var seen = new Set();
      return values.filter(function (v) {
        if (seen.has(v)) return false;
        seen.add(v);
        return true;
      });
    }
    function isPlainObject(o) { return o !== null && typeof o === 'object' && !Array.isArray(o); }
    function asList(v) { return Array.isArray(v) ? v : [v]; }

    // 'bulk' only for data-dcf-context="bulk"; missing or unknown means form.
    function contextOf(raw) { return raw === 'bulk' ? 'bulk' : 'form'; }

    // Concrete values: blanks dropped, and '__none__' in bulk context.
    function concrete(ctx, values) {
      return uniq(values.map(str).filter(function (v) { return !isBlank(v) && !(ctx === 'bulk' && v === NONE); }));
    }

    function parseFieldName(name) {
      if (typeof name !== 'string') return null;
      var m = NAME_RE.exec(name);
      return m ? { prefix: m[1], fieldId: m[2], multiple: !!m[3] } : null;
    }

    function parseJSON(raw) {
      if (raw === null || raw === undefined || raw === '') return { ok: true, value: null };
      try {
        return { ok: true, value: JSON.parse(raw) };
      } catch (e) {
        return { ok: false, value: null };
      }
    }

    // null: absent or not an object (the field stays unfiltered); {} gives an empty Map.
    function normalizeMap(obj) {
      if (!isPlainObject(obj)) return null;
      var out = new Map();
      Object.keys(obj).forEach(function (k) {
        if (isBlank(k)) return;
        var set = new Set(asList(obj[k]).filter(function (v) { return !isBlank(v); }).map(String));
        if (set.size) out.set(k, set);
      });
      return out;
    }

    function normalizeDefaults(obj) {
      var out = new Map();
      if (!isPlainObject(obj)) return out;
      Object.keys(obj).forEach(function (k) {
        if (isBlank(k)) return;
        var list = uniq(asList(obj[k]).filter(function (v) { return !isBlank(v); }).map(String));
        if (list.length) out.set(k, list);
      });
      return out;
    }

    function normalizeList(arr) {
      if (!Array.isArray(arr)) return null;
      return uniq(arr.filter(function (v) { return !isBlank(v); }).map(String));
    }

    // data-dcf-stored {"child": [...], "parent": [...]}; null when absent (new record).
    function normalizeStored(obj) {
      if (!isPlainObject(obj)) return null;
      return { child: normalizeList(obj.child) || [], parent: normalizeList(obj.parent) };
    }

    // Union in first-seen order: parent order, then map order.
    function allowedFor(map, parentValues) {
      var out = new Set();
      if (!map) return out;
      parentValues.forEach(function (pv) {
        if (isBlank(pv)) return;
        var set = map.get(String(pv));
        if (set) set.forEach(function (v) { out.add(v); });
      });
      return out;
    }

    function defaultsFor(defaults, parentValues, allowed) {
      var out = [];
      var seen = new Set();
      parentValues.forEach(function (pv) {
        if (isBlank(pv)) return;
        (defaults.get(String(pv)) || []).forEach(function (v) {
          if (allowed.has(v) && !seen.has(v)) {
            seen.add(v);
            out.push(v);
          }
        });
      });
      return out;
    }

    function parentKey(values) {
      return JSON.stringify(uniq(values.filter(function (v) { return !isBlank(v); }).map(String)).sort());
    }
    function sameSet(a, b) { return parentKey(a) === parentKey(b); }
    function isSuperset(next, prev) {
      var set = new Set(next);
      return prev.length > 0 && prev.every(function (v) { return set.has(v); });
    }

    // Frontend design 5.3. present: the parent control is in the scope; raw:
    // its selected values; staticValues: data-dcf-parent-values (form) or null;
    // hasMap false: data-dcf-map absent or invalid.
    function parentState(ctx, present, raw, staticValues, hasMap) {
      var unfiltered = { kind: 'unfiltered', values: [], key: NOCHANGE_KEY };
      if (hasMap === false) return unfiltered;
      if (!present) {
        if (ctx === 'form' && Array.isArray(staticValues)) {
          var list = normalizeList(staticValues);
          return { kind: 'static', values: list, key: parentKey(list) };
        }
        return unfiltered;
      }
      var rawList = (raw || []).map(str);
      var values = concrete(ctx, rawList);
      if (values.length) return { kind: 'values', values: values, key: parentKey(values) };
      if (ctx === 'bulk') {
        if (rawList.indexOf(NONE) !== -1) return { kind: 'none', values: [], key: NONE_KEY };
        return unfiltered;
      }
      return { kind: 'empty', values: [], key: parentKey([]) };
    }

    // D1 per value (UD-04): stored child values the allowed set lacks stay
    // usable while the server sees the parent as unchanged (ParentState#changed?:
    // current values against the baseline, a read-only parent too).
    function legacyEligible(i, allowed) {
      var out = new Set();
      if (i.ctx !== 'form' || !i.stored || !allowed) return out;
      var unchanged = i.stored.parent !== null && sameSet(i.values, i.stored.parent);
      if (!unchanged) return out;
      i.stored.child.forEach(function (v) { if (!allowed.has(v)) out.add(v); });
      return out;
    }

    function result() {
      return { values: [], legacy: new Set(), eligible: new Set(), filter: null, state: 'ok', hint: null,
               auto: false, hideField: false, rememberKey: null };
    }

    function decideUnfiltered(i, out) {
      var has = function (v) { return i.optionValues.has(v) && !(v === NONE && i.noneRequired); };
      out.state = 'unfiltered';
      if (i.ctx === 'bulk' && i.parentChanged) {
        var nc = i.memory.get(NOCHANGE_KEY);
        out.values = nc ? nc.filter(has) : [];
      } else {
        out.values = i.current.filter(has);
      }
      if (!out.values.length && !i.multiple && i.hasBlank) out.values = [BLANK];
      if (i.ctx === 'bulk' && i.initial) out.rememberKey = NOCHANGE_KEY;
      return out;
    }

    // Frontend design 5.5 (UD-09, UD-10).
    function decideBulk(i, out) {
      var allowed = i.kind === 'none' ? new Set() : (i.allowed || new Set());
      var single = !i.multiple;
      if (!allowed.size) {
        out.state = i.kind === 'none' ? 'none' : 'empty';
        out.values = i.hasNone ? [NONE] : (single && i.hasBlank ? [BLANK] : []);
        out.auto = i.hasNone && !i.initial;
        out.hint = i.hasNone ? (out.auto ? 'bulkCleared' : null) : 'empty';
        out.filter = { allowed: allowed, eligible: out.eligible, blankEnabled: !i.hasNone, noneEnabled: true,
                       requiredNoneEnabled: true };
        if (i.initial) out.rememberKey = i.key;
        return out;
      }
      var ok = function (v) { return v === BLANK || (v === NONE && !i.noneRequired) || allowed.has(v); };
      var has = function (v) { return i.optionValues.has(v); };
      var current = i.current.filter(ok);
      var values;
      if (i.initial) {
        values = current;
      } else {
        var remembered = i.memory.get(i.key);
        if (remembered !== undefined) {
          values = remembered.filter(function (v) { return ok(v) && has(v); });
          if (remembered.length && !values.length) remembered = undefined;
        }
        if (remembered === undefined) {
          // Only a value picked under (no change) is carried (frontend 5.5),
          // so a default applied under a concrete parent is never carried unmarked.
          values = i.prevValues.length === 0 ? concrete('bulk', current) : [];
          if (!values.length) {
            values = defaultsFor(i.defaults, i.values, allowed);
            out.auto = values.filter(has).length > 0;
          }
        }
      }
      values = uniq(values.filter(has));
      if (single) values = values.slice(0, 1);
      if (!values.length && single && i.hasBlank) values = [BLANK];
      out.values = values;
      out.hint = out.auto ? 'bulkDefault' : null;
      out.filter = { allowed: allowed, eligible: out.eligible, blankEnabled: true, noneEnabled: !i.noneRequired,
                     requiredNoneEnabled: false };
      if (i.initial) out.rememberKey = i.key;
      return out;
    }

    // Form state (frontend 5.4); its hint has the same name, none for 'ok'.
    function formState(kind, allowedSize, legacySize) {
      if (legacySize) return 'legacy';
      if (kind === 'empty') return 'waiting';
      return allowedSize ? 'ok' : 'empty';
    }

    // Frontend design 5.4 (D1 per value, UD-04, UD-05, UD-12).
    function decideForm(i, out) {
      var allowed = i.allowed || new Set();
      var single = !i.multiple;
      var eligible = legacyEligible(i, allowed);
      var has = function (v) { return i.optionValues.has(v); };
      var usable = function (v) { return (allowed.has(v) || eligible.has(v)) && has(v); };
      var current = concrete('form', i.current);
      var values = null;
      if (i.initial) {
        values = current.filter(usable);
        // An empty child takes memory (AJAX re-render; a pick filtered down
        // to nothing is ignored); a plain new record with no usable value
        // left takes the per-parent defaults.
        var remembered0 = current.length ? undefined : i.memory.get(i.key);
        if (remembered0 !== undefined) {
          var restored0 = remembered0.filter(usable);
          if (remembered0.length && !restored0.length) remembered0 = undefined;
          else values = restored0;
        }
        if (remembered0 === undefined && !values.length && !i.stored && i.kind === 'values') {
          values = defaultsFor(i.defaults, i.values, allowed);
        }
      } else {
        var remembered = i.memory.get(i.key);
        if (remembered !== undefined) {
          var restored = remembered.filter(usable);
          if (!(remembered.length && !restored.length)) values = restored;
        }
        if (values === null) {
          if (i.stored && i.stored.parent !== null && sameSet(i.values, i.stored.parent)) {
            values = i.stored.child.filter(usable);
          } else {
            var carry = i.prevValues.length === 0 || isSuperset(i.values, i.prevValues);
            values = carry ? current.filter(function (v) { return allowed.has(v) && has(v); }) : [];
            if (!values.length) {
              values = defaultsFor(i.defaults, i.values, allowed);
            } else if (i.multiple) {
              var before = new Set(i.prevValues);
              var added = i.values.filter(function (v) { return !before.has(v); });
              values = values.concat(defaultsFor(i.defaults, added, allowed));
            }
          }
        }
      }
      values = uniq(values.filter(has));
      if (single) values = values.slice(0, 1);
      if (!values.length && single && i.hasBlank) values = [BLANK];
      out.values = values;
      out.eligible = eligible;
      out.legacy = new Set(values.filter(function (v) { return eligible.has(v); }));
      // In form context __none__ is an ordinary value (core maps it in bulk only).
      out.filter = { allowed: allowed, eligible: eligible, blankEnabled: true,
                     noneEnabled: allowed.has(NONE) || eligible.has(NONE), requiredNoneEnabled: false };
      out.state = formState(i.kind, allowed.size, out.legacy.size);
      out.hint = out.state === 'ok' ? null : out.state;
      out.hideField = !!i.hide && !allowed.size && !out.legacy.size;
      out.rememberKey = i.key;
      return out;
    }

    // Pure decision for one evaluation of one child control.
    function decide(i) {
      var out = result();
      if (i.kind === 'unfiltered') return decideUnfiltered(i, out);
      if (i.ctx === 'bulk') return decideBulk(i, out);
      return decideForm(i, out);
    }

    // requiredNone: the option carries data-dcf-required-none="1" (UD-10).
    function optionEnabled(filter, value, requiredNone) {
      if (requiredNone && value === NONE) return !!(filter && filter.requiredNoneEnabled);
      if (!filter) return true;
      if (value === BLANK) return filter.blankEnabled;
      if (value === NONE) return filter.noneEnabled;
      return filter.allowed.has(value) || filter.eligible.has(value);
    }

    // Parents first, stable; terminates on cycles and self-parents.
    function orderByDepth(nodes) {
      var byId = new Map();
      nodes.forEach(function (n) { if (!byId.has(String(n.id))) byId.set(String(n.id), n); });
      var depth = new Map();
      function depthOf(id) {
        if (depth.has(id)) return depth.get(id);
        var seen = new Set([id]);
        var d = 0;
        var cur = byId.get(id);
        while (cur && byId.has(String(cur.parentId)) && !seen.has(String(cur.parentId))) {
          seen.add(String(cur.parentId));
          d += 1;
          cur = byId.get(String(cur.parentId));
        }
        depth.set(id, d);
        return d;
      }
      return nodes.map(function (n, idx) { return { n: n, d: depthOf(String(n.id)), idx: idx }; })
        .sort(function (a, b) { return a.d - b.d || a.idx - b.idx; })
        .map(function (x) { return x.n; });
    }

    // %{name} tokens; unknown names stay as written, inserted text is never re-read.
    function interpolate(text, vars) {
      return str(text).replace(/%\{(\w+)\}/g, function (m, k) {
        return vars && hasOwn.call(vars, k) && vars[k] !== undefined && vars[k] !== null ? String(vars[k]) : m;
      });
    }

    // UD-37 carrier (WP-16): a change of the parent to the values V is refused
    // by the server when V differs from the stored baseline as a set and some
    // stored child value is allowed by none of V.
    function lockedRefused(stored, allowedBy, values) {
      var next = normalizeList(values) || [];
      if (sameSet(next, normalizeList(stored) || [])) return false;
      var set = new Set(next);
      return (Array.isArray(allowedBy) ? allowedBy : []).some(function (entry) {
        return !(normalizeList(asList(entry)) || []).some(function (v) { return set.has(v); });
      });
    }

    return {
      VERSION: VERSION, NONE: NONE, BLANK: BLANK, NOCHANGE_KEY: NOCHANGE_KEY, NONE_KEY: NONE_KEY,
      isBlank: isBlank, contextOf: contextOf, parseFieldName: parseFieldName, parseJSON: parseJSON,
      normalizeMap: normalizeMap, normalizeDefaults: normalizeDefaults, normalizeList: normalizeList,
      normalizeStored: normalizeStored, allowedFor: allowedFor, defaultsFor: defaultsFor, parentKey: parentKey,
      sameSet: sameSet, parentState: parentState, legacyEligible: legacyEligible, formState: formState, decide: decide,
      optionEnabled: optionEnabled, orderByDepth: orderByDepth, interpolate: interpolate,
      lockedRefused: lockedRefused
    };
  }

  // -------------------------------------------------------------- runtime
  function startRuntime(window, document, R) {
    if (window.DependingCustomFields && window.DependingCustomFields.__runtime) return;

    var CHILD_SEL = '[data-dcf-parent]';
    var LOCKED_SEL = 'span[data-dcf-locked-parent]';
    var ROOT_SEL = CHILD_SEL + ', ' + LOCKED_SEL;
    var ATTRS = ['data-dcf-field', 'data-dcf-parent', 'data-dcf-context', 'data-dcf-parent-name', 'data-dcf-map',
                 'data-dcf-defaults', 'data-dcf-hide', 'data-dcf-parent-values', 'data-dcf-parent-label',
                 'data-dcf-stored'];
    // English fallbacks, equal to the en texts of large_lists_i18n_registry.md.
    var I18N = {
      selectParent: 'Select a value for %{parent} first.',
      noOptions: 'No values are available for the selected %{parent}.',
      noOptionsGeneric: 'No values are available for this field.',
      legacy: 'Stored values that do not match the selected %{parent} are kept until you change %{parent}: %{values}.',
      legacyLocked: 'Stored values that do not match %{parent} (not editable here) are kept unchanged: %{values}.',
      legacyGeneric: 'Stored values that do not match the current selection are kept unchanged: %{values}.',
      bulkDefault: 'Set to the default for the selected %{parent}. Choose (No change) to keep the current values.',
      bulkCleared: 'Cleared because the current choice for %{parent} allows no values for this field.',
      liveMessage: '%{field}: %{message}',
      saveFailed: 'The change could not be saved.',
      lockedRefused: 'A dependent field that you cannot edit has a value that this choice does not allow; saving will be refused.'
    };
    var states = new WeakMap();
    var configs = new WeakMap();
    var memories = new WeakMap();
    var ownEvents = new WeakSet();
    var hiddenByUs = new WeakSet();
    var lockedHints = new WeakMap();
    var lockedEls = new WeakSet();
    var texts = null;
    var hintSeq = 0;
    var live = { el: null, timer: null, pending: new Map() };
    var setupRoots = new Set();
    var setupTimer = null;
    var started = false;

    function t(key, vars) {
      if (texts === null) {
        texts = {};
        var meta = document.querySelector('meta[name="dcf-i18n"]');
        var parsed = meta ? R.parseJSON(meta.getAttribute('content')) : { ok: false };
        if (parsed.ok && parsed.value && typeof parsed.value === 'object' && !Array.isArray(parsed.value)) {
          texts = parsed.value;
        }
      }
      var own = Object.prototype.hasOwnProperty;
      var text = own.call(texts, key) && typeof texts[key] === 'string' ? texts[key] :
        (own.call(I18N, key) ? I18N[key] : '');
      return R.interpolate(text, vars);
    }

    function each(list, fn) { Array.prototype.forEach.call(list, fn); }
    function isSelect(el) { return !!el && el.tagName === 'SELECT'; }
    function scopeOf(el) { return el.closest('form') || el.closest('.cf-wizard') || el.ownerDocument; }
    // Radio and check box inputs only: core's hidden '' input and the WP-19
    // sentinel are never touched.
    function choiceInputs(ctl) {
      return Array.prototype.filter.call(ctl.querySelectorAll('input'), function (i) {
        return i.type === 'radio' || i.type === 'checkbox';
      });
    }
    function controlName(ctl) {
      if (isSelect(ctl)) return ctl.name;
      var input = choiceInputs(ctl).filter(function (i) { return !!i.name; })[0];
      return input ? input.name : '';
    }
    function readValues(ctl) {
      if (isSelect(ctl)) {
        return Array.prototype.filter.call(ctl.options, function (o) { return o.selected; })
          .map(function (o) { return o.value; });
      }
      return choiceInputs(ctl).filter(function (i) { return i.checked; }).map(function (i) { return i.value; });
    }
    function sameList(a, b) { return a.length === b.length && a.every(function (v, k) { return v === b[k]; }); }
    function jsonAttr(raw) { var p = R.parseJSON(raw); return p.ok ? p.value : null; }

    // Parsed attributes, cached per element while the raw strings stay the same.
    function config(ctl) {
      var raw = ATTRS.map(function (a) { return ctl.getAttribute(a); });
      var cached = configs.get(ctl);
      if (cached && sameList(cached.raw, raw)) return cached.cfg;
      var cfg = null;
      var name = controlName(ctl);
      var parsed = R.parseFieldName(name);
      var parentId = raw[1];
      var usable = isSelect(ctl) || choiceInputs(ctl).length > 0;
      if (usable && parsed && parentId && parentId !== raw[0] && parentId !== parsed.fieldId) {
        var ctx = R.contextOf(raw[2]);
        var form = ctx === 'form';
        var mapParsed = R.parseJSON(raw[4]);
        cfg = {
          fieldId: parsed.fieldId,
          prefix: parsed.prefix,
          parentName: raw[3] || (parsed.prefix + '[custom_field_values][' + parentId + ']'),
          ctx: ctx,
          multiple: isSelect(ctl) ? ctl.multiple : choiceInputs(ctl).some(function (i) { return i.type === 'checkbox'; }),
          map: mapParsed.ok ? R.normalizeMap(mapParsed.value) : null,
          defaults: R.normalizeDefaults(jsonAttr(raw[5])),
          hide: form && raw[6] === '1',
          staticValues: form ? R.normalizeList(jsonAttr(raw[7])) : null,
          parentLabel: form ? (raw[8] || '') : '',
          // A present but invalid baseline still marks a stored record (UD-12).
          stored: form && raw[9] !== null ? (R.normalizeStored(jsonAttr(raw[9])) || { child: [], parent: null }) : null
        };
      }
      configs.set(ctl, { raw: raw, cfg: cfg });
      return cfg;
    }

    // Non-hidden select or input elements named like the parent (or with []),
    // compared as strings; resolved on every evaluation.
    function findParent(scope, name) {
      var multi = name + '[]';
      var els = Array.prototype.filter.call(scope.querySelectorAll('select, input'), function (el) {
        return (el.name === name || el.name === multi) && el.type !== 'hidden';
      });
      if (!els.length) return null;
      var first = els[0];
      var values = isSelect(first) ? readValues(first) : els.filter(function (i) {
        return (i.type === 'radio' || i.type === 'checkbox') && i.checked;
      }).map(function (i) { return i.value; });
      return { el: first, values: values, els: els };
    }

    function textOf(node) { return node.textContent.replace(/\s+/g, ' ').trim(); }

    // The field label of a control: the first label or .field-description of
    // its p or .cf-wizard-field outside .check_box_group, without controls,
    // .required and hints.
    function labelText(el) {
      var box = el.closest('p, .cf-wizard-field');
      if (!box) return '';
      var lab = Array.prototype.filter.call(box.querySelectorAll('label, .field-description'), function (n) {
        return !n.closest('.check_box_group');
      })[0];
      if (!lab) return '';
      var clone = lab.cloneNode(true);
      each(clone.querySelectorAll('select, input, textarea, button, .required, .dcf-hint'), function (n) {
        n.parentNode.removeChild(n);
      });
      return textOf(clone);
    }

    function memoryFor(scope, cfg) {
      var byScope = memories.get(scope);
      if (!byScope) {
        byScope = new Map();
        memories.set(scope, byScope);
      }
      var k = cfg.prefix + '|' + cfg.fieldId;
      if (!byScope.has(k)) byScope.set(k, new Map());
      return byScope.get(k);
    }

    function optionsOf(ctl) {
      if (isSelect(ctl)) return Array.prototype.slice.call(ctl.options);
      return choiceInputs(ctl);
    }
    // v: the option value, read once per evaluation.
    function isRequiredNone(o, v) { return v === R.NONE && o.getAttribute('data-dcf-required-none') === '1'; }

    function setHidden(el, hidden) {
      if (el.hidden !== hidden) el.hidden = hidden;
      // Server pre-hidden markup (inline display:none) is reset when enabled.
      if (!hidden && el.hasAttribute('style') && el.style.display === 'none') el.style.display = '';
    }
    function setClass(el, name, on) {
      if (el.classList.contains(name) !== on) el.classList.toggle(name, on);
    }

    // Point 2: the control itself is never disabled; options and choice inputs
    // are hidden and disabled. A single select gets the target option, else
    // the enabled '' option, else no selection.
    // options: a snapshot taken before any write (a live collection would be
    // rebuilt after every attribute change); values: their values, in order.
    function apply(ctl, d, options, values) {
      var target = new Set(d.values);
      var enabled = function (o, v) {
        return R.optionEnabled(d.filter, v, isRequiredNone(o, v)) || target.has(v);
      };
      if (isSelect(ctl)) {
        options.forEach(function (o, k) {
          var on = enabled(o, values[k]);
          if (o.disabled !== !on) o.disabled = !on;
          setHidden(o, !on);
          setClass(o, 'dcf-legacy-option', d.eligible.has(values[k]));
        });
        if (ctl.multiple) {
          options.forEach(function (o, k) {
            var s = target.has(values[k]) && !o.disabled;
            if (o.selected !== s) o.selected = s;
          });
        } else {
          var want = d.values.length ? d.values[0] : R.BLANK;
          var pick = null;
          var blank = null;
          options.forEach(function (o, k) {
            if (o.disabled) return;
            if (!pick && values[k] === want) pick = o;
            if (!blank && values[k] === R.BLANK) blank = o;
          });
          pick = pick || blank;
          if (pick) {
            if (!pick.selected) pick.selected = true;
          } else if (ctl.selectedIndex !== -1) {
            ctl.selectedIndex = -1;
          }
        }
      } else {
        options.forEach(function (input, k) {
          var on = enabled(input, values[k]);
          var label = input.closest('label') || input;
          if (input.disabled !== !on) input.disabled = !on;
          setHidden(label, !on);
          setClass(label, 'dcf-legacy-option', d.eligible.has(values[k]));
          var c = target.has(values[k]) && on;
          if (input.checked !== c) input.checked = c;
        });
      }
    }

    function describedTargets(ctl) { return isSelect(ctl) ? [ctl] : choiceInputs(ctl); }
    function setDescribedBy(el, id, on) {
      var current = el.getAttribute('aria-describedby') || '';
      var tokens = current.split(/\s+/).filter(Boolean);
      var idx = tokens.indexOf(id);
      if (on && idx === -1) tokens.push(id);
      if (!on && idx !== -1) tokens.splice(idx, 1);
      var next = tokens.join(' ');
      if (next === current) return;
      if (next) el.setAttribute('aria-describedby', next);
      else el.removeAttribute('aria-describedby');
    }

    // %{values}: the labels of the first 3 values, then ', ...'; one pass
    // over the options, stopped once the 3 labels are found.
    function valueLabels(ctl, values) {
      var wanted = values.slice(0, 3);
      var want = new Set(wanted);
      var found = new Map();
      var opts = want.size ? optionsOf(ctl) : [];
      for (var k = 0; k < opts.length && found.size < want.size; k += 1) {
        var v = opts[k].value;
        if (want.has(v) && !found.has(v)) {
          found.set(v, textOf(isSelect(ctl) ? opts[k] : (opts[k].closest('label') || opts[k])) || v);
        }
      }
      return wanted.map(function (v) { return found.has(v) ? found.get(v) : v; }).join(', ') +
        (values.length > 3 ? ', ...' : '');
    }

    // legacyValues: the selected legacy values, in order.
    function hintText(ctl, cfg, hint, legacyValues, parentEl) {
      if (!hint) return '';
      var parent = (parentEl ? labelText(parentEl) : '') || cfg.parentLabel;
      var shown = hint === 'legacy' ? valueLabels(ctl, legacyValues) : '';
      switch (hint) {
        case 'waiting': return parent ? t('selectParent', { parent: parent }) : t('noOptionsGeneric');
        case 'empty': return parentEl && parent ? t('noOptions', { parent: parent }) : t('noOptionsGeneric');
        case 'legacy':
          if (parentEl && parent) return t('legacy', { parent: parent, values: shown });
          if (parent) return t('legacyLocked', { parent: parent, values: shown });
          return t('legacyGeneric', { values: shown });
        case 'bulkDefault': return parent ? t('bulkDefault', { parent: parent }) : '';
        case 'bulkCleared': return parent ? t('bulkCleared', { parent: parent }) : '';
        default: return '';
      }
    }

    // One em.info.dcf-hint per control, created lazily; true when a visible
    // text newly appeared or changed.
    function setHint(ctl, st, text, legacy) {
      if (!text && !st.hint) return false;
      if (!st.hint) {
        var em = document.createElement('em');
        em.className = 'info dcf-hint';
        em.id = 'dcf-hint-' + (++hintSeq);
        em.hidden = true;
        var box = ctl.closest('p, .cf-wizard-field');
        if (box) box.appendChild(em);
        else ctl.parentNode.insertBefore(em, ctl.nextSibling);
        st.hint = em;
      }
      var hint = st.hint;
      var changed = !!text && (hint.hidden || hint.textContent !== text);
      if (text && hint.textContent !== text) hint.textContent = text;
      if (hint.hidden !== !text) hint.hidden = !text;
      setClass(hint, 'dcf-hint--legacy', !!text && legacy);
      describedTargets(ctl).forEach(function (el) { setDescribedBy(el, hint.id, !!text); });
      return changed;
    }

    function hideHint(ctl, st) {
      if (!st.hint) return;
      if (!st.hint.hidden) st.hint.hidden = true;
      describedTargets(ctl).forEach(function (el) { setDescribedBy(el, st.hint.id, false); });
    }

    // The visible hint text of a control, or null; null too inside a hidden
    // element (a p hidden by hide_when_disabled, the server or a theme).
    // A UD-37 warning element stands for itself.
    function shownHint(ctl) {
      if (lockedEls.has(ctl)) return !ctl.hidden && !ctl.closest('[hidden]') ? ctl.textContent : null;
      var st = states.get(ctl);
      return st && st.hint && !st.hint.hidden && !ctl.closest('[hidden]') ? st.hint.textContent : null;
    }

    // UD-37 (WP-18): a carrier of a visible read-only dependent field (WP-16)
    // names its parent; while any carrier of a parent predicts that the
    // server refuses the parent's current values, one warning em sits under
    // that parent control. Text only: no option is disabled, submit is never
    // blocked and the carrier is never changed. Invalid carriers are ignored.
    function lockedParent(scope, fieldId) {
      return findParent(scope, 'issue[custom_field_values][' + fieldId + ']') ||
        findParent(scope, 'project[custom_field_values][' + fieldId + ']');
    }
    function predictsRefusal(carrier, values) {
      var stored = jsonAttr(carrier.getAttribute('data-dcf-locked-stored'));
      var allowedBy = jsonAttr(carrier.getAttribute('data-dcf-locked-allowed-by'));
      return Array.isArray(stored) && Array.isArray(allowedBy) && R.lockedRefused(stored, allowedBy, values);
    }
    function carriersOf(scope, fieldId) {
      return Array.prototype.filter.call(scope.querySelectorAll(LOCKED_SEL), function (c) {
        return c.getAttribute('data-dcf-locked-parent') === fieldId && scopeOf(c) === scope;
      });
    }
    function refusedFor(scope, fieldId, values) {
      return carriersOf(scope, fieldId).some(function (c) { return predictsRefusal(c, values); });
    }
    // The warning element when it newly appeared or changed, else null.
    function setLockedWarning(parent, on) {
      var el = parent.el;
      var em = lockedHints.get(el);
      if (!on && !em) return null;
      if (!em) {
        em = document.createElement('em');
        em.className = 'info dcf-hint dcf-hint--locked';
        em.id = 'dcf-hint-' + (++hintSeq);
        em.hidden = true;
        var box = el.closest('p, .cf-wizard-field');
        var anchor = el.closest('.check_box_group') || el;
        if (box) box.appendChild(em);
        else anchor.parentNode.insertBefore(em, anchor.nextSibling);
        lockedHints.set(el, em);
        lockedEls.add(em);
      }
      var text = t('lockedRefused');
      var appeared = on && (em.hidden || em.textContent !== text);
      if (on && em.textContent !== text) em.textContent = text;
      if (em.hidden !== !on) em.hidden = !on;
      var targets = isSelect(el) ? [el] : parent.els.filter(function (i) { return i.type === 'radio' || i.type === 'checkbox'; });
      targets.forEach(function (target) { setDescribedBy(target, em.id, on); });
      return appeared ? em : null;
    }
    // Checks the carriers of the given field ids (each once per scope) and
    // returns {ctl, announce} entries for the live region.
    function checkLocked(pairs) {
      var done = new Map();
      var out = [];
      pairs.forEach(function (pair) {
        var scope = pair[0];
        var fieldId = pair[1];
        if (!done.has(scope)) done.set(scope, new Set());
        if (done.get(scope).has(fieldId)) return;
        done.get(scope).add(fieldId);
        if (!carriersOf(scope, fieldId).length) return;
        var parent = lockedParent(scope, fieldId);
        if (!parent) return;
        var refused = refusedFor(scope, fieldId, parent.values);
        var em = setLockedWarning(parent, refused);
        var shown = lockedHints.get(parent.el);
        if (shown) out.push({ ctl: shown, announce: em ? em.textContent : null });
      });
      return out;
    }
    // The [scope, parent id] pairs of the carriers in or around +root+.
    function carrierPairs(root) {
      var list = [];
      if (root.nodeType === 1 && root.matches(LOCKED_SEL)) list.push(root);
      list = list.concat(Array.prototype.slice.call(root.querySelectorAll(LOCKED_SEL)));
      return list.filter(function (c) { return c.isConnected; }).map(function (c) {
        return [scopeOf(c), c.getAttribute('data-dcf-locked-parent')];
      });
    }

    // D3: only the field's own p, only when it holds no control of another
    // field; un-hiding removes only what the runtime added.
    function setFieldHidden(ctl, hide, cfg) {
      var p = ctl.closest('p');
      if (!p) return;
      if (hide) {
        if (hiddenByUs.has(p) || p.hidden) return;
        var foreign = Array.prototype.some.call(p.querySelectorAll('select, input, textarea'), function (el) {
          if (el === ctl || ctl.contains(el) || !el.name) return false;
          var parsed = R.parseFieldName(el.name);
          return !parsed || parsed.fieldId !== cfg.fieldId || parsed.prefix !== cfg.prefix;
        });
        if (foreign) return;
        hiddenByUs.add(p);
        p.classList.add('dcf-hidden');
        p.hidden = true;
      } else if (hiddenByUs.has(p)) {
        hiddenByUs.delete(p);
        p.classList.remove('dcf-hidden');
        p.hidden = false;
      }
    }

    function evaluate(ctl) {
      var cfg = config(ctl);
      if (!cfg) return null;
      var st = states.get(ctl);
      var initial = !st;
      var scope = scopeOf(ctl);
      var parent = findParent(scope, cfg.parentName);
      // A managed parent's dependents follow its current values from here on
      // (the re-dispatch check of recordPick).
      var pctl = parent ? childOf(parent.el) : null;
      var pst = pctl ? states.get(pctl) : null;
      if (pst) pst.followed = parent.values;
      var ps = R.parentState(cfg.ctx, !!parent, parent ? parent.values : [], cfg.staticValues, !!cfg.map);
      var sig = ps.kind + '|' + ps.key;
      if (!initial && sig === st.sig) return null;
      if (initial) {
        st = { sig: null, key: null, kind: null, values: [], applied: [], followed: [], hint: null, autoHint: false,
               form: null };
        states.set(ctl, st);
        ctl.classList.add('depending-child');
      }
      var before = readValues(ctl);
      var options = optionsOf(ctl);
      // Each option value is read once per evaluation; apply reuses them.
      var optionVals = options.map(function (o) { return o.value; });
      var optionValues = new Set(optionVals);
      var noneRequired = options.some(function (o, k) { return isRequiredNone(o, optionVals[k]); });
      var allowed = ps.kind === 'values' || ps.kind === 'static' ? R.allowedFor(cfg.map, ps.values) :
        (ps.kind === 'empty' || ps.kind === 'none' ? new Set() : null);
      var mem = memoryFor(scope, cfg);
      var d = R.decide({
        ctx: cfg.ctx, kind: ps.kind, key: ps.key, values: ps.values, prevValues: st.values, allowed: allowed,
        current: before, initial: initial, parentChanged: !initial, multiple: cfg.multiple,
        hasBlank: optionValues.has(R.BLANK), hasNone: optionValues.has(R.NONE), noneRequired: noneRequired,
        optionValues: optionValues, defaults: cfg.defaults, memory: mem, hide: cfg.hide, stored: cfg.stored
      });
      apply(ctl, d, options, optionVals);
      var legacyValues = d.values.filter(function (v) { return d.legacy.has(v); });
      var text = hintText(ctl, cfg, d.hint, legacyValues, parent && parent.el);
      var announce = setHint(ctl, st, text, d.hint === 'legacy');
      var after = readValues(ctl);
      // D3 keeps a field shown while a UD-37 carrier predicts a refusal of
      // its values, so the warning under it stays visible.
      setFieldHidden(ctl, d.hideField && !refusedFor(scope, cfg.fieldId, after), cfg);
      if (ctl.getAttribute('data-dcf-state') !== d.state) ctl.setAttribute('data-dcf-state', d.state);
      // The class marks the bulk default only; a user change hides both bulk hints.
      setClass(ctl, 'dcf-auto-applied', d.hint === 'bulkDefault');
      st.sig = sig;
      st.key = ps.key;
      st.kind = ps.kind;
      st.values = ps.values;
      st.autoHint = d.hint === 'bulkDefault' || d.hint === 'bulkCleared';
      // What a user pick needs to recompute the legacy state (recordPick).
      st.form = cfg.ctx === 'form' && d.filter ? { kind: ps.kind, allowedSize: allowed.size, eligible: d.eligible } : null;
      st.applied = after;
      st.followed = after;
      if (d.rememberKey !== null) {
        mem.set(d.rememberKey, cfg.ctx === 'form' ? after.filter(function (v) { return !R.isBlank(v); }) : after.slice());
      }
      return { ctl: ctl, fieldId: cfg.fieldId, state: d.state, values: after, changed: !sameList(before, after),
               announce: announce ? text : null };
    }

    function dependentsOf(scope, prefix, fieldId) {
      var name = prefix + '[custom_field_values][' + fieldId + ']';
      return Array.prototype.filter.call(scope.querySelectorAll('[data-dcf-parent="' + fieldId + '"]'), function (c) {
        var cfg = c.isConnected ? config(c) : null;
        return !!cfg && cfg.parentName === name && scopeOf(c) === scope;
      });
    }

    // BFS over dependents with a visited set: each control is evaluated at
    // most once per pass, so stored cycles terminate.
    function spread(scope, queue, visited, results) {
      while (queue.length) {
        var ctl = queue.shift();
        if (visited.has(ctl)) continue;
        visited.add(ctl);
        var res = evaluate(ctl);
        if (!res) continue;
        results.push(res);
        var cfg = config(ctl);
        queue = queue.concat(dependentsOf(scope, cfg.prefix, cfg.fieldId));
      }
    }

    function dispatchAll(results) {
      results.forEach(function (r) {
        if (!r.ctl.isConnected) return;
        if (r.changed) {
          var target = isSelect(r.ctl) ? r.ctl : (choiceInputs(r.ctl)[0] || r.ctl);
          var ev = new window.Event('change', { bubbles: true });
          ownEvents.add(ev);
          target.dispatchEvent(ev);
        }
        r.ctl.dispatchEvent(new window.CustomEvent('dcf:updated', {
          bubbles: true,
          // A copy: a listener never reaches the runtime's own state.
          detail: { fieldId: r.fieldId, state: r.state, values: r.values.slice(), changed: r.changed }
        }));
      });
    }

    // One page-level polite live region, created empty when the first message
    // is queued, so it exists before its text changes.
    function liveRegion() {
      if (!live.el || !live.el.isConnected) {
        live.el = document.createElement('div');
        live.el.id = 'dcf-live';
        live.el.className = 'hidden-for-sighted dcf-live';
        live.el.setAttribute('role', 'status');
        live.el.setAttribute('aria-live', 'polite');
        (document.body || document.documentElement).appendChild(live.el);
      }
      return live.el;
    }

    // 400 ms after the last user change: the latest message of each control
    // whose hint is still shown with that text; nothing when none is left.
    function flushLive() {
      live.timer = null;
      var parts = [];
      live.pending.forEach(function (text, ctl) {
        if (!ctl.isConnected || shownHint(ctl) !== text) return;
        var field = labelText(ctl);
        parts.push(field ? t('liveMessage', { field: field, message: text }) : text);
      });
      live.pending.clear();
      if (parts.length) liveRegion().textContent = parts.join(' ');
    }

    // Pending messages per control: a later one replaces it, a hidden hint drops it.
    function announce(results) {
      var queued = false;
      results.forEach(function (r) {
        if (r.announce && shownHint(r.ctl) === r.announce) {
          live.pending.delete(r.ctl);
          live.pending.set(r.ctl, r.announce);
          queued = true;
        } else if (shownHint(r.ctl) === null) {
          live.pending.delete(r.ctl);
        }
      });
      if (!live.pending.size && live.timer !== null) {
        window.clearTimeout(live.timer);
        live.timer = null;
      }
      if (!queued) return;
      liveRegion();
      if (live.timer !== null) window.clearTimeout(live.timer);
      live.timer = window.setTimeout(flushLive, 400);
    }

    // A user or third-party change of the child: its pick is remembered, the
    // bulk hints go, and in form context state and hint follow the selected
    // legacy values (frontend 5.4); no value changes and no re-evaluation.
    // Values equal to the ones the runtime or the last pick left are no pick;
    // false then: its dependents follow them too, so the event is a
    // re-dispatch and starts no cascade.
    function recordPick(ctl) {
      var cfg = config(ctl);
      var st = states.get(ctl);
      if (!cfg || !st) return true;
      var values = readValues(ctl);
      if (sameList(values, st.applied)) return !sameList(values, st.followed);
      st.applied = values;
      st.followed = values;
      if (st.kind !== 'none' && !(cfg.ctx === 'form' && st.kind === 'unfiltered')) {
        var kept = cfg.ctx === 'form' ? values.filter(function (v) { return !R.isBlank(v); }) : values;
        memoryFor(scopeOf(ctl), cfg).set(st.key, kept);
      }
      if (st.autoHint) {
        st.autoHint = false;
        setClass(ctl, 'dcf-auto-applied', false);
        hideHint(ctl, st);
      }
      if (!st.form) return true;
      var legacy = values.filter(function (v) { return st.form.eligible.has(v); });
      var state = R.formState(st.form.kind, st.form.allowedSize, legacy.length);
      var hint = state === 'ok' ? null : state;
      var parent = findParent(scopeOf(ctl), cfg.parentName);
      setHint(ctl, st, hintText(ctl, cfg, hint, legacy, parent && parent.el), hint === 'legacy');
      if (ctl.getAttribute('data-dcf-state') !== state) ctl.setAttribute('data-dcf-state', state);
      return true;
    }

    function childOf(target) {
      if (isSelect(target)) return target.hasAttribute('data-dcf-parent') ? target : null;
      if (target.type !== 'radio' && target.type !== 'checkbox') return null;
      var group = target.closest(CHILD_SEL);
      return group && !isSelect(group) ? group : null;
    }

    function handleTarget(target) {
      if (!target || (target.tagName !== 'SELECT' && target.tagName !== 'INPUT') || !target.isConnected) return;
      var parsed = R.parseFieldName(target.name);
      if (!parsed) return;
      var ctl = childOf(target);
      // A re-dispatch: no pick, and its dependents already follow the values.
      if (ctl && !recordPick(ctl)) return;
      var scope = scopeOf(target);
      var visited = new Set();
      if (ctl) visited.add(ctl);
      var results = [];
      spread(scope, dependentsOf(scope, parsed.prefix, parsed.fieldId), visited, results);
      // UD-37: the carriers of the changed field and of every field the
      // cascade changed.
      var pairs = [[scope, parsed.fieldId]].concat(changedPairs(results));
      dispatchAll(results);
      announce(results.concat(checkLocked(pairs)));
    }

    function changedPairs(results) {
      return results.filter(function (r) { return r.changed; }).map(function (r) { return [scopeOf(r.ctl), r.fieldId]; });
    }

    function onNativeChange(e) {
      if (!ownEvents.has(e)) handleTarget(e.target);
    }
    function onJQueryChange(e) {
      if (e.isTrigger) handleTarget(e.target);
    }

    function controlsIn(root) {
      var list = [];
      if (root.nodeType === 1 && root.matches(CHILD_SEL)) list.push(root);
      return list.concat(Array.prototype.slice.call(root.querySelectorAll(CHILD_SEL)));
    }

    // Synchronous and idempotent: an evaluation whose parent state did not
    // change is a no-op.
    function init(root) {
      root = root || document;
      if (!root || !root.querySelectorAll || (root.nodeType !== 9 && !root.isConnected)) return;
      var byScope = new Map();
      controlsIn(root).forEach(function (c) {
        if (!c.isConnected || !config(c)) return;
        var s = scopeOf(c);
        if (!byScope.has(s)) byScope.set(s, []);
        byScope.get(s).push(c);
      });
      var results = [];
      byScope.forEach(function (list, scope) {
        var nodes = list.map(function (c) {
          var cfg = config(c);
          var p = R.parseFieldName(cfg.parentName);
          return { id: cfg.prefix + '|' + cfg.fieldId, parentId: p ? p.prefix + '|' + p.fieldId : '', ctl: c };
        });
        var visited = new Set();
        var queue = [];
        R.orderByDepth(nodes).forEach(function (n) {
          visited.add(n.ctl);
          var res = evaluate(n.ctl);
          if (!res) return;
          results.push(res);
          // Dependents outside the root follow every evaluation in it: a new
          // element can render another value than the one they last saw.
          // A document root holds them all.
          if (root.nodeType !== 9) {
            var cfg = config(n.ctl);
            queue = queue.concat(dependentsOf(scope, cfg.prefix, cfg.fieldId));
          }
        });
        spread(scope, queue, visited, results);
      });
      var pairs = carrierPairs(root).concat(changedPairs(results));
      dispatchAll(results);
      // UD-37: a page rendered with a refused parent value (a failed save,
      // an AJAX re-render) shows the warning at once; nothing is announced.
      checkLocked(pairs);
    }

    function publicInit(root) {
      var api = window.DependingCustomFields;
      if (api && typeof api.init === 'function') api.init(root);
      else init(root);
    }

    // Gap 13: the added roots of one callback, deduplicated and without nested
    // or detached ones, are initialised synchronously; no timer. Roots with a
    // UD-37 carrier count too.
    function onMutations(records) {
      var seen = new Set();
      var roots = [];
      records.forEach(function (r) {
        each(r.addedNodes, function (n) {
          if (n.nodeType !== 1 || seen.has(n)) return;
          seen.add(n);
          // One selector, so one subtree walk per added node.
          if (n.matches(ROOT_SEL) || n.querySelector(ROOT_SEL)) roots.push(n);
        });
      });
      roots.filter(function (n) {
        return n.isConnected && !roots.some(function (o) { return o !== n && o.contains(n); });
      }).forEach(publicInit);
    }

    // Deprecated (0.1.0, removable no earlier than 0.2.0): init debounced by
    // 25 ms; roots detached by then are skipped.
    function requestSetup(root) {
      setupRoots.add(root || document);
      if (setupTimer !== null) window.clearTimeout(setupTimer);
      setupTimer = window.setTimeout(function () {
        setupTimer = null;
        var roots = Array.from(setupRoots);
        setupRoots.clear();
        roots.forEach(function (r) {
          if (r === document || r.isConnected) publicInit(r);
        });
      }, 25);
    }

    function start() {
      if (started) return;
      started = true;
      document.addEventListener('change', onNativeChange, false);
      if (typeof window.jQuery === 'function') window.jQuery(document).on('change.dcf', 'select, input', onJQueryChange);
      if (typeof window.MutationObserver === 'function') {
        new window.MutationObserver(onMutations).observe(document.body || document.documentElement,
          { childList: true, subtree: true });
      }
      init(document);
    }

    window.DependingCustomFields = {
      __runtime: true,
      VERSION: R.VERSION,
      rules: R,
      t: t,
      init: function (root) { init(root); },
      setup: function (root) { init(root); },
      requestSetup: requestSetup
    };
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
    else start();
  }

  var rules = buildRules();
  if (typeof window !== 'undefined' && window && window.document) {
    startRuntime(window, window.document, rules);
  } else if (typeof module === 'object' && module && module.exports) {
    module.exports = rules;
  }
}());
