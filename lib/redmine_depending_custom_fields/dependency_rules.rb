# frozen_string_literal: true

require 'set'
require_relative 'sanitizer'
require_relative 'field_index'

module RedmineDependingCustomFields
  # Central rules for depending fields (server design section 3): parent
  # lookup, allowed and default sets, value keys and options, mapping checks
  # and the topology helpers on FieldIndex.
  #
  # Format names are literals: this file loads before the format name
  # constants of redmine_depending_custom_fields.rb exist. The module keeps no
  # state; memoization lives only on CustomField records through
  # CustomFieldPatch#dcf_memo, never on format singletons.
  module DependencyRules
    DEPENDING_FORMATS = %w[depending_list depending_enumeration].freeze
    LIST_FAMILY = %w[list depending_list].freeze
    ENUM_FAMILY = %w[enumeration depending_enumeration].freeze
    ALL_PARENT_FORMATS = (LIST_FAMILY + ENUM_FAMILY).freeze
    PARENT_FORMATS = { 'depending_list' => LIST_FAMILY, 'depending_enumeration' => ENUM_FAMILY }.freeze
    CANONICAL_ID = /\A[1-9]\d*\z/.freeze
    CIRCULAR_ERROR = [:parent_custom_field_id, :dcf_circular_dependency].freeze

    # values/baseline: Arrays of Strings. baseline = the stored value
    # (stored_value), or the copy source's (server design section 8, rule 2).
    # rubocop:disable Lint/StructNewOverride -- the design names the member values
    ParentState = Struct.new(:parent, :available, :values, :baseline) do
      # An unavailable parent counts as changed (UD-05: the child must be
      # cleared, as today). Otherwise values and baseline compare as sets of
      # non-blank Strings: order, repeats and nil versus '' do not count.
      def changed?
        return true unless available

        Set.new(DependencyRules.normalize_values(values)) != Set.new(DependencyRules.normalize_values(baseline))
      end
    end
    # rubocop:enable Lint/StructNewOverride

    # type: :unknown_parent_key, :unknown_child_value, :unknown_default or
    # :default_not_linked. child_key is nil for :unknown_parent_key.
    Problem = Struct.new(:type, :parent_key, :child_key, keyword_init: true)

    module_function

    def depending?(cf)
      DEPENDING_FORMATS.include?(cf.field_format)
    end

    # 'list' or 'enumeration' by family, nil for other formats.
    def kind(cf)
      if LIST_FAMILY.include?(cf.field_format)
        'list'
      elsif ENUM_FAMILY.include?(cf.field_format)
        'enumeration'
      end
    end

    def parent_formats_for(cf)
      PARENT_FORMATS[cf.field_format] || []
    end

    # Mirrors to_i: a positive Integer or nil. Never raises.
    def normalize_id(raw)
      id = raw.to_s.to_i
      id.positive? ? id : nil
    end

    def normalize_values(raw)
      Array(raw).map(&:to_s).reject(&:blank?)
    end

    # The in-memory parent id of a depending field (authoritative for the
    # record itself), normalized; nil for other formats.
    def parent_id(cf)
      depending?(cf) ? normalize_id(cf.parent_custom_field_id) : nil
    end

    # Exactly the before_save lookup: the parent record a save keeps, or nil.
    # A self-parent of the same type and family resolves to the field itself.
    # Memoized on the record per raw value, nil included.
    def resolve_parent_for_save(cf)
      return nil unless depending?(cf)

      raw = cf.parent_custom_field_id
      return nil if raw.blank?

      cf.dcf_memo(:resolve, raw.to_s) do
        CustomField.find_by(id: raw.to_i, type: cf.type, field_format: parent_formats_for(cf))
      end
    end

    # The single stub point for parent lookups in specs.
    def find_parent(id)
      CustomField.find_by(id: id)
    end

    # The raw parent record (server design 2.1): nil for non-depending fields,
    # a blank, dangling or own id, another STI type or another family. No cycle
    # walk, no visibility check. Memoized on the record per pointer, nil included.
    def parent_of(cf)
      pid = parent_id(cf)
      return nil if pid.nil? || pid == cf.id

      cf.dcf_memo(:parent_of, pid) do
        record = find_parent(pid)
        record if record && record.type == cf.type && parent_formats_for(cf).include?(record.field_format)
      end
    end

    # The effective parent id (server design 2.1, WP-10): the in-memory
    # pointer as an Integer when it is not the field itself, names an
    # existing field of the same type in the field's family, and the stored
    # chain from it never revisits a field (the field included); nil
    # otherwise, so fields in or below a stored cycle (a self-parent is a
    # cycle of one) are unconstrained (UD-08, UD-35). nil without a query
    # for other formats and a blank, invalid or own pointer. +lookup+ (id =>
    # CustomField, from lookup_records) supplies loaded, unmodified records:
    # their rows are read from the raw format_store, so a chain loaded on
    # the object costs no query; a first hop it lacks comes from the
    # memoized find_parent (shared with parent_state and no_options?), later
    # unknown hops from one raw select per chain level. The index of the
    # walk is kept on the first-hop record (dcf_memo), so the children of
    # one loaded parent share the rows it fetched: an ancestor the object
    # does not carry costs one select for all of them, not one per child
    # (server design 3.3). Each child still walks from that record with its
    # own id. No visibility check (ClientData adds it, WP-16). Memoized on
    # the record per pointer, nil included; the result does not depend on
    # +lookup+.
    def effective_parent_id(cf, lookup = {})
      pid = parent_id(cf)
      return nil if pid.nil? || pid == cf.id

      cf.dcf_memo(:effective_parent, [cf.id, pid]) do
        records = lookup || {}
        first = records[pid] || parent_record(cf, pid)
        next nil unless first

        index = first.dcf_memo(:chain_index, nil) do
          FieldIndex.new(records: records[pid] ? records : records.merge(pid => first))
        end
        index.effective_parent_id_for(cf.id, cf.type, cf.field_format, pid)
      end
    end

    # True when the normalized parent id differs from the stored one (the
    # D9 refinement runs the cycle check only then, UD-08). True for new
    # records; false without reading the old store when format_store will
    # not be saved. Compares normalized ids, so '12' and 12, nil and '' or 0
    # are no change; the store dirty helpers compare raw values (F1).
    def parent_changed?(cf)
      return true if cf.new_record?
      return false unless cf.will_save_change_to_attribute?('format_store')

      FieldIndex.parent_id_from_raw(cf.attribute_in_database('format_store')) != normalize_id(cf.parent_custom_field_id)
    end

    # The parent errors of a save (server design section 9), as [attribute,
    # message] pairs for CustomField#validate_custom_field: the parent that
    # before_save keeps (same memoized lookup) is the field itself or has
    # the field in its stored chain (a fresh FieldIndex.load). Only for
    # persisted depending fields whose parent id changes; an unresolvable
    # parent keeps the silent nil of before_save (D9).
    def parent_errors(cf)
      return [] unless depending?(cf) && !cf.new_record? && parent_changed?(cf)

      candidate = resolve_parent_for_save(cf)
      return [] unless candidate
      return [CIRCULAR_ERROR] if candidate.id == cf.id || FieldIndex.load.ancestor_ids(candidate.id).include?(cf.id)

      []
    end

    # True when +customized+ is an instance of the class the field belongs to
    # (an Issue for an IssueCustomField); false for a Project passed for an
    # issue field, as context menus and query filters do.
    def carries?(cf, customized)
      klass = cf.class.customized_class
      klass ? customized.is_a?(klass) : false
    rescue StandardError
      false
    end

    # The parent read of the depending formats: nil unless +customized+ has
    # custom field values and is an object the field belongs to (carries?,
    # WP-15: a Project passed for an issue field by core menus and query
    # filters, or any other object, gives nil before the pointer is read, so
    # without a format_store parse or a query), and the field has an
    # effective parent (WP-10), so a dangling parent, the field itself,
    # another type or family and fields in or below a stored cycle give nil
    # (core validation only, UD-08). When the parent is among the loaded
    # custom field values of +customized+, its value is read there (no
    # query). Otherwise the one memoized find_parent of effective_parent_id
    # gives an unavailable parent (available false, no values). nil also for
    # a blank or invalid pointer, without a query. Values are Strings, blanks
    # kept, as 0.0.16 reads them. The baseline (WP-09) is the stored value
    # (stored_value), or for a copy the source's value (baseline_source),
    # without blanks.
    def parent_state(cf, customized)
      return nil unless customized.respond_to?(:custom_field_values) && carries?(cf, customized)

      pid = parent_id(cf)
      return nil if pid.nil?
      return nil unless effective_parent_id(cf, lookup_records(customized))

      read_parent_state(cf, customized, pid)
    end

    # The parent read of parent_state for the raw pointer +pid+, without the
    # effective-parent rule: the value from the loaded custom field values,
    # else an unavailable state for an existing field, else nil.
    def read_parent_state(cf, customized, pid)
      if customized.respond_to?(:custom_field_values)
        cfv = customized.custom_field_values.detect { |v| v.custom_field_id == pid }
        if cfv
          source = baseline_source(customized)
          baseline = if source
                       normalize_values(source.custom_field_value(pid))
                     else
                       stored_value(customized, pid, cfv.value_was)
                     end
          return ParentState.new(cfv.custom_field, true, string_values(cfv.value), baseline)
        end
      end

      record = parent_record(cf, pid)
      return nil unless record
      return ParentState.new(record, false, [], []) if customized.respond_to?(:custom_field_values)

      # Not reached by core or plugin callers: asks the object like 0.0.16
      # (NoMethodError for an object without custom fields).
      ParentState.new(record, true, string_values(customized.custom_field_value(record)), [])
    end

    # The children the parent values of +state+ allow, as a Set of Strings:
    # 0.0.16's union of the stored mapping entries, read as is (blank keys and
    # entries count, as for mappings stored before the sanitizer). Empty for
    # an unavailable parent.
    def allowed_for(cf, state)
      mapping = cf.value_dependencies || {}
      Set.new(state.values.flat_map { |v| Array(mapping[v]) }.map(&:to_s))
    end

    # D1 per value (UD-04, server design section 8). Returns [allowed_empty,
    # errors]. While the parent is unchanged the child baseline is tolerated
    # and only new values must be allowed; when it changed (an unavailable
    # parent counts as changed, UD-05) every value must be allowed. errors is
    # [] or one 'is invalid' in the active locale. No query, no current user
    # (UD-07: no editable_by? rule); the parent comes only from +state+. The
    # formats call it for the values core validates; for the children the
    # user cannot edit on issues and projects, NonEditableDependencies
    # (WP-09b) resolves the user and calls it, with an unavailable parent
    # read as unchanged (WP-09c).
    def dependency_check(custom_value, state)
      current = normalize_values(custom_value.value)
      allowed = allowed_for(custom_value.custom_field, state)
      return [allowed.empty?, []] if current.empty?

      tolerated = state.changed? ? Set.new : Set.new(child_baseline(custom_value))
      bad = current.reject { |v| allowed.include?(v) || tolerated.include?(v) }
      [allowed.empty?, bad.empty? ? [] : [::I18n.t('activerecord.errors.messages.invalid')]]
    end

    # The issue a new record was copied from (UD-06): core keeps it in
    # @copied_from without a reader (Issue#copy_from; pinned by
    # spec/requests/dcf_issue_copy_spec.rb on every supported version). nil
    # for persisted records, records that are no copy or have no copy? (only
    # Issue defines it), and on any error, so validation stays strict.
    def baseline_source(customized)
      return nil unless customized.respond_to?(:new_record?) && customized.respond_to?(:copy?)
      return nil unless customized.new_record? && customized.copy?

      source = customized.instance_variable_get(:@copied_from)
      source.respond_to?(:custom_field_value) ? source : nil
    rescue StandardError
      nil
    end

    # The stored child values D1 tolerates, as Strings without blanks: the
    # copy source's value for a copy ([] when the source does not carry the
    # field), [] for another new record (its value_was is only the default),
    # else the stored value.
    def child_baseline(custom_value)
      customized = custom_value.customized
      source = baseline_source(customized)
      return normalize_values(source.custom_field_value(custom_value.custom_field)) if source
      return [] if customized.respond_to?(:new_record?) && customized.new_record?

      stored_value(customized, custom_value.custom_field_id, custom_value.value_was)
    end

    # The stored value of field +field_id+ on +customized+, as Strings without
    # blanks: value_was when a saved row holds the field, else []. A field
    # without a row that a tracker or project change makes available gets a
    # built row holding its default (Issue#set_custom_field_default?), and
    # value_was copies that default, which was never stored. Reads the
    # custom_values that custom_field_values loaded (no query). A value
    # without a record (no custom_values) keeps value_was.
    def stored_value(customized, field_id, value_was)
      if customized.respond_to?(:custom_values)
        stored = customized.custom_values.any? { |cv| cv.custom_field_id == field_id && cv.persisted? }
        return [] unless stored
      end
      normalize_values(value_was)
    end

    # True when the parent value of +customized+ allows no child value, so
    # the required bypass (CustomFieldPatch) drops the blank error. Like
    # 0.0.16, the parent field must still exist: one find_parent per record
    # and id, memoized and shared with parent_state. Without an effective
    # parent (WP-10: in or below a stored cycle, a self-parent, another type
    # or family) it keeps the 0.0.16 read (legacy_parent_state), because the
    # legacy script still disables such a field while that parent allows
    # nothing and posts ''; WP-18 removes the fallback with the script.
    def no_options?(cf, customized)
      state = parent_state(cf, customized) || legacy_parent_state(cf, customized)
      return false unless state && allowed_for(cf, state).empty?

      !parent_record(cf, parent_id(cf)).nil?
    end

    # The parent read before WP-10, for the required bypass only: the raw
    # pointer names any existing field, of any type and family, the field
    # itself included, and its value is read from +customized+. nil for a
    # blank or invalid pointer, a nil object and a dangling parent.
    def legacy_parent_state(cf, customized)
      pid = parent_id(cf)
      return nil if pid.nil? || customized.nil?

      read_parent_state(cf, customized, pid)
    end

    # id => CustomField from what is already loaded: the custom field values of
    # one record, or the available custom fields of an Array of objects (first
    # instance per id kept). No query once those are loaded.
    def lookup_records(source)
      fields = if source.is_a?(Array)
                 source.flat_map { |o| o.respond_to?(:available_custom_fields) ? o.available_custom_fields.to_a : [] }
               elsif source.respond_to?(:custom_field_values)
                 source.custom_field_values.map(&:custom_field)
               else
                 []
               end
      fields.each_with_object({}) do |field, by_id|
        by_id[field.id] = field if field&.id && !by_id.key?(field.id)
      end
    end

    # The children linked to +parent_values+ (union), as a Set of Strings.
    def allowed_set(map, parent_values)
      Set.new(allowed_values(map, parent_values))
    end

    # The union in first-seen order: parent order, then link order. A map that
    # is not a Hash allows nothing.
    def allowed_values(map, parent_values)
      return [] unless map.is_a?(Hash)

      seen = Set.new
      normalize_values(parent_values).each_with_object([]) do |pv, out|
        normalize_values(map[pv]).each { |v| out << v if seen.add?(v) }
      end
    end

    # The defaults of +parent_values+ that are allowed, in first-seen order: an
    # Array for a multiple field, the first one (or nil) otherwise.
    def default_values(map, defaults, parent_values, multiple:)
      allowed = allowed_set(map, parent_values)
      defaults = {} unless defaults.is_a?(Hash)
      seen = Set.new
      values = normalize_values(parent_values).each_with_object([]) do |pv, out|
        normalize_values(defaults[pv]).each { |v| out << v if allowed.include?(v) && seen.add?(v) }
      end
      multiple ? values : values.first
    end

    # The stored mapping, sanitized but not pruned.
    def mapping(cf)
      Sanitizer.sanitize_dependencies(cf.value_dependencies)
    end

    # The stored defaults, sanitized but not pruned.
    def defaults(cf)
      Sanitizer.sanitize_default_dependencies(cf.default_value_dependencies)
    end

    # The stored flag cast like MappingBuilder and the API do.
    def hide_when_disabled?(cf)
      ActiveModel::Type::Boolean.new.cast(cf.hide_when_disabled) == true
    end

    # Value keys of the field from in-memory values: list values (first
    # occurrence kept) or enumeration ids as Strings by [position, id],
    # inactive included unless include_inactive is false. Not memoized.
    def value_keys(cf, include_inactive: true)
      if ENUM_FAMILY.include?(cf.field_format)
        enumerations_of(cf, include_inactive).map { |e| e.id.to_s }
      else
        list_values(cf)
      end
    end

    # The single value-option source: ordered [key, label, active] tuples, in
    # value_keys order with inactive enumerations included.
    def value_options(cf)
      if ENUM_FAMILY.include?(cf.field_format)
        enumerations_of(cf, true).map { |e| [e.id.to_s, e.name.to_s, e.active?] }
      else
        list_values(cf).map { |v| [v, v, true] }
      end
    end

    # Strict check of a mapping against the parent and child keys, in vd order
    # then dd order, one Problem per [type, parent_key, child_key]. Empty
    # exactly when DependencyMappingService#validate_mapping! passes.
    def mapping_problems(vd, dd, parent_keys:, child_keys:)
      parents = key_set(parent_keys)
      children = key_set(child_keys)
      vd = {} unless vd.is_a?(Hash)
      dd = {} unless dd.is_a?(Hash)
      links = vd.each_with_object({}) { |(key, values), h| h[key.to_s] = values }
      found = {}
      add = lambda do |type, pkey, ckey|
        found[[type, pkey, ckey]] ||= Problem.new(type: type, parent_key: pkey, child_key: ckey)
      end
      vd.each do |key, values|
        pkey = key.to_s
        add.call(:unknown_parent_key, pkey, nil) unless parents.include?(pkey)
        Array(values).each do |value|
          add.call(:unknown_child_value, pkey, value.to_s) unless children.include?(value.to_s)
        end
      end
      dd.each do |key, values|
        pkey = key.to_s
        add.call(:unknown_parent_key, pkey, nil) unless parents.include?(pkey)
        linked = nil
        Array(values).each do |value|
          ckey = value.to_s
          if children.include?(ckey)
            linked ||= Set.new(Array(links[pkey]).map(&:to_s))
            add.call(:default_not_linked, pkey, ckey) unless linked.include?(ckey)
          else
            add.call(:unknown_default, pkey, ckey)
          end
        end
      end
      found.values
    end

    # Admin JSON transport only (D6); never used by before_save,
    # storage_preview, the API or the services (BC-02). Returns [vd, dd]: vd
    # keeps the parent keys in parent_keys (all submitted keys when nil) and
    # the values in child_keys, ordered by parent then child order, empty keys
    # dropped; dd keeps only values linked under the same key, in child order,
    # the first one as a String for a single field.
    def prune_mapping(vd, dd, parent_keys:, child_keys:, multiple:)
      links = Sanitizer.sanitize_dependencies(vd)
      submitted_defaults = Sanitizer.sanitize_default_dependencies(dd)
      rank = {}
      Array(child_keys).each { |k| rank[k.to_s] = rank.size unless rank.key?(k.to_s) }
      order = parent_keys.nil? ? links.keys : Array(parent_keys).map(&:to_s).uniq
      pruned = {}
      order.each do |pkey|
        next unless links.key?(pkey)

        kept = links[pkey].select { |v| rank.key?(v) }.uniq.sort_by { |v| rank[v] }
        pruned[pkey] = kept unless kept.empty?
      end
      pruned_defaults = {}
      pruned.each do |pkey, kept|
        next unless submitted_defaults.key?(pkey)

        linked = Set.new(kept)
        values = normalize_values(submitted_defaults[pkey]).select { |v| linked.include?(v) }.uniq.sort_by { |v| rank[v] }
        pruned_defaults[pkey] = multiple ? values : values.first unless values.empty?
      end
      [pruned, pruned_defaults]
    end

    # Depending fields whose stored pointer is +field+ (any type, any family, a
    # self-parent included), loaded as full records by [position, id].
    def children_of(field, index: nil)
      return [] if field.id.nil?

      ids = (index || FieldIndex.load).children_ids(field.id)
      return [] if ids.empty?

      CustomField.where(id: ids).sorted.order(:id).to_a
    end

    def descendant_ids(cf, index: nil)
      return [] if cf.new_record?

      (index || FieldIndex.load).descendant_ids(cf.id)
    end

    # The stored cycle +cf+ is a member of, ordered along the cycle from +cf+;
    # [] when cf is not on a cycle (also when its chain only reaches one) and,
    # without a query, for new records and non-depending fields.
    def cycle_member_ids(cf, index: nil)
      return [] if cf.new_record? || !depending?(cf)

      members = (index || FieldIndex.load).cycle_from(cf.id)
      members.include?(cf.id) ? members : []
    end

    def in_cycle?(cf, index: nil)
      cycle_member_ids(cf, index: index).any?
    end

    # The fields the parent select may offer: same type and family, by
    # [position, id], minus the field itself and its descendants. The current
    # parent stays even when it is a descendant (stored cycle), but never the
    # field itself. All candidates for a new record.
    def parent_candidates(cf, index: nil)
      return [] unless depending?(cf)

      candidates = CustomField.where(type: cf.type, field_format: parent_formats_for(cf)).sorted.order(:id).to_a
      return candidates if cf.new_record?

      excluded = Set.new((index || FieldIndex.load).descendant_ids(cf.id))
      current = parent_id(cf)
      candidates.reject { |c| c.id == cf.id || (excluded.include?(c.id) && c.id != current) }
    end

    def list_values(cf)
      Array(cf.possible_values).map(&:to_s).uniq
    end

    def enumerations_of(cf, include_inactive)
      records = cf.enumerations.to_a.select(&:id)
      records = records.select(&:active?) unless include_inactive
      records.sort_by { |e| [e.position.to_i, e.id] }
    end

    def key_set(keys)
      keys = keys.keys if keys.is_a?(Hash)
      Set.new(Array(keys).map(&:to_s))
    end

    def string_values(raw)
      Array(raw).map(&:to_s)
    end

    # The record of the parent id +pid+ of +cf+ from find_parent, memoized on
    # +cf+ (nil included): the first hop effective_parent_id fetches when the
    # lookup lacks it, shared with parent_state and no_options?. Public for
    # ClientData (WP-16), so a parent the object does not carry costs no
    # second query.
    def parent_record(cf, pid)
      cf.dcf_memo(:parent_record, pid) { find_parent(pid) }
    end

    private_class_method :list_values, :enumerations_of, :key_set, :string_values, :stored_value,
                         :read_parent_state, :legacy_parent_state
  end
end
