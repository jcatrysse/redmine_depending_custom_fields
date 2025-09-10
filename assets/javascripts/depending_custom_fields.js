/* globals window, document, MutationObserver, jQuery */
(function () {
    const NONE_VALUE = '__none__';

    function collectRelevantFieldIds(mapping) {
        const ids = new Set();
        Object.keys(mapping).forEach(childId => {
            ids.add(String(childId));
            const info = mapping[childId];
            if (info && info.parent_id != null) ids.add(String(info.parent_id));
        });
        return ids;
    }

    const getValues = (select) => {
        if (select.multiple) {
            return Array.from(select.options)
                .filter(o => o.selected)
                .map(o => String(o.value));
        }
        return select.value === '' ? [] : [String(select.value)];
    };

    const setValues = (select, values) => {
        const strVals = Array.isArray(values) ? values.map(String) : [String(values)];
        if (select.multiple) {
            Array.from(select.options).forEach(opt => {
                opt.selected = strVals.includes(String(opt.value));
            });
        } else {
            select.value = strVals[0] || '';
        }
    };

    const ensureHiddenContainer = (select) => {
        if (!select.parentNode) return;
        let container = select.parentElement.querySelector(`span[data-hidden-for="${select.id}"]`);
        if (!container) {
            container = document.createElement('span');
            container.dataset.hiddenFor = select.id;
            container.style.display = 'none';
            select.parentNode.insertBefore(container, select.nextSibling);
        }
        return container;
    };

    const removeOldHiddenInputs = (select) => {
        Array.from(select.parentElement.querySelectorAll('input[type="hidden"]')).forEach(input => {
            if (input.name === select.name && !input.closest(`span[data-hidden-for="${select.id}"]`)) {
                input.remove();
            }
        });
    };

    const appendHidden = (container, name, value) => {
        const input = document.createElement('input');
        input.type = 'hidden';
        input.name = name;
        input.value = value;
        container.appendChild(input);
    };

    const syncBulkInputs = (select, values, container) => {
        if (!select.multiple && values.length === 1 && values[0] === '') return;
        if (select.multiple && values.length === 1 && values[0] === NONE_VALUE) {
            appendHidden(container, select.name.replace(/\[\]$/, ''), NONE_VALUE);
            return;
        }
        values.forEach(v => {
            if (v !== '') appendHidden(container, select.name, v);
        });
    };

    const syncInlineInputs = (select, container) => {
        appendHidden(container, select.name.replace(/\[\]$/, ''), '');
    };

    const syncRegularInputs = (select, values, container) => {
        if (values.length === 0) {
            appendHidden(container, select.name, '');
        } else {
            values.forEach(v => appendHidden(container, select.name, v));
        }
    };

    const syncHiddenInputs = (select) => {
        if (!select.parentNode) return;
        removeOldHiddenInputs(select);
        const container = ensureHiddenContainer(select);
        container.innerHTML = '';
        const values = getValues(select);
        const isBulk = !!select.closest('.cf-wizard, .cf-wizard-form, #context-menu, .bulk-edit, #bulk-edit-form');
        const isInlineEdit = !!select.closest('#inline_edit_form');

        if (isBulk) {
            syncBulkInputs(select, values, container);
        } else if (isInlineEdit && values.length === 0) {
            syncInlineInputs(select, container);
        } else {
            syncRegularInputs(select, values, container);
        }
    };

    const calculateAllowed = (parentValues, mapping) => {
        const hasMapping = parentValues.some(v => Object.prototype.hasOwnProperty.call(mapping, v));
        let allowed = [];
        parentValues.forEach(v => {
            if (Object.prototype.hasOwnProperty.call(mapping, v) && Array.isArray(mapping[v])) {
                allowed = allowed.concat(mapping[v].map(String));
            }
        });
        allowed = Array.from(new Set(allowed));
        return { allowed, hasMapping };
    };

    const updateOptionVisibility = (childSelect, allowed, hasMapping) => {
        Array.from(childSelect.querySelectorAll('option')).forEach(opt => {
            const val       = String(opt.value);
            const isSpecial = val === NONE_VALUE;
            const disallowed = !hasMapping
                ? val !== '' && !isSpecial
                : !allowed.includes(val) && val !== '' && !isSpecial;
            opt.hidden       = disallowed;
            opt.style.display = disallowed ? 'none' : '';
        });
    };

    const setParentVisibility = (childSelect, visible) => {
        const parent = childSelect.closest('p');
        if (!parent) return;
        parent.hidden = !visible;
    };

    const applyChildState = (parentValues, childSelect, allowed, hasMapping, defaults, hideParent) => {
        const isBulk        = childSelect.querySelector(`option[value="${NONE_VALUE}"]`) !== null;
        const noChangeOption = childSelect.querySelector('option[value=""]');
        const hasNone  = parentValues.includes(NONE_VALUE);
        const hasValue = parentValues.some(v => v !== '' && v !== NONE_VALUE);
        const hasAllowed = allowed.length > 0;

        let visible = true;
        if (hasNone) {
            childSelect.disabled = true;
            setValues(childSelect, [NONE_VALUE]);
            visible = false;
        } else if (!hasValue || !hasMapping || !hasAllowed) {
            childSelect.disabled = !isBulk;
            visible = false;
            if (!isBulk) {
                setValues(childSelect, []);
            } else {
                const currentVals = getValues(childSelect).filter(v => allowed.includes(v) || v === NONE_VALUE);
                setValues(childSelect, currentVals);
            }
        } else {
            childSelect.disabled = false;
            const currentVals = getValues(childSelect).filter(v => allowed.includes(v) || v === NONE_VALUE);
            setValues(childSelect, currentVals);
            visible = true;
        }

        if (isBulk && hasValue && noChangeOption) {
            noChangeOption.hidden       = true;
            noChangeOption.style.display = 'none';
            if (getValues(childSelect).length === 0) {
                setValues(childSelect, [NONE_VALUE]);
            }
        } else if (noChangeOption) {
            noChangeOption.hidden       = false;
            noChangeOption.style.display = '';
        }

        if (hideParent) {
            setParentVisibility(childSelect, visible);
        } else {
            setParentVisibility(childSelect, true);
        }

        if (!childSelect.disabled && hasValue) {
            const valueMap = childSelect.dataset.valueMap ? JSON.parse(childSelect.dataset.valueMap) : {};
            const parentWithStored = parentValues.find(v => Object.prototype.hasOwnProperty.call(valueMap, v));
            if (parentWithStored !== undefined) {
                const storedRaw = valueMap[parentWithStored];
                const stored = Array.isArray(storedRaw) ? storedRaw.map(String) : [String(storedRaw)];
                const validStored = stored.filter(v => allowed.includes(v));
                setValues(childSelect, validStored);
            } else {
                const parentWithDefault = parentValues.find(v => Object.prototype.hasOwnProperty.call(defaults, v));
                const defRaw = parentWithDefault ? defaults[parentWithDefault] : null;
                let defVals = [];
                if (Array.isArray(defRaw)) {
                    defVals = defRaw.map(String);
                } else if (defRaw) {
                    defVals = [String(defRaw)];
                }
                const validDefaults = defVals.filter(v => allowed.includes(v));
                const existing = getValues(childSelect).filter(v => v !== NONE_VALUE);
                if (validDefaults.length > 0 && existing.length === 0) {
                    setValues(childSelect, validDefaults);
                }
            }
            parentValues.forEach(pv => {
                valueMap[pv] = getValues(childSelect);
            });
            childSelect.dataset.valueMap = JSON.stringify(valueMap);
        }
    };

    const updateChild = (parentSelect, childSelect, mapping, defaults = {}, hideParentSetting = false) => {
        const parentValues = getValues(parentSelect);
        const { allowed, hasMapping } = calculateAllowed(parentValues, mapping);
        const hideParent = hideParentSetting === true || hideParentSetting === '1' || hideParentSetting === 1;
        updateOptionVisibility(childSelect, allowed, hasMapping);
        applyChildState(parentValues, childSelect, allowed, hasMapping, defaults, hideParent);
        syncHiddenInputs(childSelect);
        childSelect.dispatchEvent(new Event('change', { bubbles: true }));
    };

    const setup = (root = document) => {
        const rawData = window.DependingCustomFieldData;
        let mapping   = null;
        if (rawData && typeof rawData === 'object') {
            mapping = typeof rawData.mapping === 'object' ? rawData.mapping : rawData;
        }
        if (!mapping || typeof mapping !== 'object') {
            return;
        }

        const relevantFieldIds = collectRelevantFieldIds(mapping);

        Object.keys(mapping).forEach(cid => {
            const info = mapping[cid];
            const childSelects = root.querySelectorAll(
                `[id$="_custom_field_values_${cid}"], [id$="_custom_field_values_${cid}_"]`
            );
            childSelects.forEach(childSelect => {
                const inMenu = childSelect.closest('#context-menu');
                if (inMenu && !childSelect.closest('.cf-wizard')) {
                    const li = childSelect.closest('li');
                    if (li) li.style.display = 'none';
                    return;
                }
                if (childSelect.dataset.dependingInitialized) return;

                const prefix = childSelect.id.replace(/_custom_field_values_.*/, '');
                const parentSelect =
                    document.getElementById(`${prefix}_custom_field_values_${info.parent_id}`) ||
                    document.getElementById(`${prefix}_custom_field_values_${info.parent_id}_`);
                if (!parentSelect) return;

                syncHiddenInputs(childSelect);
                childSelect.classList.add('depending-child');
                childSelect.dataset.dependingInitialized = '1';

                if (!childSelect.dataset.changeListener) {
                    childSelect.addEventListener('change', () => syncHiddenInputs(childSelect));
                    childSelect.dataset.changeListener = '1';
                }

                const key    = 'dependingChildIds';
                const cidStr = String(cid);
                const ids    = (parentSelect.dataset[key] || '').split(',').filter(Boolean);
                if (!ids.includes(cidStr)) {
                    ids.push(cidStr);
                    parentSelect.dataset[key] = ids.join(',');
                }

                if (!parentSelect.dataset.dependingChangeListener) {
                    parentSelect.addEventListener('change', () => {
                        const allIds  = (parentSelect.dataset[key] || '').split(',').filter(Boolean);
                        const base    = parentSelect.id.replace(/_custom_field_values_.*/, '');
                        allIds.forEach(id => {
                            const child =
                                document.getElementById(`${base}_custom_field_values_${id}`) ||
                                document.getElementById(`${base}_custom_field_values_${id}_`);
                            const childInfo = mapping[id] || {};
                            if (child) updateChild(parentSelect, child, childInfo.map || {}, childInfo.defaults || {}, childInfo.hide_when_disabled);
                        });
                    });
                    parentSelect.dataset.dependingChangeListener = '1';
                }

                updateChild(parentSelect, childSelect, info.map || {}, info.defaults || {}, info.hide_when_disabled);
            });
        });

        root.querySelectorAll('select[data-field-id]').forEach(sel => {
            if (relevantFieldIds.has(String(sel.dataset.fieldId))) {
                syncHiddenInputs(sel);
                if (!sel.dataset.syncHiddenInputListener) {
                    sel.addEventListener('change', () => syncHiddenInputs(sel));
                    sel.dataset.syncHiddenInputListener = '1';
                }
            }
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
            requestSetup(menu);
        }
    };

    observeContextMenu();
    if (window.MutationObserver && document.body) {
        const bodyObserver = new MutationObserver(observeContextMenu);
        bodyObserver.observe(document.body, { childList: true });
    }

    window.DependingCustomFields = { requestSetup, setup };
})();
