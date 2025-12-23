require_relative '../rails_helper'

RSpec.describe RedmineDependingCustomFields::Sanitizer do
  describe '.parse_dependency_rules' do
    it 'returns rules for valid JSON' do
      rules, error = described_class.parse_dependency_rules('[{"operator":"equals","value":"A","child_values":["B"]}]')
      expect(error).to be_nil
      expect(rules).to be_an(Array)
    end

    it 'returns an error for invalid JSON' do
      rules, error = described_class.parse_dependency_rules('invalid-json')
      expect(error).to eq('invalid')
      expect(rules).to eq([])
    end
  end

  describe '.invalid_date_rules?' do
    it 'returns true for invalid date values' do
      rules = [{ 'operator' => 'gte', 'value' => '01/01/2024', 'child_values' => ['A'] }]
      expect(described_class.invalid_date_rules?(rules)).to be(true)
    end

    it 'returns false for ISO dates' do
      rules = [{ 'operator' => 'gte', 'value' => '2024-01-01', 'child_values' => ['A'] }]
      expect(described_class.invalid_date_rules?(rules)).to be(false)
    end

    it 'returns false for ISO datetimes' do
      rules = [{ 'operator' => 'gte', 'value' => '2024-01-01T12:30:00Z', 'child_values' => ['A'] }]
      expect(described_class.invalid_date_rules?(rules)).to be(false)
    end

    it 'returns true for invalid ISO datetimes' do
      rules = [{ 'operator' => 'gte', 'value' => '2024-01-01T99:99:99Z', 'child_values' => ['A'] }]
      expect(described_class.invalid_date_rules?(rules)).to be(true)
    end
  end

  describe '.invalid_rule_schema?' do
    it 'returns true when operator is missing' do
      rules = [{ 'value' => 'A', 'child_values' => ['B'] }]
      expect(described_class.invalid_rule_schema?(rules)).to be(true)
    end

    it 'returns true when child_values are missing' do
      rules = [{ 'operator' => 'equals', 'value' => 'A' }]
      expect(described_class.invalid_rule_schema?(rules)).to be(true)
    end

    it 'returns false when rules are valid' do
      rules = [{ 'operator' => 'equals', 'value' => 'A', 'child_values' => ['B'] }]
      expect(described_class.invalid_rule_schema?(rules)).to be(false)
    end

    it 'returns true when value is missing for value operators' do
      rules = [{ 'operator' => 'equals', 'child_values' => ['B'] }]
      expect(described_class.invalid_rule_schema?(rules)).to be(true)
    end

    it 'returns true when value_to is missing for between operators' do
      rules = [{ 'operator' => 'between', 'value' => '1', 'child_values' => ['B'] }]
      expect(described_class.invalid_rule_schema?(rules)).to be(true)
    end
  end

  describe '.rule_schema_errors' do
    it 'returns indexed errors for missing fields' do
      rules = [{ 'value' => 'A', 'child_values' => [] }]
      errors = described_class.rule_schema_errors(rules)
      expect(errors.first[:index]).to eq(0)
      expect(errors.map { |e| e[:code] }).to include('missing_operator', 'missing_child_values')
    end

    it 'returns errors for missing values in value operators' do
      rules = [{ 'operator' => 'equals', 'child_values' => ['B'] }]
      errors = described_class.rule_schema_errors(rules)
      expect(errors.map { |e| e[:code] }).to include('missing_value')
    end

    it 'returns errors for missing value_to in between operators' do
      rules = [{ 'operator' => 'between', 'value' => '1', 'child_values' => ['B'] }]
      errors = described_class.rule_schema_errors(rules)
      expect(errors.map { |e| e[:code] }).to include('missing_value_to')
    end
  end
end
