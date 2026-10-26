# Extension for CustomField: the required bypass of depending fields and the
# per-record memo. Registers no callback (server design 11; new CustomField
# callbacks go into CustomFieldValidationPatch).

module RedmineDependingCustomFields
  module Patches
    module CustomFieldPatch
      # Strips the spurious "blank" error added by CustomField's independent is_required? guard when no child options are available for the current parent value.
      # The parent read is DependencyRules.no_options? (WP-09): the effective parent's
      # state only, so a field without one keeps core's required check (WP-18).
      def validate_custom_value(custom_value)
        errs = super

        blank_msg = ::I18n.t('activerecord.errors.messages.blank')
        return errs unless errs.include?(blank_msg)
        return errs unless [FIELD_FORMAT_DEPENDING_LIST,
                            FIELD_FORMAT_DEPENDING_ENUMERATION].include?(field_format)
        return errs unless parent_custom_field_id.present?

        customized = custom_value.customized
        return errs unless customized
        return errs unless DependencyRules.no_options?(self, customized)

        errs.reject { |e| e == blank_msg }
      end

      # Memoizes the block result on this record under (name, key), nil and
      # false included, so the block runs at most once per record and key.
      # Record scoped: never shared between instances or kept on formats.
      def dcf_memo(name, key)
        memo = (@dcf_memo ||= {})
        memo_key = [name, key]
        return memo[memo_key] if memo.key?(memo_key)

        memo[memo_key] = yield
      end
    end
  end
end
