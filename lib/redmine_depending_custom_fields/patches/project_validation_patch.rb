# frozen_string_literal: true

require_relative '../non_editable_dependencies'

module RedmineDependingCustomFields
  module Patches
    # WP-09b: core Project#validate_custom_field_values validates only the
    # custom values visible to User.current (identical on Redmine 5.1 to
    # 7.0). After it, the depending children that user cannot see get the D1
    # rule (NonEditableDependencies), with core's user and gate. A copy
    # keeps its source for the baseline (copy).
    module ProjectValidationPatch
      def validate_custom_field_values
        super
        return unless new_record? || custom_field_values_changed?

        NonEditableDependencies.validate(self, User.current)
      end

      # Full review of 2026-11-05 (rules-5): Project#copy saves the new
      # project before it copies anything else; the source is kept for that
      # save, so a stored value that no longer fits an unchanged parent value
      # is judged against the source, as for an issue copy (UD-06).
      def copy(project, options = {})
        @dcf_copied_from = project if new_record? && project.is_a?(::Project)
        super
      end
    end
  end
end
