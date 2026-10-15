# frozen_string_literal: true

require_relative '../rails_helper'

# Format-level validation of depending values on real fields and a real issue
# (WP-04: replaces spec/lib/value_validation_spec.rb, which stubbed CustomField
# and CustomField.find_by; the assertions are the same).
RSpec.describe 'Depending field value validation' do
  fixtures :users

  let(:invalid) { I18n.t('activerecord.errors.messages.invalid') }
  let(:project) { dcf_create_project }

  # An unsaved issue whose parent field holds +parent_value+.
  def issue_with_parent(parent, parent_value)
    tracker, status, priority = dcf_issue_infra(project)
    tracker.custom_fields << parent unless tracker.custom_fields.include?(parent)
    issue = Issue.new(project: project, tracker: tracker, subject: 'S', author: dcf_admin,
                      status: status, priority: priority)
    issue.custom_field_values = { parent.id.to_s => parent_value }
    issue
  end

  # Sets @value directly, as acts_as_customizable does when it loads stored
  # values: CustomFieldValue#value= would turn nil into '' and [] into [''].
  def value_for(child, issue, value)
    custom_value = CustomFieldValue.new(custom_field: child, customized: issue)
    custom_value.instance_variable_set(:@value, value)
    custom_value
  end

  describe RedmineDependingCustomFields::DependingListFormat do
    let(:format) { described_class.instance }
    let(:parent) { dcf_list_field(values: %w[A B X]) }
    let(:child) do
      field = dcf_list_field(format: 'depending_list', values: %w[a b], parent: parent)
      dcf_set_dependencies(field, value_dependencies: { 'A' => ['a'], 'B' => ['b'] })
    end

    def validate(parent_value, value)
      format.validate_custom_value(value_for(child, issue_with_parent(parent, parent_value), value))
    end

    it 'passes an allowed value (no errors)' do
      expect(validate('A', 'a')).to be_empty
    end

    it 'adds exactly one invalid error for a disallowed value' do
      expect(validate('B', 'a')).to eq([invalid])
    end

    context 'when the parent value has no mapped child options' do
      it 'returns no errors for a blank value' do
        expect(validate('X', '')).to be_empty
      end

      it 'returns no errors for a nil value' do
        expect(validate('X', nil)).to be_empty
      end

      it 'returns an invalid error for a non-blank value (for example an API call)' do
        expect(validate('X', 'a')).to eq([invalid])
      end
    end

    it 'returns no errors for a blank child when the parent is blank' do
      expect(validate('', '')).to be_empty
    end
  end

  describe RedmineDependingCustomFields::DependingEnumerationFormat do
    let(:format) { described_class.instance }
    let(:parent) { dcf_enum_field(names: %w[P Q]) }
    let(:child) { dcf_enum_field(format: 'depending_enumeration', names: %w[two three], parent: parent) }
    let(:p_id) { parent.enumerations.detect { |e| e.name == 'P' }.id.to_s }
    let(:q_id) { parent.enumerations.detect { |e| e.name == 'Q' }.id.to_s }
    let(:two) { child.enumerations.detect { |e| e.name == 'two' }.id.to_s }
    let(:three) { child.enumerations.detect { |e| e.name == 'three' }.id.to_s }

    before { dcf_set_dependencies(child, value_dependencies: { p_id => [two] }) }

    def validate(parent_value, value)
      format.validate_custom_value(value_for(child, issue_with_parent(parent, parent_value), value))
    end

    it 'passes an allowed value (no errors)' do
      expect(validate(p_id, two)).to be_empty
    end

    it 'adds at least one invalid error for a disallowed value' do
      expect(validate(p_id, three)).to include(invalid)
    end

    context 'when the parent value has no mapped child options' do
      it 'returns no errors for a blank value' do
        expect(validate(q_id, '')).to be_empty
      end

      it 'returns no errors for a nil value' do
        expect(validate(q_id, nil)).to be_empty
      end

      it 'returns an invalid error for a non-blank value (for example an API call)' do
        expect(validate(q_id, two)).to eq([invalid])
      end
    end

    it 'returns no errors for a blank child when the parent is blank' do
      expect(validate('', '')).to be_empty
    end
  end

  # WP-09: D1 per value (UD-04) on a persisted issue. The stored child is
  # disallowed by the stored parent value (a legacy combination).
  describe 'stored values (D1 per value)' do
    # A persisted issue holding +values+ (field => value), stored without
    # validation and reloaded, so value_was is what the database holds.
    def stored_issue(values)
      tracker, status, priority = dcf_issue_infra(project)
      values.each_key { |f| tracker.custom_fields << f unless tracker.custom_fields.include?(f) }
      issue = Issue.new(project: project, tracker: tracker, subject: 'S', author: dcf_admin,
                        status: status, priority: priority)
      issue.custom_field_values = values.to_h { |f, v| [f.id.to_s, v] }
      issue.save!(validate: false)
      Issue.find(issue.id)
    end

    def child_errors(issue, child, value)
      issue.custom_field_values = { child.id.to_s => value }
      custom_value = issue.custom_field_values.detect { |v| v.custom_field_id == child.id }
      child.format.validate_custom_value(custom_value)
    end

    context 'for a list' do
      let(:parent) { dcf_list_field(values: %w[A B X]) }
      let(:child) do
        field = dcf_list_field(format: 'depending_list', values: %w[a b c], parent: parent, multiple: true)
        dcf_set_dependencies(field, value_dependencies: { 'A' => ['a'], 'B' => ['b'] })
      end

      it 'keeps a stored disallowed value while the parent is unchanged and checks only new values' do
        expect(child_errors(stored_issue(parent => 'A', child => %w[b]), child, %w[b])).to be_empty
        expect(child_errors(stored_issue(parent => 'A', child => %w[b]), child, %w[b a])).to be_empty
        expect(child_errors(stored_issue(parent => 'A', child => %w[b]), child, %w[b c])).to eq([invalid])
      end

      it 'checks every value once the parent changed' do
        issue = stored_issue(parent => 'A', child => %w[b a])
        issue.custom_field_values = { parent.id.to_s => 'B' }
        expect(child_errors(issue, child, %w[b a])).to eq([invalid])
        expect(child_errors(issue, child, %w[b])).to be_empty
      end
    end

    context 'for an enumeration' do
      let(:parent) { dcf_enum_field(names: %w[P Q]) }
      let(:child) { dcf_enum_field(format: 'depending_enumeration', names: %w[two three], parent: parent) }
      let(:p_id) { parent.enumerations.detect { |e| e.name == 'P' }.id.to_s }
      let(:q_id) { parent.enumerations.detect { |e| e.name == 'Q' }.id.to_s }
      let(:two) { child.enumerations.detect { |e| e.name == 'two' }.id.to_s }
      let(:three) { child.enumerations.detect { |e| e.name == 'three' }.id.to_s }

      before { dcf_set_dependencies(child, value_dependencies: { p_id => [two] }) }

      it 'keeps a stored disallowed value while the parent is unchanged, also under a value without links' do
        expect(child_errors(stored_issue(parent => p_id, child => three), child, three)).to be_empty
        expect(child_errors(stored_issue(parent => q_id, child => three), child, three)).to be_empty
      end

      it 'rejects it once the parent changed, and rejects a new disallowed value' do
        issue = stored_issue(parent => p_id, child => three)
        issue.custom_field_values = { parent.id.to_s => q_id }
        expect(child_errors(issue, child, three)).to eq([invalid])
        expect(child_errors(stored_issue(parent => p_id, child => two), child, three)).to eq([invalid])
      end
    end
  end
end
