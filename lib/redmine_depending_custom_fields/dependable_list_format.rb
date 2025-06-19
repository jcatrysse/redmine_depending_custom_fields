module RedmineDependingCustomFields
  class DependableListFormat < Redmine::FieldFormat::ListFormat
    add 'dependable_list'
    self.form_partial = 'custom_fields/formats/dependable_list'
    field_attributes :parent_custom_field_id

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
    end
  end

  class DependableEnumerationFormat < Redmine::FieldFormat::EnumerationFormat
    add 'dependable_enumeration'
    self.form_partial = 'custom_fields/formats/dependable_enumeration'
    field_attributes :parent_custom_field_id

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
    end
  end
end
