# frozen_string_literal: true

require_relative '../rails_helper'

# Full branch review of 2026-11-05 (docs/reviews/claude-full-review-2026-11-05.md),
# the project settings pages and services: project-pages-1 to project-pages-11.
RSpec.describe 'Full review: project settings pages', type: :request do
  fixtures :users

  let(:project) { dcf_create_project }
  let(:manager) { dcf_manager(project) }
  let(:events) { RedmineDependingCustomFields::ConfigAuditEvent }
  let(:other_role) { dcf_create_role(permissions: [:view_issues]) }
  let(:multipart) { { 'CONTENT_TYPE' => 'multipart/form-data' } }

  def as(user)
    allow(User).to receive(:current).and_return(user)
  end

  def doc
    Nokogiri::HTML(response.body)
  end

  def state_hash(field)
    RedmineDependingCustomFields::BaseService.state_hash(CustomField.find(field.id))
  end

  def service(klass, field, params, user: manager)
    RedmineDependingCustomFields.const_get(klass).new(project: project, field: CustomField.find(field.id), user: user,
                                                      params: params)
  end

  def refusal
    yield
    nil
  rescue RedmineDependingCustomFields::OperationError => e
    e
  end

  def sql_log(&block)
    statements = []
    callback = ->(*, payload) { statements << payload[:sql].to_s unless payload[:name].to_s == 'SCHEMA' }
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &block)
    statements
  end

  def instantiated(class_name, &block)
    count = 0
    callback = ->(*, payload) { count += payload[:record_count].to_i if payload[:class_name] == class_name }
    ActiveSupport::Notifications.subscribed(callback, 'instantiation.active_record', &block)
    count
  end

  # project-pages-1 and project-pages-6: the parent of the dependency page
  # is named, and its values are sent, only to a user who may see it; a
  # standard parent counts whatever the standard-field setting says.
  describe 'the parent field on the dependency page' do
    let(:secret) { "SECRET-#{SecureRandom.hex(3)}" }
    let(:parent) { dcf_list_field(name: "Region-#{SecureRandom.hex(3)}", values: [secret, 'Other']) }
    let(:child) do
      field = dcf_list_field(format: 'depending_list', name: "City-#{SecureRandom.hex(3)}", values: %w[c1 c2],
                             parent: parent)
      dcf_set_dependencies(field, value_dependencies: { secret => %w[c1] })
    end
    let(:path) { custom_field_configuration_field_dependencies_path(project, child) }

    def save(raw)
      patch custom_field_configuration_update_dependencies_path(project, child),
            params: { dependencies_json: raw, state_hash: state_hash(child), confirm: '1' }, headers: multipart
    end

    it 'never names a parent hidden for the role or sends its values' do
      parent.update!(visible: false, role_ids: [other_role.id])
      as(manager)

      get path

      expect(response).to have_http_status(200)
      expect(response.body).not_to include(parent.name)
      expect(response.body).not_to include(secret)
      expect(doc.css('fieldset[data-dcf-editor]')).to be_empty
      expect(doc.at_css('p.warning').text.strip).to eq(I18n.t(:text_dcf_parent_not_available_generic))

      save(JSON.generate('value_dependencies' => { secret => %w[c2] }, 'default_value_dependencies' => {}))
      expect(response).to have_http_status(404)
      expect(CustomField.find(child.id).value_dependencies.to_hash).to eq(secret => %w[c1])
      text = events.where(custom_field_id: child.id).map { |row| row.attributes.values.join(' ') }.join(' ')
      expect(text).not_to include(secret)
      expect(text).not_to include(parent.name)
    end

    it 'never names a parent that is not used in the project; an administrator gets the name' do
      parent.update!(is_for_all: false)
      parent.projects = [dcf_create_project(name: 'Elsewhere')]
      as(manager)
      get path
      expect(response.body).not_to include(parent.name)
      expect(doc.at_css('p.warning').text.strip).to eq(I18n.t(:text_dcf_parent_not_available_generic))

      as(dcf_admin)
      get path
      expect(doc.at_css('p.warning').text.strip).to eq(I18n.t(:text_dcf_parent_not_available, name: parent.name))
    end

    it 'shows the editor for a standard parent while standard fields are not managed in projects' do
      child
      allow(Setting).to receive(:plugin_redmine_depending_custom_fields)
        .and_return('manage_standard_custom_fields' => '0')
      as(manager)

      get path
      expect(response).to have_http_status(200)
      expect(doc.css('fieldset[data-dcf-editor]').size).to eq(1)

      save(JSON.generate('value_dependencies' => { secret => %w[c2] }, 'default_value_dependencies' => {}))
      expect(response).to have_http_status(302)
      expect(CustomField.find(child.id).value_dependencies.to_hash).to eq(secret => %w[c2])
    end
  end

  # project-pages-2: the default enumeration goes with its value.
  describe 'removing the default enumeration value' do
    it 'clears the default of a standard enumeration field' do
      field = dcf_enum_field(names: %w[X Y])
      x = field.enumerations.detect { |e| e.name == 'X' }
      field.update!(default_value: x.id.to_s)

      service('RemoveValueService', field, { enumeration_id: x.id.to_s, confirm: '1' }).call

      expect(CustomField.find(field.id).default_value).to be_nil
      expect(events.where(custom_field_id: field.id).last.changes_summary).to include('default value cleared')
    end

    it 'removes the default value of a depending_enumeration without a parent' do
      field = dcf_enum_field(format: 'depending_enumeration', names: %w[X Y])
      x = field.enumerations.detect { |e| e.name == 'X' }
      field.update!(default_value: x.id.to_s)

      error = refusal { service('RemoveValueService', field, { enumeration_id: x.id.to_s, confirm: '1' }).call }

      expect(error).to be_nil
      expect(CustomFieldEnumeration.where(id: x.id)).to be_empty
      expect(CustomField.find(field.id).default_value).to be_nil
    end
  end

  # project-pages-3: the overview tab needs counts, never every value or project row.
  describe 'the overview tab' do
    it 'counts values and projects without loading the rows' do
      enum = dcf_enum_field(names: Array.new(40) { |i| "E#{i}" }, name: "Enum-#{SecureRandom.hex(3)}")
      shared = dcf_list_field(values: %w[A B], is_for_all: false, name: "Shared-#{SecureRandom.hex(3)}",
                              projects: [project, dcf_create_project(name: 'P2'), dcf_create_project(name: 'P3')])
      as(manager)

      loaded = instantiated('CustomFieldEnumeration') { get settings_project_path(project) }

      expect(response).to have_http_status(200)
      expect(loaded).to eq(0)
      rows = doc.css('table.dcf-config-fields tbody tr').to_h { |tr| [tr.at_css('td a').text, tr.css('td').map(&:text)] }
      expect(rows[enum.name][4].strip).to eq('40')
      expect(rows[shared.name][3].strip).to eq('3')
      expect(rows[shared.name][2]).to include(I18n.t(:label_scope_shared))
    end

    it 'loads no enumeration row in relevant_fields' do
      dcf_enum_field(names: %w[X Y Z])
      expect(instantiated('CustomFieldEnumeration') do
        RedmineDependingCustomFields::FieldRelevance.relevant_fields(project)
      end).to eq(0)
    end
  end

  # project-pages-4: core limits an enumeration name to 60 characters.
  describe 'enumeration names longer than 60 characters' do
    let(:field) { dcf_enum_field(names: %w[X Y]) }
    let(:long) { 'n' * 61 }

    it 'gives the length error when adding, renaming or saving the table' do
      x = field.enumerations.detect { |e| e.name == 'X' }
      rows = field.enumerations.to_h do |e|
        [e.id.to_s, { 'name' => e.id == x.id ? long : e.name, 'position' => e.position.to_s, 'active' => '1' }]
      end
      [
        -> { service('AddValueService', field, { value: long }).call },
        -> { service('RenameValueService', field, { enumeration_id: x.id.to_s, new_value: long }).call },
        -> { service('UpdateEnumerationsService', field, { enumerations: rows, confirm: '1' }).call }
      ].each do |call|
        error = refusal(&call)
        expect([error&.key, error&.interpolations]).to eq([:error_dcf_value_length, { max: 60 }])
      end
      expect(field.enumerations.reload.map(&:name)).to eq(%w[X Y])
      expect(service('AddValueService', field, { value: 'n' * 60 }).call).to be_truthy
    end
  end

  # project-pages-5: a list stored with a repeated value can be reordered.
  describe 'reordering a list with a repeated value' do
    it 'accepts the order of the values the page shows and drops the repeat' do
      field = dcf_list_field(values: %w[A B])
      field.possible_values = %w[A B A]
      field.save!(validate: false)

      error = refusal { service('ReorderValuesService', field, { ordered_values: %w[B A] }).call }

      expect(error).to be_nil
      expect(CustomField.find(field.id).possible_values).to eq(%w[B A])
    end
  end

  # project-pages-7: the audit row of a refused cascade into a field the
  # manager cannot see holds no id of that field.
  describe 'a cascade into a hidden child over the storage limit' do
    it 'keeps the id of the hidden child out of the audit summary' do
      parent = dcf_list_field(name: "Parent-#{SecureRandom.hex(3)}", values: %w[A B])
      child = dcf_list_field(format: 'depending_list', name: 'HIDDEN-CHILD', values: %w[a1], parent: parent)
      child = dcf_set_dependencies(child, value_dependencies: { 'A' => %w[a1] })
      child.update!(visible: false, role_ids: [other_role.id])
      raw = CustomField.connection.select_value(CustomField.where(id: child.id).select(:format_store).to_sql)
      allow(RedmineDependingCustomFields::StorageLimits).to receive(:column_limit).and_return(nil)
      allow(RedmineDependingCustomFields::StorageLimits).to receive(:column_limit)
        .with('format_store').and_return(raw.bytesize)

      error = refusal do
        service('RenameValueService', parent, { old_value: 'A', new_value: "A#{'2' * 20}", confirm: '1' }).call
      end

      expect(error.key).to eq(:error_save_failed)
      row = events.where(custom_field_id: parent.id).order(:id).last
      expect(row.changes_summary).to match(/\Aformat_store: \d+ bytes exceeds \d+\z/)
      expect(row.attributes.values.join(' ')).not_to include("##{child.id}")
    end
  end

  # project-pages-8: one capped count for every deactivated value.
  describe 'deactivating values in the batch table' do
    it 'counts the usage of all deactivated values in one query' do
      field = dcf_enum_field(names: %w[X Y Z W])
      rows = field.enumerations.to_h do |e|
        [e.id.to_s, { 'name' => e.name, 'position' => e.position.to_s, 'active' => e.name == 'W' ? '1' : '0' }]
      end
      field.enumerations.first(2).each { |e| dcf_custom_value(field, e.id) }

      log = sql_log { service('UpdateEnumerationsService', field, { enumerations: rows, confirm: '1' }).call }

      counts = log.grep(/COUNT/i).grep(/custom_values/)
      expect(counts.size).to eq(1)
      expect(events.where(custom_field_id: field.id).last.affected_values_count).to eq(2)
    end
  end

  # project-pages-9: a removal counts each usage once and loads the
  # dependent fields once.
  describe 'the impact of a removal' do
    it 'runs two usage counts and loads the children once' do
      parent = dcf_list_field(values: %w[A B])
      child = dcf_list_field(format: 'depending_list', values: %w[a1], parent: parent)
      dcf_set_dependencies(child, value_dependencies: { 'A' => %w[a1] })
      dcf_custom_value(parent, 'A')
      allow(RedmineDependingCustomFields::FieldRelevance).to receive(:children_of).and_call_original

      log = sql_log { service('RemoveValueService', parent, { value: 'A', confirm: '1' }).call }

      expect(RedmineDependingCustomFields::FieldRelevance).to have_received(:children_of).once
      expect(log.grep(/COUNT/i).grep(/custom_values/).size).to eq(2)
      expect(CustomField.find(child.id).value_dependencies.to_hash).to eq({})
    end
  end

  # project-pages-10: one project lookup for the page of the admin audit.
  describe 'the administration audit page' do
    it 'reads the project names in one query' do
      as(dcf_admin)
      field = dcf_list_field(values: %w[A B])
      record = lambda do
        events.create!(project_id: project.id, custom_field_id: field.id, custom_field_name: field.name,
                       acting_user_id: 1, acting_user_name: 'Admin', action: 'add_value', status: 'success')
      end
      record.call
      one = sql_log { get dcf_config_audit_path }.grep(/FROM ["`]?projects["`]?/i).size
      19.times { record.call }
      many = sql_log { get dcf_config_audit_path }.grep(/FROM ["`]?projects["`]?/i).size

      expect(response.body).to include(ERB::Util.html_escape(project.name))
      expect(many).to eq(one)
    end
  end

  # project-pages-11: a closed project is not called archived.
  describe 'the read-only message' do
    it 'names closed projects in every locale' do
      { 'en' => /closed/, 'de' => /geschlossen/, 'fr' => /fermé/, 'nl' => /gesloten/ }.each do |locale, word|
        expect(I18n.t(:error_project_archived, locale: locale)).to match(word), locale
      end
    end
  end
end
