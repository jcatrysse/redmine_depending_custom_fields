require_relative '../rails_helper'

RSpec.describe RedmineDependingCustomFields::ParentMenuBuilder do
  describe '.build' do
    let(:issues) { [instance_double(Issue), instance_double(Issue)] }
    let(:parent1) { instance_double(CustomField, id: 10, name: 'Parent1') }
    let(:parent2) { instance_double(CustomField, id: 12, name: 'Parent2') }
    let(:mapping) do
      {
        '31' => { parent_id: '10', map: { 'a' => ['1'], 'b' => ['2'] } },
        '32' => { parent_id: '10', map: { 'a' => ['3'] } },
        '33' => { parent_id: '12', map: { 'x' => ['9'] } }
      }
    end

    before do
      allow(RedmineDependingCustomFields::ParentDetector).to receive(:for_issues).and_return([parent1, parent2])
      allow(Rails.cache).to receive(:fetch).with('depending_custom_fields/mapping').and_yield.and_return(mapping)
      allow(MappingBuilder).to receive(:build).and_return(mapping)
    end

    it 'detects parents using ParentDetector' do
      described_class.build(issues)
      expect(RedmineDependingCustomFields::ParentDetector).to have_received(:for_issues).with(issues)
    end

    it 'collects unique values for each parent from mapping' do
      result = described_class.build(issues)
      expect(result).to eq([
        { id: 10, name: 'Parent1', values: ['a', 'b'] },
        { id: 12, name: 'Parent2', values: ['x'] }
      ])
    end
  end
end
