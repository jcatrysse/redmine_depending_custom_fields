/* Redmine Depending Custom Fields: dependency editor model (editor design 5.5
 * and 5.6). Pure: no DOM, no output, no state outside its objects. UMD: in a
 * browser window.DcfDependencyEditorModel (the first copy loaded is kept),
 * under CommonJS module.exports. ES2017 only (npm run check). No object is
 * keyed by user values: Map and Set inside, Object.create(null) filled with
 * defineProperty for the JSON output, so __proto__ and constructor survive
 * (QA-11). The payload is schema v1 of DependencyPayload (WP-21). */
(function (factory) {
  'use strict';
  var model = factory();
  if (typeof window !== 'undefined' && window) {
    if (!window.DcfDependencyEditorModel) window.DcfDependencyEditorModel = model;
  } else if (typeof module === 'object' && module && module.exports) {
    module.exports = model;
  }
}(function () {
  'use strict';

  var VERSION = 1;
  var MAX_IMPORT_ROWS = 10000000;
  var hasOwn = Object.prototype.hasOwnProperty;

  // ---------------------------------------------------------------- collation
  // The tables of ValueCollation (project design 2.7, WP-28): NFKD, strip
  // COMBINING, lowercase, SPECIAL, collapse white space, trim. White space is
  // Ruby [[:space:]] (not JS \s: U+FEFF is not white space, U+0085 is), and
  // the final sigma is mapped to sigma, as Ruby downcase never makes it.
  var COMBINING = /[\u0300-\u036f\u1ab0-\u1aff\u1dc0-\u1dff\u20d0-\u20ff\ufe20-\ufe2f]/g;
  var SPECIAL = new Map([['\u00df', 'ss'], ['\u00e6', 'ae'], ['\u0153', 'oe'], ['\u00f8', 'o'], ['\u0111', 'd'],
    ['\u0142', 'l'], ['\u0131', 'i'], ['\u00fe', 'th'], ['\u03c2', '\u03c3']]);
  var SPECIAL_RE = /[\u00df\u00e6\u0153\u00f8\u0111\u0142\u0131\u00fe\u03c2]/g;
  var SPACE_RUN = /[\t\n\v\f\r \u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]+/g;
  var EDGE_SPACE = /^ | $/g;
  // Ruby blank?: nil, '' and [[:space:]] only.
  var BLANK_RE = /^[\t\n\v\f\r \u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]*$/;
  // Ruby strip (core possible_values=): NUL and ASCII white space at both ends.
  var STRIP_RE = /^[\u0000\t\n\v\f\r ]+|[\u0000\t\n\v\f\r ]+$/g;
  var SURROGATE_RE = /[\ud800-\udfff]/;
  var BASE_RE = /^[0-9a-f]{64}$/;
  // Enumeration ids written as JSON integers: canonical and at most 16 digits.
  var ID_RE = /^[1-9][0-9]{0,15}$/;

  // Search key: case- and accent-insensitive, white space collapsed.
  function fold(s) {
    var out = String(s === null || s === undefined ? '' : s).normalize('NFKD').replace(COMBINING, '').toLowerCase();
    out = out.replace(SPECIAL_RE, function (c) { return SPECIAL.get(c); });
    return out.replace(SPACE_RUN, ' ').replace(EDGE_SPACE, '');
  }

  // Folded query split on spaces; [] (unfiltered) when nothing is left.
  function tokens(query) {
    var f = fold(query);
    return f === '' ? [] : f.split(' ');
  }

  // Every token is a substring of the folded label (AND).
  function matchesTokens(folded, toks) {
    var s = String(folded);
    for (var i = 0; i < toks.length; i++) {
      if (s.indexOf(toks[i]) === -1) return false;
    }
    return true;
  }

  function isBlank(v) {
    return v === null || v === undefined || BLANK_RE.test(String(v));
  }

  // A DependencyPayload digest: 64 lowercase hex characters.
  function isDigest(s) {
    return typeof s === 'string' && BASE_RE.test(s);
  }

  // ---------------------------------------------------------------- helpers
  function isObject(o) {
    return o !== null && typeof o === 'object' && !Array.isArray(o);
  }

  function own(o, key) {
    return hasOwn.call(o, key) ? o[key] : undefined;
  }

  function asList(v) {
    return Array.isArray(v) ? v : [v];
  }

  // A mapping item as a key: a non-blank String or a positive safe integer;
  // null for anything else (never '[object Object]').
  function idString(v) {
    if (typeof v === 'string') return isBlank(v) ? null : v;
    if (typeof v === 'number' && Number.isSafeInteger(v) && v > 0) return String(v);
    return null;
  }

  // {mode, rows} as DependencyPayload accepts it, or null.
  function importMeta(meta) {
    if (!isObject(meta)) return null;
    var mode = own(meta, 'mode');
    var rows = own(meta, 'rows');
    if (mode !== 'merge' && mode !== 'replace') return null;
    if (typeof rows !== 'number' || !Number.isInteger(rows) || rows < 0 || rows > MAX_IMPORT_ROWS) return null;
    return { mode: mode, rows: rows };
  }

  // Lone surrogates become U+FFFD, as the UTF-8 form submission does.
  function wellFormed(s) {
    var out = '';
    for (var i = 0; i < s.length; i++) {
      var c = s.charCodeAt(i);
      if (c >= 0xd800 && c <= 0xdbff) {
        var d = s.charCodeAt(i + 1);
        if (d >= 0xdc00 && d <= 0xdfff) {
          out += s.charAt(i) + s.charAt(i + 1);
          i++;
        } else {
          out += '\ufffd';
        }
      } else if (c >= 0xdc00 && c <= 0xdfff) {
        out += '\ufffd';
      } else {
        out += s.charAt(i);
      }
    }
    return out;
  }

  // UTF-8 byte length (a lone surrogate counts as U+FFFD, like TextEncoder).
  function utf8Bytes(text) {
    var s = String(text);
    var n = 0;
    for (var i = 0; i < s.length; i++) {
      var c = s.charCodeAt(i);
      if (c < 0x80) {
        n += 1;
      } else if (c < 0x800) {
        n += 2;
      } else if (c >= 0xd800 && c <= 0xdbff) {
        var d = s.charCodeAt(i + 1);
        if (d >= 0xdc00 && d <= 0xdfff) {
          n += 4;
          i++;
        } else {
          n += 3;
        }
      } else {
        n += 3;
      }
    }
    return n;
  }

  // ---------------------------------------------------------------- values
  // Items {key, label, active, index, folded} in wire order; byKey is a Map.
  function ValueList() {
    this.items = [];
    this.byKey = new Map();
  }
  ValueList.prototype.has = function (key) { return this.byKey.has(String(key)); };
  ValueList.prototype.get = function (key) { return this.byKey.get(String(key)); };
  ValueList.prototype.keys = function () { return this.items.map(function (item) { return item.key; }); };

  // The compact wire shape of DependencyEditorConfig.wire_values (editor
  // design 4.1): label only when it differs from the key, active only when
  // false. A blank or repeated key is skipped (the first one is kept);
  // anything but an Array of {key} objects is a TypeError (fail closed).
  ValueList.fromWire = function (values) {
    if (!Array.isArray(values)) throw new TypeError('DcfDependencyEditorModel: values must be an Array');
    var list = new ValueList();
    values.forEach(function (o, i) {
      var key = isObject(o) && hasOwn.call(o, 'key') ? o.key : undefined;
      if (typeof key !== 'string' && !(typeof key === 'number' && isFinite(key))) {
        throw new TypeError('DcfDependencyEditorModel: value ' + i + ' has no key');
      }
      key = String(key);
      if (isBlank(key) || list.byKey.has(key)) return;
      var label = hasOwn.call(o, 'label') ? String(o.label) : key;
      var item = { key: key, label: label, active: !(hasOwn.call(o, 'active') && o.active === false),
                   index: list.items.length, folded: fold(label) };
      list.items.push(item);
      list.byKey.set(key, item);
    });
    return list;
  };

  // List values as core possible_values= stores them: split on CR/LF, Ruby
  // strip, blanks dropped; repeated values once (value_keys). Wire shape.
  function listValuesFromText(text) {
    var s = text === null || text === undefined ? '' : String(text);
    if (SURROGATE_RE.test(s)) s = wellFormed(s);
    var seen = new Set();
    var out = [];
    s.split(/[\n\r]+/).forEach(function (line) {
      var v = line.replace(STRIP_RE, '');
      if (isBlank(v) || seen.has(v)) return;
      seen.add(v);
      out.push({ key: v });
    });
    return out;
  }

  // ---------------------------------------------------------------- state
  // Superset of the mapping: links Map<parentKey, Set<childKey>> and defaults
  // Map<parentKey, childKey[]> (linked children only) keep keys unknown to the
  // current lists, so list edits never lose links; serialize() intersects.
  // The mapping is a JSON.parse result (data-dcf-editor-mapping or the
  // conflict mapping): keys and values become Strings, blanks and items that
  // are not a String or a positive integer are dropped, a default may be one
  // value or a list. source and import come from a conflict mapping.
  function State(mapping) {
    this.links = new Map();
    this.defaults = new Map();
    this.source = 'editor';
    this.importMeta = null;
    if (!isObject(mapping)) return;
    var self = this;
    var vd = own(mapping, 'value_dependencies');
    var dd = own(mapping, 'default_value_dependencies');
    if (isObject(vd)) {
      Object.keys(vd).forEach(function (pk) {
        asList(vd[pk]).forEach(function (v) {
          var ck = idString(v);
          if (ck !== null) self.link(pk, ck, true);
        });
      });
    }
    if (isObject(dd)) {
      Object.keys(dd).forEach(function (pk) {
        var keys = [];
        asList(dd[pk]).forEach(function (v) {
          var ck = idString(v);
          if (ck !== null) keys.push(ck);
        });
        self.setDefaults(pk, keys);
      });
    }
    if (own(mapping, 'source') === 'import') {
      this.source = 'import';
      this.importMeta = importMeta(own(mapping, 'import'));
    }
  }

  State.prototype.isLinked = function (pk, ck) {
    var set = this.links.get(String(pk));
    return !!(set && set.has(String(ck)));
  };

  // Links (on) or unlinks a pair; true when it changed. Unlinking also
  // removes the child from that parent's defaults.
  State.prototype.link = function (pk, ck, on) {
    var p = String(pk);
    var c = String(ck);
    if (isBlank(p) || isBlank(c)) return false;
    var set = this.links.get(p);
    if (on) {
      if (!set) {
        set = new Set();
        this.links.set(p, set);
      }
      if (set.has(c)) return false;
      set.add(c);
      return true;
    }
    if (!set || !set.has(c)) return false;
    set.delete(c);
    if (set.size === 0) this.links.delete(p);
    var d = this.defaults.get(p);
    if (d) {
      var kept = d.filter(function (k) { return k !== c; });
      if (kept.length) this.defaults.set(p, kept);
      else this.defaults.delete(p);
    }
    return true;
  };

  // Defaults of pk: the linked keys among +keys+, once each, in that order.
  State.prototype.setDefaults = function (pk, keys) {
    var p = String(pk);
    var set = this.links.get(p);
    var seen = new Set();
    var kept = [];
    (Array.isArray(keys) ? keys : []).forEach(function (k) {
      var c = String(k);
      if (set && set.has(c) && !seen.has(c)) {
        seen.add(c);
        kept.push(c);
      }
    });
    if (kept.length) this.defaults.set(p, kept);
    else this.defaults.delete(p);
  };

  State.prototype.defaultsOf = function (pk) {
    var d = this.defaults.get(String(pk));
    return d ? d.slice() : [];
  };

  State.prototype.clone = function () {
    var copy = new State(null);
    this.links.forEach(function (set, pk) { copy.links.set(pk, new Set(set)); });
    this.defaults.forEach(function (keys, pk) { copy.defaults.set(pk, keys.slice()); });
    copy.source = this.source;
    copy.importMeta = importMeta(this.importMeta);
    return copy;
  };

  // Counters on the current lists. parents null (values not loaded) counts
  // every state parent key as current.
  function current(parents, pk) {
    return parents === null || parents.byKey.has(pk);
  }

  // Current children linked under pk.
  State.prototype.linkedCount = function (pk, children) {
    var set = this.links.get(String(pk));
    var n = 0;
    if (set) set.forEach(function (ck) { if (children.byKey.has(ck)) n++; });
    return n;
  };

  // Map<childKey, number of current parents linking it>, linked children only.
  State.prototype.childLinkCounts = function (parents, children) {
    var counts = new Map();
    this.links.forEach(function (set, pk) {
      if (!current(parents, pk)) return;
      set.forEach(function (ck) {
        if (children.byKey.has(ck)) counts.set(ck, (counts.get(ck) || 0) + 1);
      });
    });
    return counts;
  };

  // Current parents without a current child (0 when parents is null).
  State.prototype.parentsWithoutLinks = function (parents, children) {
    var self = this;
    if (parents === null) return 0;
    return parents.items.filter(function (item) { return self.linkedCount(item.key, children) === 0; }).length;
  };

  // Current children not linked to any current parent, in child order.
  State.prototype.unlinkedChildren = function (parents, children) {
    var counts = this.childLinkCounts(parents, children);
    return children.items.filter(function (item) { return !counts.has(item.key); });
  };

  // Link pairs serialize() leaves out: parent or child not in the current
  // lists (orphans at init, links dropped by a parent change).
  State.prototype.orphanCount = function (parents, children) {
    var n = 0;
    this.links.forEach(function (set, pk) {
      var known = current(parents, pk);
      set.forEach(function (ck) { if (!known || !children.byKey.has(ck)) n++; });
    });
    return n;
  };

  function onlyIn(a, b, parents, children) {
    var n = 0;
    a.links.forEach(function (set, pk) {
      if (!current(parents, pk)) return;
      var other = b.links.get(pk);
      set.forEach(function (ck) {
        if (children.byKey.has(ck) && !(other && other.has(ck))) n++;
      });
    });
    return n;
  }

  // Conflict panel counts: link pairs on the current lists present only in
  // my version or only in the current one.
  function conflictCounts(mine, latest, parents, children) {
    return { onlyMine: onlyIn(mine, latest, parents, children),
             onlyCurrent: onlyIn(latest, mine, parents, children) };
  }

  // ---------------------------------------------------------------- serialize
  function put(obj, key, value) {
    Object.defineProperty(obj, key, { value: value, enumerable: true, writable: true, configurable: true });
  }

  function wireValue(key, integers) {
    if (integers && ID_RE.test(key)) {
      var n = Number(key);
      if (Number.isSafeInteger(n) && String(n) === key) return n;
    }
    return key;
  }

  // Payload v1 for the hidden input. Parent keys in parents order (state
  // order when parents is null: the values could not be loaded and the server
  // prunes), each with its linked current children in children order; keys
  // without a current child are left out (orphans stay in the state).
  // Defaults: linked current children in child order, an Array when
  // opts.multiple === true, else the first one as a String. opts.kind
  // 'enumeration' writes canonical ids as JSON integers. version is the
  // Number 1; import only with source import and a valid {mode, rows}
  // (opts.importMeta, else state.importMeta); base only for a non-empty
  // String (admin). JSON.stringify puts array-index keys ('2', '10',
  // enumeration ids) first in ascending order; the server orders by parent.
  function serialize(state, parents, children, opts) {
    if (!(state instanceof State)) throw new TypeError('DcfDependencyEditorModel: state must be a State');
    if (parents !== null && !(parents instanceof ValueList)) {
      throw new TypeError('DcfDependencyEditorModel: parents must be a ValueList or null');
    }
    if (!(children instanceof ValueList)) throw new TypeError('DcfDependencyEditorModel: children must be a ValueList');
    var o = opts || {};
    var multiple = o.multiple === true;
    var integers = o.kind === 'enumeration';
    var vd = Object.create(null);
    var dd = Object.create(null);
    var parentKeys = parents === null ? Array.from(state.links.keys()) : parents.keys();
    var out = function (item) { return wireValue(item.key, integers); };
    parentKeys.forEach(function (pk) {
      var set = state.links.get(pk);
      if (!set || isBlank(pk)) return;
      var kept = [];
      set.forEach(function (ck) {
        var item = children.byKey.get(ck);
        if (item) kept.push(item);
      });
      if (!kept.length) return;
      kept.sort(function (a, b) { return a.index - b.index; });
      put(vd, pk, kept.map(out));
      var d = state.defaults.get(pk);
      if (!d || !d.length) return;
      var chosen = new Set(d);
      var defaults = kept.filter(function (item) { return chosen.has(item.key); });
      if (defaults.length) put(dd, pk, multiple ? defaults.map(out) : out(defaults[0]));
    });
    var source = state.source === 'import' ? 'import' : 'editor';
    var payload = { version: VERSION, source: source };
    if (source === 'import') {
      var meta = importMeta(hasOwn.call(o, 'importMeta') && o.importMeta !== undefined ? o.importMeta : state.importMeta);
      if (meta) payload.import = meta;
    }
    if (typeof o.base === 'string' && o.base !== '') payload.base = o.base;
    payload.value_dependencies = vd;
    payload.default_value_dependencies = dd;
    return payload;
  }

  // The hidden input value.
  function stringify(payload) {
    return JSON.stringify(payload);
  }

  return {
    VERSION: VERSION,
    fold: fold,
    tokens: tokens,
    matchesTokens: matchesTokens,
    isBlank: isBlank,
    isDigest: isDigest,
    utf8Bytes: utf8Bytes,
    ValueList: ValueList,
    listValuesFromText: listValuesFromText,
    State: State,
    conflictCounts: conflictCounts,
    serialize: serialize,
    stringify: stringify
  };
}));
