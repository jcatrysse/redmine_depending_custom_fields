require_relative 'lib/redmine_depending_custom_fields'
require_relative 'lib/redmine_depending_custom_fields/patches/query_custom_field_column_patch'
require_relative 'lib/redmine_depending_custom_fields/patches/custom_field_patch'

Redmine::Plugin.register :redmine_depending_custom_fields do
  name 'Redmine Depending Custom Fields'
  author 'Jan Catrysse'
  description 'Provides depending / cascading custom field formats that can be toggled via plugin settings.'
  url 'https://github.com/jcatrysse/redmine_depending_custom_fields'
  version '0.0.1'
  requires_redmine version_or_higher: '5.0'
end

Rails.configuration.to_prepare do
  RedmineDependingCustomFields.register_formats
end

CustomField.safe_attributes(
  'group_ids',
  'exclude_admins',
  'show_active',
  'show_registered',
  'show_locked',
  'parent_custom_field_id',
  'value_dependencies'
)

