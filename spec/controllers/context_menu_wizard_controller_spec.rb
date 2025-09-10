require_relative '../rails_helper'

RSpec.describe ContextMenuWizardController, type: :controller do
  describe '#options' do
    let(:issues_relation) { double('relation', find_each: nil) }
    let(:mapping) { { '1' => { parent_id: '2', map: {} } } }

    before do
      allow(Issue).to receive(:where).and_return(issues_relation)
      allow(Rails.cache).to receive(:fetch).and_return(mapping)
    end

    it 'renders child options when parent params are present' do
      allow(controller).to receive(:child_options).with(mapping).and_return([{ id: 1 }])

      get :options, params: { issue_ids: '1,2', parent_id: '1', parent_value: '2' }

      expect(response.media_type).to eq('application/json')
      expect(response.body).to eq([{ id: 1 }].to_json)
    end

    it 'renders parent options when parent params are missing' do
      allow(controller).to receive(:parent_options).with(mapping).and_return([{ id: 3 }])

      get :options, params: { issue_ids: '1,2' }

      expect(response.body).to eq([{ id: 3 }].to_json)
    end
  end

  describe '#save' do
    let(:issue1) { double('Issue') }
    let(:issue2) { double('Issue') }
    let(:relation) { double('relation') }

    before do
      allow(relation).to receive(:find_each).and_yield(issue1).and_yield(issue2)
      allow(Issue).to receive(:where).and_return(relation)
      allow(issue1).to receive(:custom_field_values=)
      allow(issue1).to receive(:save)
      allow(issue1).to receive(:errors).and_return(double(any?: false, full_messages: []))
      allow(issue2).to receive(:custom_field_values=)
      allow(issue2).to receive(:save)
      allow(issue2).to receive(:errors).and_return(double(any?: false, full_messages: []))
    end

    it 'sets the field value on each issue and saves them' do
      post :save, params: { issue_ids: '1,2', issue: { custom_field_values: { '5' => 'foo' } } }

      expect(issue1).to have_received(:custom_field_values=).with('5' => 'foo')
      expect(issue1).to have_received(:save)
      expect(issue2).to have_received(:custom_field_values=).with('5' => 'foo')
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

      expect(issue1).to have_received(:custom_field_values=).with('5' => '')
      expect(issue2).to have_received(:custom_field_values=).with('5' => '')
    end

    it 'does nothing when blank value is submitted' do
      expect(issue1).not_to receive(:custom_field_values=)
      expect(issue2).not_to receive(:custom_field_values=)

      post :save, params: { issue_ids: '1,2', issue: { custom_field_values: { '5' => '' } } }

      expect(response).to have_http_status(:ok)
    end

    it 'does nothing when empty array is submitted' do
      expect(issue1).not_to receive(:custom_field_values=)
      expect(issue2).not_to receive(:custom_field_values=)

      post :save, params: { issue_ids: '1,2', issue: { custom_field_values: { '5' => [] } } }

      expect(response).to have_http_status(:ok)
    end

    it 'accepts ids[] array parameters' do
      post :save, params: { ids: ['1', '2'], issue: { custom_field_values: { '5' => 'bar' } } }

      expect(issue1).to have_received(:custom_field_values=).with('5' => 'bar')
      expect(issue2).to have_received(:custom_field_values=).with('5' => 'bar')
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

  describe 'query count' do
    let(:issues_relation) { double('relation') }

    before do
      controller.instance_variable_set(:@issues, issues_relation)
      allow(controller).to receive(:intersect_allowed_values).and_return([])
    end

    it 'loads parent custom fields with a single query' do
      mapping = {
        '10' => { parent_id: '2', map: {} },
        '11' => { parent_id: '3', map: {} }
      }
      allow(CustomField).to receive(:where).and_return([])

      recorder = ActiveRecord::QueryRecorder.new do
        controller.send(:parent_options, mapping)
      end

      expect(recorder.count).to eq(1)
    end

    it 'loads child custom fields with a single query' do
      mapping = {
        '20' => { parent_id: '5', map: {} },
        '21' => { parent_id: '6', map: {} }
      }
      controller.params[:parent_id] = '5'
      controller.params[:parent_value] = 'a'
      allow(CustomField).to receive(:where).and_return([])
      allow_any_instance_of(CustomField).to receive(:possible_values_options).and_return([])

      recorder = ActiveRecord::QueryRecorder.new do
        controller.send(:child_options, mapping)
      end

      expect(recorder.count).to eq(1)
    end
  end
end
