module RedmineDependingCustomFields
  def self.sanitize_dependencies(hash)
    return {} unless hash.is_a?(Hash)
    hash.each_with_object({}) do |(k, v), h|
      key = k.to_s
      next if key.blank?
      values = Array(v).map(&:to_s).reject(&:blank?)
      h[key] = values if values.any?
    end
  end
  class DependableListFormat < Redmine::FieldFormat::ListFormat
    add 'dependable_list'
    self.form_partial = 'custom_fields/formats/dependable_list'
    field_attributes :parent_custom_field_id, :value_dependencies

    def label
      :label_dependable_list
    end

    def before_custom_field_save(custom_field)
      super
      if custom_field.parent_custom_field_id.present?
        parent = CustomField.find_by(id: custom_field.parent_custom_field_id.to_i,
                                     type: custom_field.type,
                                     field_format: ['list', RedmineDependingCustomFields::FIELD_FORMAT_DEPENDABLE_LIST])
        custom_field.parent_custom_field_id = parent&.id
      end
      custom_field.value_dependencies = RedmineDependingCustomFields.sanitize_dependencies(custom_field.value_dependencies)
    end

    def possible_values_options(custom_field, object = nil)
      single_object = object.is_a?(Array) ? object.first : object
      options = super(custom_field, single_object)
      return options if object.nil?

      if custom_field.parent_custom_field_id.present?
        parent  = CustomField.find_by(id: custom_field.parent_custom_field_id)
        if parent
          mapping = custom_field.value_dependencies || {}
          objects = object.is_a?(Array) ? object : [object]
          allowed = nil
          objects.each do |obj|
            pv = obj.custom_field_value(parent)
            vals = Array(mapping[pv.to_s])
            allowed = allowed.nil? ? vals : allowed & vals
          end
          allowed ||= []
          options = options.map do |opt|
            label, value = opt.is_a?(Array) ? opt.take(2) : [opt, opt]
            if value.blank? || value.to_s == '__none__' || allowed.include?(value.to_s)
              opt
            else
              [label, value, { hidden: true, style: 'display:none;' }]
            end
          end
        end
      end
      options
    end

    def query_filter_values(custom_field, query = nil)
      project = query&.project
      raw     = possible_values_options(custom_field, project)

      [].tap do |flat|
        raw.each do |opt|
          label, value = opt.is_a?(Array) ? opt.take(2) : [opt, opt]
          next if value.blank?
          flat << [label, value.to_s]
        end
      end
    end

    def after_custom_field_save(_custom_field)
      Rails.cache.delete('depending_custom_fields/mapping')
    end

  end

  class DependableEnumerationFormat < Redmine::FieldFormat::EnumerationFormat
    add 'dependable_enumeration'
    self.form_partial = 'custom_fields/formats/dependable_enumeration'
    field_attributes :parent_custom_field_id, :value_dependencies

    def label
      :label_dependable_enumeration
    end

    def before_custom_field_save(custom_field)
      super
      if custom_field.parent_custom_field_id.present?
        parent = CustomField.find_by(id: custom_field.parent_custom_field_id.to_i,
                                     type: custom_field.type,
                                     field_format: ['enumeration', RedmineDependingCustomFields::FIELD_FORMAT_DEPENDABLE_ENUMERATION])
        custom_field.parent_custom_field_id = parent&.id
      end
      custom_field.value_dependencies = RedmineDependingCustomFields.sanitize_dependencies(custom_field.value_dependencies)
    end

    def possible_values_options(custom_field, object = nil)
      single_object = object.is_a?(Array) ? object.first : object
      options = super(custom_field, single_object)
      return options if object.nil?

      return options unless custom_field.parent_custom_field_id.present?

      parent  = CustomField.find_by(id: custom_field.parent_custom_field_id)
      return options unless parent

      mapping = custom_field.value_dependencies || {}
      objects = object.is_a?(Array) ? object : [object]

      allowed = nil
      objects.each do |obj|
        pv = obj.custom_field_value(parent)
        vals = Array(mapping[pv.to_s])
        allowed = allowed.nil? ? vals : allowed & vals
      end

      allowed ||= []
      options.map do |opt|
        label, value = opt.is_a?(Array) ? opt.take(2) : [opt, opt]
        if value.blank? || value.to_s == '__none__' || allowed.include?(value.to_s)
          opt
        else
          [label, value, { hidden: true, style: 'display:none;' }]
        end
      end
    end

    def query_filter_values(custom_field, query = nil)
      project = query&.project
      raw     = super(custom_field, query)

      parent  = CustomField.find_by(id: custom_field.parent_custom_field_id)
      parent_value = project&.custom_field_value(parent)
      mapping = custom_field.value_dependencies || {}
      allowed = Array(mapping[parent_value.to_s])

      [].tap do |flat|
        raw.each do |opt|
          if opt.is_a?(Array) && opt[1].is_a?(Array)
            opt[1].each do |lbl, val|
              next if val.blank?
              next if allowed.any? && !allowed.include?(val.to_s)
              flat << [lbl, val.to_s]
            end
          else
            lbl, val = opt.is_a?(Array) ? opt.take(2) : [opt, opt]
            next if val.blank?
            next if allowed.any? && !allowed.include?(val.to_s)
            flat << [lbl, val.to_s]
          end
        end
      end
    end

    def after_custom_field_save(_custom_field)
      Rails.cache.delete('depending_custom_fields/mapping')
    end

  end
end
