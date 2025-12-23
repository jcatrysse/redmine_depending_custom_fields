require_relative '../rails_helper'

RSpec.describe RedmineDependingCustomFields::DependingEnumerationFormat do
  let(:format) { described_class.instance }

  describe '#before_custom_field_save' do
    let(:custom_field) do
      Struct.new(:id, :type, :field_format, :parent_custom_field_id, :parent_field_type,
                 :parent_field_key, :dependency_rules, :value_dependencies,
                 :default_value_dependencies, :default_value).new(
        11,
        'IssueCustomField',
        RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_ENUMERATION,
        '5',
        nil,
        nil,
        [],
        { '1' => ['2'] },
        { '1' => '2' },
        'X'
      )
    end

    context 'when a matching parent exists' do
      let(:parent) { Struct.new(:id).new(5) }

      before do
        allow(CustomField).to receive(:find_by).with(
          id: 5,
          type: custom_field.type,
          field_format: ['enumeration', RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_ENUMERATION]
        ).and_return(parent)
        allow(RedmineDependingCustomFields::Sanitizer).to receive(:sanitize_dependencies)
          .with(custom_field.value_dependencies).and_return(custom_field.value_dependencies)
        allow(RedmineDependingCustomFields::Sanitizer).to receive(:sanitize_default_dependencies)
          .with(custom_field.default_value_dependencies).and_return(custom_field.default_value_dependencies)
        allow(RedmineDependingCustomFields::Sanitizer).to receive(:sanitize_dependency_rules)
          .with(custom_field.dependency_rules).and_return(custom_field.dependency_rules)
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
      before do
        allow(CustomField).to receive(:find_by).and_return(nil)
        allow(RedmineDependingCustomFields::Sanitizer).to receive(:sanitize_dependencies).and_return({})
        allow(RedmineDependingCustomFields::Sanitizer).to receive(:sanitize_default_dependencies).and_return({})
        allow(RedmineDependingCustomFields::Sanitizer).to receive(:sanitize_dependency_rules).and_return([])
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

    it 'adds an error when dependency rules are invalid JSON' do
      errors = instance_double(ActiveModel::Errors)
      allow(errors).to receive(:add)

      invalid_cf = Struct.new(:id, :type, :field_format, :parent_custom_field_id, :parent_field_type,
                              :parent_field_key, :dependency_rules, :value_dependencies,
                              :default_value_dependencies, :default_value, :errors).new(
        1,
        'IssueCustomField',
        RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_ENUMERATION,
        nil,
        'core_field',
        'tracker_id',
        'invalid-json',
        {},
        {},
        nil,
        errors
      )

      allow(RedmineDependingCustomFields::Sanitizer).to receive(:sanitize_dependencies).and_return({})
      allow(RedmineDependingCustomFields::Sanitizer).to receive(:sanitize_default_dependencies).and_return({})

      format.before_custom_field_save(invalid_cf)

      expect(errors).to have_received(:add).with(:dependency_rules, I18n.t(:text_dependency_rules_invalid_json))
    end
  end
end
