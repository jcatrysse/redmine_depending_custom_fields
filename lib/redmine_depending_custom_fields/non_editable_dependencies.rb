# frozen_string_literal: true

require 'set'
require_relative 'dependency_rules'

module RedmineDependingCustomFields
  # WP-09b (UD-07 confirmed: the rules lead on every object). Core Issue and
  # Project validate only editable_custom_field_values, so a depending child
  # the user cannot edit was never judged there. This applies the D1 rule of
  # the formats (DependencyRules.parent_state and dependency_check) to those
  # children and nothing else: no core required, inclusion or regexp check
  # and no value rewrite. Called by the Issue and Project patches with core's
  # user, inside core's gate.
  #
  # WP-09c (owner, UD-07 refinements): for these children a parent field
  # that is not available on the record (disabled for the tracker or
  # project, or not carried) does not count as changed, because nobody
  # changed it: their stored value is tolerated and only new values must be
  # allowed. Editable children keep UD-05 through the formats, which read
  # DependencyRules.parent_state unchanged.
  #
  # Placement: a child the user can see (read-only by workflow) gets core's
  # 'is invalid' under its name. A child the user cannot see is never named:
  # one message per changed parent field, or one on base when the parent is
  # not shown to the user either (hidden) or its value did not change (core
  # gave the child a stale default on a new record, a copy or a tracker or
  # project move, also under an unavailable parent). No state: the user sets
  # are computed at most once per call, and only when a depending value
  # fails.
  #
  # WP-38 (SD-22): time entries get the same check (TimeEntryValidationPatch,
  # with User.current). There editable means visible, so only the hidden
  # placements occur, and the formats leave the D1 error of a hidden value
  # to this check on cores that still validate it (judged_by_record?).
  #
  # Full review of 2026-11-05 (rules-1): core validates every value of the
  # other customizables (versions, users, groups, documents, enumerations)
  # and files an error under the field's own name, so a child User.current
  # cannot see is judged here too (validate_hidden through
  # HiddenDependenciesValidationPatch), with the same two placements.
  module NonEditableDependencies
    module_function

    # +user+ is the user core validates with; nil means User.current, as in
    # core's editable_custom_field_values and visible_custom_field_values.
    # +values+ are the custom values to judge (WP-38: for a time entry also
    # the values core dropped, TimeEntryValidationPatch.dropped_values).
    def validate(record, user, values = record.custom_field_values)
      failing = failing_values(record, values)
      return if failing.empty?

      editable = id_set(record.editable_custom_field_values(user))
      failing = failing.reject { |custom_value, _state| editable.include?(custom_value.custom_field_id) }
      return if failing.empty?

      visible = id_set(record.visible_custom_field_values(user))
      failing.each do |custom_value, state|
        if visible.include?(custom_value.custom_field_id)
          add_once(record, custom_value.custom_field.name, ::I18n.t('activerecord.errors.messages.invalid'))
        elsif state.changed? && visible.include?(state.parent.id)
          add_once(record, state.parent.name, ::I18n.t('activerecord.errors.messages.dcf_hidden_child_conflict'))
        else
          add_once(record, :base, ::I18n.t('error_dcf_hidden_child_conflict'))
        end
      end
    end

    # WP-38: true for a value of a time entry that User.current cannot see.
    # validate places its D1 error (TimeEntryValidationPatch), so the formats
    # leave that error out where core still validates such a value (5.1 and
    # 6.0): one error, never under the child's name. False for issues and
    # projects: their core validates only the editable values. Full review
    # (rules-1): true as well for a value User.current cannot see on any
    # other record with custom fields (validate_hidden places its error).
    def judged_by_record?(custom_value)
      record = custom_value.customized
      return false if record.nil? || record.is_a?(::Issue) || record.is_a?(::Project)

      !custom_value.custom_field.visible_by?(record.try(:project), ::User.current)
    end

    # Full review (rules-1): the D1 rule for the values of +record+ that
    # User.current cannot see (judged_by_record?), on a record whose core
    # validates every value (versions, users, groups, documents,
    # enumerations). Never under the child's name: on the changed parent
    # field when User.current can see it, else on base.
    def validate_hidden(record, values = record.custom_field_values)
      failing = failing_values(record, values).select { |custom_value, _state| judged_by_record?(custom_value) }
      failing.map(&:last).each do |state|
        if state.changed? && state.parent.visible_by?(record.try(:project), ::User.current)
          add_once(record, state.parent.name, ::I18n.t('activerecord.errors.messages.dcf_hidden_child_conflict'))
        else
          add_once(record, :base, ::I18n.t('error_dcf_hidden_child_conflict'))
        end
      end
    end

    # [custom value, parent state] of each depending value of +values+ with
    # a parent that D1 rejects, in their order, an unavailable parent read as
    # unchanged (unchanged_if_unavailable). Values of editable children are
    # dropped by validate before any placement. The format check runs in
    # memory; only an unavailable parent costs one memoized find_parent.
    def failing_values(record, values)
      values.each_with_object([]) do |custom_value, out|
        next unless DependencyRules.parent_id(custom_value.custom_field)

        state = DependencyRules.parent_state(custom_value.custom_field, record)
        next unless state

        state = unchanged_if_unavailable(state)
        _allowed_empty, errors = DependencyRules.dependency_check(custom_value, state)
        out << [custom_value, state] if errors.any?
      end
    end

    # WP-09c: an unavailable parent as an available one without values or
    # baseline, so changed? is false, nothing is allowed and the child
    # baseline is tolerated (none on a new record that is no copy, so a
    # stale default is still refused, on base for a hidden child).
    def unchanged_if_unavailable(state)
      return state if state.available

      DependencyRules::ParentState.new(state.parent, true, [], [])
    end

    def id_set(custom_values)
      Set.new(custom_values.map(&:custom_field_id))
    end

    # Adds +message+ unless +attribute+ already carries it (one message per
    # parent, and no second 'is invalid' if core ever validates the child).
    def add_once(record, attribute, message)
      record.errors.add(attribute, message) unless record.errors[attribute].include?(message)
    end

    private_class_method :failing_values, :unchanged_if_unavailable, :id_set, :add_once
  end
end
