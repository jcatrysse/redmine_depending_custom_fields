# frozen_string_literal: true

require_relative '../rails_helper'

# WP-04 characterization: pins how the context menu wizard routes resolve today
# (0.0.16), including the options route shadowed by depending_custom_fields/:id.
# Only the SD-14 security fix (removes the unused options endpoint) and WP-15
# may change an expectation here, and only as a listed flip.
RSpec.describe 'Context menu wizard routing (characterization)', type: :routing do
  it 'routes GET /depending_custom_fields/options to the API show action with id "options"' do
    expect(get: '/depending_custom_fields/options')
      .to route_to(controller: 'depending_custom_fields_api', action: 'show', id: 'options', format: 'json')
  end

  it 'routes GET /depending_custom_fields/options.json to the same API show action' do
    expect(get: '/depending_custom_fields/options.json')
      .to route_to(controller: 'depending_custom_fields_api', action: 'show', id: 'options', format: 'json')
  end

  it 'does not route the bare options path to context_menu_wizard#options' do
    expect(get: '/depending_custom_fields/options')
      .not_to route_to(controller: 'context_menu_wizard', action: 'options')
  end

  # Flipped by the SD-14 fix: the wizard options route is removed.
  it 'has no route for context_menu_wizard#options (SD-14)' do
    expect do
      Rails.application.routes.url_helpers
           .url_for(controller: 'context_menu_wizard', action: 'options', only_path: true)
    end.to raise_error(ActionController::UrlGenerationError)
  end

  # Flipped by the SD-14 fix: the API routes require format json, and the
  # wizard route that other extensions fell through to is removed.
  it 'does not route the options path with a non-json extension (SD-14)' do
    expect(get: '/depending_custom_fields/options.html').not_to be_routable
    expect(get: '/depending_custom_fields/options.js').not_to be_routable
  end

  it 'routes POST /depending_custom_fields/save to context_menu_wizard#save' do
    expect(post: '/depending_custom_fields/save')
      .to route_to(controller: 'context_menu_wizard', action: 'save')
  end

  it 'routes GET /depending_custom_fields/save to the API show action with id "save"' do
    expect(get: '/depending_custom_fields/save')
      .to route_to(controller: 'depending_custom_fields_api', action: 'show', id: 'save', format: 'json')
  end
end

RSpec.describe 'GET /depending_custom_fields/options requests (characterization)', type: :request do
  fixtures :users

  let(:project) { dcf_create_project }
  let(:parent) { dcf_list_field(name: 'Parent', values: %w[Alpha Beta]) }
  let(:child) do
    field = dcf_list_field(format: 'depending_list', name: 'Child', values: %w[a1 b1], parent: parent)
    dcf_set_dependencies(field, value_dependencies: { 'Alpha' => %w[a1], 'Beta' => %w[b1] })
  end
  let(:outsider) { dcf_create_user("outsider-#{SecureRandom.hex(3)}") }

  def as(user)
    allow(User).to receive(:current).and_return(user)
  end

  def mapping_cache_key
    'depending_custom_fields/mapping'
  end

  before { Rails.cache.delete(mapping_cache_key) }

  after { Rails.cache.delete(mapping_cache_key) }

  it 'answers an administrator with the API 404 JSON body instead of wizard options' do
    child
    as(dcf_admin)

    get '/depending_custom_fields/options'

    expect(response).to have_http_status(:not_found)
    expect(response.media_type).to eq('application/json')
    expect(JSON.parse(response.body)).to eq('errors' => ['Custom field not found'])
  end

  it 'answers a logged-in non-administrator with 403 from the API require_admin' do
    child
    as(outsider)

    get '/depending_custom_fields/options'

    expect(response).to have_http_status(:forbidden)
  end

  # Flipped by the SD-14 fix. Before: reachable through the .html extension,
  # with no edit permission and no issue visibility check (and list options
  # reduced to their last character by map(&:last)).
  it 'answers 404 over .html to a non-member for an issue of a private project (SD-14)' do
    issue = dcf_real_issue(project, parent => 'Alpha', child => 'a1')
    project.update_column(:is_public, false)
    expect(issue.reload.visible?(outsider)).to be false
    as(outsider)

    get '/depending_custom_fields/options.html', params: { issue_ids: issue.id.to_s }

    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include('Parent')
  end
end
