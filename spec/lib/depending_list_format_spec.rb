# frozen_string_literal: true

require_relative '../rails_helper'

# WP-06: on real fields (the parent lookup now memoizes on the record through
# CustomFieldPatch#dcf_memo, which a stand-in cannot answer); the assertions
# are the same as with the former instance_double.
RSpec.describe RedmineDependingCustomFields::DependingListFormat do
  describe '#before_custom_field_save' do
    let(:format) { described_class.instance }
    let(:parent) { dcf_list_field(values: %w[1 2 3]) }

    let(:unsanitized) do
      {
        'a' => ['1', '', nil],
        '' => ['2'],
        nil => ['3'],
        :b => '2',
        'c' => [nil, ''],
        'd' => nil
      }
    end

    let(:unsanitized_defaults) do
      {
        'a' => ['1', '', nil],
        '' => '',
        nil => '3',
        :b => nil
      }
    end

    let(:cf) do
      field = CustomField.find(dcf_list_field(format: 'depending_list', values: %w[1 2 3 X]).id)
      field.parent_custom_field_id = parent.id.to_s
      field.value_dependencies = unsanitized
      field.default_value_dependencies = unsanitized_defaults
      field.default_value = 'X'
      field
    end

    it 'corrects parent id, sanitizes dependencies and clears default value' do
      sanitized = RedmineDependingCustomFields::Sanitizer.sanitize_dependencies(unsanitized)
      sanitized_defaults = RedmineDependingCustomFields::Sanitizer.sanitize_default_dependencies(unsanitized_defaults)
      format.before_custom_field_save(cf)
      expect(cf.parent_custom_field_id).to eq(parent.id)
      expect(cf.value_dependencies).to eq(sanitized)
      expect(cf.default_value_dependencies).to eq(sanitized_defaults)
      expect(cf.default_value).to be_nil
    end
  end
end
