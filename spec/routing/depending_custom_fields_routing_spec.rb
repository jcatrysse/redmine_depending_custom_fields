# frozen_string_literal: true

require_relative '../rails_helper'

# WP-15: the wizard save route is named explicitly (the name equals the one
# Rails derived from the path before); path, verb and controller are
# unchanged, and the API routes keep the GET paths.
RSpec.describe 'Depending custom fields routes', type: :routing do
  let(:helpers) { Rails.application.routes.url_helpers }
  let(:named) { Rails.application.routes.named_routes[:depending_custom_fields_save] }

  it 'names the POST-only save route depending_custom_fields_save, without a format default' do
    expect(helpers.depending_custom_fields_save_path).to eq('/depending_custom_fields/save')
    expect(post: helpers.depending_custom_fields_save_path).to route_to('context_menu_wizard#save')
    expect(named.verb).to eq('POST')
    expect(named.defaults).to eq(controller: 'context_menu_wizard', action: 'save')
  end

  it 'keeps GET and PUT on the save path for the API and routes no PATCH' do
    expect(get: '/depending_custom_fields/save')
      .to route_to(controller: 'depending_custom_fields_api', action: 'show', id: 'save', format: 'json')
    expect(put: '/depending_custom_fields/save')
      .to route_to(controller: 'depending_custom_fields_api', action: 'update', id: 'save', format: 'json')
    expect(patch: '/depending_custom_fields/save').not_to be_routable
  end

  it 'lets GET options reach the API show action and has no route to context_menu_wizard#options' do
    expect(get: '/depending_custom_fields/options')
      .to route_to(controller: 'depending_custom_fields_api', action: 'show', id: 'options', format: 'json')
    expect(get: '/depending_custom_fields/options.html').not_to be_routable
    expect do
      helpers.url_for(controller: 'context_menu_wizard', action: 'options', only_path: true)
    end.to raise_error(ActionController::UrlGenerationError)
  end
end
