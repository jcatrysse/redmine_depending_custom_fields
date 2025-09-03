require_relative 'sanitizer'

# Field format for list custom fields whose options are filtered based on the
# value of a parent custom field. `value_dependencies` defines the mapping of
# allowed child options per parent value. This class handles filtering, validation
# and persistence of that mapping.

module RedmineDependingCustomFields
  class DependingListFormat < Redmine::FieldFormat::ListFormat
    add 'depending_list'
    self.form_partial = 'custom_fields/formats/depending_list'
    field_attributes :parent_custom_field_id, :value_dependencies, :default_value_dependencies, :hide_when_disabled

    def label
      :label_depending_list
    end

    def before_custom_field_save(custom_field)
      super
      if custom_field.parent_custom_field_id.present?
        parent = CustomField.find_by(id: custom_field.parent_custom_field_id.to_i,
                                     type: custom_field.type,
                                     field_format: ['list', RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST])
        custom_field.parent_custom_field_id = parent&.id
        custom_field.default_value = nil if parent
      end
      custom_field.value_dependencies = RedmineDependingCustomFields::Sanitizer.sanitize_dependencies(custom_field.value_dependencies)
      custom_field.default_value_dependencies = RedmineDependingCustomFields::Sanitizer.sanitize_default_dependencies(custom_field.default_value_dependencies)
    end

    # lib/redmine_depending_custom_fields/depending_list_format.rb
    # lib/redmine_depending_custom_fields/depending_list_format.rb
    def possible_values_options(custom_field, object = nil)
      # Ask the core for the base options.
      # When bulk-editing (array of issues) any single object suffices for i18n, etc.
      single_object = object.is_a?(Array) ? object.first : object
      base_options  = super(custom_field, single_object)

      # === UI path ==========================================================
      # - new / edit     → object == nil
      # - bulk-edit      → object is an Array
      # In both cases we need to show the **full list** of possible values.
      return base_options if object.nil? || object.is_a?(Array)
      # ======================================================================

      # === Filter path (single record) ======================================
      # Filter only when a parent custom field exists and can be found.
      return base_options unless custom_field.parent_custom_field_id.present?

      parent = CustomField.find_by(id: custom_field.parent_custom_field_id)
      return base_options unless parent

      mapping = custom_field.value_dependencies || {}
      parent_values = Array(object.custom_field_value(parent)).map(&:to_s)
      allowed = parent_values.flat_map { |v| Array(mapping[v]) }.map(&:to_s).uniq

      # Keep every option in the markup, but hide the ones that aren’t allowed.
      # This lets legacy values remain visible while preventing new invalid picks.
      base_options.map do |opt|
        label, value = opt.is_a?(Array) ? opt.take(2) : [opt, opt]
        if value.blank? || value.to_s == '__none__' || allowed.include?(value.to_s)
          [label, value]
        else
          [label, value, { hidden: true, style: 'display:none;' }]
        end
      end
      # ======================================================================
    end

    def query_filter_values(custom_field, query = nil)
      raw = possible_values_options(custom_field, query&.project)
      raw.map do |opt|
        label, value = opt.is_a?(Array) ? opt.take(2) : [opt, opt]
        next if value.blank?
        [label, value.to_s]
      end.compact
    end

    def after_custom_field_save(_custom_field)
      Rails.cache.delete('depending_custom_fields/mapping')
      Rails.cache.delete_matched('dcf/*')
    end

    def validate_custom_value(custom_value)
      errors = super
      cf = custom_value.custom_field
      customized = custom_value.customized
      return errors unless cf.parent_custom_field_id.present? && customized

      parent = CustomField.find_by(id: cf.parent_custom_field_id)
      return errors unless parent

      mapping = cf.value_dependencies || {}
      parent_vals = Array(customized.custom_field_value(parent)).map(&:to_s)
      allowed = parent_vals.flat_map { |pv| Array(mapping[pv]) }.map(&:to_s)

      child_vals = Array(custom_value.value).map(&:to_s)
      invalid = child_vals.reject(&:blank?) - allowed
      errors << ::I18n.t('activerecord.errors.messages.invalid') if invalid.any?
      errors
    end

    def value_from_keyword(custom_field, keyword, customized = nil, **_options)
      return if keyword.blank?

      opts = possible_values_options(custom_field, customized)
      keywords = if custom_field.multiple?
                   keyword.split(/[;,]/).map(&:strip).reject(&:blank?)
                 else
                   [keyword.strip]
                 end

      matched = keywords.filter_map do |kw|
        opt = opts.find do |opt|
          label, _val = opt.is_a?(Array) ? opt.take(2) : [opt, opt]
          label.to_s.strip.casecmp?(kw)
        end
        opt.is_a?(Array) ? opt[1] : opt
      end

      if custom_field.multiple?
        matched.presence
      else
        matched.first
      end
    end
  end
end
