require_relative '../rails_helper'

RSpec.describe 'Depending field value validation' do
  let(:parent) do
    build_custom_field(id: 1, type: 'IssueCustomField', field_format: 'list')
  end

  # ------------------------------------------------------------
  # 1. DEPENDING LIST FORMAT
  # ------------------------------------------------------------
  describe RedmineDependingCustomFields::DependingListFormat do
    let(:format) { described_class.instance }
    let(:child) do
      build_custom_field(
        id: 2,
        type: parent.type,
        field_format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST,
        parent_custom_field_id: parent.id,
        value_dependencies: { 'A' => ['a'], 'B' => ['b'] }
      )
    end
    let(:issue) { double('Issue') }

    before do
      allow(CustomField).to receive(:find_by).with(id: parent.id).and_return(parent)
      allow(issue).to receive(:custom_field_value).with(parent).and_return(parent_value)
      allow(child).to receive(:set_custom_field_value) { |_cv, v| v }
      allow(child).to receive(:possible_values).and_return(%w[a b])
    end

    def make_value(val)
      CustomFieldValue.new(custom_field: child, customized: issue, value: val)
    end

    context 'with allowed value' do
      let(:parent_value) { 'A' }

      it 'passes validation (no errors)' do
        expect(format.validate_custom_value(make_value('a'))).to be_empty
      end
    end

    context 'with disallowed value' do
      let(:parent_value) { 'B' }

      it 'adds exactly one invalid error' do
        expect(format.validate_custom_value(make_value('a'))).to eq(
                                                                   [I18n.t('activerecord.errors.messages.invalid')]
                                                                 )
      end
    end

    # ------------------------------------------------------------------
    # Edge case: parent value maps to no child options
    # ------------------------------------------------------------------
    context 'when parent value has no mapped child options' do
      # parent_value must be defined so the shared outer before block does not raise.
      # The inner before overrides the stub with the actual value used by these tests.
      let(:parent_value) { 'X' }

      let(:child_no_mapping) do
        build_custom_field(
          id: 4,
          type: parent.type,
          field_format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST,
          parent_custom_field_id: parent.id,
          value_dependencies: { 'A' => ['a'] },
          multiple?: false
        )
      end

      before do
        allow(issue).to receive(:custom_field_value).with(parent).and_return('X')
        allow(child_no_mapping).to receive(:set_custom_field_value) { |_cv, v| v }
        allow(child_no_mapping).to receive(:possible_values).and_return(%w[a])
      end

      def make_no_mapping_value(val)
        CustomFieldValue.new(custom_field: child_no_mapping, customized: issue, value: val)
      end

      it 'returns no errors for a blank value when no options are mapped' do
        expect(format.validate_custom_value(make_no_mapping_value(''))).to be_empty
      end

      it 'returns no errors for a nil value when no options are mapped' do
        expect(format.validate_custom_value(make_no_mapping_value(nil))).to be_empty
      end

      # Edge: non-blank value submitted (e.g. via API bypass) is still invalid
      it 'returns an invalid error when a non-blank value is submitted despite no mapping' do
        errors = format.validate_custom_value(make_no_mapping_value('a'))
        expect(errors).to eq([I18n.t('activerecord.errors.messages.invalid')])
      end
    end

    context 'when parent field has no value selected' do
      let(:parent_value) { '' }

      let(:child_required) do
        build_custom_field(
          id: 5,
          type: parent.type,
          field_format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST,
          parent_custom_field_id: parent.id,
          value_dependencies: { 'A' => ['a'] },
          multiple?: false
        )
      end

      before do
        allow(issue).to receive(:custom_field_value).with(parent).and_return('')
        allow(child_required).to receive(:set_custom_field_value) { |_cv, v| v }
        allow(child_required).to receive(:possible_values).and_return(%w[a])
      end

      def make_required_value(val)
        CustomFieldValue.new(custom_field: child_required, customized: issue, value: val)
      end

      it 'returns no errors for a blank child value when parent is also blank' do
        expect(format.validate_custom_value(make_required_value(''))).to be_empty
      end
    end
  end

  # ------------------------------------------------------------
  # 2. DEPENDING ENUMERATION FORMAT
  # ------------------------------------------------------------
  describe RedmineDependingCustomFields::DependingEnumerationFormat do
    let(:format) { described_class.instance }
    let(:child) do
      build_custom_field(
        id: 3,
        type: parent.type,
        field_format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_ENUMERATION,
        parent_custom_field_id: parent.id,
        value_dependencies: { '1' => ['2'] }
      )
    end
    let(:issue) { double('Issue') }

    before do
      allow(CustomField).to receive(:find_by).with(id: parent.id).and_return(parent)
      allow(issue).to receive(:custom_field_value).with(parent).and_return(parent_value)
      allow(child).to receive(:set_custom_field_value) { |_cv, v| v }

      enum1 = instance_double(Enumeration, id: 2, name: 'two')
      enum2 = instance_double(Enumeration, id: 3, name: 'three')
      enum_assoc = instance_double('Assoc', active: [enum1, enum2])
      allow(child).to receive(:enumerations).and_return(enum_assoc)
      allow(child).to receive(:possible_values).and_return(%w[2 3])

      allow(format).to receive(:possible_values_options)
                         .and_return([['two', '2'], ['three', '3']])
    end

    def make_value(val)
      CustomFieldValue.new(custom_field: child, customized: issue, value: val)
    end

    context 'with allowed value' do
      let(:parent_value) { '1' }

      it 'passes validation (no errors)' do
        expect(format.validate_custom_value(make_value('2'))).to be_empty
      end
    end

    context 'with disallowed value' do
      let(:parent_value) { '1' }

      it 'adds at least one invalid error for wrong value' do
        errors = format.validate_custom_value(make_value('3'))
        invalid_msg = I18n.t('activerecord.errors.messages.invalid')
        expect(errors).to include(invalid_msg)
      end
    end

    # ------------------------------------------------------------------
    # Edge case: parent value maps to no child options
    # ------------------------------------------------------------------
    context 'when parent value has no mapped child options' do
      # parent_value must be defined so the shared outer before block does not raise.
      let(:parent_value) { '99' }

      let(:child_no_mapping) do
        build_custom_field(
          id: 6,
          type: parent.type,
          field_format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_ENUMERATION,
          parent_custom_field_id: parent.id,
          value_dependencies: { '1' => ['2'] },
          multiple?: false
        )
      end

      before do
        allow(issue).to receive(:custom_field_value).with(parent).and_return('99')
        allow(child_no_mapping).to receive(:set_custom_field_value) { |_cv, v| v }

        enum1 = instance_double(Enumeration, id: 2, name: 'two')
        enum_assoc = instance_double('Assoc', active: [enum1])
        allow(child_no_mapping).to receive(:enumerations).and_return(enum_assoc)
        allow(child_no_mapping).to receive(:possible_values).and_return(%w[2])
      end

      def make_no_mapping_value(val)
        CustomFieldValue.new(custom_field: child_no_mapping, customized: issue, value: val)
      end

      it 'returns no errors for a blank value when no options are mapped' do
        expect(format.validate_custom_value(make_no_mapping_value(''))).to be_empty
      end

      it 'returns no errors for a nil value when no options are mapped' do
        expect(format.validate_custom_value(make_no_mapping_value(nil))).to be_empty
      end

      # Edge: non-blank value submitted (e.g. via API bypass) is still invalid
      it 'returns an invalid error when a non-blank value is submitted despite no mapping' do
        errors = format.validate_custom_value(make_no_mapping_value('2'))
        expect(errors).to eq([I18n.t('activerecord.errors.messages.invalid')])
      end
    end

    context 'when parent field has no value selected' do
      let(:parent_value) { '' }

      let(:child_required) do
        build_custom_field(
          id: 7,
          type: parent.type,
          field_format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_ENUMERATION,
          parent_custom_field_id: parent.id,
          value_dependencies: { '1' => ['2'] },
          multiple?: false
        )
      end

      before do
        allow(issue).to receive(:custom_field_value).with(parent).and_return('')
        allow(child_required).to receive(:set_custom_field_value) { |_cv, v| v }

        enum1 = instance_double(Enumeration, id: 2, name: 'two')
        enum_assoc = instance_double('Assoc', active: [enum1])
        allow(child_required).to receive(:enumerations).and_return(enum_assoc)
        allow(child_required).to receive(:possible_values).and_return(%w[2])
      end

      def make_required_value(val)
        CustomFieldValue.new(custom_field: child_required, customized: issue, value: val)
      end

      it 'returns no errors for a blank child value when parent is also blank' do
        expect(format.validate_custom_value(make_required_value(''))).to be_empty
      end
    end
  end
end
