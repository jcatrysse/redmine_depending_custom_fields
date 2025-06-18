require_relative 'lib/redmine_depending_custom_fields'

Redmine::Plugin.register :redmine_depending_custom_fields do
  name 'Depending Custom Fields'
  author 'ChatGPT'
  description 'Provides additional custom field formats that can be toggled via plugin settings.'
  version RedmineDependingCustomFields::VERSION
  requires_redmine version_or_higher: '5.1'
  settings default: { 'enabled_formats' => [RedmineDependingCustomFields::FIELD_FORMAT_USER] },
           partial: 'settings/depending_custom_fields_settings'
end

Rails.configuration.to_prepare do
  RedmineDependingCustomFields.register_formats
end
