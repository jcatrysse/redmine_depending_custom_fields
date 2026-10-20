# Helper methods to determine whether a custom field is visible for a
# given user. The logic mirrors Redmine's own checks but falls back to
# `true` when required associations are missing.
#
# Deprecated in 0.1.0: the plugin no longer calls it (the context menu
# wizard uses core visible_by? and fails closed since WP-15). Kept unchanged
# at least throughout 0.1.x, removable no earlier than 0.2.0.
#
# Example:
#   if CustomFieldVisibility.visible_to_user?(cf, project, current_user)
#     # show field
#   end
module RedmineDependingCustomFields
  module CustomFieldVisibility
    module_function

    # Returns true if the custom field is visible to the user on the given project
    def visible_to_user?(custom_field, project, user = User.current)
      return true if user.admin?
      return true if custom_field.visible?

      role_ids = Array(custom_field.role_ids)
      return false if role_ids.empty?

      user_role_ids = Array(user.roles_for_project(project)).map(&:id)
      (role_ids & user_role_ids).any?
    rescue NoMethodError
      # In case roles or project are not available, assume it's visible
      true
    end
  end
end
