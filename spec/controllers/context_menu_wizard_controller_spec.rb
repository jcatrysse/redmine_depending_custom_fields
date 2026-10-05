require_relative '../rails_helper'

RSpec.describe ContextMenuWizardController, type: :controller do
  describe '#save' do
    let(:issue1) { double('Issue') }
    let(:issue2) { double('Issue') }
    let(:relation) { double('relation') }

    before do
      allow(relation).to receive(:find_each).and_yield(issue1).and_yield(issue2)
      allow(Issue).to receive(:where).and_return(relation)
      allow(issue1).to receive(:safe_attributes=)
      allow(issue1).to receive(:save)
      allow(issue1).to receive(:errors).and_return(double(any?: false, full_messages: []))
      allow(issue2).to receive(:safe_attributes=)
      allow(issue2).to receive(:save)
      allow(issue2).to receive(:errors).and_return(double(any?: false, full_messages: []))
    end

    it 'sets the field value on each issue and saves them' do
      post :save, params: { issue_ids: '1,2', issue: { custom_field_values: { '5' => 'foo' } } }

      expect(issue1).to have_received(:safe_attributes=).with('custom_field_values' => { '5' => 'foo' })
      expect(issue1).to have_received(:save)
      expect(issue2).to have_received(:safe_attributes=).with('custom_field_values' => { '5' => 'foo' })
      expect(issue2).to have_received(:save)
      expect(response).to have_http_status(:ok)
    end

    it 'returns errors when an issue fails to save' do
      allow(issue2).to receive(:errors).and_return(double(any?: true, full_messages: ['oops']))

      post :save, params: { issue_ids: '1,2', issue: { custom_field_values: { '5' => 'foo' } } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)).to eq('errors' => ['oops'])
    end

    it 'clears the value when __none__ is passed' do
      post :save, params: { issue_ids: '1,2', issue: { custom_field_values: { '5' => '__none__' } } }

      expect(issue1).to have_received(:safe_attributes=).with('custom_field_values' => { '5' => '' })
      expect(issue2).to have_received(:safe_attributes=).with('custom_field_values' => { '5' => '' })
    end

    it 'does nothing when blank value is submitted' do
      expect(issue1).not_to receive(:safe_attributes=)
      expect(issue2).not_to receive(:safe_attributes=)

      post :save, params: { issue_ids: '1,2', issue: { custom_field_values: { '5' => '' } } }

      expect(response).to have_http_status(:ok)
    end

    it 'does nothing when empty array is submitted' do
      expect(issue1).not_to receive(:safe_attributes=)
      expect(issue2).not_to receive(:safe_attributes=)

      post :save, params: { issue_ids: '1,2', issue: { custom_field_values: { '5' => [] } } }

      expect(response).to have_http_status(:ok)
    end

    it 'accepts ids[] array parameters' do
      post :save, params: { ids: ['1', '2'], issue: { custom_field_values: { '5' => 'bar' } } }

      expect(issue1).to have_received(:safe_attributes=).with('custom_field_values' => { '5' => 'bar' })
      expect(issue2).to have_received(:safe_attributes=).with('custom_field_values' => { '5' => 'bar' })
    end

    context 'when user lacks permission' do
      before do
        allow(issue1).to receive(:visible?).and_return(false)
      end

      it 'denies access' do
        post :save, params: { issue_ids: '1', fieldId: 1, value: '42' }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
