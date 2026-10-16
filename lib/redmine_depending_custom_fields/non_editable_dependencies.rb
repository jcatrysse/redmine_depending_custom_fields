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
  # Placement: a child the user can see (read-only by workflow) gets core's
  # 'is invalid' under its name. A child the user cannot see is never named:
  # one message per changed parent field, or one on base when the parent is
  # not shown to the user either (unavailable or hidden) or its value did
  # not change (core gave the child a stale default on a copy or a tracker
  # or project move). No state: the user sets are computed at most once per
  # call, and only when a depending value fails.
  module NonEditableDependencies
    module_function

    # +user+ is the user core validates with; nil means User.current, as in
    # core's editable_custom_field_values and visible_custom_field_values.
    def validate(record, user)
      failing = failing_values(record)
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

    # [custom value, parent state] of each depending value with a parent
    # that D1 rejects, in custom_field_values order. The format check runs
    # in memory; only an unavailable parent costs one memoized find_parent.
    def failing_values(record)
      record.custom_field_values.each_with_object([]) do |custom_value, out|
        next unless DependencyRules.parent_id(custom_value.custom_field)

        state = DependencyRules.parent_state(custom_value.custom_field, record)
        next unless state

        _allowed_empty, errors = DependencyRules.dependency_check(custom_value, state)
        out << [custom_value, state] if errors.any?
      end
    end

    def id_set(custom_values)
      Set.new(custom_values.map(&:custom_field_id))
    end

    # Adds +message+ unless +attribute+ already carries it (one message per
    # parent, and no second 'is invalid' if core ever validates the child).
    def add_once(record, attribute, message)
      record.errors.add(attribute, message) unless record.errors[attribute].include?(message)
    end

    private_class_method :failing_values, :id_set, :add_once
  end
end
