require_relative '../rails_helper'

# Changed by the full review of 2026-11-05 (storage-api-boot-1): the import
# reads the users once per import instead of Principal.detect_by_keyword over
# User.all per token, so this spec runs against a real IssueImport and real
# users (was a stubbed User and Principal). The matching rules are core's.
RSpec.describe RedmineDependingCustomFields::Patches::IssueImportPatch do
  fixtures :users

  let(:project) { dcf_create_project }
  let(:role) { dcf_create_role(permissions: [:view_issues, :add_issues, :edit_issues, :import_issues]) }
  let(:importer) do
    member = dcf_create_user("importer-#{SecureRandom.hex(3)}")
    dcf_add_member(member, project, role)
    member
  end
  let(:tracker) { dcf_issue_infra(project).first }
  let(:jane) do
    user = User.new(login: "jdoe-#{SecureRandom.hex(2)}", firstname: 'Jane', lastname: 'Doe',
                    status: User::STATUS_ACTIVE, admin: false)
    user.mail = "jane-#{SecureRandom.hex(2)}@example.net"
    user.save!(validate: false)
    dcf_add_member(user, project, role)
    user
  end
  let(:field) do
    cf = IssueCustomField.new(name: "EU-#{SecureRandom.hex(3)}", field_format: 'extended_user', is_for_all: true,
                              multiple: true)
    cf.show_active = '1'
    cf.save!
    tracker.custom_fields << cf
    tracker.save!
    cf
  end

  def imported(cell)
    mapping = { 'project_id' => project.id.to_s, 'tracker' => "value:#{tracker.id}", 'subject' => '0',
                "cf_#{field.id}" => '1' }
    import = IssueImport.new(user: importer)
    import.settings = { 'mapping' => mapping }
    allow(User).to receive(:current).and_return(importer)
    import.send(:build_object, ['Imported subject', cell], 1).custom_field_value(field)
  end

  it 'assigns extended user values by full name, login, mail and id, case-insensitively' do
    jane
    expect(imported('Jane Doe')).to eq([jane.id.to_s])
    expect(imported('JANE doe')).to eq([jane.id.to_s])
    expect(imported(jane.login.upcase)).to eq([jane.id.to_s])
    expect(imported(jane.mail.upcase)).to eq([jane.id.to_s])
    expect(imported(jane.id.to_s)).to eq([jane.id.to_s])
    expect(imported("Jane Doe, #{importer.login}")).to eq([jane.id.to_s, importer.id.to_s])
    expect(imported('Nobody Here').reject(&:blank?)).to eq([])
  end
end
