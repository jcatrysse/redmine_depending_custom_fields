require_dependency 'custom_field'

# Extension for CustomField that triggers a callback on the field format after
# the record is saved. This allows formats to invalidate caches when their
# configuration changes.

module RedmineDependingCustomFields
  module Patches
    module CustomFieldPatch
      def self.prepended(base)
        base.after_save :dispatch_after_custom_field_save
      end

      # Strips the spurious "blank" error added by CustomField's independent is_required? guard when no child options are available for the current parent value.
      def validate_custom_value(custom_value)
        errs = super

        blank_msg = ::I18n.t('activerecord.errors.messages.blank')
        return errs unless errs.include?(blank_msg)
        return errs unless [FIELD_FORMAT_DEPENDING_LIST,
                            FIELD_FORMAT_DEPENDING_ENUMERATION].include?(field_format)
        return errs unless parent_custom_field_id.present?

        customized = custom_value.customized
        return errs unless customized

        parent_cf = CustomField.find_by(id: parent_custom_field_id)
        return errs unless parent_cf

        mapping     = value_dependencies || {}
        parent_vals = Array(customized.custom_field_value(parent_cf)).map(&:to_s)
        allowed     = parent_vals.flat_map { |pv| Array(mapping[pv]) }.map(&:to_s)

        return errs if allowed.any?

        errs.reject { |e| e == blank_msg }
      end

      private

      def dispatch_after_custom_field_save
        if format.respond_to?(:after_custom_field_save)
          format.after_custom_field_save(self)
        end
      end
    end
  end
end
