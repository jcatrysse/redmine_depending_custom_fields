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
      # Core moet 'a' en 'b' kennen zodat alleen plugin valideert
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

      it 'adds exactly one inclusion error' do
        expect(format.validate_custom_value(make_value('a'))).to eq(
                                                                   [I18n.t('activerecord.errors.messages.inclusion')]
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

      # Stub enumerations (id 2 en 3) zodat Redmine core ze geldig vindt
      enum1 = instance_double(Enumeration, id: 2, name: 'two')
      enum2 = instance_double(Enumeration, id: 3, name: 'three')
      enum_assoc = instance_double('Assoc', active: [enum1, enum2])
      allow(child).to receive(:enumerations).and_return(enum_assoc)

      # Zorg dat possible_values ook ['2','3'] bevat zodat core geen fout geeft
      allow(child).to receive(:possible_values).and_return(%w[2 3])

      # Laat possible_values_options altijd beide waarden leveren zodat alleen
      # validate_custom_value de beperking afdwingt
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

      it 'adds at least one inclusion error for wrong value' do
        errors = format.validate_custom_value(make_value('3'))
        inclusion_msg = I18n.t('activerecord.errors.messages.inclusion')
        expect(errors).to include(inclusion_msg) # minstens één inclusion-fout
      end
    end
  end
end
