module RedmineDependingCustomFields
  # Detects all parent custom fields that are available for every provided issue.
  class ParentDetector
    PARENT_FORMATS = [
      'list',
      'enumeration',
      RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST,
      RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_ENUMERATION
    ].freeze

    def self.for_issues(issues)
      issues = Array(issues).compact
      return [] if issues.empty?

      mapping = Rails.cache.fetch('depending_custom_fields/mapping') do
        RedmineDependingCustomFields::MappingBuilder.build
      end

      child_ids  = mapping.keys.map(&:to_i)
      parent_ids = mapping.values.select do |info|
        parent_type = info[:parent_type] || 'custom_field'
        parent_format = info[:parent_format]
        parent_type == 'custom_field' &&
          (parent_format.nil? || PARENT_FORMATS.include?(parent_format))
      end.map { |info| info[:parent_id].to_i }.uniq - child_ids
      return [] if parent_ids.empty?

      parents = CustomField.where(id: parent_ids, field_format: PARENT_FORMATS)

      user = User.current
      parents = parents.select do |cf|
        issues.all? do |issue|
          begin
            issue.available_custom_fields.include?(cf) &&
              RedmineDependingCustomFields::CustomFieldVisibility.visible_to_user?(cf, issue.project, user)
          rescue NoMethodError
            true
          end
        end
      end

      parents.sort_by(&:position)
    end
  end
end
