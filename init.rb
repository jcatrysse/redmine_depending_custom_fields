require_relative 'lib/redmine_depending_custom_fields'
require_relative 'lib/redmine_depending_custom_fields/patches/custom_field_patch'
require_relative 'lib/redmine_depending_custom_fields/patches/custom_field_validation_patch'
require_relative 'lib/redmine_depending_custom_fields/patches/context_menus_controller_patch'
require_relative 'lib/redmine_depending_custom_fields/patches/issue_import_patch'
require_relative 'lib/redmine_depending_custom_fields/patches/issue_validation_patch'
require_relative 'lib/redmine_depending_custom_fields/patches/project_validation_patch'
require_relative 'lib/redmine_depending_custom_fields/patches/projects_helper_patch'
require_relative 'lib/redmine_depending_custom_fields/hooks/context_menu_hook'
require_relative 'lib/redmine_depending_custom_fields/hooks/custom_field_storage_hook'
require_relative 'lib/redmine_depending_custom_fields/hooks/read_only_carrier_hook'

Redmine::Plugin.register :redmine_depending_custom_fields do
  name 'Redmine Depending Custom Fields'
  author 'Jan Catrysse'
  description 'Provides depending / cascading custom field formats.'
  url 'https://github.com/jcatrysse/redmine_depending_custom_fields'
  version '0.0.16'
  requires_redmine version_or_higher: '5.0'

  settings default: { 'manage_standard_custom_fields' => true,
                      'block_removal_when_used' => false },
           partial: 'settings/dcf_project_config'
end

# Project-level custom field configuration permission. Module-independent (not
# inside a project_module block) so administrators always have access; admins
# pass allowed_to? unconditionally. read: true keeps the tab/overview/audit
# reachable on closed/archived projects — the read/write boundary is enforced
# by the controller's require_active_project guard. require: :member prevents
# granting it to the Non member / Anonymous roles. See Permissions Spec §4.
Redmine::AccessControl.map do |map|
  map.permission :manage_project_custom_field_configuration,
                 { project_custom_field_configuration:
                     %i[index show add_value rename_value remove_value
                        reorder_values update_enumerations set_default_value
                        edit_dependencies update_dependencies audit],
                   # Grant access to the project settings page itself so a
                   # permission holder can reach the tab (mirrors how core
                   # settings-tab permissions list projects/settings).
                   projects: %i[settings] },
                 require: :member,
                 read: true
end

RedmineDependingCustomFields.register_formats
CustomField.safe_attributes(
  'group_ids',
  'exclude_admins',
  'show_active',
  'show_registered',
  'show_locked',
  'parent_custom_field_id',
  'value_dependencies',
  'default_value_dependencies',
  'hide_when_disabled'
)

CustomField.prepend RedmineDependingCustomFields::Patches::CustomFieldPatch
CustomField.prepend RedmineDependingCustomFields::Patches::CustomFieldValidationPatch
# The issue context menu controller was namespaced in Redmine 7.0
# (ContextMenus::IssuesController#index); Redmine 5.x/6.x used the flat
# ContextMenusController#issues. Prepend onto whichever the running version
# provides. Referencing the constant lets Zeitwerk autoload it; the older
# constant does not exist on 7.0, so we try the namespaced one first.
context_menu_controller =
  begin
    ContextMenus::IssuesController
  rescue NameError
    ContextMenusController
  end
context_menu_controller.prepend RedmineDependingCustomFields::Patches::ContextMenusControllerPatch
IssueImport.prepend RedmineDependingCustomFields::Patches::IssueImportPatch
# WP-09b (UD-07): Issue and Project are the only customizables that override
# validate_custom_field_values to skip values the user cannot edit (Redmine
# 5.1 to 7.0, same constants everywhere). The patches add the dependency
# check for those values; the other customizables already validate every
# value and are not patched. A repeated prepend is a no-op.
Issue.prepend RedmineDependingCustomFields::Patches::IssueValidationPatch
Project.prepend RedmineDependingCustomFields::Patches::ProjectValidationPatch
