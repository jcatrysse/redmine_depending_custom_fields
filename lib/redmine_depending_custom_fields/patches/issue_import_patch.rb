require_dependency 'issue_import'

module RedmineDependingCustomFields
  module Patches
    module IssueImportPatch
      def build_object(row, item)
        issue = super
        return issue unless issue.respond_to?(:custom_field_values)

        issue.custom_field_values.each do |cfv|
          cf = cfv.custom_field
          next unless cf.field_format == RedmineDependingCustomFields::FIELD_FORMAT_EXTENDED_USER

          raw = row_value(row, "cf_#{cf.id}")
          next if raw.blank?

          users = raw.to_s.split(',').map do |token|
            keyword = token.strip
            next if keyword.blank?

            user = Principal.detect_by_keyword(User.all, keyword)
            user ||= User.find_by_id(keyword.to_i)
            user&.id&.to_s
          end.compact

          cfv.value = cf.multiple? ? users : users.first
        end

        issue
      end
    end
  end
end
