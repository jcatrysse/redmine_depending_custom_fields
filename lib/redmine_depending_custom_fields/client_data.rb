# frozen_string_literal: true

require 'set'
require_relative 'dependency_rules'

module RedmineDependingCustomFields
  # The issue-form data contract of one depending field (server design 2.2
  # and 6, WP-16): the data-dcf-* attributes the format edit tags merge into
  # the options core passes to its select or check box group. Keys are
  # Symbols (Rails dasherizes them and JSON-encodes and escapes non-String
  # values once). Parent data only for a parent the user can see (SP-05);
  # any error gives no attribute at all (fail open, BC-12).
  #
  # Also the UD-37 carrier of the depending children the user sees but
  # cannot edit (locked_children, rendered by Hooks::ReadOnlyCarrierHook).
  #
  # module_function and stateless like DependencyRules: lookups are memoized
  # only on CustomField records (dcf_memo), never here.
  module ClientData
    PARENT_NAME_RE = /\A(.+)\[custom_field_values\]\[\d+\](\[\])?\z/.freeze
    # Larger canonical ids stay Strings: JavaScript numbers lose them.
    MAX_SAFE_INTEGER = 9_007_199_254_740_991

    module_function

    # The attributes of +cf+ in +context+ (:form from edit_tag, :bulk from
    # bulk_edit_tag). Form context reads +customized+ (and +custom_value+ for
    # the stored baseline), bulk context the selected +objects+. {} for
    # fields that are not depending and on any error.
    def attributes_for(cf, context:, customized: nil, objects: nil, custom_value: nil, tag_name: nil, user: User.current)
      return {} unless DependencyRules.depending?(cf)

      bulk = context.to_s == 'bulk'
      data = { dcf_field: cf.id, dcf_context: bulk ? 'bulk' : 'form', dcf_kind: DependencyRules.kind(cf) }
      data[:dcf_multiple] = 1 if cf.multiple?
      lookup = DependencyRules.lookup_records(bulk ? representatives(objects) : customized)
      pid = DependencyRules.effective_parent_id(cf, lookup)
      return data unless pid

      parent = lookup[pid] || DependencyRules.parent_record(cf, pid)
      scope = bulk ? Array(objects) : form_scope(customized)
      return data unless parent && parent_visible?(parent, scope, bulk, user, bulk ? nil : customized)

      add_parent_data(data, cf, pid, tag_name)
      add_form_data(data, cf, parent, customized, custom_value) unless bulk
      data
    rescue StandardError => e
      Rails.logger.warn("[DCF] client data skipped for custom field ##{cf&.id}: #{e.class}")
      {}
    end

    # +options+ with +data+ merged into options[:data]; neither the Hash
    # nor its :data is changed. Core passes data: nil for list fields.
    def merge_options(options, data)
      return options if data.empty?

      base = options[:data].is_a?(Hash) ? options[:data] : {}
      options.merge(data: base.merge(data))
    end

    # UD-37: one Hash of data attributes per depending child of +record+
    # that the user sees but cannot edit (workflow read-only), holds a stored
    # value and whose effective parent the user can see and edit on the
    # form: the parent id, the stored parent baseline and, per stored child
    # value, the parent keys that allow it (sanitized mapping, not pruned).
    # Persisted records only: core gives a new record's non-editable fields
    # their default. Nothing when the user may not edit the record's custom
    # fields at all (the guard core's form uses before rendering them, for
    # example a notes-only user on edit.js), nothing for a child the user
    # cannot see (no id, name, value or flag reaches the page). Uses core's
    # memoized sets for the current user; [] on any error.
    def locked_children(record)
      return [] unless record.respond_to?(:editable_custom_field_values) && record.persisted?
      return [] if record.respond_to?(:safe_attribute?) && !record.safe_attribute?('custom_field_values')

      editable = Set.new(record.editable_custom_field_values.map(&:custom_field_id))
      locked = record.visible_custom_field_values.select do |value|
        !editable.include?(value.custom_field_id) && DependencyRules.depending?(value.custom_field)
      end
      return [] if locked.empty?

      lookup = DependencyRules.lookup_records(record)
      locked.filter_map { |value| locked_child(value, record, lookup, editable) }
    rescue StandardError => e
      Rails.logger.warn("[DCF] read-only carrier skipped: #{e.class}")
      []
    end

    def locked_child(custom_value, record, lookup, editable)
      stored = DependencyRules.child_baseline(custom_value).uniq
      return nil if stored.empty?

      cf = custom_value.custom_field
      pid = DependencyRules.effective_parent_id(cf, lookup)
      parent = pid && editable.include?(pid) ? lookup[pid] : nil
      return nil unless parent && parent_visible?(parent, [record], false, User.current)

      state = DependencyRules.parent_state(cf, record)
      return nil unless state&.available

      mapping = DependencyRules.mapping(cf)
      { dcf_locked_parent: pid,
        dcf_locked_stored: DependencyRules.normalize_values(state.baseline),
        dcf_locked_allowed_by: stored.map { |value| mapping.select { |_key, values| values.include?(value) }.keys } }
    end

    def add_parent_data(data, cf, pid, tag_name)
      data[:dcf_parent] = pid
      match = PARENT_NAME_RE.match(tag_name.to_s)
      data[:dcf_parent_name] = "#{match[1]}[custom_field_values][#{pid}]" if match
      raise ArgumentError, 'stored mapping is not a Hash' unless cf.value_dependencies.nil? || cf.value_dependencies.is_a?(Hash)

      data[:dcf_map] = encode(cf, DependencyRules.mapping(cf))
      defaults = encode(cf, DependencyRules.defaults(cf))
      data[:dcf_defaults] = defaults unless defaults.empty?
      data[:dcf_hide] = 1 if DependencyRules.hide_when_disabled?(cf)
    end

    # Parent values and label while the record carries the field, and the
    # stored baseline of persisted records and issue copies.
    def add_form_data(data, cf, parent, customized, custom_value)
      state = DependencyRules.parent_state(cf, customized)
      return unless state

      data[:dcf_parent_values] = DependencyRules.normalize_values(state.values)
      data[:dcf_parent_label] = parent.name
      stored = stored_baseline(custom_value, customized, state)
      data[:dcf_stored] = stored if stored
    end

    # The server D1 baseline (section 8): the stored values of a persisted
    # record (value_was with a saved row, else []), the source values of an
    # issue copy (UD-06); nil, so no attribute, for any other new record. The
    # child baseline is [] while the parent is not available (UD-05: the
    # server tolerates nothing then).
    def stored_baseline(custom_value, customized, state)
      return nil unless custom_value
      return nil unless customized.persisted? || DependencyRules.baseline_source(customized)

      child = state.available ? DependencyRules.child_baseline(custom_value) : []
      { 'child' => child, 'parent' => DependencyRules.normalize_values(state.baseline) }
    end

    # Form context: the projects of form_scope, or on a user form a parent
    # core renders there as a control (user_form_control?, UD-39). Bulk
    # context: every distinct project of the objects, the base rule (nil
    # project) without objects. An error counts as not visible (fail closed).
    def parent_visible?(parent, objects, bulk, user, customized = nil)
      return true if !bulk && user_form_control?(parent, customized, user)

      projects = objects.map { |object| scope_project(object) }.uniq
      projects = [nil] if projects.empty? && bulk
      projects.all? { |project| parent.visible_by?(project, user) }
    rescue StandardError => e
      Rails.logger.warn("[DCF] client data visibility check failed for custom field ##{parent&.id}: #{e.class}")
      false
    end

    # UD-39 (WP-18): core renders a user field as a control, whatever its
    # visibility, on the viewer's own My account when it is editable and on
    # the registration form (a new User) when the setting shows editable
    # fields or it is required (core my/account and account/register). The
    # admin user form keeps the base rule. No query.
    def user_form_control?(parent, customized, user)
      return false unless customized.is_a?(User)

      if customized.new_record?
        (Setting.show_custom_fields_on_registration? && parent.editable?) || parent.is_required?
      else
        !user.nil? && customized.id == user.id && parent.editable?
      end
    end

    # The objects whose projects must all grant the parent in form context:
    # the record, the source of an issue copy (UD-06: its values and baseline
    # reach the page) and, for a persisted record moved in memory
    # (updateIssueFrom), its stored project (nil, so the base rule, when
    # gone). Fail closed.
    def form_scope(customized)
      objects = [customized]
      source = DependencyRules.baseline_source(customized)
      objects << source if source
      objects << Project.find_by(id: customized.project_id_was) if moved?(customized)
      objects
    end

    def moved?(record)
      record.respond_to?(:project_id_changed?) && record.respond_to?(:persisted?) && record.persisted? &&
        record.project_id_changed?
    end

    # Project#project is the project itself; User and Group have none.
    def scope_project(object)
      object.respond_to?(:project) ? object.project : nil
    end

    # One object per class, and for issues per project and tracker (the only
    # available fields that depend on them): other classes, such as time
    # entries (one unmemoized query each), are asked once whatever the
    # selection and its projects.
    def representatives(objects)
      Array(objects).each_with_object({}) do |object, by_scope|
        key = object.is_a?(Issue) ? [object.class.name, object.project_id, object.tracker_id] : [object.class.name]
        by_scope[key] ||= object
      end.values
    end

    # Enumeration ids matching CANONICAL_ID become Integers, inside arrays
    # too; keys and every other value stay Strings. List values unchanged.
    def encode(cf, value)
      return value unless DependencyRules.kind(cf) == 'enumeration'

      encode_value(value)
    end

    def encode_value(value)
      case value
      when Hash then value.each_with_object({}) { |(key, item), out| out[key.to_s] = encode_value(item) }
      when Array then value.map { |item| encode_value(item) }
      else
        text = value.to_s
        text.match?(DependencyRules::CANONICAL_ID) && text.to_i <= MAX_SAFE_INTEGER ? text.to_i : text
      end
    end

    private_class_method :locked_child, :add_parent_data, :add_form_data, :form_scope, :moved?, :scope_project,
                         :representatives, :encode, :encode_value
  end
end
