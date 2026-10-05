# frozen_string_literal: true

require_relative '../rails_helper'

# SD-14: the context menu wizard 'options' action had no client and no
# visibility or edit check, and was reachable over non-JSON formats because
# the API routes only accept json. It is removed; only the wizard save stays.
RSpec.describe 'Context menu wizard options endpoint (SD-14)', type: :request do
  fixtures :users

  let(:project) { dcf_create_project }
  let(:parent) { dcf_list_field(name: 'Secret parent', values: %w[Alpha Beta]) }
  let(:child) do
    field = dcf_list_field(format: 'depending_list', name: 'Secret child', values: %w[a1 b1], parent: parent)
    dcf_set_dependencies(field, value_dependencies: { 'Alpha' => %w[a1], 'Beta' => %w[b1] })
  end
  let(:outsider) { dcf_create_user("outsider-#{SecureRandom.hex(3)}") }
  let!(:issue) { dcf_real_issue(project, parent => 'Alpha', child => 'a1') }

  before do
    project.update_column(:is_public, false)
    allow(User).to receive(:current).and_return(outsider)
  end

  %w[html js xml].each do |ext|
    it "answers 404 without field data for /depending_custom_fields/options.#{ext}" do
      expect(issue.reload.visible?(outsider)).to be false

      get "/depending_custom_fields/options.#{ext}", params: { issue_ids: issue.id.to_s }

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include('Secret parent')
      expect(response.body).not_to include('Secret child')
    end

    it "answers 404 for the child options query over .#{ext}" do
      get "/depending_custom_fields/options.#{ext}",
          params: { issue_ids: issue.id.to_s, parent_id: parent.id.to_s, parent_value: 'Alpha' }

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include('Secret child')
    end
  end

  it 'routes no format of the options path to the wizard controller' do
    %w[/depending_custom_fields/options /depending_custom_fields/options.html
       /depending_custom_fields/options.js /depending_custom_fields/options.json].each do |path|
      recognized = begin
        Rails.application.routes.recognize_path(path, method: :get)
      rescue ActionController::RoutingError
        {}
      end
      expect(recognized[:controller]).not_to eq('context_menu_wizard'), path
    end
  end

  it 'keeps the wizard save route' do
    expect(Rails.application.routes.recognize_path('/depending_custom_fields/save', method: :post))
      .to include(controller: 'context_menu_wizard', action: 'save')
  end
end
