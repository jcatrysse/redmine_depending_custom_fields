# frozen_string_literal: true

require_relative '../non_editable_dependencies'

module RedmineDependingCustomFields
  module Patches
    # Full review of 2026-11-05 (rules-1): core validates every custom value
    # of a version, user, group, document or enumeration and files an error
    # under the field's own name. The formats leave the D1 error of a value
    # User.current cannot see to this check (NonEditableDependencies
    # .judged_by_record?), which places it on the changed parent field or on
    # base, so a hidden child is never named. Same gate as core.
    module HiddenDependenciesValidationPatch
      def validate_custom_field_values
        super
        return unless new_record? || custom_field_values_changed?

        NonEditableDependencies.validate_hidden(self)
      end
    end
  end
end
