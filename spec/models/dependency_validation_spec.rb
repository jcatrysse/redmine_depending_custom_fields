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

  def value_for(child, issue, value)
    CustomFieldValue.new(custom_field: child, customized: issue, value: value)
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
end
