# frozen_string_literal: true

require_relative '../client_config'

# Loads the front-end assets of depending custom fields into the head of
# every page (server design 2.4, WP-18): the dcf-i18n meta tag with the texts
# of the current locale, the runtime, the wizard script and the stylesheet.
# No inline script, no database access and no cache: per-field data comes
# with each rendered field (data-dcf-*, WP-16). On the custom field and
# project custom field configuration pages the dependency editor model,
# script and stylesheet follow (WP-25, editor design 5.1).
module RedmineDependingCustomFields
  module Hooks
    class ViewLayoutsBaseHtmlHeadHook < Redmine::Hook::ViewListener
      PLUGIN = 'redmine_depending_custom_fields'

      def view_layouts_base_html_head(context = {})
        tags = [
          tag.meta(name: ClientConfig::META_NAME, content: ClientConfig.payload.to_json),
          javascript_include_tag('depending_custom_fields', plugin: PLUGIN),
          javascript_include_tag('context_menu_wizard', plugin: PLUGIN),
          stylesheet_link_tag('depending_custom_fields', plugin: PLUGIN)
        ]
        tags.concat(ClientConfig.editor_asset_tags(self)) if ClientConfig.editor_page?((context || {})[:controller])
        safe_join(tags)
      end
    end
  end
end
