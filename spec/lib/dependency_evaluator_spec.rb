require_relative '../rails_helper'

RSpec.describe RedmineDependingCustomFields::DependencyEvaluator do
  describe '.evaluate' do
    it 'uses rule-based dependencies when rules are present' do
      parent = build_custom_field(id: 2, field_format: 'date')
      child = build_custom_field(
        parent_custom_field_id: 2,
        dependency_rules: [
          { 'operator' => 'gte', 'value' => '2024-01-01', 'child_values' => ['A'] }
        ]
      )
      customized = double('issue', custom_field_value: '2024-02-01')

      allow(CustomField).to receive(:find_by).with(id: 2).and_return(parent)

      result = described_class.evaluate(child, customized)

      expect(result.allowed).to eq(['A'])
      expect(result.has_rules).to be(true)
    end

    it 'uses value mappings when no rules are defined' do
      parent = build_custom_field(id: 3, field_format: 'list')
      child = build_custom_field(
        parent_custom_field_id: 3,
        value_dependencies: { 'X' => ['A'] },
        dependency_rules: []
      )
      customized = double('issue', custom_field_value: 'X')

      allow(CustomField).to receive(:find_by).with(id: 3).and_return(parent)

      result = described_class.evaluate(child, customized)

      expect(result.allowed).to eq(['A'])
      expect(result.has_rules).to be(false)
      expect(result.has_mapping).to be(true)
    end

    it 'does not match not_equals when any parent value equals the rule value' do
      parent = build_custom_field(id: 4, field_format: 'list')
      child = build_custom_field(
        parent_custom_field_id: 4,
        dependency_rules: [
          { 'operator' => 'not_equals', 'value' => 'A', 'child_values' => ['B'] }
        ]
      )
      customized = double('issue', custom_field_value: ['A', 'C'])

      allow(CustomField).to receive(:find_by).with(id: 4).and_return(parent)

      result = described_class.evaluate(child, customized)

      expect(result.allowed).to eq([])
    end

    it 'matches equals when any parent value matches' do
      parent = build_custom_field(id: 5, field_format: 'list')
      child = build_custom_field(
        parent_custom_field_id: 5,
        dependency_rules: [
          { 'operator' => 'equals', 'value' => 'A', 'child_values' => ['B'] }
        ]
      )
      customized = double('issue', custom_field_value: ['C', 'A'])

      allow(CustomField).to receive(:find_by).with(id: 5).and_return(parent)

      result = described_class.evaluate(child, customized)

      expect(result.allowed).to eq(['B'])
    end

    it 'ignores invalid date formats for date rules' do
      parent = build_custom_field(id: 6, field_format: 'date')
      child = build_custom_field(
        parent_custom_field_id: 6,
        dependency_rules: [
          { 'operator' => 'gte', 'value' => '2024-01-01', 'child_values' => ['A'] }
        ]
      )
      customized = double('issue', custom_field_value: '01/01/2024')

      allow(CustomField).to receive(:find_by).with(id: 6).and_return(parent)

      result = described_class.evaluate(child, customized)

      expect(result.allowed).to eq([])
    end

    it 'matches between for date rules with ISO values' do
      parent = build_custom_field(id: 7, field_format: 'date')
      child = build_custom_field(
        parent_custom_field_id: 7,
        dependency_rules: [
          { 'operator' => 'between', 'value' => '2024-01-01', 'value_to' => '2024-12-31', 'child_values' => ['A'] }
        ]
      )
      customized = double('issue', custom_field_value: '2024-06-01')

      allow(CustomField).to receive(:find_by).with(id: 7).and_return(parent)

      result = described_class.evaluate(child, customized)

      expect(result.allowed).to eq(['A'])
    end

    it 'rejects between rules without value_to' do
      parent = build_custom_field(id: 11, field_format: 'date')
      child = build_custom_field(
        parent_custom_field_id: 11,
        dependency_rules: [
          { 'operator' => 'between', 'value' => '2024-01-01', 'child_values' => ['A'] }
        ]
      )
      customized = double('issue', custom_field_value: '2024-06-01')

      allow(CustomField).to receive(:find_by).with(id: 11).and_return(parent)

      result = described_class.evaluate(child, customized)

      expect(result.allowed).to eq([])
    end

    it 'matches between for numeric rules' do
      parent = build_custom_field(id: 12, field_format: 'int')
      child = build_custom_field(
        parent_custom_field_id: 12,
        dependency_rules: [
          { 'operator' => 'between', 'value' => '1', 'value_to' => '5', 'child_values' => ['A'] }
        ]
      )
      customized = double('issue', custom_field_value: '3')

      allow(CustomField).to receive(:find_by).with(id: 12).and_return(parent)

      result = described_class.evaluate(child, customized)

      expect(result.allowed).to eq(['A'])
    end

    it 'returns empty allowed list when rules are empty' do
      parent = build_custom_field(id: 13, field_format: 'list')
      child = build_custom_field(
        parent_custom_field_id: 13,
        dependency_rules: []
      )
      customized = double('issue', custom_field_value: 'A')

      allow(CustomField).to receive(:find_by).with(id: 13).and_return(parent)

      result = described_class.evaluate(child, customized)

      expect(result.allowed).to eq([])
    end

    it 'handles reversed between values' do
      parent = build_custom_field(id: 10, field_format: 'date')
      child = build_custom_field(
        parent_custom_field_id: 10,
        dependency_rules: [
          { 'operator' => 'between', 'value' => '2024-12-31', 'value_to' => '2024-01-01', 'child_values' => ['A'] }
        ]
      )
      customized = double('issue', custom_field_value: '2024-06-01')

      allow(CustomField).to receive(:find_by).with(id: 10).and_return(parent)

      result = described_class.evaluate(child, customized)

      expect(result.allowed).to eq(['A'])
    end

    it 'handles invalid regex rules without raising' do
      parent = build_custom_field(id: 8, field_format: 'string')
      child = build_custom_field(
        parent_custom_field_id: 8,
        dependency_rules: [
          { 'operator' => 'regex', 'value' => '(', 'child_values' => ['A'] }
        ]
      )
      customized = double('issue', custom_field_value: 'test')

      allow(CustomField).to receive(:find_by).with(id: 8).and_return(parent)

      result = described_class.evaluate(child, customized)

      expect(result.allowed).to eq([])
    end

    it 'matches present and blank rules' do
      parent = build_custom_field(id: 9, field_format: 'string')
      child = build_custom_field(
        parent_custom_field_id: 9,
        dependency_rules: [
          { 'operator' => 'present', 'child_values' => ['A'] },
          { 'operator' => 'blank', 'child_values' => ['B'] }
        ]
      )

      allow(CustomField).to receive(:find_by).with(id: 9).and_return(parent)

      present_result = described_class.evaluate(child, double('issue', custom_field_value: 'x'))
      blank_result = described_class.evaluate(child, double('issue', custom_field_value: ''))

      expect(present_result.allowed).to eq(['A'])
      expect(blank_result.allowed).to eq(['B'])
    end
  end
end
