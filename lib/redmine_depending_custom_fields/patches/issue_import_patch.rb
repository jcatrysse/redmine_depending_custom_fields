module RedmineDependingCustomFields
  module Patches
    module IssueImportPatch
      def build_object(row, item)
        issue = super
        # Fail closed: without the editable filter nothing is written.
        return issue unless issue.respond_to?(:editable_custom_field_values)

        # Same filter as core's Issue#safe_attributes=, which core applies to the
        # other custom fields of this import: only fields the importing user may
        # edit (visible for the user's roles and not read-only by workflow).
        issue.editable_custom_field_values(user).each do |cfv|
          cf = cfv.custom_field
          next unless cf.field_format == RedmineDependingCustomFields::FIELD_FORMAT_EXTENDED_USER

          raw = row_value(row, "cf_#{cf.id}")
          next if raw.blank?

          users = raw.to_s.split(',').map do |token|
            keyword = token.strip
            next if keyword.blank?

            found = Principal.detect_by_keyword(User.all, keyword)
            found ||= User.find_by_id(keyword.to_i)
            found&.id&.to_s
          end.compact

          cfv.value = cf.multiple? ? users : users.first
        end

        issue
      end
    end
  end
end
