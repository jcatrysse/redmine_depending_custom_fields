module RedmineDependingCustomFields
  module Patches
    # Appends the "Custom field configuration" tab to Project → Settings.
    # Prepended, not alias_method: other plugins (redmine_agile, redmine_contacts)
    # prepend on project_settings_tabs too, and an alias_method chain taken after
    # their prepend captures their method instead of core's, and the settings
    # page raised NoMethodError (super: no superclass method). Prepending chains
    # through super in any load order and is a no-op when applied twice. The tab
    # is added only when the current user holds the project permission; admins
    # always do (module-independent permission). See Integration Spec §4.
    module ProjectsHelperPatch
      def project_settings_tabs
        tabs = super
        if User.current.allowed_to?(:manage_project_custom_field_configuration, @project)
          tabs << {
            name:    'custom_field_configuration',
            action:  :manage_project_custom_field_configuration,
            partial: 'project_custom_field_configuration/settings_tab',
            label:   :label_project_custom_field_configuration
          }
        end
        tabs
      end
    end
  end
end

# Make the dcf_* view helpers available where the settings tab partial is
# rendered. Including them into ProjectsHelper alone is not enough: a plugin
# that loads ProjectsController first (redmine_custom_workflows calls
# ProjectsController.helper in its init) leaves ProjectsController::HelperMethods
# without them, and the tab partial raised NoMethodError
# (dcf_relevant_custom_fields). Registering them on the controller itself works
# in any load order.
ProjectsHelper.include(ProjectCustomFieldConfigurationHelper)
ProjectsController.helper(ProjectCustomFieldConfigurationHelper)
ProjectsHelper.prepend(RedmineDependingCustomFields::Patches::ProjectsHelperPatch)
