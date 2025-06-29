module RedmineDependingCustomFields
  module Hooks
    class ContextMenuHook < Redmine::Hook::ViewListener
      render_on :view_issues_context_menu_end,
                partial: 'depending_custom_fields/context_menu_wizard'
    end
  end
end
