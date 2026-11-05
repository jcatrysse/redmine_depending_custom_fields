module RedmineDependingCustomFields
  # Operation D: reorder possible values / enumeration positions. The submitted
  # set must be an exact permutation of the current set. No CustomValue rewrite
  # or cascade (identity is unchanged). See Operations Spec §D. The audit row
  # carries the SHA-256 of the old and the new order (WP-29, additive).
  class ReorderValuesService < BaseService
    def audit_action
      'reorder_values'
    end

    private

    def perform!
      submitted = Array(@params[:ordered_values]).map(&:to_s)

      if list_family?
        current = possible_values.map(&:to_s)
        # Full review of 2026-11-05 (project-pages-5): the page lists a value
        # stored twice once (DependencyRules.value_options), so the order is
        # a permutation of the distinct values; the save drops the repeat.
        validate_permutation!(submitted, current.uniq)
        field.possible_values = submitted
        save_field!(field)
      else
        enums = field.enumerations.to_a
        current = enums.sort_by { |e| [e.position.to_i, e.id] }.map { |e| e.id.to_s }
        validate_permutation!(submitted, current)
        by_id = enums.index_by { |e| e.id.to_s }
        submitted.each_with_index do |id, idx|
          by_id.fetch(id).update!(position: idx + 1)
        end
      end

      Outcome.new(before: { order_sha256: SortValuesService.order_sha256(current) },
                  after: { order: submitted.first(20), truncated: submitted.length > 20,
                           order_sha256: SortValuesService.order_sha256(submitted) },
                  summary: 'Reordered values')
    end

    def validate_permutation!(submitted, current)
      mismatch = submitted.length != current.length ||
                 submitted.uniq.length != submitted.length ||
                 submitted.sort != current.sort
      raise OperationError.new(:error_reorder_mismatch) if mismatch
    end
  end
end
