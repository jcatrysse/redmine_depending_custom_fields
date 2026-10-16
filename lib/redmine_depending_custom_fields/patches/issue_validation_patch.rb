# frozen_string_literal: true

require_relative '../non_editable_dependencies'

module RedmineDependingCustomFields
  module Patches
    # WP-09b: core Issue#validate_custom_field_values validates only the
    # editable custom values (identical on Redmine 5.1 to 7.0). After it, the
    # depending children the same user cannot edit get the D1 rule
    # (NonEditableDependencies), with core's user and gate: the author of a
    # new issue, else the journal user; nil falls back to User.current.
    module IssueValidationPatch
      def validate_custom_field_values
        super
        return unless new_record? || custom_field_values_changed?

        NonEditableDependencies.validate(self, new_record? ? author : current_journal.try(:user))
      end
    end
  end
end
