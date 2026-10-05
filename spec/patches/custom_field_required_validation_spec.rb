# frozen_string_literal: true

require_relative '../rails_helper'

# CustomFieldPatch#validate_custom_value strips the "cannot be blank" error that
# core CustomField#validate_custom_value adds on its own after the format
# returned no errors, when the depending field has no options for the current
# parent value. WP-04 rewrote these examples on real fields and real issues
# (they used a stand-in class without a callback API); the assertions are the
# same.
RSpec.describe 'CustomFieldPatch#validate_custom_value required-check bypass' do
  fixtures :users

  let(:blank_msg)   { I18n.t('activerecord.errors.messages.blank') }
  let(:invalid_msg) { I18n.t('activerecord.errors.messages.invalid') }
  let(:project)     { dcf_create_project }

  # Parent values A and Z; the child is required and A maps to its value x.
  # Returns [parent, child]; mapping: false leaves the mapping empty.
  def build_pair(fmt, multiple: false, mapping: true)
    if fmt == RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST
      parent = dcf_list_field(values: %w[A Z])
      child = dcf_list_field(format: fmt, values: %w[x], parent: parent, multiple: multiple)
    else
      parent = dcf_enum_field(names: %w[A Z])
      child = dcf_enum_field(format: fmt, names: %w[x], parent: parent)
    end
    child.update!(is_required: true, multiple: multiple)
    dcf_set_dependencies(child, value_dependencies: mapping ? { key(parent, 'A') => [key(child, 'x')] } : {})
    [parent, child]
  end

  def key(field, name)
    return name if field.field_format.end_with?('list')

    field.enumerations.detect { |e| e.name == name }.id.to_s
  end

  # An unsaved issue whose parent field holds +parent_name+ ('' for blank).
  def issue_with_parent(parent, parent_name)
    tracker, status, priority = dcf_issue_infra(project)
    tracker.custom_fields << parent unless tracker.custom_fields.include?(parent)
    issue = Issue.new(project: project, tracker: tracker, subject: 'S', author: dcf_admin,
                      status: status, priority: priority)
    issue.custom_field_values = { parent.id.to_s => parent_name.empty? ? '' : key(parent, parent_name) }
    issue
  end

  def validate(child, customized, value)
    child.validate_custom_value(CustomFieldValue.new(custom_field: child, customized: customized, value: value))
  end

  [
    RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST,
    RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_ENUMERATION
  ].each do |fmt|
    context "field_format: #{fmt}" do
      let(:pair) { build_pair(fmt) }
      let(:parent) { pair.first }
      let(:child) { pair.last }

      context 'when parent value has no mapped child options' do
        let(:issue) { issue_with_parent(parent, 'Z') }

        it 'returns no errors for a blank child value' do
          expect(validate(child, issue, '')).to be_empty
        end

        it 'returns no errors for a nil child value' do
          expect(validate(child, issue, nil)).to be_empty
        end
      end

      context 'when parent value has a valid mapping' do
        it 'preserves the blank error when options are available but value is blank' do
          expect(validate(child, issue_with_parent(parent, 'A'), '')).to include(blank_msg)
        end
      end

      context 'when parent field has no value selected (blank parent)' do
        it 'strips the blank error when parent is blank (no options available)' do
          expect(validate(child, issue_with_parent(parent, ''), '')).not_to include(blank_msg)
        end
      end
    end
  end

  context 'when field_format is not a depending format' do
    it 'preserves the blank error for a plain list field' do
      field = dcf_list_field(values: %w[A])
      field.update!(is_required: true)
      expect(validate(field, issue_with_parent(dcf_list_field(values: %w[A]), 'A'), '')).to include(blank_msg)
    end
  end

  context 'when the format itself returns errors' do
    it 'passes through the format errors unchanged' do
      parent, child = build_pair(RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST, mapping: false)
      result = validate(child, issue_with_parent(parent, 'Z'), 'bad')
      expect(result).to eq([invalid_msg])
      expect(result).not_to include(blank_msg)
    end
  end

  context 'when customized is nil' do
    it 'preserves the blank error when customized is nil' do
      _parent, child = build_pair(RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST)
      expect(validate(child, nil, '')).to include(blank_msg)
    end
  end

  context 'when parent custom field record no longer exists' do
    it 'preserves the blank error when the parent field cannot be found' do
      parent, child = build_pair(RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST)
      issue = issue_with_parent(parent, 'Z')
      CustomField.where(id: parent.id).delete_all
      expect(validate(child.reload, issue, '')).to include(blank_msg)
    end
  end

  context 'when the field accepts multiple values' do
    let(:pair) { build_pair(RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST, multiple: true) }
    let(:issue) { issue_with_parent(pair.first, 'Z') }

    it 'strips the blank error for an empty array when no options are available' do
      expect(validate(pair.last, issue, [])).to be_empty
    end

    it 'strips the blank error for an all-blank array when no options are available' do
      expect(validate(pair.last, issue, ['', nil])).to be_empty
    end
  end
end
