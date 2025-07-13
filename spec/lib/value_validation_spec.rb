require_relative '../rails_helper'

RSpec.describe 'Depending field value validation' do
  let(:parent) do
    build_custom_field(id: 1, type: 'IssueCustomField', field_format: 'list')
  end

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
    end

    def make_value(val)
      CustomFieldValue.new(custom_field: child, customized: issue, value: val)
    end

    context 'with allowed value' do
      let(:parent_value) { 'A' }
      it 'passes validation' do
        expect(format.validate_custom_value(make_value('a'))).to eq([])
      end
    end

    context 'with disallowed value' do
      let(:parent_value) { 'B' }
      it 'adds an inclusion error' do
        expect(format.validate_custom_value(make_value('a'))).
          to include(I18n.t('activerecord.errors.messages.inclusion'))
      end
    end
  end

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
    end

    def make_value(val)
      CustomFieldValue.new(custom_field: child, customized: issue, value: val)
    end

    context 'with allowed value' do
      let(:parent_value) { '1' }
      it 'passes validation' do
        expect(format.validate_custom_value(make_value('2'))).to eq([])
      end
    end

    context 'with disallowed value' do
      let(:parent_value) { '1' }
      it 'adds an inclusion error for wrong value' do
        expect(format.validate_custom_value(make_value('3'))).
          to include(I18n.t('activerecord.errors.messages.inclusion'))
      end
    end
  end
end
