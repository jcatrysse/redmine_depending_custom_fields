'use strict';
// User-like changes. choose(): sets the selection of a select (or the checked
// inputs of a radio or check box group, given the group or one of its inputs)
// and dispatches a bubbling native change, on the select or on the input that
// changed. jq(): the same selection through jQuery .val() and
// .trigger('change') (select2 style), which never reaches native listeners.
const choicesOf = (el) => {
  const group = el.tagName === 'INPUT' ? (el.closest('.check_box_group') || el.parentNode) : el;
  return Array.from(group.querySelectorAll('input')).filter((i) => i.type === 'radio' || i.type === 'checkbox');
};

function setSelection(el, value) {
  const vals = [].concat(value).map(String);
  if (el.tagName === 'SELECT') {
    if (el.multiple) Array.from(el.options).forEach((o) => { o.selected = vals.includes(o.value); });
    else el.value = vals.length ? vals[0] : '';
    return el;
  }
  const inputs = choicesOf(el);
  let changed = null;
  inputs.forEach((i) => {
    const c = vals.includes(i.value);
    if (i.checked !== c) {
      i.checked = c;
      if (c || !changed) changed = i;
    }
  });
  return changed || inputs[0];
}

function choose(window, el, value) {
  const target = setSelection(el, value);
  target.dispatchEvent(new window.Event('change', { bubbles: true }));
  return target;
}

// A bubbling native change without changing anything.
function change(window, el) {
  el.dispatchEvent(new window.Event('change', { bubbles: true }));
}

function jq(window, el, value) {
  const $ = window.jQuery;
  if (el.tagName === 'SELECT') {
    $(el).val(el.multiple ? [].concat(value) : value).trigger('change');
    return el;
  }
  const target = setSelection(el, value);
  $(target).trigger('change');
  return target;
}

module.exports = { choose, change, jq, setSelection };
