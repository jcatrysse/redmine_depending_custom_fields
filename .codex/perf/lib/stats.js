'use strict';
function sorted(a) { return a.filter((x) => typeof x === 'number' && !Number.isNaN(x)).sort((x, y) => x - y); }
function median(a) {
  const s = sorted(a); if (!s.length) return null;
  const m = s.length >> 1;
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}
// nearest-rank percentile
function pct(a, p) {
  const s = sorted(a); if (!s.length) return null;
  return s[Math.min(s.length - 1, Math.max(0, Math.ceil((p / 100) * s.length) - 1))];
}
function min(a) { const s = sorted(a); return s.length ? s[0] : null; }
function max(a) { const s = sorted(a); return s.length ? s[s.length - 1] : null; }
function summarize(a) { return { n: sorted(a).length, median: median(a), p90: pct(a, 90), min: min(a), max: max(a) }; }
module.exports = { median, pct, min, max, summarize };
