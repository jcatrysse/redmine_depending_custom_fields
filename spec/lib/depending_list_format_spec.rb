require_relative '../rails_helper'

RSpec.describe RedmineDependingCustomFields::DependingListFormat do
  describe '#before_custom_field_save' do
    let(:format) { described_class.instance }
    let(:parent) do
      build_custom_field(
        id: 42,
        type: 'IssueCustomField',
        field_format: 'list'
      )
    end

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
      build_custom_field(
        parent_custom_field_id: parent.id.to_s,
        parent_field_type: nil,
        parent_field_key: nil,
        type: parent.type,
        field_format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST,
        value_dependencies: unsanitized,
        default_value_dependencies: unsanitized_defaults,
        dependency_rules: [],
        default_value: 'X'
      )
    end

    before do
      allow(CustomField).to receive(:find_by).and_return(parent)
      allow(cf).to receive(:parent_custom_field_id=)
      allow(cf).to receive(:parent_field_type=)
      allow(cf).to receive(:parent_field_key=)
      allow(cf).to receive(:value_dependencies=)
      allow(cf).to receive(:default_value_dependencies=)
      allow(cf).to receive(:dependency_rules=)
      allow(cf).to receive(:default_value=)
    end

    it 'corrects parent id, sanitizes dependencies and clears default value' do
      sanitized = RedmineDependingCustomFields::Sanitizer.sanitize_dependencies(unsanitized)
      sanitized_defaults = RedmineDependingCustomFields::Sanitizer.sanitize_default_dependencies(unsanitized_defaults)
      sanitized_rules = RedmineDependingCustomFields::Sanitizer.sanitize_dependency_rules(cf.dependency_rules)
      format.before_custom_field_save(cf)
      expect(cf).to have_received(:parent_custom_field_id=).with(parent.id)
      expect(cf).to have_received(:value_dependencies=).with(sanitized)
      expect(cf).to have_received(:default_value_dependencies=).with(sanitized_defaults)
      expect(cf).to have_received(:dependency_rules=).with(sanitized_rules)
      expect(cf).to have_received(:default_value=).with(nil)
    end

    it 'adds an error when dependency rules are invalid JSON' do
      errors = instance_double(ActiveModel::Errors)
      allow(errors).to receive(:add)

      invalid_cf = Struct.new(:parent_custom_field_id, :parent_field_type, :parent_field_key, :type,
                              :dependency_rules, :value_dependencies, :default_value_dependencies,
                              :errors, :default_value).new(
        nil,
        'core_field',
        'tracker_id',
        'IssueCustomField',
        'invalid-json',
        {},
        {},
        errors,
        nil
      )

      format.before_custom_field_save(invalid_cf)

      expect(errors).to have_received(:add).with(:dependency_rules, I18n.t(:text_dependency_rules_invalid_json))
    end

    context 'with core_field parent' do
      let(:core_cf) do
        build_custom_field(
          parent_custom_field_id: nil,
          parent_field_type: 'core_field',
          parent_field_key: 'tracker_id',
          type: 'IssueCustomField',
          field_format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST,
          value_dependencies: {},
          default_value_dependencies: {},
          dependency_rules: [],
          default_value: 'X'
        )
      end

      before do
        allow(core_cf).to receive(:parent_custom_field_id=)
        allow(core_cf).to receive(:parent_field_type=)
        allow(core_cf).to receive(:parent_field_key=)
        allow(core_cf).to receive(:value_dependencies=)
        allow(core_cf).to receive(:default_value_dependencies=)
        allow(core_cf).to receive(:dependency_rules=)
        allow(core_cf).to receive(:default_value=)
      end

      it 'explicitly sets parent_field_type to core_field when key is present' do
        format.before_custom_field_save(core_cf)

        expect(core_cf).to have_received(:parent_field_type=).with('core_field')
        expect(core_cf).to have_received(:parent_custom_field_id=).with(nil)
        expect(core_cf).to have_received(:default_value=).with(nil)
      end
    end

    context 'when clearing parent (core_field with blank key)' do
      let(:clearing_cf) do
        build_custom_field(
          parent_custom_field_id: nil,
          parent_field_type: 'core_field',
          parent_field_key: '',
          type: 'IssueCustomField',
          field_format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST,
          value_dependencies: {},
          default_value_dependencies: {},
          dependency_rules: [{ 'operator' => 'equals', 'value' => 'x', 'child_values' => ['a'] }],
          default_value: nil
        )
      end

      before do
        allow(clearing_cf).to receive(:parent_custom_field_id=)
        allow(clearing_cf).to receive(:parent_field_type=)
        allow(clearing_cf).to receive(:parent_field_key=)
        allow(clearing_cf).to receive(:value_dependencies=)
        allow(clearing_cf).to receive(:default_value_dependencies=)
        allow(clearing_cf).to receive(:dependency_rules=)
        allow(clearing_cf).to receive(:default_value=)
      end

      it 'clears parent_field_type and dependency_rules' do
        format.before_custom_field_save(clearing_cf)

        expect(clearing_cf).to have_received(:parent_field_type=).with(nil)
        expect(clearing_cf).to have_received(:parent_field_key=).with(nil)
        expect(clearing_cf).to have_received(:dependency_rules=).with([])
      end
    end

    context 'when clearing parent (custom_field with blank id)' do
      let(:clearing_cf) do
        build_custom_field(
          parent_custom_field_id: '',
          parent_field_type: 'custom_field',
          parent_field_key: '',
          type: 'IssueCustomField',
          field_format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST,
          value_dependencies: { 'a' => ['1'] },
          default_value_dependencies: {},
          dependency_rules: [{ 'operator' => 'present', 'child_values' => ['b'] }],
          default_value: nil
        )
      end

      before do
        allow(clearing_cf).to receive(:parent_custom_field_id=)
        allow(clearing_cf).to receive(:parent_field_type=)
        allow(clearing_cf).to receive(:parent_field_key=)
        allow(clearing_cf).to receive(:value_dependencies=)
        allow(clearing_cf).to receive(:default_value_dependencies=)
        allow(clearing_cf).to receive(:dependency_rules=)
        allow(clearing_cf).to receive(:default_value=)
      end

      it 'clears parent_field_type and dependency_rules' do
        format.before_custom_field_save(clearing_cf)

        expect(clearing_cf).to have_received(:parent_field_type=).with(nil)
        expect(clearing_cf).to have_received(:dependency_rules=).with([])
      end
    end
  end
end
