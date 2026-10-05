# frozen_string_literal: true

require_relative '../rails_helper'

# WP-04 characterization: pins what the project custom field configuration page
# saves today (0.0.16) for dependency mappings and enumeration order. Only WP-27
# may change an expectation here, and only as a listed flip.
RSpec.describe 'Project custom field configuration saves (characterization)', type: :request do
  fixtures :users

  let(:project) { dcf_create_project }
  let(:manager) { dcf_manager(project) }

  before { allow(User).to receive(:current).and_return(manager) }

  def audit_events(field)
    RedmineDependingCustomFields::ConfigAuditEvent.where(custom_field_id: field.id).order(:id)
  end

  def stores(field)
    field.reload
    [field.value_dependencies, field.default_value_dependencies]
  end

  describe 'PATCH update_dependencies' do
    def depending_pair(scope)
      parent = dcf_list_field(name: 'Parent', values: %w[A B], **scope)
      child = dcf_list_field(format: 'depending_list', name: 'Child', values: %w[c1 c2], parent: parent, **scope)
      dcf_set_dependencies(child, value_dependencies: { 'A' => %w[c1], 'B' => %w[c2] },
                                  default_value_dependencies: { 'A' => 'c1' })
    end

    # Shared (is_for_all) field: the dependency save has no confirmation step.
    it 'clears both stores of a global field when no dependency params are sent' do
      child = depending_pair(is_for_all: true)

      patch custom_field_configuration_update_dependencies_path(project, child)

      expect(response).to redirect_to(custom_field_configuration_field_dependencies_path(project, child))
      expect(flash[:notice]).to eq(I18n.t(:notice_dependencies_saved))
      expect(stores(child)).to eq([{}, {}])
      event = audit_events(child).last
      expect([event.action, event.status]).to eq(%w[update_dependencies success])
      expect(JSON.parse(event.after_value)).to eq('value_dependencies' => {}, 'default_value_dependencies' => {})
    end

    # The matrix cells are bare checkboxes (no hidden companion) and every row
    # has an always enabled default select, so an all-unticked submit with
    # blank defaults carries only state_hash and blank defaults.
    it 'clears the mapping of a project-only field from an all-unticked submit with blank defaults' do
      child = depending_pair(is_for_all: false, projects: [project])
      get custom_field_configuration_field_dependencies_path(project, child)
      cells = Nokogiri::HTML(response.body).css('[name^="value_dependencies"]')
      expect(cells.map { |c| c['type'] }.uniq).to eq(%w[checkbox])

      patch custom_field_configuration_update_dependencies_path(project, child),
            params: { state_hash: RedmineDependingCustomFields::BaseService.state_hash(child),
                      default_value_dependencies: { 'A' => '', 'B' => '' } }

      expect(response).to redirect_to(custom_field_configuration_field_dependencies_path(project, child))
      expect(stores(child)).to eq([{}, {}])
    end

    it 'rejects an all-unticked submit with 422 while a row default is still selected, keeping both stores' do
      child = depending_pair(is_for_all: false, projects: [project])

      patch custom_field_configuration_update_dependencies_path(project, child),
            params: { default_value_dependencies: { 'A' => 'c1', 'B' => '' } }

      expect(response).to have_http_status(422)
      expect(response.body).to include(I18n.t(:error_invalid_dependency))
      expect(stores(child)).to eq([{ 'A' => %w[c1], 'B' => %w[c2] }, { 'A' => 'c1' }])
    end
  end

  describe 'enumeration order' do
    let(:enum_field) { dcf_enum_field(names: %w[W X Y Z]) }

    def by_name(field)
      field.enumerations.reload.index_by(&:name)
    end

    # Positions as [name, position] pairs in stored order.
    def stored_order(field)
      CustomFieldEnumeration.where(custom_field_id: field.id).order(:position, :id).map { |e| [e.name, e.position] }
    end

    def save_positions(field, positions)
      rows = by_name(field).values.to_h do |enum|
        [enum.id.to_s, { name: enum.name, position: positions.fetch(enum.name).to_s, active: '1' }]
      end
      patch custom_field_configuration_update_enumerations_path(project, field), params: { enumerations: rows }
      expect(response).to redirect_to(custom_field_configuration_field_path(project, field))
    end

    describe 'through update_enumerations' do
      it 'applies a staged drag of the last row to the top as positions 1..4' do
        save_positions(enum_field, 'W' => 2, 'X' => 3, 'Y' => 4, 'Z' => 1)

        expect(stored_order(enum_field)).to eq([['Z', 1], ['W', 2], ['X', 3], ['Y', 4]])
      end

      it 'breaks equal submitted positions by the stored position' do
        save_positions(enum_field, 'W' => 2, 'X' => 2, 'Y' => 1, 'Z' => 1)

        expect(stored_order(enum_field)).to eq([['Y', 1], ['Z', 2], ['W', 3], ['X', 4]])
      end

      it 'renumbers sparse submitted positions to 1..4 in their relative order' do
        save_positions(enum_field, 'W' => 40, 'X' => 10, 'Y' => 30, 'Z' => 20)

        expect(stored_order(enum_field)).to eq([['X', 1], ['Z', 2], ['Y', 3], ['W', 4]])
      end

      it 'sorts blank and non-numeric submitted positions first, as 0' do
        save_positions(enum_field, 'W' => 3, 'X' => '', 'Y' => 'abc', 'Z' => 2)

        expect(stored_order(enum_field)).to eq([['X', 1], ['Y', 2], ['Z', 3], ['W', 4]])
      end

      # The screen renders the hidden positions as 1..n, so an untouched save
      # rewrites gapped stored positions and is audited as a reorder.
      it 'renumbers gapped stored positions on an untouched save and audits it as reordered' do
        { 'W' => 2, 'X' => 5, 'Y' => 7, 'Z' => 11 }.each do |name, position|
          by_name(enum_field)[name].update_column(:position, position)
        end

        save_positions(enum_field, 'W' => 1, 'X' => 2, 'Y' => 3, 'Z' => 4)

        expect(stored_order(enum_field)).to eq([['W', 1], ['X', 2], ['Y', 3], ['Z', 4]])
        event = audit_events(enum_field).last
        expect(event.changes_summary).to eq('Saved 4 enumeration value(s): reordered')
        expect(JSON.parse(event.after_value)).to eq('reordered' => true)
      end
    end

    describe 'through reorder_values' do
      it 'writes positions 1..4 in the submitted id order over gapped stored positions' do
        { 'W' => 2, 'X' => 4, 'Y' => 6, 'Z' => 8 }.each do |name, position|
          by_name(enum_field)[name].update_column(:position, position)
        end
        ids = by_name(enum_field).transform_values { |e| e.id.to_s }

        patch custom_field_configuration_reorder_values_path(project, enum_field),
              params: { ordered_values: ids.values_at('Y', 'W', 'Z', 'X') }

        expect(response).to redirect_to(custom_field_configuration_field_path(project, enum_field))
        expect(stored_order(enum_field)).to eq([['Y', 1], ['W', 2], ['Z', 3], ['X', 4]])
      end
    end
  end
end
