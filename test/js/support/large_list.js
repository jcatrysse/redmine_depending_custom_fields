'use strict';
// JS twin of spec/support/dcf_large_list.rb (names, sizes, partition, full). ES2017.
const SYLLABLES = ('ba be bi bo bu ca ce ci co cu da de di do du fa fe fi fo fu ga ge gi go gu la le li lo lu ' +
  'ma me mi mo mu na ne ni no nu pa pe pi po pu ra re ri ro ru sa se si so su ta te ti to tu').split(' ');
const ACCENTS = { a: 'ã', e: 'é', i: 'í', o: 'ô', u: 'ú' };
const PREFIXES = ['', '', '', 'São ', 'Santa ', 'Nova ', 'Porto ', 'Rio '];
const TRICKY = ['yes', 'no', 'null', '1.0', 'a: b', '# hash', '- dash', "O'Brien", 'say "hi"',
  '[x]', 'a]', 'semi;colon', 'comma, value', 'tab\tin', 'Ünïcødé ñ'];
const BRAZIL_SIZES = [853, 645, 497, 417, 399, 295, 246, 224, 223, 217, 185, 184, 167, 144, 141, 139,
  102, 92, 79, 78, 75, 62, 52, 22, 16, 15, 1];
function stem(index, minSyllables) {
  const min = minSyllables === undefined ? 4 : minSyllables;
  const parts = []; let n = index;
  for (;;) { parts.push(SYLLABLES[n % 60]); n = Math.floor(n / 60); if (n === 0 && parts.length >= min) break; }
  return parts.join('');
}
function name(index, prefix) {
  let s = stem(index);
  if (index % 3 === 0) { const pos = s.search(/[aeiou]/); if (pos >= 0) s = s.slice(0, pos) + ACCENTS[s[pos]] + s.slice(pos + 1); }
  return (prefix || '') + PREFIXES[Math.floor(index / 3) % PREFIXES.length] + s.charAt(0).toUpperCase() + s.slice(1);
}
function names(count, opts) {
  const o = opts || {}; const offset = o.offset || 0; const every = o.trickyEvery || null; const seen = new Set(); const out = [];
  for (let k = 0; k < count; k++) {
    const i = offset + k;
    const v = every && k % every === 0 ? TRICKY[Math.floor(k / every) % TRICKY.length] + ' ' + i : name(i, o.prefix);
    if (seen.has(v)) throw new Error('duplicate fixture name ' + v);
    seen.add(v); out.push(v);
  }
  return out;
}
function sizes(total, parts) {
  if (total === 5570 && parts === 27) return BRAZIL_SIZES.slice();
  if (total < parts) throw new Error('total must be >= parts');
  const w = []; for (let k = 0; k < parts; k++) w.push(1.0 / (k + 1));
  let sum = 0.0; w.forEach((x) => { sum += x; });
  const out = w.map((x) => Math.max(1, Math.floor((total - parts) * x / sum) + 1));
  out[0] += total - out.reduce((a, b) => a + b, 0);
  return out;
}
function partition(parentKeys, childKeys, partSizes) {
  const ps = partSizes || sizes(childKeys.length, parentKeys.length); const m = {}; let off = 0;
  parentKeys.forEach((pk, k) => { m[String(pk)] = childKeys.slice(off, off + ps[k]).map(String); off += ps[k]; });
  return m;
}
module.exports = { names, name, sizes, partition, TRICKY };
