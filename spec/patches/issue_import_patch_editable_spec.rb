# frozen_string_literal: true

require_relative '../rails_helper'

# SD-13: the extended_user import patch may only write the custom fields the
# importing user may edit, the same filter core's Issue#safe_attributes= applies
# to every other custom field of the import (visible for the user's roles and
# not read-only by workflow).
RSpec.describe 'IssueImportPatch editable filter', type: :model do
  fixtures :users

  let(:project) { dcf_create_project }
  let(:role) { dcf_create_role(permissions: [:view_issues, :add_issues, :edit_issues, :import_issues]) }
  let(:other_role) { dcf_create_role(permissions: [:view_issues, :add_issues]) }
  let(:importer) do
    member = dcf_create_user("importer-#{SecureRandom.hex(3)}")
    dcf_add_member(member, project, role)
    member
  end
  let(:target) do
    member = dcf_create_user("target-#{SecureRandom.hex(3)}")
    dcf_add_member(member, project, other_role)
    member
  end
  let(:infra) { dcf_issue_infra(project) }
  let(:tracker) { infra[0] }
  let(:status) { infra[1] }

  def extended_user_field(attributes = {})
    field = IssueCustomField.new({ name: "EU-#{SecureRandom.hex(3)}", field_format: 'extended_user',
                                   is_for_all: true }.merge(attributes))
    field.show_active = '1'
    field.save!
    tracker.custom_fields << field
    tracker.save!
    field
  end

  def build_issue(fields)
    mapping = { 'project_id' => project.id.to_s, 'tracker' => "value:#{tracker.id}", 'subject' => '0' }
    row = ['Imported subject']
    fields.each_with_index do |field, index|
      mapping["cf_#{field.id}"] = (index + 1).to_s
      row << target.login
    end
    import = IssueImport.new(user: importer)
    import.settings = { 'mapping' => mapping }
    allow(User).to receive(:current).and_return(importer)
    import.send(:build_object, row, 1)
  end

  it 'writes an extended_user field the importing user may edit' do
    editable = extended_user_field
    issue = build_issue([editable])

    expect(issue.custom_field_value(editable)).to eq(target.id.to_s)
  end

  it 'does not write an extended_user field hidden for the importing user role' do
    editable = extended_user_field
    hidden = extended_user_field(visible: false, role_ids: [other_role.id])
    issue = build_issue([editable, hidden])

    expect(issue.read_only_attribute_names(importer)).to be_empty
    expect(issue.custom_field_value(editable)).to eq(target.id.to_s)
    expect(issue.custom_field_value(hidden)).to be_blank
  end

  it 'does not write an extended_user field that is read-only by workflow for the importer' do
    editable = extended_user_field
    read_only = extended_user_field
    WorkflowPermission.create!(tracker_id: tracker.id, old_status_id: status.id, role_id: role.id,
                               field_name: read_only.id.to_s, rule: 'readonly')
    issue = build_issue([editable, read_only])

    expect(issue.custom_field_value(editable)).to eq(target.id.to_s)
    expect(issue.custom_field_value(read_only)).to be_blank
  end
end
