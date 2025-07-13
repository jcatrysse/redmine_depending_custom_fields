require_relative 'sanitizer'

module RedmineDependingCustomFields
  class DependingListFormat < Redmine::FieldFormat::ListFormat
    add 'depending_list'
    self.form_partial = 'custom_fields/formats/depending_list'
    field_attributes :parent_custom_field_id, :value_dependencies

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
      end
      custom_field.value_dependencies = RedmineDependingCustomFields::Sanitizer.sanitize_dependencies(custom_field.value_dependencies)
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
            pvals = Array(obj.custom_field_value(parent)).map(&:to_s)
            vals = pvals.flat_map { |v| Array(mapping[v]) }.map(&:to_s).uniq
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
    errors << ::I18n.t('activerecord.errors.messages.inclusion') if invalid.any?
    errors
  end

  end
end
