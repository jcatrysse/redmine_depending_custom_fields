require_relative '../rails_helper'

RSpec.describe RedmineDependingCustomFields::ParentValueResolver do
  describe '.values' do
    context 'with a core_field parent reference' do
      let(:parent_ref) do
        instance_double(
          RedmineDependingCustomFields::ParentReference,
          type: 'core_field',
          key: key,
          custom_field: nil
        )
      end

      context 'when key is tracker_id' do
        let(:key) { 'tracker_id' }

        it 'returns the tracker_id as a string array' do
          issue = double('issue', tracker_id: 3)
          expect(described_class.values(issue, parent_ref)).to eq(['3'])
        end

        it 'returns empty array when the value is nil' do
          issue = double('issue', tracker_id: nil)
          expect(described_class.values(issue, parent_ref)).to eq([])
        end
      end

      context 'when key is status_id' do
        let(:key) { 'status_id' }

        it 'returns the status_id as a string array' do
          issue = double('issue', status_id: 5)
          expect(described_class.values(issue, parent_ref)).to eq(['5'])
        end
      end

      context 'when key is subject' do
        let(:key) { 'subject' }

        it 'returns the subject string' do
          issue = double('issue', subject: 'Bug report')
          expect(described_class.values(issue, parent_ref)).to eq(['Bug report'])
        end

        it 'returns empty array when subject is blank' do
          issue = double('issue', subject: '')
          expect(described_class.values(issue, parent_ref)).to eq([])
        end
      end

      context 'when key is done_ratio' do
        let(:key) { 'done_ratio' }

        it 'returns the done_ratio as a string' do
          issue = double('issue', done_ratio: 50)
          expect(described_class.values(issue, parent_ref)).to eq(['50'])
        end
      end

      context 'when the object does not respond to the key' do
        let(:key) { 'tracker_id' }

        it 'returns empty array' do
          project = double('project')
          expect(described_class.values(project, parent_ref)).to eq([])
        end
      end
    end

    context 'with a custom_field parent reference' do
      let(:parent_cf) { build_custom_field(id: 10, field_format: 'list') }
      let(:parent_ref) do
        instance_double(
          RedmineDependingCustomFields::ParentReference,
          type: 'custom_field',
          key: nil,
          custom_field: parent_cf
        )
      end

      it 'returns the custom field value as a string array' do
        issue = double('issue')
        allow(issue).to receive(:custom_field_value).with(parent_cf).and_return('A')
        expect(described_class.values(issue, parent_ref)).to eq(['A'])
      end

      it 'returns multiple values as string arrays' do
        issue = double('issue')
        allow(issue).to receive(:custom_field_value).with(parent_cf).and_return(%w[A B])
        expect(described_class.values(issue, parent_ref)).to eq(%w[A B])
      end
    end

    context 'with nil arguments' do
      it 'returns empty array when customized is nil' do
        parent_ref = instance_double(
          RedmineDependingCustomFields::ParentReference,
          type: 'core_field', key: 'tracker_id', custom_field: nil
        )
        expect(described_class.values(nil, parent_ref)).to eq([])
      end

      it 'returns empty array when parent_reference is nil' do
        issue = double('issue')
        expect(described_class.values(issue, nil)).to eq([])
      end
    end
  end
end
