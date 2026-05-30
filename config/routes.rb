RedmineApp::Application.routes.draw do
  match 'depending_custom_fields', :to => 'depending_custom_fields_api#index', :via => :get, :format => 'json'
  match 'depending_custom_fields/:id', :to => 'depending_custom_fields_api#show', :via => :get, :format => 'json'
  match 'depending_custom_fields', :to => 'depending_custom_fields_api#create', :via => :post, :format => 'json'
  match 'depending_custom_fields/:id', :to => 'depending_custom_fields_api#update', :via => :put, :format => 'json'
  match 'depending_custom_fields/:id', :to => 'depending_custom_fields_api#destroy', :via => :delete, :format => 'json'
  match 'depending_custom_fields/options', to: 'context_menu_wizard#options', via: :get
  match 'depending_custom_fields/save',    to: 'context_menu_wizard#save',    via: :post

  # Project-level custom field configuration (HTML only; no API auth).
  scope 'projects/:project_id' do
    get    'custom_field_configuration',
           to: 'project_custom_field_configuration#index',
           as: 'custom_field_configuration'
    get    'custom_field_configuration/audit',
           to: 'project_custom_field_configuration#audit',
           as: 'custom_field_configuration_audit'
    get    'custom_field_configuration/fields/:field_id',
           to: 'project_custom_field_configuration#show',
           as: 'custom_field_configuration_field'
    post   'custom_field_configuration/fields/:field_id/values',
           to: 'project_custom_field_configuration#add_value',
           as: 'custom_field_configuration_add_value'
    patch  'custom_field_configuration/fields/:field_id/values/rename',
           to: 'project_custom_field_configuration#rename_value',
           as: 'custom_field_configuration_rename_value'
    delete 'custom_field_configuration/fields/:field_id/values',
           to: 'project_custom_field_configuration#remove_value',
           as: 'custom_field_configuration_remove_value'
    patch  'custom_field_configuration/fields/:field_id/values/reorder',
           to: 'project_custom_field_configuration#reorder_values',
           as: 'custom_field_configuration_reorder_values'
    patch  'custom_field_configuration/fields/:field_id/default_value',
           to: 'project_custom_field_configuration#set_default_value',
           as: 'custom_field_configuration_set_default_value'
    get    'custom_field_configuration/fields/:field_id/dependencies',
           to: 'project_custom_field_configuration#edit_dependencies',
           as: 'custom_field_configuration_field_dependencies'
    patch  'custom_field_configuration/fields/:field_id/dependencies',
           to: 'project_custom_field_configuration#update_dependencies',
           as: 'custom_field_configuration_update_dependencies'
  end

  # Admin-only global audit view (read-only). Separate controller guarded by
  # require_admin — NOT the project permission.
  get 'dcf_config_audit', to: 'dcf_config_audit#index', as: 'dcf_config_audit'
end
