# frozen_string_literal: true

module RedmineDependingCustomFields
  module Hooks
    # Storage usage line on the admin custom field form at 90 percent of a
    # column limit, MySQL only (UD-28). A hint never breaks the form.
    class CustomFieldStorageHook < Redmine::Hook::ViewListener
      def view_custom_fields_form_upper_box(context = {})
        field = context[:custom_field]
        return '' unless field.is_a?(CustomField)

        usage = RedmineDependingCustomFields::StorageLimits.usage(field)
        return '' if usage.empty?

        context[:hook_caller].render(partial: 'custom_fields/dcf_storage_usage',
                                     locals: { usage: usage, admin: true })
      rescue StandardError
        ''
      end
    end
  end
end
