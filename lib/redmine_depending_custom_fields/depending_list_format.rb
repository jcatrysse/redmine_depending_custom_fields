require_relative 'sanitizer'

# Field format for list custom fields whose options are filtered based on the
# value of a parent custom field. `value_dependencies` defines the mapping of
# allowed child options per parent value. This class handles filtering, validation
# and persistence of that mapping.

module RedmineDependingCustomFields
  class DependingListFormat < Redmine::FieldFormat::ListFormat
    add 'depending_list'
    self.form_partial = 'custom_fields/formats/depending_list'
    field_attributes :parent_custom_field_id, :parent_field_type, :parent_field_key,
                     :value_dependencies, :default_value_dependencies, :dependency_rules,
                     :hide_when_disabled

    def label
      :label_depending_list
    end

    def before_custom_field_save(custom_field)
      super
      parent_type = custom_field.parent_field_type.to_s

      parent = nil
      if parent_type == 'core_field'
        custom_field.parent_custom_field_id = nil
        custom_field.parent_field_key = custom_field.parent_field_key.presence
        if custom_field.parent_field_key.present?
          custom_field.default_value = nil
        else
          custom_field.parent_field_type = nil
        end
      else
        parent_id = custom_field.parent_custom_field_id
        if parent_id.present?
          parent = CustomField.find_by(
            id: parent_id.to_i,
            type: custom_field.type,
            field_format: ['list', RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST]
          )
          custom_field.parent_custom_field_id = parent&.id
          custom_field.parent_field_type = parent ? 'custom_field' : nil
          custom_field.parent_field_key = nil
          custom_field.default_value = nil if parent
        else
          custom_field.parent_field_type = nil if custom_field.parent_field_key.blank?
        end
      end

      custom_field.value_dependencies = RedmineDependingCustomFields::Sanitizer.sanitize_dependencies(custom_field.value_dependencies)
      custom_field.default_value_dependencies = RedmineDependingCustomFields::Sanitizer.sanitize_default_dependencies(custom_field.default_value_dependencies)

      parsed_rules, error = RedmineDependingCustomFields::Sanitizer.parse_dependency_rules(custom_field.dependency_rules)
      if error
        custom_field.errors.add(:dependency_rules, ::I18n.t(:text_dependency_rules_invalid_json))
      end
      parent_reference = if parent_type == 'core_field'
                           key = custom_field.parent_field_key.to_s
                           key.present? ? RedmineDependingCustomFields::ParentReference.new(type: 'core_field', key: key) : nil
                         elsif parent
                           RedmineDependingCustomFields::ParentReference.new(type: 'custom_field', custom_field: parent)
                         end
      if parent_reference&.format == 'date' &&
         RedmineDependingCustomFields::Sanitizer.invalid_date_rules?(parsed_rules)
        custom_field.errors.add(:dependency_rules, ::I18n.t(:text_dependency_rules_invalid_date))
      end
      schema_errors = RedmineDependingCustomFields::Sanitizer.rule_schema_errors(parsed_rules)
      schema_errors.each do |error|
        custom_field.errors.add(
          :dependency_rules,
          ::I18n.t(:text_dependency_rules_invalid_rule_index, index: error[:index] + 1)
        )
      end
      sanitized_rules = RedmineDependingCustomFields::Sanitizer.sanitize_dependency_rules(parsed_rules)
      custom_field.dependency_rules = sanitized_rules.to_json
    end

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
      evaluation = RedmineDependingCustomFields::DependencyEvaluator.evaluate(custom_field, object)
      return base_options unless evaluation.applicable

      allowed = evaluation.allowed

      # Keep every option in the markup, but hide the ones that aren’t allowed.
      # This lets legacy values remain visible while preventing new invalid picks.
      base_options.map do |opt|
        label, value = opt.is_a?(Array) ? opt.take(2) : [opt, opt]
        if value.blank? || allowed.include?(value.to_s)
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
      cf = custom_value.custom_field
      sanitized = Array(custom_value.value).map(&:to_s).reject(&:blank?)
      custom_value.value = cf.multiple? ? sanitized : sanitized.first

      errors = super
      customized = custom_value.customized
      return errors unless customized

      evaluation = RedmineDependingCustomFields::DependencyEvaluator.evaluate(cf, customized)
      return errors unless evaluation.applicable

      allowed = evaluation.allowed

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
