module RedmineDependingCustomFields
  module Hooks
    class ViewLayoutsBaseHtmlHeadHook < Redmine::Hook::ViewListener
      def view_layouts_base_html_head(_context = {})
        mapping = Rails.cache.fetch('depending_custom_fields/mapping') do
          cfs = CustomField.where(field_format: [RedmineDependingCustomFields::FIELD_FORMAT_DEPENDABLE_LIST,
                                                RedmineDependingCustomFields::FIELD_FORMAT_DEPENDABLE_ENUMERATION])
          cfs.each_with_object({}) do |cf, h|
            next unless cf.parent_custom_field_id.present?

            h[cf.id.to_s] = {
              parent_id: cf.parent_custom_field_id.to_s,
              map: RedmineDependingCustomFields.sanitize_dependencies(cf.value_dependencies)
            }
          end
        end

        script = "window.DependingCustomFieldData = #{mapping.to_json};"
        javascript_include_tag('depending_custom_fields', plugin: 'redmine_depending_custom_fields') +
          stylesheet_link_tag('depending_custom_fields', plugin: 'redmine_depending_custom_fields') +
          javascript_tag(script)
      end
    end
  end
end
