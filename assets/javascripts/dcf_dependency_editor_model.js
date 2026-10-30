/* Redmine Depending Custom Fields: dependency editor model (editor design 5.5
 * and 5.6). Pure: no DOM, no output, no state outside its objects. UMD: in a
 * browser window.DcfDependencyEditorModel (the first copy loaded is kept),
 * under CommonJS module.exports. ES2017 only (npm run check). No object is
 * keyed by user values: Map and Set inside, Object.create(null) filled with
 * defineProperty for the JSON output, so __proto__ and constructor survive
 * (QA-11). The payload is schema v1 of DependencyPayload (WP-21). WP-26:
 * CSV import (parseRecords, planImport, applyImport) and export (buildCsv). */
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
  // Ruby strip (core possible_values=): NUL and ASCII white space at both
  // ends, by index (a regex is quadratic on long inner white space).
  function stripCode(c) {
    return c === 0 || c === 32 || (c >= 9 && c <= 13);
  }

  function strip(text) {
    var s = String(text);
    var a = 0;
    var b = s.length;
    while (a < b && stripCode(s.charCodeAt(a))) a++;
    while (b > a && stripCode(s.charCodeAt(b - 1))) b--;
    return a === 0 && b === s.length ? s : s.slice(a, b);
  }

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
  // Items {key, label, active, index, folded} in wire order; byKey is a Map;
  // labelIndex holds the import lookups once built (candidates below).
  function ValueList() {
    this.items = [];
    this.byKey = new Map();
    this.labelIndex = null;
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
      var v = strip(line);
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

  // ---------------------------------------------------------------- import
  // CSV import and export (editor design 6.1 to 6.7, WP-26). Line errors are
  // {line, code} plus count, max or value: data, never text (the DOM layer
  // words them). Lookups use Map and Set only (QA-11).
  var MAX_IMPORT_CHARS = 10000000;
  var MAX_IMPORT_RECORDS = 200000;
  var MAX_LINE_ERRORS = 200;
  var DETECT_CHARS = 65536;
  var DETECT_RECORDS = 20;
  var KEEP_CELLS = 10;
  // Detection and tie order: tab, semicolon, comma.
  var CANDIDATES = ['\t', ';', ','];
  // Quoted on export: a candidate separator, a quote, CR or LF.
  var QUOTE_RE = /[\t;,"\r\n]/;
  var LINE_BREAK_RE = /[\r\n]/;

  function isSeparator(sep) {
    return sep === '\t' || sep === ';' || sep === ',';
  }

  // White space a cell is trimmed of: before an opening quote, after a
  // closing quote, around an unquoted cell (not the separator, CR or LF).
  function padCode(c, sep) {
    return (c === 32 || c === 0 || c === 9 || c === 11 || c === 12) && c !== sep;
  }

  // One pass over text[0, end). visit(rec) gets every record that is not
  // blank: {line (start line), cells (the first KEEP_CELLS), count (cells
  // after trailing empty ones are dropped), error, errorLine, plainQuote (a
  // quote inside an unquoted cell)}; returning false stops. A bad quote
  // skips to the end of its line; an unterminated quote ends the scan. With
  // partial (detection on a prefix) a record cut at end is left out.
  function scan(text, sep, end, partial, visit) {
    var n = end;
    var s = sep.charCodeAt(0);
    var i = 0;
    var line = 1;
    var buf = [];
    while (i < n) {
      var first = text.charCodeAt(i);
      if (first === 10 || first === 13) {
        // an empty line
        i++;
        if (first === 13 && i < n && text.charCodeAt(i) === 10) i++;
        line++;
        if (partial && i >= n) return;
        continue;
      }
      var start = line;
      var count = 0;
      var filled = 0;
      var error = null;
      var errorLine = 0;
      var plainQuote = false;
      var cut = false;
      for (;;) {
        var j = i;
        while (j < n && padCode(text.charCodeAt(j), s)) j++;
        var value;
        if (j < n && text.charCodeAt(j) === 34) {
          var k = j + 1;
          var escaped = false;
          var closed = false;
          while (k < n) {
            var q = text.indexOf('"', k);
            if (q === -1 || q >= n) q = n;
            for (; k < q; k++) {
              var c = text.charCodeAt(k);
              if (c === 10 || (c === 13 && !(k + 1 < n && text.charCodeAt(k + 1) === 10))) line++;
            }
            if (q >= n) break;
            if (q + 1 < n && text.charCodeAt(q + 1) === 34) {
              escaped = true;
              k = q + 2;
              continue;
            }
            closed = true;
            break;
          }
          if (!closed) {
            if (partial) cut = true;
            else {
              error = 'unterminated_quote';
              errorLine = start;
            }
            i = n;
            break;
          }
          value = text.slice(j + 1, k);
          // the content holds no lone quote; split is linear and fast here
          if (escaped) value = value.split('""').join('"');
          k++;
          while (k < n && padCode(text.charCodeAt(k), s)) k++;
          if (k < n) {
            var d = text.charCodeAt(k);
            if (d !== s && d !== 10 && d !== 13) {
              error = 'bad_quote';
              errorLine = line;
              // kept for the header warning (header yes); the rest of the line goes
              if (count < KEEP_CELLS) buf[count] = value;
              count++;
              if (value !== '') filled = count;
              while (k < n && text.charCodeAt(k) !== 10 && text.charCodeAt(k) !== 13) k++;
              i = k;
              break;
            }
          }
          i = k;
        } else {
          var m = i;
          while (m < n) {
            var e = text.charCodeAt(m);
            if (e === s || e === 10 || e === 13) break;
            if (e === 34) plainQuote = true;
            m++;
          }
          value = m === i ? '' : strip(text.slice(i, m));
          i = m;
        }
        if (count < KEEP_CELLS) buf[count] = value;
        count++;
        if (value !== '') filled = count;
        if (i < n && text.charCodeAt(i) === s) {
          i++;
          continue;
        }
        break;
      }
      var terminated = false;
      if (i < n) {
        var t = text.charCodeAt(i);
        if (t === 13 || t === 10) {
          i++;
          if (t === 13 && i < n && text.charCodeAt(i) === 10) i++;
          line++;
          terminated = true;
        }
      }
      if (cut || (partial && !terminated)) return;
      if (error === null && filled === 0) continue;
      var rec = { line: start, cells: buf.slice(0, Math.min(filled, KEEP_CELLS)), count: filled, error: error,
                  errorLine: errorLine, plainQuote: plainQuote };
      if (visit(rec) === false) return;
    }
  }

  // Separator auto (editor design 6.1): the real scan of the first 64 KB per
  // candidate, scoring the first 20 records with exactly two non-blank
  // cells; a tie goes to more such records without a quote inside an
  // unquoted cell, then to the order tab ; ,; nothing found: +fallback+ when
  // it is one of them, else ','.
  function detect(text, fallback) {
    var end = Math.min(text.length, DETECT_CHARS);
    var partial = text.length > DETECT_CHARS;
    var best = null;
    var bestScore = 0;
    var bestClean = 0;
    CANDIDATES.forEach(function (sep) {
      var score = 0;
      var clean = 0;
      var seen = 0;
      scan(text, sep, end, partial, function (rec) {
        seen++;
        if (rec.error === null && rec.count === 2 && !isBlank(rec.cells[0]) && !isBlank(rec.cells[1])) {
          score++;
          if (!rec.plainQuote) clean++;
        }
        return seen < DETECT_RECORDS;
      });
      if (score > bestScore || (score > 0 && score === bestScore && clean > bestClean)) {
        best = sep;
        bestScore = score;
        bestClean = clean;
      }
    });
    if (best !== null) return best;
    return isSeparator(fallback) ? fallback : ',';
  }

  function capError(code, max) {
    return { line: null, code: code, max: max };
  }

  // keep: how many line errors are stored (the rest are counted).
  function parse(text, sep, fallback, keep) {
    var s = text === null || text === undefined ? '' : String(text);
    var out = { separator: isSeparator(sep) ? sep : (isSeparator(fallback) ? fallback : ','), records: [], first: null,
                errors: [], errorCount: 0, lines: 0 };
    if (s.length > MAX_IMPORT_CHARS) {
      out.errors.push(capError('too_large', MAX_IMPORT_CHARS));
      out.errorCount = 1;
      return out;
    }
    if (s.charCodeAt(0) === 0xfeff) s = s.slice(1);
    if (!isSeparator(sep)) out.separator = detect(s, fallback);
    var tooMany = false;
    scan(s, out.separator, s.length, false, function (rec) {
      out.lines++;
      if (out.lines > MAX_IMPORT_RECORDS) {
        tooMany = true;
        return false;
      }
      var code = rec.error;
      if (code === null && rec.count !== 2) code = 'columns';
      if (code === null && (isBlank(rec.cells[0]) || isBlank(rec.cells[1]))) code = 'blank_value';
      if (out.first === null) {
        out.first = { line: rec.line, cells: rec.cells, count: rec.count, code: code,
                      errorLine: rec.error === null ? rec.line : rec.errorLine };
      }
      if (code === null) {
        out.records.push({ line: rec.line, cells: [rec.cells[0], rec.cells[1]] });
        return true;
      }
      out.errorCount++;
      if (out.errors.length < keep) {
        var entry = { line: rec.error === null ? rec.line : rec.errorLine, code: code };
        if (code === 'columns') entry.count = rec.count;
        out.errors.push(entry);
      }
      return true;
    });
    if (tooMany) {
      out.records = [];
      out.first = null;
      out.errors = [capError('too_many_lines', MAX_IMPORT_RECORDS)];
      out.errorCount = 1;
      out.lines = 0;
    }
    return out;
  }

  // Pasted or decoded text as records (editor design 6.1): sep is ';', ','
  // or TAB, anything else detects it (opts.fallback: the locale separator).
  // Returns {separator, records [{line, cells [a, b]}], first (the first
  // record as read, with the line of its error), errors (the first 200 by
  // line), errorCount, lines}.
  function parseRecords(text, sep, opts) {
    var o = opts || {};
    return parse(text, sep, o.fallback, MAX_LINE_ERRORS);
  }

  // The NFC lowercase key of import matching (accents significant, not fold).
  function caseKey(s) {
    return String(s).normalize('NFC').toLowerCase();
  }

  function addTo(map, key, item) {
    var list = map.get(key);
    if (list) list.push(item);
    else map.set(key, [item]);
  }

  // The items a cell matches (editor design 6.3): every item with that exact
  // label, else with that NFC label, else with that NFC lowercase label;
  // [] when none. Labels can repeat (enumerations), so each step keeps every
  // candidate. The index is built once per list, on the list.
  function candidates(list, cell) {
    var index = list.labelIndex;
    if (!index) {
      index = { exact: new Map(), nfc: new Map(), lower: new Map() };
      list.items.forEach(function (item) {
        var nfc = item.label.normalize('NFC');
        addTo(index.exact, item.label, item);
        addTo(index.nfc, nfc, item);
        addTo(index.lower, nfc.toLowerCase(), item);
      });
      list.labelIndex = index;
    }
    var s = String(cell);
    var nfc = s.normalize('NFC');
    return index.exact.get(s) || index.nfc.get(nfc) || index.lower.get(nfc.toLowerCase()) || [];
  }

  ValueList.prototype.match = function (cell) {
    return candidates(this, cell).slice();
  };

  // A formula trigger (= + - @ TAB CR) after any leading apostrophes
  // (UD-18, SP-14). Protect adds one apostrophe and unprotect removes one,
  // so with both options every value comes back unchanged.
  function formulaLike(s) {
    var i = 0;
    while (i < s.length && s.charCodeAt(i) === 39) i++;
    if (i >= s.length) return false;
    var c = s.charCodeAt(i);
    return c === 61 || c === 43 || c === 45 || c === 64 || c === 9 || c === 13;
  }

  function protectCell(s) {
    return formulaLike(s) ? "'" + s : s;
  }

  function unprotectCell(s) {
    return s.charCodeAt(0) === 39 && formulaLike(s) ? s.slice(1) : s;
  }

  // RFC 4180 field: quoted when it holds a candidate separator, a quote, CR
  // or LF, or starts or ends with a character the import trims.
  function csvField(value) {
    var s = String(value);
    if (QUOTE_RE.test(s) || (s !== '' && (stripCode(s.charCodeAt(0)) || stripCode(s.charCodeAt(s.length - 1))))) {
      return '"' + s.replace(/"/g, '""') + '"';
    }
    return s;
  }

  function byIndex(a, b) {
    return a.index - b.index;
  }

  // The children list with +values+ appended (add missing child values).
  function extended(list, values) {
    var wire = list.items.map(function (item) {
      var o = { key: item.key };
      if (item.label !== item.key) o.label = item.label;
      if (!item.active) o.active = false;
      return o;
    });
    values.forEach(function (v) { wire.push({ key: v }); });
    return ValueList.fromWire(wire);
  }

  // Two sorted error lists merged by line (null first), the first +keep+.
  function mergeErrors(a, b, keep) {
    var out = [];
    var i = 0;
    var j = 0;
    var rank = function (e) { return e.line === null ? 0 : e.line; };
    while (out.length < keep && (i < a.length || j < b.length)) {
      if (j >= b.length || (i < a.length && rank(a[i]) <= rank(b[j]))) out.push(a[i++]);
      else out.push(b[j++]);
    }
    return out;
  }

  function checkLists(state, parents, children) {
    if (!(state instanceof State)) throw new TypeError('DcfDependencyEditorModel: state must be a State');
    if (!(parents instanceof ValueList)) throw new TypeError('DcfDependencyEditorModel: parents must be a ValueList');
    if (!(children instanceof ValueList)) throw new TypeError('DcfDependencyEditorModel: children must be a ValueList');
  }

  // The import plan (editor design 6.2 to 6.5); changes nothing. opts:
  // separator ('auto', ';', ',', TAB), defaultSeparator (the locale one),
  // header ('auto', 'yes', 'no'), mode ('merge', 'replace'), addMissing
  // (kind 'list' only), unprotect, parentName, childName, and the payload
  // options of the editor (kind, multiple, base) plus maxPayloadBytes for
  // the estimate. ok: no error, a pair (or replace mode after a non-empty
  // input) and the resulting payload within maxPayloadBytes.
  function planImport(text, state, parents, children, opts) {
    checkLists(state, parents, children);
    var o = opts || {};
    var mode = o.mode === 'replace' ? 'replace' : 'merge';
    var header = o.header === 'yes' || o.header === 'no' ? o.header : 'auto';
    var addMissing = o.addMissing === true && o.kind === 'list';
    var unprotect = o.unprotect === true;
    var parsed = parse(text, o.separator, o.defaultSeparator, MAX_LINE_ERRORS + 1);
    var plan = { ok: false, mode: mode, errors: [], errorCount: 0, warnings: [], warningCount: 0, pairs: [], added: 0,
                 existing: 0, removed: 0, duplicates: 0, newValues: [], headerSkipped: false, headerCells: [],
                 separator: parsed.separator, lines: parsed.lines, estimatedPayloadBytes: null, tooLarge: false };
    var cell = function (v) { return unprotect ? unprotectCell(v) : v; };
    var matchErrors = [];
    var matchCount = 0;
    var report = {
      error: function (line, code, value) {
        matchCount++;
        if (matchErrors.length >= MAX_LINE_ERRORS) return;
        var entry = { line: line, code: code };
        if (value !== undefined) entry.value = value;
        matchErrors.push(entry);
      },
      inactive: function (line, value) {
        plan.warningCount++;
        if (plan.warnings.length < MAX_LINE_ERRORS) plan.warnings.push({ line: line, code: 'inactive', value: value });
      }
    };

    // The parent and child of one record, or null (errors reported).
    var resolve = function (cells, line, out) {
      var pc = cell(cells[0]);
      var cc = cell(cells[1]);
      var bad = false;
      var parent = null;
      var child = null;
      var created = null;
      var found = candidates(parents, pc);
      if (found.length === 1) parent = found[0];
      else {
        bad = true;
        if (out) out.error(line, found.length ? 'ambiguous_parent' : 'unknown_parent', cells[0]);
      }
      found = candidates(children, cc);
      if (found.length === 1) child = found[0];
      else if (found.length > 1 || !addMissing) {
        bad = true;
        if (out) out.error(line, found.length ? 'ambiguous_child' : 'unknown_child', cells[1]);
      } else if (LINE_BREAK_RE.test(cc)) {
        bad = true;
        if (out) out.error(line, 'multiline_value', cells[1]);
      } else {
        // trimmed as core strips, NFC, lone surrogates as the form posts them
        var v = strip(cc).normalize('NFC');
        if (SURROGATE_RE.test(v)) v = wellFormed(v);
        var again = isBlank(v) || v.indexOf('\u0000') !== -1 ? null : candidates(children, v);
        if (isBlank(v)) {
          bad = true;
          if (out) out.error(line, 'blank_value');
        } else if (again === null) {
          // HTML turns a NUL into U+FFFD: the stored value would not stay the link key
          bad = true;
          if (out) out.error(line, 'nul_value', cells[1]);
        } else if (again.length === 1) {
          child = again[0];
        } else if (again.length > 1) {
          bad = true;
          if (out) out.error(line, 'ambiguous_child', cells[1]);
        } else {
          created = v;
        }
      }
      if (out && parent && !parent.active) out.inactive(line, cells[0]);
      if (out && child && !child.active) out.inactive(line, cells[1]);
      return bad ? null : { parent: parent, child: child, created: created };
    };

    var errors = parsed.errors;
    var errorCount = parsed.errorCount;
    var records = parsed.records;
    var first = parsed.first;
    // yes skips any first record but an unterminated quote (it holds the rest
    // of the input); auto never takes a quote error for a header, and 'both
    // unknown' needs two non-blank cells (a blank cell is blank_value).
    if (first && first.code !== 'unterminated_quote' &&
        (header === 'yes' || (header === 'auto' && first.code !== 'bad_quote'))) {
      var skip = header === 'yes';
      if (!skip && !(first.code === null && resolve(first.cells, first.line, null))) {
        var c0 = first.cells.length > 0 ? cell(first.cells[0]) : '';
        var c1 = first.cells.length > 1 ? cell(first.cells[1]) : '';
        var k0 = caseKey(c0);
        var k1 = caseKey(c1);
        skip = k0 === 'parent' || k1 === 'child' || (!!o.parentName && k0 === caseKey(o.parentName)) ||
          (!!o.childName && k1 === caseKey(o.childName)) ||
          (first.count >= 2 && !isBlank(c0) && !isBlank(c1) &&
            candidates(parents, c0).length === 0 && candidates(children, c1).length === 0);
      }
      if (skip) {
        plan.headerSkipped = true;
        plan.headerCells = first.cells.slice();
        plan.lines = parsed.lines - 1;
        if (first.code === null) {
          records = records.slice(1);
        } else {
          errors = errors.filter(function (e) { return !(e.line === first.errorLine && e.code === first.code); });
          errorCount--;
        }
      }
    }

    var newByKey = new Map();
    var pairSets = new Map();
    records.forEach(function (rec) {
      var r = resolve(rec.cells, rec.line, report);
      if (!r) return;
      var pk = r.parent.key;
      var ck;
      if (r.created === null) {
        ck = r.child.key;
      } else {
        var key = caseKey(r.created);
        ck = newByKey.get(key);
        if (ck === undefined) {
          ck = r.created;
          newByKey.set(key, ck);
          plan.newValues.push(ck);
        }
      }
      var set = pairSets.get(pk);
      if (!set) {
        set = new Set();
        pairSets.set(pk, set);
      }
      if (set.has(ck)) {
        plan.duplicates++;
        return;
      }
      set.add(ck);
      var existing = r.created === null && state.isLinked(pk, ck);
      plan.pairs.push({ line: rec.line, parent: pk, child: ck, parentLabel: r.parent.label,
                        childLabel: r.child ? r.child.label : ck, existing: existing });
      if (existing) plan.existing++;
      else plan.added++;
    });

    plan.errors = mergeErrors(errors, matchErrors, MAX_LINE_ERRORS);
    plan.errorCount = errorCount + matchCount;
    if (mode === 'replace') {
      state.links.forEach(function (set, pk) {
        if (!parents.byKey.has(pk)) return;
        var kept = pairSets.get(pk);
        set.forEach(function (ck) { if (children.byKey.has(ck) && !(kept && kept.has(ck))) plan.removed++; });
      });
    }
    if (plan.errorCount === 0) {
      var applied = applyImport(state.clone(), plan);
      var list = plan.newValues.length ? extended(children, plan.newValues) : children;
      var payloadOpts = { multiple: o.multiple === true, kind: o.kind };
      if (typeof o.base === 'string' && o.base !== '') payloadOpts.base = o.base;
      plan.estimatedPayloadBytes = utf8Bytes(stringify(serialize(applied, parents, list, payloadOpts)));
      plan.tooLarge = typeof o.maxPayloadBytes === 'number' && plan.estimatedPayloadBytes > o.maxPayloadBytes;
    }
    plan.ok = plan.errorCount === 0 && !plan.tooLarge &&
      (plan.pairs.length > 0 || (mode === 'replace' && parsed.lines > 0));
    return plan;
  }

  // Applies plan.pairs to +state+ (editor design 6.4): merge links them;
  // replace keeps only them (orphans go) and the defaults that stay linked.
  // Sets source import and importMeta {mode, rows: pairs}. Returns state.
  function applyImport(state, plan) {
    if (!(state instanceof State)) throw new TypeError('DcfDependencyEditorModel: state must be a State');
    if (!isObject(plan) || !Array.isArray(plan.pairs)) throw new TypeError('DcfDependencyEditorModel: plan has no pairs');
    var mode = plan.mode === 'replace' ? 'replace' : 'merge';
    var defaults = state.defaults;
    if (mode === 'replace') {
      state.links = new Map();
      state.defaults = new Map();
    }
    plan.pairs.forEach(function (pair) { state.link(pair.parent, pair.child, true); });
    if (mode === 'replace') defaults.forEach(function (keys, pk) { state.setDefaults(pk, keys); });
    state.source = 'import';
    state.importMeta = { mode: mode, rows: plan.pairs.length };
    return state;
  }

  // The links of +state+ on the current lists as CSV (editor design 6.7):
  // one BOM, a header of the field names, one row per link in parent then
  // child order with labels (orphans and defaults left out), CRLF after
  // every row. opts: separator (';', ',', TAB, else ','), parentName,
  // childName, protect (UD-18). parents null: the header only.
  function buildCsv(state, parents, children, opts) {
    if (!(state instanceof State)) throw new TypeError('DcfDependencyEditorModel: state must be a State');
    if (parents !== null && !(parents instanceof ValueList)) {
      throw new TypeError('DcfDependencyEditorModel: parents must be a ValueList or null');
    }
    if (!(children instanceof ValueList)) throw new TypeError('DcfDependencyEditorModel: children must be a ValueList');
    var o = opts || {};
    var sep = isSeparator(o.separator) ? o.separator : ',';
    var guard = o.protect === true ? protectCell : function (s) { return s; };
    var row = function (a, b) { return csvField(guard(a)) + sep + csvField(guard(b)); };
    var lines = [row(o.parentName ? String(o.parentName) : 'parent', o.childName ? String(o.childName) : 'child')];
    if (parents !== null) {
      parents.items.forEach(function (p) {
        var set = state.links.get(p.key);
        if (!set) return;
        var kept = [];
        set.forEach(function (ck) {
          var item = children.byKey.get(ck);
          if (item) kept.push(item);
        });
        kept.sort(byIndex).forEach(function (c) { lines.push(row(p.label, c.label)); });
      });
    }
    return '\ufeff' + lines.join('\r\n') + '\r\n';
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
    stringify: stringify,
    strip: strip,
    parseRecords: parseRecords,
    planImport: planImport,
    applyImport: applyImport,
    buildCsv: buildCsv
  };
}));
