'use strict';
// The entry list a form submission carries (HTML "constructing the entry
// list"): disabled controls, controls in a disabled fieldset, selected
// disabled options, unchecked radios and check boxes, buttons and nameless
// controls are skipped; hidden inputs are kept. jsdom 29 FormData wrongly
// keeps a selected disabled option, so it is never used here.
const SKIPPED_TYPES = new Set(['submit', 'button', 'reset', 'image', 'file']);

function disabledByFieldset(el) {
  for (let fs = el.closest('fieldset[disabled]'); fs; fs = fs.parentElement && fs.parentElement.closest('fieldset[disabled]')) {
    const legend = Array.from(fs.children).find((c) => c.tagName === 'LEGEND');
    if (!(legend && legend.contains(el))) return true;
  }
  return false;
}

// [[name, value], ...] in tree order.
function entries(form) {
  const out = [];
  Array.from(form.elements).forEach((el) => {
    if (!el.name || el.disabled || disabledByFieldset(el)) return;
    const tag = el.tagName;
    if (tag === 'BUTTON' || tag === 'FIELDSET' || tag === 'OBJECT' || tag === 'OUTPUT') return;
    if (tag === 'SELECT') {
      Array.from(el.options).forEach((o) => {
        const group = o.parentElement && o.parentElement.tagName === 'OPTGROUP' ? o.parentElement : null;
        if (o.selected && !o.disabled && !(group && group.disabled)) out.push([el.name, o.value]);
      });
      return;
    }
    if (tag === 'INPUT') {
      if (SKIPPED_TYPES.has(el.type)) return;
      if (el.type === 'checkbox' || el.type === 'radio') {
        if (el.checked) out.push([el.name, el.value]);
        return;
      }
    }
    out.push([el.name, el.value]);
  });
  return out;
}

// "name=value" strings, optionally only names starting with keyPrefix.
function list(form, keyPrefix) {
  return entries(form).filter(([k]) => !keyPrefix || k.startsWith(keyPrefix)).map(([k, v]) => `${k}=${v}`);
}

// Decoded pairs of jQuery's $(form).serialize() ('+' is a space).
function serialized(window, form) {
  return Array.from(new window.URLSearchParams(window.jQuery(form).serialize()).entries());
}

module.exports = { entries, list, serialized };
