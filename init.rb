require_relative 'lib/redmine_depending_custom_fields'
require_relative 'lib/redmine_depending_custom_fields/patches/query_custom_field_column_patch'
require_relative 'lib/redmine_depending_custom_fields/patches/custom_field_patch'
require_relative 'lib/redmine_depending_custom_fields/patches/context_menus_controller_patch'
require_relative 'lib/redmine_depending_custom_fields/patches/issue_import_patch'
require_relative 'lib/redmine_depending_custom_fields/patches/projects_helper_patch'
require_relative 'lib/redmine_depending_custom_fields/hooks/context_menu_hook'

Redmine::Plugin.register :redmine_depending_custom_fields do
  name 'Redmine Depending Custom Fields'
  author 'Jan Catrysse'
  description 'Provides depending / cascading custom field formats.'
  url 'https://github.com/jcatrysse/redmine_depending_custom_fields'
  version '0.0.12'
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
                        reorder_values set_default_value edit_dependencies
                        update_dependencies audit],
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

QueryCustomFieldColumn.prepend RedmineDependingCustomFields::Patches::QueryCustomFieldColumnPatch
CustomField.prepend RedmineDependingCustomFields::Patches::CustomFieldPatch
ContextMenusController.prepend RedmineDependingCustomFields::Patches::ContextMenusControllerPatch
IssueImport.prepend RedmineDependingCustomFields::Patches::IssueImportPatch
