# frozen_string_literal: true

require_relative '../dependency_rules'
require_relative '../non_editable_dependencies'

module RedmineDependingCustomFields
  module Patches
    # WP-38 (SD-22, owner decision of 2026-11-03): the WP-09b rule for time
    # entries, with core's user (User.current) and gate, and the same result
    # on every supported core. On a time entry editable means visible, so the
    # children the user cannot edit are the ones the user cannot see. Core
    # 6.1 and 7.0 validate only the values that user can see
    # (TimeEntry#validate_custom_field_values); 5.1 and 6.0 validate every
    # value (acts_as_customizable), where the formats leave the D1 error of
    # such a value to this check (NonEditableDependencies.judged_by_record?),
    # but their TimeEntry#safe_attributes= first drops these values from
    # custom_field_values, so they are judged here by their stored value
    # (dropped_values). Either way one error, on the parent field or on base,
    # never under the child's name. No version check: the values decide.
    module TimeEntryValidationPatch
      def validate_custom_field_values
        super
        return unless new_record? || custom_field_values_changed?

        NonEditableDependencies.validate(self, User.current,
                                         custom_field_values + TimeEntryValidationPatch.dropped_values(self))
      end

      # The depending values core 5.1 and 6.0 TimeEntry#safe_attributes=
      # removed from custom_field_values (the fields the user cannot see),
      # each with its stored value: a saved row of a field the entry no longer
      # lists. Nothing on 6.1 and 7.0 (core restores such values) and nothing
      # for a new entry (no saved row; these cores do not save its default
      # either). No query: custom_field_values loaded the rows.
      def self.dropped_values(entry)
        listed = entry.custom_field_values.map(&:custom_field_id)
        saved = entry.custom_values.select(&:persisted?)
        saved.reject { |row| listed.include?(row.custom_field_id) }.group_by(&:custom_field).filter_map do |field, rows|
          next unless DependencyRules.parent_id(field)

          dropped = CustomFieldValue.new(custom_field: field, customized: entry)
          dropped.value = field.multiple? ? rows.map(&:value) : rows.first.value
          dropped.value_was = dropped.value.dup
          dropped
        end
      end
    end
  end
end
