# Hook that loads front-end assets for depending custom fields and exposes the
# dependency mapping via JavaScript. Inserted into the HTML head of every page.
module RedmineDependingCustomFields
  module Hooks
    class ViewLayoutsBaseHtmlHeadHook < Redmine::Hook::ViewListener
      def view_layouts_base_html_head(_context = {})
        mapping = Rails.cache.fetch('depending_custom_fields/mapping') do
          RedmineDependingCustomFields::MappingBuilder.build
        end

        base_path = if ActionController::Base.respond_to?(:relative_url_root)
                      ActionController::Base.relative_url_root.to_s
                    else
                      ''
                    end

        mapping_json = ERB::Util.json_escape(mapping.to_json)

        script = <<~JS.html_safe
          window.DependingCustomFieldData = #{mapping_json};
          window.ContextMenuWizardConfig = #{
            {
              basePath: base_path
            }.to_json
          };
        JS

        javascript_include_tag('depending_custom_fields', plugin: 'redmine_depending_custom_fields') +
          javascript_tag(script) +
          javascript_include_tag('context_menu_wizard', plugin: 'redmine_depending_custom_fields') +
          stylesheet_link_tag('depending_custom_fields', plugin: 'redmine_depending_custom_fields')
      end
    end
  end
end
