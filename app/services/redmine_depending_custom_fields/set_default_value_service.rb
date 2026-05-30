module RedmineDependingCustomFields
  # Operation H — set (or clear) the plain `default_value` of a field that is NOT
  # a depending child. Child depending fields derive their default per parent
  # value through `default_value_dependencies` (the dependency matrix screen), so
  # the plain default does not apply to them and the operation is rejected.
  #
  # Redmine stores `default_value` as a single string column (list values are
  # value strings, enumeration values are enumeration ids), so this operation is
  # single-valued by design even for `multiple` fields — mirroring core's admin
  # form. See Operations Spec §G and Functional Spec §15.
  class SetDefaultValueService < BaseService
    def audit_action
      'set_default_value'
    end

    private

    def perform!
      # A depending child derives its default from the parent value; the plain
      # default is meaningless (and is nil'd on save by the field format).
      if field.parent_custom_field_id.present?
        raise OperationError.new(:error_format_unsupported)
      end

      value = normalize(@params[:default_value])
      before = field.default_value

      validate_default!(value) if value.present?

      field.default_value = value.presence
      field.save!

      Outcome.new(before: { default_value: before },
                  after:  { default_value: field.default_value },
                  summary: "Set default value to '#{field.default_value}'",
                  affected_values_count: 0)
    end

    def validate_default!(value)
      allowed = value_keys_of(field)
      raise OperationError.new(:error_invalid_default_value) unless allowed.include?(value.to_s)
    end
  end
end
