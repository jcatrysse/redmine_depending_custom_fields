# frozen_string_literal: true

require_relative '../rails_helper'

# Full branch review of 2026-11-05 (docs/reviews/claude-full-review-2026-11-05.md),
# the Extended user format and its import: storage-api-boot-1 to
# storage-api-boot-5.
RSpec.describe 'Full review: Extended user', type: :model do
  fixtures :users

  let(:project) { dcf_create_project }
  let(:role) { dcf_create_role(permissions: [:view_issues, :add_issues, :edit_issues, :import_issues]) }
  let(:importer) do
    member = dcf_create_user("importer-#{SecureRandom.hex(3)}")
    dcf_add_member(member, project, role)
    member
  end
  let(:target) do
    member = dcf_create_user("target-#{SecureRandom.hex(3)}")
    dcf_add_member(member, project, role)
    member
  end
  let(:infra) { dcf_issue_infra(project) }
  let(:tracker) { infra[0] }

  def extended_user_field(attributes = {})
    field = IssueCustomField.new({ name: "EU-#{SecureRandom.hex(3)}", field_format: 'extended_user',
                                   is_for_all: true }.merge(attributes))
    field.show_active = '1' unless attributes.key?(:show_active)
    field.save!
    tracker.custom_fields << field
    tracker.save!
    field
  end

  def import_for(field)
    mapping = { 'project_id' => project.id.to_s, 'tracker' => "value:#{tracker.id}", 'subject' => '0',
                "cf_#{field.id}" => '1' }
    import = IssueImport.new(user: importer)
    import.settings = { 'mapping' => mapping }
    allow(User).to receive(:current).and_return(importer)
    import
  end

  def build(import, cell)
    import.send(:build_object, ['Imported subject', cell], 1)
  end

  def users_queries(&block)
    statements = []
    callback = ->(*, payload) { statements << payload[:sql].to_s unless payload[:name].to_s == 'SCHEMA' }
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &block)
    statements.grep(/FROM ["`]?(users|email_addresses)["`]?/i).size
  end

  # storage-api-boot-1: the candidate users are read once per import, not
  # once per token, and not one mail query per user.
  describe 'resolving a full name in an import' do
    it 'reads the users once per import whatever their number' do
      field = extended_user_field
      import = import_for(field)
      name = "#{target.firstname} #{target.lastname}"
      expect(build(import, name).custom_field_value(field)).to eq(target.id.to_s)
      second = users_queries { build(import, name) }

      5.times { |i| dcf_create_user("extra-#{i}-#{SecureRandom.hex(2)}") }
      fresh = import_for(field)
      few = users_queries { build(fresh, name) }
      10.times { |i| dcf_create_user("more-#{i}-#{SecureRandom.hex(2)}") }
      again = import_for(field)
      many = users_queries { build(again, name) }

      expect(many).to eq(few)
      expect(second).to be < few
    end
  end

  # storage-api-boot-2: a number followed by text is not an id.
  describe 'a cell that starts with a number' do
    it 'selects no user for a number followed by text and the user for a plain id' do
      field = extended_user_field
      import = import_for(field)
      expect(build(import, "#{target.id} Nobody Known").custom_field_value(field)).to be_blank
      expect(build(import, target.id.to_s).custom_field_value(field)).to eq(target.id.to_s)
    end
  end

  # storage-api-boot-3: validation checks the submitted ids, it does not
  # build the whole option list. As an administrator, so the list is not
  # limited by Users visibility.
  describe 'validation' do
    before { allow(User).to receive(:current).and_return(dcf_admin) }

    it 'does not load every selectable user to validate one value' do
      field = extended_user_field
      5.times { |i| dcf_create_user("pool-#{i}-#{SecureRandom.hex(2)}") }
      value = CustomFieldValue.new(custom_field: CustomField.find(field.id), customized: Issue.new, value: target.id.to_s)
      loaded = 0
      callback = ->(*, payload) { loaded += payload[:record_count].to_i if payload[:class_name] == 'User' }
      errors = nil
      ActiveSupport::Notifications.subscribed(callback, 'instantiation.active_record') do
        errors = field.format.validate_custom_value(value)
      end
      expect(errors).to eq([])
      expect(loaded).to be <= 1
    end

    it 'refuses an unknown id, a locked user when only active users are offered and a group marker' do
      field = extended_user_field
      locked = dcf_create_user("locked-#{SecureRandom.hex(2)}")
      locked.update_column(:status, User::STATUS_LOCKED)
      inclusion = [I18n.t('activerecord.errors.messages.inclusion')]
      ['999999999', locked.id.to_s, '__group_active__', "#{target.id}x"].each do |raw|
        value = CustomFieldValue.new(custom_field: CustomField.find(field.id), customized: Issue.new, value: raw)
        expect(field.format.validate_custom_value(value)).to eq(inclusion), raw
      end
    end

    it 'keeps a stored value that is no longer offered' do
      field = extended_user_field
      locked = dcf_create_user("locked-#{SecureRandom.hex(2)}")
      locked.update_column(:status, User::STATUS_LOCKED)
      value = CustomFieldValue.new(custom_field: CustomField.find(field.id), customized: Issue.new)
      value.value_was = locked.id.to_s
      value.value = locked.id.to_s
      expect(field.format.validate_custom_value(value)).to eq([])
    end
  end

  # storage-api-boot-4: a viewer sees only the users core lets the viewer see.
  describe 'users the viewer may not see' do
    let(:viewer) do
      limited = dcf_create_role(permissions: [:view_issues, :edit_issues])
      limited.update!(users_visibility: 'members_of_visible_projects')
      member = dcf_create_user("viewer-#{SecureRandom.hex(3)}")
      dcf_add_member(member, project, limited)
      member
    end
    let(:stranger) { dcf_create_user("stranger-#{SecureRandom.hex(3)}") }

    it 'are not offered, not listed in filters and not accepted' do
      field = extended_user_field
      target
      stranger
      allow(User).to receive(:current).and_return(viewer)
      record = CustomField.find(field.id)

      offered = record.format.possible_values_options(record).map { |option| option[1].to_s }
      filtered = record.format.query_filter_values(record, nil).map { |option| option[1].to_s }
      expect(offered).to include(target.id.to_s, viewer.id.to_s)
      expect(offered).not_to include(stranger.id.to_s)
      expect(filtered).to include(target.id.to_s)
      expect(filtered).not_to include(stranger.id.to_s)
      value = CustomFieldValue.new(custom_field: record, customized: Issue.new, value: stranger.id.to_s)
      expect(record.format.validate_custom_value(value)).to eq([I18n.t('activerecord.errors.messages.inclusion')])

      allow(User).to receive(:current).and_return(dcf_admin)
      expect(record.format.possible_values_options(record).map { |option| option[1].to_s }).to include(stranger.id.to_s)
    end
  end

  # storage-api-boot-5: a field saved without show_active lists active users.
  describe 'a field created without show_active' do
    it 'stores show_active as true and lists active users' do
      field = IssueCustomField.new(name: "EU-#{SecureRandom.hex(3)}", field_format: 'extended_user', is_for_all: true)
      field.save!
      target
      record = CustomField.find(field.id)
      expect(record.show_active).to be(true)
      expect(record.format.possible_values_options(record).map { |option| option[1].to_s }).to include(target.id.to_s)
    end

    it 'keeps an explicit false' do
      field = IssueCustomField.new(name: "EU-#{SecureRandom.hex(3)}", field_format: 'extended_user', is_for_all: true)
      field.show_active = '0'
      field.save!
      expect(CustomField.find(field.id).show_active).to be(false)
    end
  end
end
