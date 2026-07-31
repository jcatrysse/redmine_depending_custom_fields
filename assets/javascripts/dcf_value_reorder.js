/* globals window */
/*
 * Drag-and-drop ordering for the project custom field configuration values
 * table. A `.sort-handle` per row drives a jQuery UI sortable, as in core.
 *
 * Core has two reorder models and this screen uses both, one per value family:
 *
 * - Enumeration table — core's `custom_field_enumerations#index` model: the
 *   whole table is one form and the drag only rewrites the hidden `position`
 *   inputs (`input.dcf-position`). Nothing is submitted; the single Save commits
 *   names, positions and active flags together. Detected by the presence of
 *   those inputs.
 * - List table — core's `positionedItems` / `reorder_handle` model: a drop is
 *   persisted immediately. Here it submits the resulting order through the
 *   separate reorder form, so the server contract stays a full permutation plus
 *   state_hash, one drag being one operation and one audit event.
 */
(function ($) {
    'use strict';

    if (!$ || !$.fn || !$.fn.sortable) return;

    const TABLE_SELECTOR = 'table.dcf-values';
    const FORM_SELECTOR = 'form.dcf-reorder-form';
    const HANDLE_SELECTOR = '.dcf-sort-handle';
    const POSITION_SELECTOR = 'input.dcf-position';
    const ORDERED_INPUT_CLASS = 'dcf-ordered-value';

    const orderedIds = ($rows) => $rows.map(function () {
        return $(this).attr('data-dcf-value');
    }).get();

    const submitOrder = ($form, $body, ids) => {
        $form.find('input.' + ORDERED_INPUT_CLASS).remove();
        ids.forEach(id => {
            $('<input>', {
                type: 'hidden',
                name: 'ordered_values[]',
                class: ORDERED_INPUT_CLASS
            }).val(id).appendTo($form);
        });
        // Lock the table for the round trip: one drag is one operation.
        $body.sortable('disable');
        $body.find(HANDLE_SELECTOR).addClass('ajax-loading');
        $body.find('input[type="submit"], button').prop('disabled', true);
        $form.get(0).submit();
    };

    // Core's custom_field_enumerations#index: rewrite the hidden position inputs
    // so the pending order travels with the form's single Save.
    const stagePositions = ($body) => {
        $body.children('tr').each(function (index) {
            $(this).find(POSITION_SELECTOR).val(index + 1);
        });
    };

    $(function () {
        const $table = $(TABLE_SELECTOR).first();
        if (!$table.length) return;

        const $body = $table.children('tbody');
        if ($body.children('tr').length < 2) return;

        const staged = $table.find(POSITION_SELECTOR).length > 0;
        const $form = $(FORM_SELECTOR).first();
        if (!staged && !$form.length) return;

        $table.addClass('dcf-values-sortable');

        $body.sortable({
            axis: 'y',
            handle: HANDLE_SELECTOR,
            // Freeze the cell widths of the dragged row so the table layout
            // does not collapse mid-drag (same trick as core positionedItems).
            helper: function (event, ui) {
                ui.children('td').each(function () {
                    $(this).width($(this).width());
                });
                return ui;
            },
            update: function () {
                if (staged) {
                    stagePositions($body);
                    return;
                }
                const ids = orderedIds($body.children('tr'));
                // A row without an identifier would produce an incomplete
                // permutation and a 422; bail out rather than submit it.
                if (ids.some(id => typeof id !== 'string')) {
                    $body.sortable('cancel');
                    return;
                }
                submitOrder($form, $body, ids);
            }
        });
    });
}(window.jQuery));
