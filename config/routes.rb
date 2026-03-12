RedmineApp::Application.routes.draw do
  match 'depending_custom_fields/options', to: 'context_menu_wizard#options', via: :get
  match 'depending_custom_fields/save',    to: 'context_menu_wizard#save',    via: :post
  match 'depending_custom_fields', :to => 'depending_custom_fields_api#index', :via => :get, :format => 'json'
  match 'depending_custom_fields/:id', :to => 'depending_custom_fields_api#show', :via => :get, :format => 'json'
  match 'depending_custom_fields', :to => 'depending_custom_fields_api#create', :via => :post, :format => 'json'
  match 'depending_custom_fields/:id', :to => 'depending_custom_fields_api#update', :via => :put, :format => 'json'
  match 'depending_custom_fields/:id', :to => 'depending_custom_fields_api#destroy', :via => :delete, :format => 'json'
end
