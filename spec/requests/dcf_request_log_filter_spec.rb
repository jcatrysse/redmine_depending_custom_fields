# frozen_string_literal: true

require_relative '../rails_helper'

# WP-32 (WP-25 and WP-27 inputs): the posted dependency mapping (up to 4 MiB)
# never reaches the request log. The plugin appends one anchored filter to
# Rails.application.config.filter_parameters, in place and once, so only the
# key dependencies_json is masked, on the admin form and the project page.
# The log line 'Parameters: ...' prints the start_processing payload, which
# is request.filtered_parameters; the saved value is unchanged.
RSpec.describe 'Request log filter for dependencies_json (WP-32)', type: :request do
  fixtures :users

  let(:filter) { RedmineDependingCustomFields::LOG_FILTER }
  let(:project) { dcf_create_project }
  let(:parent) { dcf_list_field(name: "Hardware-#{SecureRandom.hex(3)}", values: %w[Laptop Desktop]) }
  let(:child) do
    field = dcf_list_field(format: 'depending_list', name: "Model-#{SecureRandom.hex(3)}",
                           values: %w[MARKER-L1 MARKER-D1], parent: parent)
    dcf_set_dependencies(field, value_dependencies: { 'Laptop' => %w[MARKER-L1] })
  end

  def as(user)
    allow(User).to receive(:current).and_return(user)
  end

  def json(links)
    JSON.generate('value_dependencies' => links, 'default_value_dependencies' => {})
  end

  def stored(field)
    CustomField.find(field.id).value_dependencies.to_hash
  end

  # The params of every start_processing event during the block.
  def logged_params(&block)
    events = []
    callback = ->(*, payload) { events << payload[:params] }
    ActiveSupport::Notifications.subscribed(callback, 'start_processing.action_controller', &block)
    expect(events.size).to eq(1)
    events.first
  end

  def multipart
    { 'CONTENT_TYPE' => 'multipart/form-data' }
  end

  describe 'the filter' do
    it 'is in the application filter list once, in the Array the request env reads' do
      filters = Rails.application.config.filter_parameters
      expect(filters.count { |entry| entry == filter }).to eq(1)
      expect(Rails.application.env_config['action_dispatch.parameter_filter']).to equal(filters)
    end

    it 'appends in place and only once, also when it runs again (to_prepare, development reload)' do
      filters = Rails.application.config.filter_parameters
      saved = filters.dup
      begin
        filters.delete(filter)
        RedmineDependingCustomFields.filter_request_log
        RedmineDependingCustomFields.filter_request_log
        expect(Rails.application.config.filter_parameters).to equal(filters)
        expect(filters.count { |entry| entry == filter }).to eq(1)
      ensure
        filters.replace(saved)
      end
    end

    it 'masks only the key dependencies_json, at the top level and nested' do
      masked = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter(
        'dependencies_json' => '{"a":1}', 'state_hash' => 'h', 'q' => 'x', 'page' => '2', 'batch_scope' => 'page',
        'value_dependencies' => { 'A' => ['b'] }, 'default_value_dependencies' => { 'A' => 'b' },
        'enumerations' => { '1' => { 'name' => 'N' } },
        'custom_field' => { 'name' => 'N', 'dependencies_json' => '{}', 'value_dependencies' => { 'A' => ['b'] },
                            'possible_values' => "A\nB" }
      )
      expect(masked['dependencies_json']).to eq('[FILTERED]')
      expect(masked['custom_field']['dependencies_json']).to eq('[FILTERED]')
      expect(masked.except('dependencies_json', 'custom_field'))
        .to eq('state_hash' => 'h', 'q' => 'x', 'page' => '2', 'batch_scope' => 'page',
               'value_dependencies' => { 'A' => ['b'] }, 'default_value_dependencies' => { 'A' => 'b' },
               'enumerations' => { '1' => { 'name' => 'N' } })
      expect(masked['custom_field'].except('dependencies_json'))
        .to eq('name' => 'N', 'value_dependencies' => { 'A' => ['b'] }, 'possible_values' => "A\nB")
    end
  end

  describe 'admin custom field form' do
    before { as(dcf_admin) }

    it 'logs custom_field[dependencies_json] as [FILTERED] and still saves the posted mapping' do
      child
      params = logged_params do
        put "/custom_fields/#{child.id}",
            params: { custom_field: { name: 'Model renamed', dependencies_json: json('Desktop' => %w[MARKER-D1]) } },
            headers: multipart
      end

      expect(response).to redirect_to("/custom_fields/#{child.id}/edit")
      expect(params['custom_field']['dependencies_json']).to eq('[FILTERED]')
      expect(params['custom_field']['name']).to eq('Model renamed')
      expect(params.to_s).not_to include('MARKER-D1')
      expect(stored(child)).to eq('Desktop' => %w[MARKER-D1])
    end

    it 'filters a refused payload too (edit re-rendered with 200)' do
      child
      params = logged_params do
        put "/custom_fields/#{child.id}", params: { custom_field: { dependencies_json: '{"MARKER-BAD"' } },
                                          headers: multipart
      end

      expect(response).to have_http_status(200)
      expect(params['custom_field']['dependencies_json']).to eq('[FILTERED]')
      expect(params.to_s).not_to include('MARKER-BAD')
      expect(stored(child)).to eq('Laptop' => %w[MARKER-L1])
    end
  end

  describe 'project dependency page' do
    before { as(dcf_manager(project)) }

    # Changed by WP-34 (UD-23): the child is global, so the save posts
    # confirm '1'; was no confirm. The filter is the same for both.
    def save(raw, state)
      logged_params do
        patch custom_field_configuration_update_dependencies_path(project, child),
              params: { dependencies_json: raw, state_hash: state, confirm: '1' }, headers: multipart
      end
    end

    def state_hash
      RedmineDependingCustomFields::BaseService.state_hash(CustomField.find(child.id))
    end

    it 'logs dependencies_json as [FILTERED] on a save, a refused payload and a stale page' do
      child
      state = state_hash
      logged = [save(json('Desktop' => %w[MARKER-D1]), state)]
      expect(response).to redirect_to(custom_field_configuration_field_dependencies_path(project, child))
      expect(stored(child)).to eq('Desktop' => %w[MARKER-D1])
      logged << save('{"MARKER-BAD"', state_hash)
      expect(response).to have_http_status(422)
      logged << save(json('Laptop' => %w[MARKER-STALE]), 'stale')
      expect(response).to have_http_status(409)

      expect(logged.map { |params| params['dependencies_json'] }).to eq(['[FILTERED]'] * 3)
      expect(logged.map { |params| params['state_hash'] }).to eq([state, state_hash, 'stale'])
      expect(logged.map(&:to_s).grep(/MARKER-/)).to be_empty
      expect(stored(child)).to eq('Desktop' => %w[MARKER-D1])
      rows = RedmineDependingCustomFields::ConfigAuditEvent.where(custom_field_id: child.id).order(:id)
      expect(rows.count).to eq(3)
      expect(rows.first.status).to eq('success')
    end
  end
end
