RedmineApp::Application.routes.draw do
  match 'dependable_custom_fields', :to => 'dependable_custom_fields_api#index', :via => :get, :format => 'json'
  match 'dependable_custom_fields/:id', :to => 'dependable_custom_fields_api#show', :via => :get, :format => 'json'
  match 'dependable_custom_fields', :to => 'dependable_custom_fields_api#create', :via => :post, :format => 'json'
  match 'dependable_custom_fields/:id', :to => 'dependable_custom_fields_api#update', :via => :put, :format => 'json'
  match 'dependable_custom_fields/:id', :to => 'dependable_custom_fields_api#destroy', :via => :delete, :format => 'json'
end
