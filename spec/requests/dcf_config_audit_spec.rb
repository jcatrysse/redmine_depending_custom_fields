require_relative '../rails_helper'

RSpec.describe 'Global config audit view', type: :request do
  fixtures :users

  let(:project) { dcf_create_project }

  def as(user)
    allow(User).to receive(:current).and_return(user)
  end

  it 'is accessible to an admin (T-SEC-9)' do
    RedmineDependingCustomFields::ConfigAuditEvent.create!(action: 'add_value', status: 'success', created_at: Time.now)
    as(dcf_admin)
    get dcf_config_audit_path
    expect(response).to have_http_status(:ok)
  end

  it 'is forbidden to a non-admin permission holder (T-SEC-9)' do
    as(dcf_manager(project))
    get dcf_config_audit_path
    expect(response).to have_http_status(:forbidden)
  end

  it 'is forbidden to an anonymous-like non-member' do
    as(dcf_create_user('nobody'))
    get dcf_config_audit_path
    expect(response).to have_http_status(:forbidden)
  end
end
