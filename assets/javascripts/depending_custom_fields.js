(function () {
  const NONE_VALUE = '__none__';

  const updateChild = (parentSelect, childSelect, mapping, hiddenInput) => {
    const parentValue = String(parentSelect.value);
    const hasMapping = Object.prototype.hasOwnProperty.call(mapping, parentValue);
    const allowed = hasMapping && Array.isArray(mapping[parentValue])
      ? mapping[parentValue].map(String)
      : [];

    const isBulk = childSelect.querySelector(`option[value="${NONE_VALUE}"]`) !== null;
    const noChangeOption = childSelect.querySelector('option[value=""]');

    Array.from(childSelect.querySelectorAll('option')).forEach(opt => {
      const val = String(opt.value);
      const isSpecial = val === NONE_VALUE;
      const disallowed = !hasMapping
        ? val !== '' && !isSpecial
        : !allowed.includes(val) && val !== '' && !isSpecial;
      opt.hidden = disallowed;
      opt.style.display = disallowed ? 'none' : '';
    });

    if (parentValue === NONE_VALUE) {
      childSelect.disabled = true;
      childSelect.value = NONE_VALUE;
    } else if (!parentValue || !hasMapping) {
      childSelect.disabled = !isBulk;
      if (!isBulk) {
        childSelect.value = '';
      } else if (!allowed.includes(String(childSelect.value)) && childSelect.value !== NONE_VALUE) {
        childSelect.value = '';
      }
    } else {
      childSelect.disabled = false;
      if (!allowed.includes(String(childSelect.value)) && childSelect.value !== NONE_VALUE) {
        childSelect.value = '';
      }
    }

    if (parentValue && parentValue !== NONE_VALUE && noChangeOption) {
      noChangeOption.hidden = true;
      noChangeOption.style.display = 'none';
      if (childSelect.value === '') {
        childSelect.value = NONE_VALUE;
      }
    } else if (noChangeOption) {
      noChangeOption.hidden = false;
      noChangeOption.style.display = '';
    }

    if (hiddenInput) hiddenInput.value = childSelect.value;

    childSelect.dispatchEvent(new Event('change', { bubbles: true }));
  };

  const setup = (root = document) => {
    const data = window.DependingCustomFieldData || {};
    Object.keys(data).forEach(cid => {
      const info = data[cid];
      const childSelects = root.querySelectorAll(`[id$="_custom_field_values_${cid}"]`);
      childSelects.forEach(childSelect => {
        if (childSelect.dataset.dependingInitialized) return;
        const prefix = childSelect.id.replace(/_custom_field_values_.*/, '');
        const parentSelect = document.getElementById(`${prefix}_custom_field_values_${info.parent_id}`);
        if (!parentSelect) return;

        let hiddenInput = childSelect.parentElement.querySelector(`input[type="hidden"][name="${childSelect.name}"]`);
        if (!hiddenInput) {
          hiddenInput = document.createElement('input');
          hiddenInput.type = 'hidden';
          hiddenInput.name = childSelect.name;
          childSelect.parentNode.insertBefore(hiddenInput, childSelect.nextSibling);
        }

        hiddenInput.value = childSelect.value;
        childSelect.classList.add('depending-child');
        childSelect.dataset.dependingInitialized = '1';
        childSelect.addEventListener('change', () => {
          hiddenInput.value = childSelect.value;
        });
        parentSelect.addEventListener('change', () => {
          updateChild(parentSelect, childSelect, info.map || {}, hiddenInput);
        });
        updateChild(parentSelect, childSelect, info.map || {}, hiddenInput);
      });
    });
  };

  let debounceTimeout;
  const requestSetup = (root = document) => {
    clearTimeout(debounceTimeout);
    debounceTimeout = setTimeout(() => setup(root), 100);
  };

  document.addEventListener('DOMContentLoaded', () => setup());
  if (window.jQuery) {
    jQuery(document).ajaxComplete(() => requestSetup(document));
  }

  const observeContextMenu = () => {
    const menu = document.getElementById('context-menu');
    if (menu && !menu.dataset.dependingObserver) {
      const observer = new MutationObserver(() => requestSetup(menu));
      observer.observe(menu, { childList: true, subtree: true });
      menu.dataset.dependingObserver = '1';
    }
  };

  observeContextMenu();
  if (window.MutationObserver) {
    const bodyObserver = new MutationObserver(observeContextMenu);
    bodyObserver.observe(document.body, { childList: true });
  }
})();
