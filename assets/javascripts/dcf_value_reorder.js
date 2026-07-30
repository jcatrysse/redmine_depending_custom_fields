/* globals window */
/*
 * Drag-and-drop ordering for the project custom field configuration values
 * table, mirroring Redmine core (`table.enumerations tbody` +
 * `positionedItems`, `custom_field_enumerations#index`): a `.sort-handle` per
 * row drives a jQuery UI sortable.
 *
 * Dropping a row submits the resulting order through the regular reorder form,
 * so the server contract is unchanged (full permutation + state_hash + audit)
 * and the up/down buttons remain the no-JS fallback.
 */
(function ($) {
    'use strict';

    if (!$ || !$.fn || !$.fn.sortable) return;

    const TABLE_SELECTOR = 'table.dcf-values';
    const FORM_SELECTOR = 'form.dcf-reorder-form';
    const HANDLE_SELECTOR = '.dcf-sort-handle';
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

    $(function () {
        const $table = $(TABLE_SELECTOR).first();
        const $form = $(FORM_SELECTOR).first();
        if (!$table.length || !$form.length) return;

        const $body = $table.children('tbody');
        if ($body.children('tr').length < 2) return;

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
