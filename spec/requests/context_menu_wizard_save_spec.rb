# frozen_string_literal: true

require_relative '../rails_helper'

# SD-01: the context-menu wizard save may only write the custom fields the
# current user may edit on each issue, exactly like core bulk_update does
# through Issue#safe_attributes= (fields visible for the user's roles and not
# read-only by workflow).
RSpec.describe 'Context menu wizard save', type: :request do
  fixtures :users

  let(:project) { dcf_create_project }
  let(:role) { dcf_create_role(permissions: [:view_issues, :edit_issues]) }
  let(:other_role) { dcf_create_role(permissions: [:view_issues, :edit_issues]) }
  let(:user) do
    member = dcf_create_user("wizard-#{SecureRandom.hex(3)}")
    dcf_add_member(member, project, role)
    member
  end

  let(:editable) { dcf_list_field(values: %w[A B]) }
  let(:read_only) { dcf_list_field(values: %w[A B]) }
  let(:hidden) do
    field = dcf_list_field(values: %w[A B])
    field.update!(visible: false, role_ids: [other_role.id])
    field
  end
  let!(:issue) { dcf_real_issue(project, editable => 'A', read_only => 'A', hidden => 'A') }

  before do
    WorkflowPermission.create!(tracker_id: issue.tracker_id, old_status_id: issue.status_id,
                               role_id: role.id, field_name: read_only.id.to_s, rule: 'readonly')
    allow(User).to receive(:current).and_return(user)
  end

  def post_values(values, current_issue = issue)
    post '/depending_custom_fields/save',
         params: { issue_ids: current_issue.id.to_s, issue: { custom_field_values: values } }
  end

  def stored(field)
    issue.reload.custom_field_value(field)
  end

  it 'writes a field the user may edit' do
    post_values(editable.id.to_s => 'B')

    expect(response).to have_http_status(:ok)
    expect(stored(editable)).to eq('B')
  end

  it 'does not write a field that is read-only by workflow for the user' do
    post_values(read_only.id.to_s => 'B')

    expect(response).to have_http_status(:ok)
    expect(stored(read_only)).to eq('A')
  end

  it 'does not write a field that is not visible for the user role' do
    post_values(hidden.id.to_s => 'B')

    expect(response).to have_http_status(:ok)
    expect(stored(hidden)).to eq('A')
  end

  it 'writes only the editable field when all three are posted together' do
    post_values(editable.id.to_s => 'B', read_only.id.to_s => 'B', hidden.id.to_s => 'B')

    expect(response).to have_http_status(:ok)
    expect(stored(editable)).to eq('B')
    expect(stored(read_only)).to eq('A')
    expect(stored(hidden)).to eq('A')
  end

  it 'still clears an editable field with __none__' do
    post_values(editable.id.to_s => '__none__')

    expect(response).to have_http_status(:ok)
    expect(stored(editable)).to be_blank
  end

  it 'still lets an administrator write a field hidden for the member role' do
    allow(User).to receive(:current).and_return(dcf_admin)

    post_values(hidden.id.to_s => 'B')

    expect(response).to have_http_status(:ok)
    expect(stored(hidden)).to eq('B')
  end

  it 'denies a member without the edit permission and writes nothing' do
    viewer_role = dcf_create_role(permissions: [:view_issues])
    viewer = dcf_create_user("viewer-#{SecureRandom.hex(3)}")
    dcf_add_member(viewer, project, viewer_role)
    allow(User).to receive(:current).and_return(viewer)

    post_values(editable.id.to_s => 'B')

    expect(response).to have_http_status(:forbidden)
    expect(stored(editable)).to eq('A')
  end
end
