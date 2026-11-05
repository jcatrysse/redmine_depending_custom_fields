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

            found = dcf_detect_user(keyword)
            # Full review of 2026-11-05 (storage-api-boot-2): only a plain
            # number is an id ('42 Jane Roe' is no id 42).
            found ||= User.find_by_id(keyword.to_i) if keyword.match?(/\A\d+\z/)
            found&.id&.to_s
          end.compact

          cfv.value = cf.multiple? ? users : users.first
        end

        issue
      end

      private

      # Core's Principal.detect_by_keyword over every user (login, then mail,
      # then 'firstname lastname', then the name, ASCII case-insensitive as
      # casecmp, the first user wins), from indexes built once per import
      # object (full review of 2026-11-05, storage-api-boot-1: was every user
      # loaded per token and one mail query per user).
      def dcf_detect_user(keyword)
        index = dcf_user_index
        key = keyword.downcase(:ascii)
        found = index[:login][key] || index[:mail][key]
        if found.nil? && keyword.include?(' ')
          firstname, lastname = keyword.split
          found = index[:full]["#{firstname.downcase(:ascii)} #{lastname.to_s.downcase(:ascii)}"]
        end
        found || index[:name][key]
      end

      def dcf_user_index
        @dcf_user_index ||= begin
          index = { login: {}, mail: {}, full: {}, name: {} }
          User.preload(:email_address).find_each do |u|
            index[:login][u.login.to_s.downcase(:ascii)] ||= u
            index[:mail][u.mail.to_s.downcase(:ascii)] ||= u if u.mail.present?
            index[:full]["#{u.firstname.to_s.downcase(:ascii)} #{u.lastname.to_s.downcase(:ascii)}"] ||= u
            index[:name][u.name.to_s.downcase(:ascii)] ||= u
          end
          index
        end
      end
    end
  end
end
