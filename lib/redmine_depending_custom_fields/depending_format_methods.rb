# frozen_string_literal: true

require_relative 'dependency_rules'
require_relative 'client_data'

module RedmineDependingCustomFields
  # The methods DependingListFormat and DependingEnumerationFormat share
  # (server design section 5). Included, not prepended, so super reaches the
  # core list and enumeration formats; the class bodies keep add,
  # form_partial, label and query_filter_values.
  #
  # Format objects are process-wide singletons: nothing here assigns instance
  # variables. Lookups are cached only on CustomField records, through
  # CustomFieldPatch#dcf_memo (DependencyRules).
  module DependingFormatMethods
    def self.included(base)
      base.field_attributes :parent_custom_field_id, :value_dependencies, :default_value_dependencies, :hide_when_disabled
    end

    # The format_store pairs before_save assigns, in order: the parent id when
    # one is given (a String id becomes the Integer id, an id that names no
    # field of the same type and family becomes nil), then both mappings,
    # sanitized. Never prunes (BC-02).
    def normalized_store_pairs(custom_field)
      pairs = []
      if custom_field.parent_custom_field_id.present?
        pairs << ['parent_custom_field_id', DependencyRules.resolve_parent_for_save(custom_field)&.id]
      end
      pairs << ['value_dependencies', Sanitizer.sanitize_dependencies(custom_field.value_dependencies)]
      pairs << ['default_value_dependencies', Sanitizer.sanitize_default_dependencies(custom_field.default_value_dependencies)]
      pairs
    end

    # The format_store a save of +custom_field+ writes, as a new Hash whose
    # YAML equals the stored bytes (limits V4). +store+ is converted as the
    # store coder does; neither it nor the record is changed.
    def storage_preview(custom_field, store)
      preview = ActiveRecord::Store::IndifferentCoder.as_indifferent_hash(store).to_hash
      normalized_store_pairs(custom_field).each { |key, value| preview[key] = value }
      preview
    end

    # Clears the core default value when a given parent resolves.
    def before_custom_field_save(custom_field)
      super
      pairs = normalized_store_pairs(custom_field)
      pairs.each { |key, value| custom_field.public_send("#{key}=", value) }
      parent = pairs.assoc('parent_custom_field_id')
      custom_field.default_value = nil if parent && parent.last
    end

    # nil (new and edit forms, admin views) and an Array of objects (bulk
    # edit) give the full core list, and so does one object without a parent
    # state: no effective parent (WP-10), or an object the field does not
    # belong to, such as the Project core menus and query filters pass for an
    # issue field (WP-15; they read only label and value). Otherwise every
    # option is kept and the ones its parent value does not allow are hidden,
    # so a stored legacy value stays visible.
    def possible_values_options(custom_field, object = nil)
      single = object.is_a?(Array) ? object.first : object
      base = super(custom_field, single)
      return base if object.nil? || object.is_a?(Array)

      state = DependencyRules.parent_state(custom_field, object)
      return base unless state

      allowed = DependencyRules.allowed_for(custom_field, state)
      base.map do |opt|
        label, value = opt.is_a?(Array) ? opt.take(2) : [opt, opt]
        if value.blank? || allowed.include?(value.to_s)
          [label, value]
        else
          [label, value, { hidden: true, style: 'display:none;' }]
        end
      end
    end

    # Drops blank values first (kept: the value is assigned back). Without a
    # parent state (no effective parent: none, dangling, in or below a stored
    # cycle, WP-10) only core validates. With one,
    # DependencyRules.dependency_check applies D1 per value: while
    # the parent is unchanged the stored values (for a copy, the source's)
    # are kept and only new values must be allowed. When the parent value
    # allows nothing, a blank or rejected value skips the core check; values
    # the rule keeps still get it (core inclusion stays for copies).
    # Otherwise the core errors come first, plus one 'is invalid' not already
    # among them.
    def validate_custom_value(custom_value)
      cf = custom_value.custom_field
      sanitized = DependencyRules.normalize_values(custom_value.value)
      custom_value.value = cf.multiple? ? sanitized : sanitized.first

      state = DependencyRules.parent_state(cf, custom_value.customized)
      return super unless state

      allowed_empty, dep_errors = DependencyRules.dependency_check(custom_value, state)
      return dep_errors if allowed_empty && (sanitized.empty? || dep_errors.any?)

      errors = super
      errors + (dep_errors - errors)
    end

    # The core checks, then the parent check (WP-10): a persisted field whose
    # parent id changes may not name itself or one of its dependent fields.
    # Core adds each pair to the record's errors, so the plugin API, the
    # admin form and the services all refuse such a save.
    def validate_custom_field(custom_field)
      super + DependencyRules.parent_errors(custom_field)
    end

    # Matches labels of the full list, hidden values included: import and
    # email set the child before the parent. Case-insensitive (Unicode case
    # folding, as casecmp?), the first label wins; one index per call.
    def value_from_keyword(custom_field, keyword, customized = nil, **_options)
      return if keyword.blank?

      index = {}
      possible_values_options(custom_field).each do |opt|
        label, value = opt.is_a?(Array) ? opt.take(2) : [opt, opt]
        key = label.to_s.strip.downcase(:fold)
        index[key] = value unless index.key?(key)
      end
      return if index.empty?

      keywords = custom_field.multiple? ? keyword.split(/[;,]/).map(&:strip).reject(&:blank?) : [keyword.strip]
      matched = keywords.filter_map { |kw| index[kw.downcase(:fold)] }
      custom_field.multiple? ? matched.presence : matched.first
    end

    # WP-16: core's tag plus the data-dcf-* attributes of ClientData (server
    # design 2.2) on the select or the check box group; the caller's options
    # are not changed. Without data (ClientData failed or the field has
    # none), core gets the caller's options as they are. WP-19: before a
    # managed single radio group (or a required select without a '' option)
    # an id-less hidden input with the same name posts '' first; a checked
    # radio or selected option comes later and wins (last-wins parsing).
    def edit_tag(view, tag_id, tag_name, custom_value, options = {})
      cf = custom_value.custom_field
      data = ClientData.attributes_for(cf, context: :form, customized: custom_value.customized,
                                           custom_value: custom_value, tag_name: tag_name)
      html = super(view, tag_id, tag_name, custom_value, ClientData.merge_options(options, data))
      return html unless ClientData.sentinel?(cf, data) && !tag_name.to_s.end_with?('[]')

      view.hidden_field_tag(tag_name, '', id: nil, data: { dcf_blank: 1 }) + html
    end

    # Bulk edit, time-entry bulk edit and the context-menu wizard: core's
    # select plus the bulk attributes for the selected +objects+. WP-19
    # (UD-10): for a required child with parent data, core's body with its
    # (none) option kept and marked data-dcf-required-none (core drops it for
    # required fields); the runtime enables it only while the parent
    # selection allows no value, and the server still refuses a blank value
    # per record while the parent value allows options.
    def bulk_edit_tag(view, tag_id, tag_name, custom_field, objects, value, options = {})
      data = ClientData.attributes_for(custom_field, context: :bulk, objects: objects, tag_name: tag_name)
      merged = ClientData.merge_options(options, data)
      unless custom_field.is_required? && data.key?(:dcf_parent)
        return super(view, tag_id, tag_name, custom_field, objects, value, merged)
      end

      opts = []
      opts << [l(:label_no_change_option), ''] unless custom_field.multiple?
      opts << [l(:label_none), '__none__', { 'data-dcf-required-none' => '1' }]
      opts += possible_values_options(custom_field, objects)
      view.select_tag(tag_name, view.options_for_select(opts, value), merged.merge(multiple: custom_field.multiple?))
    end
  end
end
