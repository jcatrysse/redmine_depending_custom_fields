require_relative '../rails_helper'

RSpec.describe RedmineDependingCustomFields::ParentReference do
  describe '.from_custom_field' do
    it 'accepts list parent for depending_enumeration child' do
      parent = build_custom_field(id: 10, type: 'IssueCustomField', field_format: 'list')
      child = build_custom_field(
        type: 'IssueCustomField',
        field_format: RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_ENUMERATION,
        parent_custom_field_id: 10
      )

      allow(CustomField).to receive(:find_by).with(id: 10).and_return(parent)

      expect(described_class.from_custom_field(child)).not_to be_nil
    end
  end
end
