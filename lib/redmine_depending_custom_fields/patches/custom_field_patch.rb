# Extension for CustomField: the required bypass of depending fields, the
# per-record memo and the copy of a depending enumeration field. Registers no
# callback (server design 11; new CustomField
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

      # True when dcf_memo holds a result for (name, key).
      def dcf_memoized?(name, key)
        (@dcf_memo || {}).key?([name, key])
      end

      # Full review of 2026-11-05 (admin-editor-3): core copies format_store,
      # so the links of a Key/Value list (depending) field, and builds new
      # entries for the copy; the source's links name the source's entries,
      # so the copy starts without links (a List copy keeps its values and
      # its links). The admin form posts no links for a new enumeration.
      def copy_from(arg, options = {})
        copied = super
        if copied && DependencyRules.depending?(self) && DependencyRules.kind(self) == 'enumeration'
          self.value_dependencies = {}
          self.default_value_dependencies = {}
        end
        copied
      end
    end
  end
end
