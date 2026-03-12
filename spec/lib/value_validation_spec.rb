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



    context 'without mutating custom_value during validation' do
      let(:parent_value) { 'A' }

      it 'keeps the original value unchanged' do
        cv = make_value(['a', ''])
        original = cv.value
        format.validate_custom_value(cv)
        expect(cv.value).to eq(original)
      end
    end
    context 'with disallowed value' do
      let(:parent_value) { 'B' }

      it 'adds exactly one invalid error' do
        expect(format.validate_custom_value(make_value('a'))).to eq(
                                                                   [I18n.t(:text_dependency_value_not_allowed)]
                                                                 )
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



    context 'without mutating custom_value during validation' do
      let(:parent_value) { '1' }

      it 'keeps the original value unchanged' do
        cv = make_value(['2', ''])
        original = cv.value
        format.validate_custom_value(cv)
        expect(cv.value).to eq(original)
      end
    end
    context 'with disallowed value' do
      let(:parent_value) { '1' }

      it 'adds at least one invalid error for wrong value' do
        errors = format.validate_custom_value(make_value('3'))
        invalid_msg = I18n.t(:text_dependency_value_not_allowed)
        expect(errors).to include(invalid_msg)
      end
    end
  end
end
