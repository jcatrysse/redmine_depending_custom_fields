require_relative 'lib/redmine_depending_custom_fields'
require_relative 'lib/redmine_depending_custom_fields/patches/query_custom_field_column_patch'
require_relative 'lib/redmine_depending_custom_fields/patches/custom_field_patch'
require_relative 'lib/redmine_depending_custom_fields/patches/context_menus_controller_patch'
require_relative 'lib/redmine_depending_custom_fields/patches/issue_import_patch'
require_relative 'lib/redmine_depending_custom_fields/hooks/context_menu_hook'

Redmine::Plugin.register :redmine_depending_custom_fields do
  name 'Redmine Depending Custom Fields'
  author 'Jan Catrysse'
  description 'Provides depending / cascading custom field formats.'
  url 'https://github.com/jcatrysse/redmine_depending_custom_fields'
  version '0.0.6'
  requires_redmine version_or_higher: '5.0'
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
