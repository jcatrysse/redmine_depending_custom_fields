# frozen_string_literal: true

require_relative '../non_editable_dependencies'

module RedmineDependingCustomFields
  module Patches
    # WP-09b: core Project#validate_custom_field_values validates only the
    # custom values visible to User.current (identical on Redmine 5.1 to
    # 7.0). After it, the depending children that user cannot see get the D1
    # rule (NonEditableDependencies), with core's user and gate.
    module ProjectValidationPatch
      def validate_custom_field_values
        super
        return unless new_record? || custom_field_values_changed?

        NonEditableDependencies.validate(self, User.current)
      end
    end
  end
end
