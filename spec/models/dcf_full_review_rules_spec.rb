# frozen_string_literal: true

require_relative '../rails_helper'

# Full branch review of 2026-11-05 (docs/reviews/claude-full-review-2026-11-05.md),
# the server rules: the hidden-child rule on every customizable (rules-1),
# a role-hidden time entry parent on 5.1 and 6.0 (rules-2), the keyword
# lookup cost (rules-3), labels with a comma in imports (rules-4), project
# copies judged against their source (rules-5), the enumeration filter values
# (rules-6) and depending_enumeration copies (admin-editor-3).
RSpec.describe 'Full review: server rules', type: :model do
  include DcfFormatCharacterization

  fixtures :users

  let(:invalid) { I18n.t('activerecord.errors.messages.invalid') }
  let(:hidden_message) { I18n.t('activerecord.errors.messages.dcf_hidden_child_conflict') }
  let(:base_message) { I18n.t('error_dcf_hidden_child_conflict') }
  let(:project) { dcf_create_project }
  let(:other_role) { dcf_create_role(permissions: [:view_issues]) }

  def instantiated(class_name, &block)
    count = 0
    callback = lambda do |*, payload|
      count += payload[:record_count].to_i if payload[:class_name] == class_name
    end
    ActiveSupport::Notifications.subscribed(callback, 'instantiation.active_record', &block)
    count
  end

  # rules-1: core validates every value of these records and names the field
  # it files the error under; a depending child the user cannot see must not
  # be named there either (same placement as NonEditableDependencies).
  describe 'a hidden child on a version (rules-1)' do
    let(:manager) do
      member = dcf_create_user("ver-#{SecureRandom.hex(3)}")
      dcf_add_member(member, project, dcf_create_role(permissions: [:manage_versions]))
      member
    end
    let(:parent) { dcf_list_field(values: %w[A B], type: VersionCustomField, name: "VParent-#{SecureRandom.hex(3)}") }
    let(:child) do
      field = dcf_list_field(format: 'depending_list', values: %w[a1 b1], parent: parent, type: VersionCustomField,
                             name: "VSecret-#{SecureRandom.hex(3)}")
      field = dcf_set_dependencies(field, value_dependencies: { 'A' => %w[a1], 'B' => %w[b1] })
      field.update!(visible: false, role_ids: [other_role.id])
      field
    end
    let(:version) do
      record = Version.new(project: project, name: "V-#{SecureRandom.hex(3)}")
      record.custom_field_values = { parent.id.to_s => 'A', child.id.to_s => 'a1' }
      record.save!(validate: false)
      Version.find(record.id)
    end

    before { allow(User).to receive(:current).and_return(manager) }

    it 'refuses the parent change on the parent field without naming the child' do
      version.safe_attributes = { 'custom_field_values' => { parent.id.to_s => 'B' } }

      expect(version.save).to be(false)
      expect(version.errors[child.name]).to eq([])
      expect(version.errors[parent.name]).to eq([hidden_message])
      expect(version.errors.full_messages.join(' ').downcase).not_to include(child.name.downcase)
      expect(Version.find(version.id).custom_field_value(parent)).to eq('A')
    end

    it 'refuses it on base when the parent is hidden too' do
      parent.update!(visible: false, role_ids: [other_role.id])
      record = Version.find(version.id)
      record.custom_field_values = { parent.id.to_s => 'B' }

      expect(record.valid?).to be(false)
      expect(record.errors.attribute_names).to eq([:base])
      expect(record.errors[:base]).to eq([base_message])
    end

    it 'saves a parent change the hidden child allows' do
      version.custom_field_values = { parent.id.to_s => 'A' }
      expect(version.valid?).to be(true)
    end

    it 'keeps core is invalid under the child name for an administrator' do
      allow(User).to receive(:current).and_return(dcf_admin)
      version.custom_field_values = { parent.id.to_s => 'B' }

      expect(version.valid?).to be(false)
      expect(version.errors[child.name]).to eq([invalid])
    end
  end

  describe 'a hidden child on a user account (rules-1)' do
    let(:parent) { dcf_list_field(values: %w[A B], type: UserCustomField, name: "UParent-#{SecureRandom.hex(3)}") }
    let(:child) do
      field = dcf_list_field(format: 'depending_list', values: %w[a1 b1], parent: parent, type: UserCustomField,
                             name: "USecret-#{SecureRandom.hex(3)}")
      field = dcf_set_dependencies(field, value_dependencies: { 'A' => %w[a1], 'B' => %w[b1] })
      field.update!(visible: false, editable: false)
      field
    end
    # The fields exist before the user: a saved user memoizes the custom
    # field values that are available at its first save.
    let(:account) do
      values = { parent.id.to_s => 'A', child.id.to_s => 'a1' }
      record = User.find(dcf_create_user("acc-#{SecureRandom.hex(3)}").id)
      record.custom_field_values = values
      record.save!(validate: false)
      User.find(record.id)
    end

    it 'refuses a change of the own account without naming the hidden child' do
      allow(User).to receive(:current).and_return(account)
      account.custom_field_values = { parent.id.to_s => 'B' }

      expect(account.valid?).to be(false)
      expect(account.errors[child.name]).to eq([])
      expect(account.errors[parent.name]).to eq([hidden_message])
      expect(account.errors.full_messages.join(' ').downcase).not_to include(child.name.downcase)
    end
  end

  # rules-2: core 5.1 and 6.0 TimeEntry#safe_attributes= drop a parent the
  # user cannot see from custom_field_values; its stored value still counts
  # as the unchanged parent of a visible child. 6.1 and 7.0 keep the value.
  describe 'a time entry child under a parent hidden for the role (rules-2)' do
    let(:te_project) do
      record = dcf_create_project
      record.enabled_module_names = %w[issue_tracking time_tracking]
      record
    end
    let(:role) do
      dcf_create_role(permissions: [:view_time_entries, :log_time, :edit_time_entries, :edit_own_time_entries])
    end
    let(:user) do
      member = dcf_create_user("te-#{SecureRandom.hex(3)}")
      dcf_add_member(member, te_project, role)
      member
    end
    let(:activity) { TimeEntryActivity.create!(name: "Act-#{SecureRandom.hex(3)}", active: true) }
    let(:parent) do
      field = dcf_list_field(values: %w[A B], type: TimeEntryCustomField, name: "TParent-#{SecureRandom.hex(3)}")
      field.update!(visible: false, role_ids: [other_role.id])
      field
    end
    let(:child) do
      field = dcf_list_field(format: 'depending_list', values: %w[a1 a2 b1], parent: parent, type: TimeEntryCustomField,
                             name: "TChild-#{SecureRandom.hex(3)}")
      dcf_set_dependencies(field, value_dependencies: { 'A' => %w[a1 a2], 'B' => %w[b1] })
    end
    let(:entry) do
      record = TimeEntry.new(project: te_project, user: user, author: user, spent_on: Date.new(2026, 1, 1), hours: 1,
                             activity: activity)
      record.custom_field_values = { parent.id.to_s => 'A', child.id.to_s => 'a2' }
      record.save!(validate: false)
      TimeEntry.find(record.id)
    end

    before { allow(User).to receive(:current).and_return(user) }

    it 'saves an edit that keeps the visible child under the unchanged hidden parent' do
      entry.send(:safe_attributes=, { 'hours' => '2', 'custom_field_values' => { child.id.to_s => 'a2' } }, user)
      expect(entry.valid?).to be(true), entry.errors.full_messages.inspect
    end

    it 'saves a new allowed value and refuses one the stored parent value does not allow' do
      entry.send(:safe_attributes=, { 'custom_field_values' => { child.id.to_s => 'a1' } }, user)
      expect(entry.valid?).to be(true), entry.errors.full_messages.inspect

      refused = TimeEntry.find(entry.id)
      refused.send(:safe_attributes=, { 'custom_field_values' => { child.id.to_s => 'b1' } }, user)
      expect(refused.valid?).to be(false)
      expect(refused.errors[child.name]).to eq([invalid])
    end
  end

  # rules-3: one indexed lookup per keyword for an enumeration, never every
  # enumeration row; one label index per record for a list.
  describe 'value_from_keyword cost (rules-3)' do
    let(:names) { Array.new(300) { |i| format('v%03d', i) } }

    it 'does not load every enumeration of a depending_enumeration for each keyword' do
      field = dcf_enum_field(format: 'depending_enumeration', names: names)
      expected = [kit_key(field, 'v150'), kit_key(field, 'v299')]
      record = CustomField.find(field.id)
      found = []
      loaded = instantiated('CustomFieldEnumeration') do
        found << record.format.value_from_keyword(record, 'V150', nil)
        found << record.format.value_from_keyword(record, 'v299', nil)
      end
      expect(found).to eq(expected)
      expect(loaded).to be <= 2
    end

    it 'still matches a folded label through the full list' do
      field = dcf_enum_field(format: 'depending_enumeration', names: %w[Straße other])
      record = CustomField.find(field.id)
      expect(record.format.value_from_keyword(record, 'STRASSE', nil)).to eq(kit_key(field, 'Straße'))
    end

    it 'builds the label index of a depending_list once per record' do
      field = dcf_list_field(format: 'depending_list', values: names)
      record = CustomField.find(field.id)
      allow(record.format).to receive(:possible_values_options).and_call_original
      record.format.value_from_keyword(record, 'v001', nil)
      record.format.value_from_keyword(record, 'v002', nil)
      expect(record.format).to have_received(:possible_values_options).once
    end
  end

  # rules-4: the longest label first, as core parse_keyword does.
  describe 'labels with a comma in a multiple field (rules-4)' do
    [:list, :enumeration].each do |kind|
      it "imports a #{kind} label that contains a comma" do
        _parent, child = build_kit(kind, multiple: true, child_names: ['a1', 'a2', 'b1', 'Berlin, Germany', 'c,d'])
        fmt = child.format
        expect(fmt.value_from_keyword(child, 'Berlin, Germany', nil)).to eq([kit_key(child, 'Berlin, Germany')])
        expect(fmt.value_from_keyword(child, 'c,d', nil)).to eq([kit_key(child, 'c,d')])
        expect(fmt.value_from_keyword(child, 'a1,c,d;b1', nil))
          .to eq([kit_key(child, 'a1'), kit_key(child, 'c,d'), kit_key(child, 'b1')])
        expect(fmt.value_from_keyword(child, 'zz,a1', nil)).to eq([kit_key(child, 'a1')])
      end
    end
  end

  # rules-5: a project copy is judged against its source like an issue copy.
  describe 'a project copy (rules-5)' do
    let(:parent) { dcf_list_field(values: %w[A B], type: ProjectCustomField, name: "PParent-#{SecureRandom.hex(3)}") }
    let(:child) do
      field = dcf_list_field(format: 'depending_list', values: %w[x y z], parent: parent, type: ProjectCustomField,
                             name: "PChild-#{SecureRandom.hex(3)}")
      dcf_set_dependencies(field, value_dependencies: { 'A' => %w[y], 'B' => %w[z] })
    end
    let(:source) do
      record = dcf_create_project(name: 'Source')
      record.custom_field_values = { parent.id.to_s => 'A', child.id.to_s => 'x' }
      record.save!(validate: false)
      Project.find(record.id)
    end

    before { allow(User).to receive(:current).and_return(dcf_admin) }

    def copy_with(values)
      copy = Project.new
      copy.safe_attributes = { 'name' => 'Copy', 'identifier' => "copy-#{SecureRandom.hex(3)}",
                               'custom_field_values' => values.transform_keys { |f| f.id.to_s } }
      [copy, copy.copy(source, only: [])]
    end

    it 'keeps a stored value that no longer fits an unchanged parent value' do
      copy, result = copy_with(parent => 'A', child => 'x')
      expect(result).to be_truthy, copy.errors.full_messages.inspect
      expect(Project.find(copy.id).custom_field_value(child)).to eq('x')
    end

    it 'refuses it when the copy changes the parent value' do
      copy, result = copy_with(parent => 'B', child => 'x')
      expect(result).to be_falsey
      expect(copy.errors[child.name]).to eq([invalid])
    end

    it 'refuses a new value the parent value does not allow' do
      copy, result = copy_with(parent => 'A', child => 'z')
      expect(result).to be_falsey
      expect(copy.errors[child.name]).to eq([invalid])
    end
  end

  # rules-6: an issue or time entry field never reads a parent value on the
  # query's project, so the filter values cost no project lookup.
  describe 'depending_enumeration filter values (rules-6)' do
    it 'reads nothing of the project for an issue field' do
      _parent, child = build_kit(:enumeration)
      record = CustomField.find(child.id)
      with_project = IssueQuery.new(name: '_', project: Project.find(project.id))
      without = IssueQuery.new(name: '_')
      expect(record.format.query_filter_values(record, with_project)).to eq(record.format.query_filter_values(record, without))
      first = CustomField.find(child.id)
      second = CustomField.find(child.id)
      query = IssueQuery.new(name: '_', project: Project.find(project.id))
      plain = IssueQuery.new(name: '_')
      expect(dcf_count_queries { first.format.query_filter_values(first, query) })
        .to eq(dcf_count_queries { second.format.query_filter_values(second, plain) })
    end
  end

  # admin-editor-3: a copied Key/Value list (depending) field gets new
  # entries, so the source's links (entry ids of the source) are not kept.
  describe 'copying a depending_enumeration field (admin-editor-3)' do
    it 'starts the copy without links or defaults' do
      parent, child = build_kit(:enumeration)
      copy = IssueCustomField.new
      copy.copy_from(CustomField.find(child.id))
      copy.name = "Copy-#{SecureRandom.hex(3)}"
      copy.save!
      saved = CustomField.find(copy.id)

      expect(saved.parent_custom_field_id.to_i).to eq(parent.id)
      expect(saved.enumerations.map(&:name)).to eq(%w[a1 a2 b1])
      expect(saved.value_dependencies.to_h).to eq({})
      expect(saved.default_value_dependencies.to_h).to eq({})
      expect(CustomField.find(child.id).value_dependencies.to_h).not_to eq({})
    end

    it 'keeps the links of a copied List (depending) field' do
      _parent, child = build_kit(:list)
      copy = IssueCustomField.new
      copy.copy_from(CustomField.find(child.id))
      copy.name = "Copy-#{SecureRandom.hex(3)}"
      copy.save!
      expect(CustomField.find(copy.id).value_dependencies.to_h).to eq(child.value_dependencies.to_h)
    end
  end
end
