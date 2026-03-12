require_relative '../rails_helper'

RSpec.describe RedmineDependingCustomFields::ParentValueOptions do
  describe '::CORE_FIELDS' do
    it 'contains all expected core field keys' do
      expected_keys = %w[
        project_id tracker_id status_id priority_id
        assigned_to_id author_id category_id fixed_version_id
        subject start_date due_date done_ratio
      ]
      expect(described_class::CORE_FIELDS.keys).to match_array(expected_keys)
    end

    it 'marks enumerated fields correctly' do
      enumerated = %w[project_id tracker_id status_id priority_id assigned_to_id author_id category_id fixed_version_id]
      non_enumerated = %w[subject start_date due_date done_ratio]

      enumerated.each do |key|
        expect(described_class::CORE_FIELDS[key][:enumerated]).to be(true),
          "Expected #{key} to be enumerated"
      end

      non_enumerated.each do |key|
        expect(described_class::CORE_FIELDS[key][:enumerated]).to be(false),
          "Expected #{key} to NOT be enumerated"
      end
    end

    it 'assigns a format to every field' do
      described_class::CORE_FIELDS.each do |key, info|
        expect(info[:format]).to be_a(String).and(be_present),
          "Expected #{key} to have a format"
      end
    end

    it 'assigns a label symbol to every field' do
      described_class::CORE_FIELDS.each do |key, info|
        expect(info[:label]).to be_a(Symbol),
          "Expected #{key} to have a label symbol"
      end
    end
  end

  describe '.enumerated_core_field?' do
    it 'returns true for tracker_id' do
      expect(described_class.enumerated_core_field?('tracker_id')).to be true
    end

    it 'returns false for subject' do
      expect(described_class.enumerated_core_field?('subject')).to be false
    end

    it 'returns nil for unknown keys' do
      expect(described_class.enumerated_core_field?('unknown')).to be_falsey
    end
  end

  describe '.core_field_format' do
    it 'returns list for tracker_id' do
      expect(described_class.core_field_format('tracker_id')).to eq('list')
    end

    it 'returns date for start_date' do
      expect(described_class.core_field_format('start_date')).to eq('date')
    end

    it 'returns int for done_ratio' do
      expect(described_class.core_field_format('done_ratio')).to eq('int')
    end

    it 'returns string for subject' do
      expect(described_class.core_field_format('subject')).to eq('string')
    end

    it 'returns string for unknown keys' do
      expect(described_class.core_field_format('unknown')).to eq('string')
    end
  end

  describe '.core_field_options' do
    it 'returns an array of [label, key] pairs' do
      options = described_class.core_field_options
      expect(options).to be_an(Array)
      expect(options.length).to eq(described_class::CORE_FIELDS.length)
      options.each do |opt|
        expect(opt).to be_an(Array)
        expect(opt.length).to eq(2)
        expect(opt[1]).to be_a(String) # the key
      end
    end
  end
end
