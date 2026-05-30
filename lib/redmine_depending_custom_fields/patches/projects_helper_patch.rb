module RedmineDependingCustomFields
  module Patches
    # Appends the "Custom field configuration" tab to Project → Settings.
    # Uses alias_method (NOT prepend, per the environment requirement). The tab
    # is added only when the current user holds the project permission; admins
    # always do (module-independent permission). See Integration Spec §4.
    module ProjectsHelperPatch
      def self.included(base)
        # Make the dcf_* view helpers available where the settings tab partial
        # is rendered (the ProjectsController settings view uses ProjectsHelper).
        base.include(ProjectCustomFieldConfigurationHelper)

        base.class_eval do
          alias_method :project_settings_tabs_without_dcf, :project_settings_tabs

          def project_settings_tabs
            tabs = project_settings_tabs_without_dcf
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
  end
end

ProjectsHelper.include(RedmineDependingCustomFields::Patches::ProjectsHelperPatch)
