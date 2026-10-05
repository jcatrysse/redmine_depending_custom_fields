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
  let(:user) { member_with(role) }

  let(:editable) { dcf_list_field(values: %w[A B]) }
  let(:read_only) { dcf_list_field(values: %w[A B]) }
  let(:hidden) do
    field = dcf_list_field(values: %w[A B])
    field.update!(visible: false, role_ids: [other_role.id])
    field
  end
  let!(:issue) { dcf_real_issue(project, editable => 'A', read_only => 'A', hidden => 'A') }

  before { allow(User).to receive(:current).and_return(user) }

  def member_with(member_role)
    member = dcf_create_user("wizard-#{SecureRandom.hex(3)}")
    dcf_add_member(member, project, member_role)
    member
  end

  def read_only_rule(field, rule_role: role, status_id: issue.status_id)
    WorkflowPermission.create!(tracker_id: issue.tracker_id, old_status_id: status_id,
                               role_id: rule_role.id, field_name: field.id.to_s, rule: 'readonly')
  end

  def post_values(values, issues = [issue])
    post '/depending_custom_fields/save',
         params: { issue_ids: issues.map(&:id).join(','), issue: { custom_field_values: values } }
  end

  def stored(field, target = issue)
    target.reload.custom_field_value(field)
  end

  it 'writes a field the user may edit' do
    post_values(editable.id.to_s => 'B')

    expect(response).to have_http_status(:ok)
    expect(stored(editable)).to eq('B')
  end

  it 'does not write a field that is read-only by workflow for the user' do
    read_only_rule(read_only)
    post_values(read_only.id.to_s => 'B')

    expect(response).to have_http_status(:ok)
    expect(stored(read_only)).to eq('A')
  end

  it 'does not write a field that is not visible for the user role, without any workflow rule' do
    # No WorkflowPermission row exists here: core would otherwise also report
    # role-hidden fields as read-only and mask this case.
    expect(issue.read_only_attribute_names(user)).to be_empty

    post_values(hidden.id.to_s => 'B')

    expect(response).to have_http_status(:ok)
    expect(stored(hidden)).to eq('A')
  end

  it 'writes only the editable field when all three are posted together' do
    read_only_rule(read_only)
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

  it 'writes an editable multi-value field and leaves a read-only one alone' do
    multi = dcf_list_field(values: %w[A B C], multiple: true)
    multi_ro = dcf_list_field(values: %w[A B C], multiple: true)
    # Project#reload clears Redmine's memoized all_issue_custom_fields, so the
    # fields created above are available on the new issue.
    target = dcf_real_issue(project.reload, multi => %w[A], multi_ro => %w[A])
    expect(Array(stored(multi_ro, target))).to eq(%w[A])
    read_only_rule(multi_ro, status_id: target.status_id)

    post_values({ multi.id.to_s => %w[B C], multi_ro.id.to_s => %w[B C] }, [target])

    expect(response).to have_http_status(:ok)
    expect(Array(stored(multi, target)).sort).to eq(%w[B C])
    expect(Array(stored(multi_ro, target))).to eq(%w[A])
  end

  it 'filters per issue when the field is read-only on the first issue only' do
    other_status = IssueStatus.create!(name: "Other-#{SecureRandom.hex(3)}", is_closed: false)
    second = dcf_real_issue(project, editable => 'A')
    Issue.where(id: second.id).update_all(status_id: other_status.id)
    read_only_rule(editable, status_id: issue.status_id)

    post_values({ editable.id.to_s => 'B' }, [issue, second])

    expect(response).to have_http_status(:ok)
    expect(stored(editable, issue)).to eq('A')
    expect(stored(editable, second)).to eq('B')
  end

  it 'filters the legacy fieldId/value parameters the same way' do
    read_only_rule(read_only)
    post '/depending_custom_fields/save', params: { issue_ids: issue.id.to_s, fieldId: read_only.id, value: 'B' }
    expect(stored(read_only)).to eq('A')

    post '/depending_custom_fields/save', params: { issue_ids: issue.id.to_s, fieldId: editable.id, value: 'B' }
    expect(stored(editable)).to eq('B')
  end

  it 'still lets an administrator write a field hidden for the member role' do
    allow(User).to receive(:current).and_return(dcf_admin)

    post_values(hidden.id.to_s => 'B')

    expect(response).to have_http_status(:ok)
    expect(stored(hidden)).to eq('B')
  end

  it 'applies a read-only rule to an administrator when every workflow role has it, like core' do
    Role.all.select(&:consider_workflow?).each { |workflow_role| read_only_rule(read_only, rule_role: workflow_role) }
    allow(User).to receive(:current).and_return(dcf_admin)

    post_values(read_only.id.to_s => 'B')

    expect(response).to have_http_status(:ok)
    expect(stored(read_only)).to eq('A')
  end

  it 'denies a member who may only add notes and writes nothing' do
    allow(User).to receive(:current).and_return(member_with(dcf_create_role(permissions: [:view_issues, :add_notes])))

    post_values(editable.id.to_s => 'B')

    expect(response).to have_http_status(:forbidden)
    expect(stored(editable)).to eq('A')
  end

  it 'denies a member without the edit permission and writes nothing' do
    allow(User).to receive(:current).and_return(member_with(dcf_create_role(permissions: [:view_issues])))

    post_values(editable.id.to_s => 'B')

    expect(response).to have_http_status(:forbidden)
    expect(stored(editable)).to eq('A')
  end
end
