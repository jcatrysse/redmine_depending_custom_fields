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

    const FIELD_NAME_REGEX = /^([^[]+)\[custom_field_values\]\[(\d+)\](\[\])?/;

    const parseFieldName = (name) => {
        if (!name) return null;
        const match = name.match(FIELD_NAME_REGEX);
        if (!match) return null;
        return { prefix: match[1], fieldId: match[2] };
    };

    const isSelectElement = (element) => element && element.tagName === 'SELECT';

    const ensureElementId = (() => {
        let counter = 0;
        return (element) => {
            if (!element.id) {
                counter += 1;
                element.id = `depending_cf_${counter}`;
            }
            return element.id;
        };
    })();

    const getFieldInputs = (element) => {
        if (!element || isSelectElement(element)) return [];
        const fieldId = element.dataset.dependingFieldId;
        return Array.from(element.querySelectorAll('input[type="checkbox"], input[type="radio"]')).filter(input => {
            if (!fieldId) return true;
            const parsed = parseFieldName(input.name || '');
            return parsed && parsed.fieldId === fieldId;
        });
    };

    const extractPrefix = (element) => {
        if (!element) return null;
        if (isSelectElement(element)) {
            if (element.name) {
                const parsed = parseFieldName(element.name);
                if (parsed) return parsed.prefix;
            }
            if (element.id) return element.id.replace(/_custom_field_values_.*/, '');
            return null;
        }
        const input = element.querySelector('input[name]');
        if (!input) return null;
        const parsed = parseFieldName(input.name);
        return parsed ? parsed.prefix : null;
    };

    const findCheckboxGroup = (root, prefix, fieldId) => {
        if (!root || !root.querySelectorAll) return null;
        const spans = Array.from(root.querySelectorAll('span.check_box_group'));
        return spans.find(span => {
            return Array.from(span.querySelectorAll('input[name]')).some(input => {
                const parsed = parseFieldName(input.name);
                return parsed && parsed.prefix === prefix && parsed.fieldId === String(fieldId);
            });
        }) || null;
    };

    const findFieldElement = (root, prefix, fieldId) => {
        if (!prefix) return null;
        const baseId = `${prefix}_custom_field_values_${fieldId}`;
        const altId  = `${baseId}_`;

        const searchIn = (container) => {
            if (!container || !container.querySelector) return null;
            return container.querySelector(`#${baseId}, #${altId}`);
        };

        const candidate = searchIn(root) || document.getElementById(baseId) || document.getElementById(altId);
        if (candidate) {
            if (!root || root === document || (candidate.parentNode && root.contains(candidate))) {
                return candidate;
            }
        }

        const checkbox = findCheckboxGroup(root, prefix, fieldId) || findCheckboxGroup(document, prefix, fieldId);
        if (checkbox && (!root || root === document || root.contains(checkbox))) {
            return checkbox;
        }

        return candidate || checkbox;
    };

    const getContextRoot = (element) => {
        if (!element || !element.closest) return document;
        return element.closest('.cf-wizard, .cf-wizard-form, #context-menu, .bulk-edit, #bulk-edit-form, form') || document;
    };

    const getValues = (field) => {
        if (!field) return [];
        if (isSelectElement(field)) {
            if (field.multiple) {
                return Array.from(field.options)
                    .filter(o => o.selected)
                    .map(o => String(o.value));
            }
            return field.value === '' ? [] : [String(field.value)];
        }
        const inputs = getFieldInputs(field);
        const checked = inputs.filter(input => input.checked).map(input => String(input.value || ''));
        return checked;
    };

    const setValues = (field, values) => {
        if (!field) return;
        const strVals = Array.isArray(values) ? values.map(String) : [String(values)];
        if (isSelectElement(field)) {
            if (field.multiple) {
                Array.from(field.options).forEach(opt => {
                    opt.selected = strVals.includes(String(opt.value));
                });
            } else {
                field.value = strVals[0] || '';
            }
        } else {
            const inputs = getFieldInputs(field);
            const hasNone = strVals.includes(NONE_VALUE);
            inputs.forEach(input => {
                if (hasNone) {
                    input.checked = false;
                } else {
                    input.checked = strVals.includes(String(input.value || ''));
                }
            });
        }
    };

    const ensureHiddenContainer = (field) => {
        if (!field || !field.parentNode || !isSelectElement(field)) return null;
        let container = field.parentElement.querySelector(`span[data-hidden-for="${field.id}"]`);
        if (!container) {
            container = document.createElement('span');
            container.dataset.hiddenFor = field.id;
            container.style.display = 'none';
            field.parentNode.insertBefore(container, field.nextSibling);
        }
        return container;
    };

    const removeOldHiddenInputs = (field) => {
        if (!field || !isSelectElement(field) || !field.parentElement) return;
        Array.from(field.parentElement.querySelectorAll('input[type="hidden"]')).forEach(input => {
            if (input.name === field.name && !input.closest(`span[data-hidden-for="${field.id}"]`)) {
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

    const syncHiddenInputs = (field) => {
        if (!field || !isSelectElement(field) || !field.parentNode) return;
        removeOldHiddenInputs(field);
        const container = ensureHiddenContainer(field);
        container.innerHTML = '';
        const values = getValues(field);
        const isBulk = !!field.closest('.cf-wizard, .cf-wizard-form, #context-menu, .bulk-edit, #bulk-edit-form');
        const isInlineEdit = !!field.closest('#inline_edit_form');

        if (isBulk) {
            syncBulkInputs(field, values, container);
        } else if (isInlineEdit && values.length === 0) {
            syncInlineInputs(field, container);
        } else {
            syncRegularInputs(field, values, container);
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

    const updateOptionVisibility = (field, allowed, hasMapping) => {
        if (isSelectElement(field)) {
            Array.from(field.querySelectorAll('option')).forEach(opt => {
                const val       = String(opt.value);
                const isSpecial = val === NONE_VALUE;
                const disallowed = !hasMapping
                    ? val !== '' && !isSpecial
                    : !allowed.includes(val) && val !== '' && !isSpecial;
                opt.hidden        = disallowed;
                opt.style.display = disallowed ? 'none' : '';
            });
            return;
        }

        getFieldInputs(field).forEach(input => {
            const val       = String(input.value || '');
            const isSpecial = val === NONE_VALUE;
            const disallowed = !hasMapping
                ? val !== '' && !isSpecial
                : !allowed.includes(val) && val !== '' && !isSpecial;
            const label = input.closest('label');
            if (label) {
                label.style.display = disallowed ? 'none' : '';
            }
            input.dataset.dependingHiddenOption = disallowed ? '1' : '0';
            if (disallowed && input.checked) {
                input.checked = false;
            }
        });
    };

    const setParentVisibility = (childSelect, visible) => {
        const parent = childSelect.closest('p');
        if (!parent) return;
        parent.hidden = !visible;
    };

    const parseStoredCombos = (field) => {
        if (!field || !field.dataset) return { combos: {} };
        const raw = field.dataset.valueMap;
        if (!raw) return { combos: {} };
        try {
            const parsed = JSON.parse(raw);
            if (parsed && typeof parsed === 'object') {
                if (parsed.combos && typeof parsed.combos === 'object') {
                    return { combos: parsed.combos };
                }
                const combos = {};
                Object.keys(parsed).forEach(key => {
                    combos[key] = parsed[key];
                });
                return { combos };
            }
        } catch (e) {
            // ignore invalid state
        }
        return { combos: {} };
    };

    const storeCombos = (field, combos) => {
        if (!field || !field.dataset) return;
        field.dataset.valueMap = JSON.stringify({ combos });
    };

    const buildParentKey = (values) => {
        if (!values || values.length === 0) return '';
        return values.slice().sort().join('||');
    };

    const applyChildState = (parentValues, childSelect, allowed, hasMapping, defaults, hideParent) => {
        const isSelect = isSelectElement(childSelect);
        const isBulk = isSelect
            ? childSelect.querySelector(`option[value="${NONE_VALUE}"]`) !== null
            : !!childSelect.closest('.cf-wizard, .cf-wizard-form, #context-menu, .bulk-edit, #bulk-edit-form');
        const noChangeOption = isSelect ? childSelect.querySelector('option[value=""]') : null;
        const hasNone  = parentValues.includes(NONE_VALUE);
        const hasValue = parentValues.some(v => v !== '' && v !== NONE_VALUE);
        const hasAllowed = allowed.length > 0;

        let visible = true;
        if (hasNone) {
            if (isSelect) {
                childSelect.disabled = true;
                setValues(childSelect, [NONE_VALUE]);
            } else {
                getFieldInputs(childSelect).forEach(input => { input.disabled = true; });
                setValues(childSelect, []);
            }
            visible = false;
        } else if (!hasValue || !hasMapping || !hasAllowed) {
            if (isSelect) {
                childSelect.disabled = !isBulk;
            } else {
                getFieldInputs(childSelect).forEach(input => { input.disabled = !isBulk; });
            }
            visible = false;
            if (!isBulk) {
                setValues(childSelect, []);
            } else {
                const currentVals = getValues(childSelect).filter(v => allowed.includes(v) || v === NONE_VALUE);
                setValues(childSelect, currentVals);
            }
        } else {
            if (isSelect) {
                childSelect.disabled = false;
            } else {
                getFieldInputs(childSelect).forEach(input => { input.disabled = false; });
            }
            const currentVals = getValues(childSelect).filter(v => allowed.includes(v) || v === NONE_VALUE);
            setValues(childSelect, currentVals);
            visible = true;
        }

        if (isSelect && isBulk && hasValue && noChangeOption) {
            noChangeOption.hidden       = true;
            noChangeOption.style.display = 'none';
            if (getValues(childSelect).length === 0) {
                setValues(childSelect, [NONE_VALUE]);
            }
        } else if (isSelect && noChangeOption) {
            noChangeOption.hidden       = false;
            noChangeOption.style.display = '';
        }

        if (hideParent) {
            setParentVisibility(childSelect, visible);
        } else {
            setParentVisibility(childSelect, true);
        }

        const isDisabled = isSelect ? childSelect.disabled : getFieldInputs(childSelect).every(input => input.disabled);
        if (!isDisabled && hasValue) {
            const { combos } = parseStoredCombos(childSelect);
            const uniqueParents = Array.from(new Set(parentValues.filter(v => v !== '' && v !== NONE_VALUE)));
            const parentKey = buildParentKey(uniqueParents);
            const previousKey = childSelect.dataset.lastParentKey || '';
            const previousParents = previousKey ? previousKey.split('||').filter(Boolean) : [];
            const canCarryExisting = previousParents.length > 0 && previousParents.every(p => uniqueParents.includes(p));
            const initialRun = childSelect.dataset.initialized !== 'true';

            const collectValues = (source) => {
                if (!source) return [];
                const raw = Array.isArray(source) ? source : [source];
                return raw.map(String).filter(v => allowed.includes(v));
            };

            const hasStoredCombo = parentKey !== '' && Object.prototype.hasOwnProperty.call(combos, parentKey);
            const storedValues = hasStoredCombo ? collectValues(combos[parentKey]) : [];
            const currentSelection = getValues(childSelect).filter(v => v !== NONE_VALUE && allowed.includes(v));
            const canReuseExisting = initialRun || canCarryExisting;

            if (hasStoredCombo) {
                setValues(childSelect, storedValues);
            } else {
                const baseValues = canReuseExisting ? currentSelection.slice() : [];
                const nextValues = baseValues.slice();
                const addedParents = uniqueParents.filter(v => !previousParents.includes(v));
                const shouldApplyDefaults = () => {
                    if (initialRun && currentSelection.length > 0) return false;
                    if (nextValues.length === 0) return true;
                    return addedParents.length > 0;
                };

                if (shouldApplyDefaults()) {
                    const defaultValues = uniqueParents
                        .filter(v => Object.prototype.hasOwnProperty.call(defaults, v))
                        .reduce((acc, parent) => {
                            collectValues(defaults[parent]).forEach(val => {
                                if (!acc.includes(val)) acc.push(val);
                            });
                            return acc;
                        }, []);

                    defaultValues.forEach(val => {
                        if (!nextValues.includes(val)) nextValues.push(val);
                    });
                }

                setValues(childSelect, nextValues);
            }

            const storedSelection = getValues(childSelect).filter(v => v !== NONE_VALUE && allowed.includes(v));
            if (parentKey) {
                combos[parentKey] = storedSelection;
            }
            storeCombos(childSelect, combos);
            childSelect.dataset.lastParentKey = parentKey;
            childSelect.dataset.initialized = 'true';
        }
    };

    const updateChild = (parentSelect, childSelect, mapping, defaults = {}, hideParentSetting = false) => {
        const parentValues = getValues(parentSelect);
        const { allowed, hasMapping } = calculateAllowed(parentValues, mapping);
        const hideParent = hideParentSetting === true || hideParentSetting === '1' || hideParentSetting === 1;
        updateOptionVisibility(childSelect, allowed, hasMapping);
        applyChildState(parentValues, childSelect, allowed, hasMapping, defaults, hideParent);
        syncHiddenInputs(childSelect);
        if (isSelectElement(childSelect)) {
            childSelect.dispatchEvent(new Event('change', { bubbles: true }));
        } else {
            const inputs = getFieldInputs(childSelect);
            if (inputs.length > 0) {
                inputs[0].dispatchEvent(new Event('change', { bubbles: true }));
            }
        }
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
            const cidStr = String(cid);
            const selectMatches = Array.from(root.querySelectorAll(
                `[id$="_custom_field_values_${cid}"], [id$="_custom_field_values_${cid}_"]`
            ));
            const checkboxMatches = Array.from(root.querySelectorAll('span.check_box_group')).filter(span => {
                return Array.from(span.querySelectorAll('input[name]')).some(input => {
                    const parsed = parseFieldName(input.name);
                    return parsed && parsed.fieldId === cidStr;
                });
            });
            const childElements = Array.from(new Set([...selectMatches, ...checkboxMatches]));

            childElements.forEach(childElement => {
                const inMenu = childElement.closest('#context-menu');
                if (inMenu && !childElement.closest('.cf-wizard')) {
                    const li = childElement.closest('li');
                    if (li) li.style.display = 'none';
                    return;
                }
                if (childElement.dataset.dependingInitialized) return;

                const prefix = extractPrefix(childElement);
                if (!prefix) return;
                childElement.dataset.dependingFieldId = cidStr;
                childElement.dataset.dependingPrefix = prefix;

                const contextRoot = getContextRoot(childElement);
                const parentSelect = findFieldElement(contextRoot, prefix, info.parent_id);
                if (!parentSelect) return;

                const parentPrefix = extractPrefix(parentSelect) || prefix;
                parentSelect.dataset.dependingFieldId = parentSelect.dataset.dependingFieldId || String(info.parent_id);
                parentSelect.dataset.dependingPrefix = parentSelect.dataset.dependingPrefix || parentPrefix;
                const parentIdAttr = ensureElementId(parentSelect);
                const parentKey = parentSelect.dataset.dependingKey || `${parentPrefix}:${parentSelect.dataset.dependingFieldId}:${parentIdAttr}`;
                parentSelect.dataset.dependingKey = parentKey;
                childElement.dataset.dependingParentKey = parentKey;

                syncHiddenInputs(childElement);
                childElement.classList.add('depending-child');
                childElement.dataset.dependingInitialized = '1';

                if (!childElement.dataset.changeListener) {
                    childElement.addEventListener('change', () => syncHiddenInputs(childElement));
                    childElement.dataset.changeListener = '1';
                }

                const key = 'dependingChildKeys';
                const entry = `${prefix}|${cidStr}`;
                const stored = (parentSelect.dataset[key] || '').split(',').filter(Boolean);
                if (!stored.includes(entry)) {
                    stored.push(entry);
                    parentSelect.dataset[key] = stored.join(',');
                }

                if (!parentSelect.dataset.dependingChangeListener) {
                    parentSelect.addEventListener('change', () => {
                        const allEntries = (parentSelect.dataset[key] || '').split(',').filter(Boolean);
                        const searchRoot = getContextRoot(parentSelect);
                        allEntries.forEach(item => {
                            const [childPrefix, childId] = item.split('|');
                            if (!childPrefix || !childId) return;
                            const child = findFieldElement(searchRoot, childPrefix, childId) || findFieldElement(document, childPrefix, childId);
                            const childInfo = mapping[childId] || {};
                            if (child) updateChild(parentSelect, child, childInfo.map || {}, childInfo.defaults || {}, childInfo.hide_when_disabled);
                        });
                    });
                    parentSelect.dataset.dependingChangeListener = '1';
                }

                updateChild(parentSelect, childElement, info.map || {}, info.defaults || {}, info.hide_when_disabled);
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
