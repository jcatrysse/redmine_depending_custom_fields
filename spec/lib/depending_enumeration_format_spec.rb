# frozen_string_literal: true

require_relative '../rails_helper'

# WP-06: on real fields (the parent lookup now memoizes on the record through
# CustomFieldPatch#dcf_memo, which a Struct cannot answer); the assertions are
# the same as with the former stand-in.
RSpec.describe RedmineDependingCustomFields::DependingEnumerationFormat do
  let(:format) { described_class.instance }

  describe '#before_custom_field_save' do
    let(:parent) { dcf_enum_field(names: %w[P Q]) }
    let(:parent_id) { parent.id.to_s }

    let(:custom_field) do
      field = CustomField.find(dcf_enum_field(format: 'depending_enumeration', names: %w[two]).id)
      field.parent_custom_field_id = parent_id
      field.value_dependencies = { '1' => ['2'] }
      field.default_value_dependencies = { '1' => '2' }
      field.default_value = 'X'
      field
    end

    context 'when a matching parent exists' do
      before do
        allow(RedmineDependingCustomFields::Sanitizer).to receive(:sanitize_dependencies)
          .with(custom_field.value_dependencies).and_return(custom_field.value_dependencies)
        allow(RedmineDependingCustomFields::Sanitizer).to receive(:sanitize_default_dependencies)
          .with(custom_field.default_value_dependencies).and_return(custom_field.default_value_dependencies)
      end

      it 'sets the parent_custom_field_id to the resolved parent id and clears the default value' do
        format.before_custom_field_save(custom_field)
        expect(custom_field.parent_custom_field_id).to eq(parent.id)
        expect(custom_field.default_value).to be_nil
      end

      it 'sanitizes the dependencies and defaults' do
        format.before_custom_field_save(custom_field)
        expect(RedmineDependingCustomFields::Sanitizer)
          .to have_received(:sanitize_dependencies).with(custom_field.value_dependencies)
        expect(RedmineDependingCustomFields::Sanitizer)
          .to have_received(:sanitize_default_dependencies).with(custom_field.default_value_dependencies)
      end
    end

    context 'when no matching parent exists' do
      let(:parent_id) { (CustomField.maximum(:id).to_i + 1_000).to_s }

      before do
        allow(RedmineDependingCustomFields::Sanitizer).to receive(:sanitize_dependencies).and_return({})
        allow(RedmineDependingCustomFields::Sanitizer).to receive(:sanitize_default_dependencies).and_return({})
      end

      it 'clears the parent_custom_field_id but leaves the default value intact' do
        format.before_custom_field_save(custom_field)
        expect(custom_field.parent_custom_field_id).to be_nil
        expect(custom_field.default_value).to eq('X')
      end

      it 'sanitizes the value and default dependencies' do
        format.before_custom_field_save(custom_field)
        expect(custom_field.value_dependencies).to eq({})
        expect(custom_field.default_value_dependencies).to eq({})
      end
    end
  end
end
