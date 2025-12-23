# Builds a cached mapping of depending custom fields and their parent
# relationships. The structure is used by hooks and JavaScript to decide which
# fields to display.
#
# The returned hash is keyed by the child field id as a string with the
# following structure:
#   {
#     '31' => { parent_id: '10', map: { 'a' => ['1'] }, defaults: { 'a' => '1' } },
#     '32' => { parent_id: '11', map: { 'b' => ['3'] }, defaults: {} }
#   }
module RedmineDependingCustomFields
  class MappingBuilder
    def self.build
      cfs = CustomField.where(field_format: [
        RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST,
        RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_ENUMERATION
      ])

      mapping = cfs.each_with_object({}) do |cf, h|
        parent_reference = ParentReference.from_custom_field(cf)
        next unless parent_reference

        h[cf.id.to_s] = {
          parent_id: parent_reference.custom_field&.id&.to_s,
          parent_type: parent_reference.type,
          parent_key: parent_reference.key,
          parent_format: parent_reference.format,
          map: RedmineDependingCustomFields::Sanitizer.sanitize_dependencies(cf.value_dependencies),
          defaults: RedmineDependingCustomFields::Sanitizer.sanitize_default_dependencies(cf.default_value_dependencies),
          rules: RedmineDependingCustomFields::Sanitizer.sanitize_dependency_rules(cf.dependency_rules),
          hide_when_disabled: ActiveModel::Type::Boolean.new.cast(cf.hide_when_disabled)
        }
      end

      mapping
    end
  end
end
