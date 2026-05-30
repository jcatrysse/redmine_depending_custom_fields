module RedmineDependingCustomFields
  # Operation D — reorder possible values / enumeration positions. The submitted
  # set must be an exact permutation of the current set. No CustomValue rewrite
  # or cascade (identity is unchanged). See Operations Spec §D.
  class ReorderValuesService < BaseService
    def audit_action
      'reorder_values'
    end

    private

    def perform!
      submitted = Array(@params[:ordered_values]).map(&:to_s)

      if list_family?
        validate_permutation!(submitted, possible_values.map(&:to_s))
        field.possible_values = submitted
        field.save!
      else
        enums = field.enumerations.to_a
        validate_permutation!(submitted, enums.map { |e| e.id.to_s })
        submitted.each_with_index do |id, idx|
          enums.find { |e| e.id.to_s == id }.update!(position: idx + 1)
        end
      end

      Outcome.new(after: { order: submitted.first(20), truncated: submitted.length > 20 },
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
