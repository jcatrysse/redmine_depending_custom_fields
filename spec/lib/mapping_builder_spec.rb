require_relative '../rails_helper'

RSpec.describe RedmineDependingCustomFields::MappingBuilder do
  describe '.build' do
    it 'returns mapping with parent ids and sanitized dependencies' do
      cf1 = build_custom_field(
        id: 31,
        parent_custom_field_id: 10,
        value_dependencies: {
          'a' => ['1', '', nil],
          '' => ['2']
        },
        default_value_dependencies: {
          'a' => ['1', '', nil],
          '' => '',
          nil => '2'
        },
        hide_when_disabled: true
      )
      cf2 = build_custom_field(
        id: 32,
        parent_custom_field_id: 11,
        value_dependencies: {
          b: '3',
          c: nil
        },
        default_value_dependencies: {
          b: '3',
          c: nil
        },
        hide_when_disabled: false
      )
      cf3 = build_custom_field(
        id: 33,
        parent_custom_field_id: nil,
        value_dependencies: { 'd' => ['4'] },
        default_value_dependencies: { 'd' => '4' }
      )

      allow(CustomField).to receive(:where).and_return([cf1, cf2, cf3])

      result = described_class.build

      expect(result).to eq(
        '31' => { parent_id: '10', map: { 'a' => ['1'] }, defaults: { 'a' => ['1'] }, hide_when_disabled: true },
        '32' => { parent_id: '11', map: { 'b' => ['3'] }, defaults: { 'b' => '3' }, hide_when_disabled: false }
      )
    end
  end
end
