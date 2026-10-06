# frozen_string_literal: true

require_relative 'dependency_rules'

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
    # edit) give the full core list. For one object every option is kept and
    # the ones its parent value does not allow are hidden, so a stored legacy
    # value stays visible.
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

    # Drops blank values first (kept: the value is assigned back). With a
    # parent, every non-blank value must be allowed by the parent value, an
    # unchanged stored value included. When the parent value allows nothing,
    # the core check is skipped and a blank value passes. Otherwise the core
    # errors come first, plus one 'is invalid' not already among them.
    def validate_custom_value(custom_value)
      cf = custom_value.custom_field
      sanitized = DependencyRules.normalize_values(custom_value.value)
      custom_value.value = cf.multiple? ? sanitized : sanitized.first

      state = DependencyRules.parent_state(cf, custom_value.customized)
      return super unless state

      allowed = DependencyRules.allowed_for(cf, state)
      dep_errors = dcf_disallowed?(custom_value, allowed) ? [dcf_invalid_message] : []
      return dep_errors if allowed.empty?

      errors = super
      errors + (dep_errors - errors)
    end

    # The core checks only; WP-10 adds the parent checks here.
    def validate_custom_field(custom_field) # rubocop:disable Lint/UselessMethodDefinition
      super
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

    def after_custom_field_save(_custom_field)
      Rails.cache.delete('depending_custom_fields/mapping')
    end

    private

    def dcf_disallowed?(custom_value, allowed)
      DependencyRules.normalize_values(custom_value.value).any? { |v| !allowed.include?(v) }
    end

    def dcf_invalid_message
      ::I18n.t('activerecord.errors.messages.invalid')
    end
  end
end
