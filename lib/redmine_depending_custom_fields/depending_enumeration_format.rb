require_relative 'sanitizer'

# Field format for enumeration custom fields that depend on the value of
# another custom field. It filters possible values according to the configured
# `value_dependencies` mapping and validates submitted values. The mapping is a
# hash where the parent option maps to an array of allowed child enumeration
# ids.

module RedmineDependingCustomFields
  class DependingEnumerationFormat < Redmine::FieldFormat::EnumerationFormat
    add 'depending_enumeration'
    self.form_partial = 'custom_fields/formats/depending_enumeration'
    field_attributes :parent_custom_field_id, :parent_field_type, :parent_field_key,
                     :value_dependencies, :default_value_dependencies, :dependency_rules,
                     :hide_when_disabled

    def label
      :label_depending_enumeration
    end

    def before_custom_field_save(custom_field)
      super
      parent_type = custom_field.parent_field_type.to_s

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
          parent = CustomField.find_by(id: parent_id.to_i, type: custom_field.type)
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
      parent_reference = RedmineDependingCustomFields::ParentReference.from_custom_field(custom_field)
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
      raw = super(custom_field, query)
      parent_reference = RedmineDependingCustomFields::ParentReference.from_custom_field(custom_field)
      return raw unless parent_reference&.type == 'custom_field' && parent_reference.enumerated?

      project = query&.project
      return raw unless project

      parent_values = Array(project.custom_field_value(parent_reference.custom_field)).map(&:to_s)
      mapping = custom_field.value_dependencies || {}
      allowed = parent_values.flat_map { |pv| Array(mapping[pv]) }.map(&:to_s).uniq

      raw.flat_map do |opt|
        if opt.is_a?(Array) && opt[1].is_a?(Array)
          opt[1].map { |lbl, val| [lbl, val.to_s] if val.present? && (allowed.empty? || allowed.include?(val.to_s)) }.compact
        else
          lbl, val = opt.is_a?(Array) ? opt.take(2) : [opt, opt]
          [[lbl, val.to_s]] if val.present? && (allowed.empty? || allowed.include?(val.to_s))
        end
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

      # meerdere keywords opsplitsen op komma, puntkomma of nieuwe regel
      keywords = if custom_field.multiple?
                   keyword.split(/[;,]/).map(&:strip).reject(&:blank?)
                 else
                   [keyword.strip]
                 end

      # Zoek per keyword naar een optie.  We bewaren alleen de id-kolom (opt[1]).
      matched = keywords.filter_map do |kw|
        hit = opts.find do |opt|
          label, _val = opt.is_a?(Array) ? opt.take(2) : [opt, opt]
          label.to_s.strip.casecmp?(kw)
        end
        # Enumeration-veld: altijd de value-kolom (id) nemen
        hit.is_a?(Array) ? hit[1] : hit
      end

      if custom_field.multiple?
        matched.presence
      else
        matched.first
      end
    end
  end
end
