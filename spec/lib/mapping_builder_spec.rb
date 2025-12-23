require_relative '../rails_helper'

RSpec.describe RedmineDependingCustomFields::MappingBuilder do
  describe '.build' do
    it 'returns mapping with parent ids and sanitized dependencies' do
      cf1 = build_custom_field(
        id: 31,
        parent_custom_field_id: 10,
        parent_field_type: nil,
        parent_field_key: nil,
        value_dependencies: {
          'a' => ['1', '', nil],
          '' => ['2']
        },
        default_value_dependencies: {
          'a' => ['1', '', nil],
          '' => '',
          nil => '2'
        },
        dependency_rules: [],
        field_format: 'list',
        hide_when_disabled: true
      )
      cf2 = build_custom_field(
        id: 32,
        parent_custom_field_id: 11,
        parent_field_type: nil,
        parent_field_key: nil,
        value_dependencies: {
          b: '3',
          c: nil
        },
        default_value_dependencies: {
          b: '3',
          c: nil
        },
        dependency_rules: [],
        field_format: 'list',
        hide_when_disabled: false
      )
      cf3 = build_custom_field(
        id: 33,
        parent_custom_field_id: nil,
        value_dependencies: { 'd' => ['4'] },
        default_value_dependencies: { 'd' => '4' },
        dependency_rules: []
      )

      allow(CustomField).to receive(:where).and_return([cf1, cf2, cf3])
      allow(CustomField).to receive(:find_by).with(id: 10).and_return(build_custom_field(id: 10, field_format: 'list'))
      allow(CustomField).to receive(:find_by).with(id: 11).and_return(build_custom_field(id: 11, field_format: 'list'))

      result = described_class.build

      expect(result).to eq(
        '31' => {
          parent_id: '10',
          parent_type: 'custom_field',
          parent_key: nil,
          parent_format: 'list',
          map: { 'a' => ['1'] },
          defaults: { 'a' => ['1'] },
          rules: [],
          hide_when_disabled: true
        },
        '32' => {
          parent_id: '11',
          parent_type: 'custom_field',
          parent_key: nil,
          parent_format: 'list',
          map: { 'b' => ['3'] },
          defaults: { 'b' => '3' },
          rules: [],
          hide_when_disabled: false
        }
      )
    end
  end
end
