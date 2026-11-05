# frozen_string_literal: true

require_relative '../rails_helper'

# Full branch review of 2026-11-05 (docs/reviews/claude-full-review-2026-11-05.md),
# the context-menu wizard: context-menu-1 to context-menu-4.
RSpec.describe 'Full review: context-menu wizard', type: :request do
  fixtures :users

  let(:project) { dcf_create_project }
  let(:role) { dcf_create_role(permissions: [:view_issues, :edit_issues]) }
  let(:user) do
    member = dcf_create_user("cm-#{SecureRandom.hex(3)}")
    dcf_add_member(member, project, role)
    member
  end
  let(:parent) { dcf_list_field(values: %w[none low high], name: "Level-#{SecureRandom.hex(3)}") }
  let(:child) do
    field = dcf_list_field(format: 'depending_list', values: %w[c1 c2], parent: parent,
                           name: "Sub-#{SecureRandom.hex(3)}")
    dcf_set_dependencies(field, value_dependencies: { 'none' => %w[c1], 'low' => %w[c1], 'high' => %w[c2] })
  end
  let!(:issue) { dcf_real_issue(project, parent => 'low', child => 'c1') }

  before { allow(User).to receive(:current).and_return(user) }

  def post_values(values, issues = [issue])
    post '/depending_custom_fields/save',
         params: { issue_ids: issues.map(&:id).join(','), issue: { custom_field_values: values } }
  end

  # context-menu-1: only core's __none__ marker clears a field.
  it 'saves a value named none and clears with __none__' do
    post_values(parent.id.to_s => 'none')
    expect(response).to have_http_status(:ok)
    expect(issue.reload.custom_field_value(parent)).to eq('none')

    post_values(parent.id.to_s => '__none__', child.id.to_s => '__none__')
    expect(response).to have_http_status(:ok)
    expect(issue.reload.custom_field_value(parent)).to be_blank
  end

  it 'saves none in a multi-value field and in the legacy fieldId parameters' do
    multi = dcf_list_field(values: %w[none other], multiple: true, name: "Multi-#{SecureRandom.hex(3)}")
    target = dcf_real_issue(project, multi => %w[other])
    post_values({ multi.id.to_s => %w[none] }, [target])
    expect(target.reload.custom_field_value(multi)).to eq(%w[none])

    post '/depending_custom_fields/save', params: { issue_ids: issue.id.to_s, fieldId: parent.id.to_s, value: 'none' }
    expect(issue.reload.custom_field_value(parent)).to eq('none')
  end

  # context-menu-2: journaled like core bulk edit.
  it 'records the change in the issue history' do
    expect { post_values(parent.id.to_s => 'high', child.id.to_s => 'c2') }.to change { issue.journals.count }.by(1)

    journal = issue.journals.order(:id).last
    expect(journal.user).to eq(user)
    expect(journal.details.map { |d| [d.property, d.prop_key, d.old_value, d.value] })
      .to contain_exactly(['cf', parent.id.to_s, 'low', 'high'], ['cf', child.id.to_s, 'c1', 'c2'])
  end

  # context-menu-4: each error names its issue.
  it 'names the issue in each error' do
    second = dcf_real_issue(project, parent => 'low', child => 'c1')
    post_values({ parent.id.to_s => 'high' }, [issue, second])

    expect(response).to have_http_status(:unprocessable_entity)
    errors = JSON.parse(response.body)['errors']
    expect(errors).to eq(["##{issue.id}: #{child.name} #{I18n.t('activerecord.errors.messages.invalid')}",
                          "##{second.id}: #{child.name} #{I18n.t('activerecord.errors.messages.invalid')}"])
  end

  # context-menu-3: the tracker-specific edit permission, as core's menu.
  describe 'a role that may edit only another tracker' do
    let(:other_tracker) { dcf_tracker }

    before do
      project.trackers << other_tracker
      role.set_permission_trackers(:edit_issues, [other_tracker.id])
      role.save!
      child
    end

    it 'offers no wizard entry and refuses the wizard body' do
      expect(issue.attributes_editable?(user)).to be(false)

      post '/issues/context_menu', params: { ids: [issue.id] }
      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).css('li.folder.cf-parent')).to be_empty

      dcf_get_wizard(parent.id, [issue.id])
      expect(response).to have_http_status(:forbidden)
    end
  end
end
