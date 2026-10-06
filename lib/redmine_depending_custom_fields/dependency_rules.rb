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

    # values/baseline: Arrays of Strings. baseline = value_was, or the copy
    # source's stored value (server design section 8, rule 2).
    # rubocop:disable Lint/StructNewOverride -- the design names the member values
    ParentState = Struct.new(:parent, :available, :values, :baseline) do
      # An unavailable parent counts as changed (UD-05: the child must be cleared, as today).
      def changed?
        !available || values.sort != baseline.sort
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

    # True when +customized+ is an instance of the class the field belongs to
    # (an Issue for an IssueCustomField); false for a Project passed for an
    # issue field, as context menus and query filters do.
    def carries?(cf, customized)
      klass = cf.class.customized_class
      klass ? customized.is_a?(klass) : false
    rescue StandardError
      false
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

    private_class_method :list_values, :enumerations_of, :key_set
  end
end
