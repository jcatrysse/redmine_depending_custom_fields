module RedmineDependingCustomFields
  # Detects all parent custom fields that are available for every provided issue.
  class ParentDetector
    PARENT_FORMATS = [
      'list',
      'enumeration',
      RedmineDependingCustomFields::FIELD_FORMAT_DEPENDABLE_LIST,
      RedmineDependingCustomFields::FIELD_FORMAT_DEPENDABLE_ENUMERATION
    ].freeze

    def self.for_issues(issues)
      issues = Array(issues).compact
      return [] if issues.empty?

      mapping = Rails.cache.fetch('depending_custom_fields/mapping') do
        RedmineDependingCustomFields::MappingBuilder.build
      end

      child_ids  = mapping.keys.map(&:to_i)
      parent_ids = mapping.values.map { |i| i[:parent_id].to_i }.uniq - child_ids
      return [] if parent_ids.empty?

      parents = CustomField.where(id: parent_ids, field_format: PARENT_FORMATS)

      parents = parents.select do |cf|
        issues.all? do |issue|
          begin
            issue.available_custom_fields.include?(cf)
          rescue NoMethodError
            true
          end
        end
      end

      parents.sort_by(&:position)
    end
  end
end
