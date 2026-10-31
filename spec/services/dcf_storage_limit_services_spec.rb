# frozen_string_literal: true

require_relative '../rails_helper'

# WP-12 (limits design 5.1 to 5.3, quality S3): BaseService maps a storage
# violation to an error naming the field and both sizes, and
# ActiveRecord::ValueTooLong to a save_failed row without database content.
# Every rejected call writes exactly one failure row and changes nothing.
RSpec.describe 'Service storage error mapping (WP-12)' do
  fixtures :users

  let(:limits) { RedmineDependingCustomFields::StorageLimits }
  let(:events) { RedmineDependingCustomFields::ConfigAuditEvent }
  let(:project) { dcf_create_project }
  let(:secret_sql) do
    "Mysql2::Error: Data too long for column 'possible_values' at row 1: " \
      "UPDATE `custom_fields` SET `possible_values` = '--- SECRET_VALUE_42'"
  end

  def service(klass, field, params, user: dcf_admin)
    "RedmineDependingCustomFields::#{klass}".constantize
                                            .new(project: project, field: field, user: user, params: params)
  end

  # The OperationError the call raises (the example fails when none is raised).
  def rejected
    yield
    raise 'expected an OperationError'
  rescue RedmineDependingCustomFields::OperationError => e
    e
  end

  def stub_limit(column, bytes)
    allow(limits).to receive(:column_limit).and_return(nil)
    allow(limits).to receive(:column_limit).with(column).and_return(bytes)
  end

  def column_value(field, column)
    CustomField.connection.select_value(CustomField.where(id: field.id).select(column).to_sql)
  end

  def yaml_bytes(values)
    limits.serialized_bytesize(CustomField, 'possible_values', values)
  end

  def value_too_long(message = secret_sql)
    ActiveRecord::ValueTooLong.new(message, sql: "UPDATE custom_fields SET possible_values = '--- SECRET_VALUE_42'")
  end

  def row_text(row)
    row.attributes.values.join(' ')
  end

  describe 'OperationError' do
    let(:klass) { RedmineDependingCustomFields::OperationError }

    it 'keeps the defaults of every existing call' do
      e = klass.new(:k)
      expect([e.key, e.http_status, e.audit_status, e.summary, e.interpolations, e.payload, e.message])
        .to eq([:k, :unprocessable_entity, 'validation_failed', nil, {}, nil, 'k'])
    end

    it 'echoes all six arguments and keeps them out of the message' do
      payload = Object.new
      e = klass.new(:k, http_status: :conflict, audit_status: 'save_failed', summary: 'S3CRET',
                        interpolations: { field: 'F' }, payload: payload)
      expect([e.key, e.http_status, e.audit_status, e.summary, e.interpolations, e.payload])
        .to eq([:k, :conflict, 'save_failed', 'S3CRET', { field: 'F' }, payload])
      expect(e.message).to eq('k')
      expect(e.full_message(highlight: false)).not_to include('S3CRET')
    end

    it 'gives every instance its own interpolations Hash' do
      expect(klass.new(:a).interpolations).not_to be(klass.new(:b).interpolations)
    end
  end

  describe 'a possible_values violation (T-SIZE-1)' do
    let(:field) { dcf_list_field(name: 'R&D', values: %w[A B], is_for_all: false, projects: [project]) }

    it 'raises error_dcf_values_too_large with field and sizes and writes one validation_failed row' do
      stored = column_value(field, 'possible_values')
      stub_limit('possible_values', stored.bytesize)
      bytes = yaml_bytes(%w[A B SECRET_VAL])

      error = nil
      expect { error = rejected { service('AddValueService', field, { value: 'SECRET_VAL' }).call } }
        .to change(events, :count).by(1)

      expect(error.key).to eq(:error_dcf_values_too_large)
      expect(error.interpolations)
        .to eq(field: 'R&D', size: limits.delimited(bytes), limit: limits.delimited(stored.bytesize))
      expect([error.http_status, error.audit_status]).to eq([:unprocessable_entity, 'validation_failed'])
      row = events.order(:id).last
      expect([row.action, row.status, row.error_message])
        .to eq(%w[validation_failed validation_failed error_dcf_values_too_large])
      expect(row.changes_summary)
        .to eq("possible_values: #{bytes} bytes exceeds #{stored.bytesize} (custom field ##{field.id})")
      expect(row_text(row)).not_to include('SECRET_VAL')
      expect(row.changes_summary).not_to include('R&D')
      expect(events.where(status: 'success').count).to eq(0)
      expect(column_value(field, 'possible_values')).to eq(stored)
      expect(field.reload.possible_values).to eq(%w[A B])
    end

    it 'names the edited field also when it is hidden from the manager role' do
      hidden = dcf_list_field(name: 'Hidden-Edited', values: %w[A B], is_for_all: false, projects: [project])
      hidden.update!(visible: false, role_ids: [dcf_create_role.id])
      stub_limit('possible_values', column_value(hidden, 'possible_values').bytesize)

      error = rejected { service('AddValueService', hidden, { value: 'C' }, user: dcf_manager(project)).call }

      expect([error.key, error.interpolations[:field]]).to eq([:error_dcf_values_too_large, 'Hidden-Edited'])
    end

    it 'still raises the mapped error when the failure row cannot be written' do
      stub_limit('possible_values', column_value(field, 'possible_values').bytesize)
      allow_any_instance_of(RedmineDependingCustomFields::AuditRecorder)
        .to receive(:record_failure!).and_raise(StandardError, 'audit down')

      error = nil
      expect { error = rejected { service('AddValueService', field, { value: 'C' }).call } }
        .not_to change(events, :count)
      expect(error.key).to eq(:error_dcf_values_too_large)
    end
  end

  describe 'a format_store violation (T-SIZE-2)' do
    let(:parent) { dcf_list_field(name: "Parent-#{SecureRandom.hex(3)}", values: %w[A B]) }
    let(:child) do
      dcf_list_field(format: 'depending_list', name: 'Child <b>&', values: %w[a1 b1], parent: parent)
    end

    it 'raises error_dcf_mapping_too_large for DependencyMappingService and changes nothing' do
      stored = column_value(child, 'format_store')
      stub_limit('format_store', stored.bytesize)

      error = nil
      expect do
        error = rejected do
          service('DependencyMappingService', child, { value_dependencies: { 'A' => %w[a1 b1] },
                                                       default_value_dependencies: { 'A' => 'a1' } }).call
        end
      end.to change(events, :count).by(1)

      expect(error.key).to eq(:error_dcf_mapping_too_large)
      expect(error.interpolations[:field]).to eq('Child <b>&')
      expect(error.interpolations.keys).to contain_exactly(:field, :size, :limit)
      expect(error.interpolations[:limit]).to eq(limits.delimited(stored.bytesize))
      row = events.order(:id).last
      expect([row.status, row.error_message]).to eq(%w[validation_failed error_dcf_mapping_too_large])
      expect(row.changes_summary)
        .to match(/\Aformat_store: \d+ bytes exceeds #{stored.bytesize} \(custom field ##{child.id}\)\z/)
      expect(column_value(child, 'format_store')).to eq(stored)
      expect(child.reload.value_dependencies).to eq({})
    end
  end

  describe 'a rename cascade that overflows a dependent field' do
    let(:parent) { dcf_list_field(name: "Parent-#{SecureRandom.hex(3)}", values: %w[A B]) }
    let(:other_role) { dcf_create_role }

    def child_of(parent, name: "Child-#{SecureRandom.hex(3)}", **options)
      child = dcf_list_field(format: 'depending_list', name: name, values: %w[a1 b1], parent: parent, **options)
      dcf_set_dependencies(child, value_dependencies: { 'A' => %w[a1] }, default_value_dependencies: { 'A' => 'a1' })
    end

    def rename_over_limit(child, user: dcf_admin)
      stub_limit('format_store', column_value(child, 'format_store').bytesize)
      rejected do
        service('RenameValueService', CustomField.find(parent.id),
                { old_value: 'A', new_value: "A#{'2' * 20}", confirm: '1' }, user: user).call
      end
    end

    it 'names the child, keeps the parent on the audit row and rolls everything back (T-SIZE-2)' do
      child = child_of(parent)
      value = dcf_custom_value(parent, 'A')
      raw_child = column_value(child, 'format_store')
      values_before = CustomField.find(parent.id).possible_values

      error = nil
      expect { error = rename_over_limit(child) }.to change(events, :count).by(1)

      expect(error.key).to eq(:error_dcf_mapping_too_large)
      expect(error.interpolations[:field]).to eq(child.name)
      expect(error.summary).to end_with("(custom field ##{child.id})")
      row = events.order(:id).last
      expect([row.custom_field_id, row.custom_field_name, row.status]).to eq([parent.id, parent.name, 'validation_failed'])
      expect(row.changes_summary).to include("custom field ##{child.id}")
      expect(row.changes_summary).not_to include(child.name)
      expect(events.where(status: 'success').count).to eq(0)
      expect(column_value(child, 'format_store')).to eq(raw_child)
      expect(CustomField.find(parent.id).possible_values).to eq(values_before)
      expect(value.reload.value).to eq('A')
    end

    it 'names a child the manager can see in the project' do
      child = child_of(parent)
      error = rename_over_limit(child, user: dcf_manager(project))
      expect([error.key, error.interpolations[:field]]).to eq([:error_dcf_mapping_too_large, child.name])
    end

    # The flash is the generic text; the row keeps the storage key and the
    # numeric summary, which holds the field id, not its name.
    it 'never names a child hidden from the manager role (security model 5)' do
      child = child_of(parent, name: 'Hidden-Child')
      child.update!(visible: false, role_ids: [other_role.id])

      error = nil
      expect { error = rename_over_limit(child, user: dcf_manager(project)) }.to change(events, :count).by(1)

      expect(error.key).to eq(:error_save_failed)
      expect(error.interpolations).to eq({})
      row = events.order(:id).last
      expect([row.action, row.status, row.error_message])
        .to eq(%w[validation_failed validation_failed error_dcf_mapping_too_large])
      expect(row.changes_summary).to match(/\Aformat_store: \d+ bytes exceeds \d+ \(custom field ##{child.id}\)\z/)
      expect(row_text(row)).not_to include('Hidden-Child')
    end

    it 'never names a child that is not used in this project' do
      child = child_of(parent, name: 'Elsewhere-Child', is_for_all: false, projects: [dcf_create_project(name: 'Other')])

      error = rename_over_limit(child, user: dcf_manager(project))

      expect(error.key).to eq(:error_save_failed)
      expect(error.interpolations).to eq({})
      expect(events.order(:id).last.error_message).to eq('error_dcf_mapping_too_large')
    end

    it 'names a child of another project to an administrator' do
      child = child_of(parent, is_for_all: false, projects: [dcf_create_project(name: 'Other')])

      error = rename_over_limit(child)

      expect([error.key, error.interpolations[:field]]).to eq([:error_dcf_mapping_too_large, child.name])
    end
  end

  describe 'ActiveRecord::ValueTooLong (T-SIZE-4, SP-09)' do
    let(:field) { dcf_list_field(values: %w[A B], is_for_all: false, projects: [project]) }

    def add_raising(error)
      allow(field).to receive(:save!).and_raise(error)
      rejected { service('AddValueService', field, { value: 'C' }).call }
    end

    it 'maps to error_dcf_value_too_long with one save_failed row holding no database content' do
      error = nil
      expect { error = add_raising(value_too_long) }.to change(events, :count).by(1)

      expect([error.key, error.audit_status, error.http_status])
        .to eq([:error_dcf_value_too_long, 'save_failed', :unprocessable_entity])
      expect(error.interpolations).to eq({})
      expect(error.cause).to be_nil
      expect(error.full_message(highlight: false)).not_to include('SECRET_VALUE_42')
      row = events.order(:id).last
      expect([row.action, row.status, row.error_message]).to eq(%w[save_failed save_failed error_dcf_value_too_long])
      expect(row.changes_summary).to match(
        /\AActiveRecord::ValueTooLong column=possible_values field_id=#{field.id} possible_values_bytes=\d+ format_store_bytes=\d+\z/
      )
      %w[SECRET_VALUE_42 UPDATE Mysql2 Data\ too\ long].each { |text| expect(row_text(row)).not_to include(text) }
      expect(field.reload.possible_values).to eq(%w[A B])
    end

    it 'stores column=unknown for a message without a column name' do
      add_raising(value_too_long('PG::StringDataRightTruncation: ERROR: value too long for type character varying(255)'))
      expect(events.order(:id).last.changes_summary).to start_with('ActiveRecord::ValueTooLong column=unknown ')
    end

    it 'stores column=unknown for a column the plugin does not know' do
      add_raising(value_too_long("Data too long for column 'p4ss_fragment' at row 1"))
      expect(events.order(:id).last.changes_summary).to start_with('ActiveRecord::ValueTooLong column=unknown ')
    end

    it 'still writes the row for a message with invalid bytes' do
      expect { add_raising(value_too_long((+"\xFF column '").force_encoding('UTF-8'))) }.to change(events, :count).by(1)
      expect(events.order(:id).last.changes_summary).to start_with('ActiveRecord::ValueTooLong')
    end

    it 'falls back to the class name when the sizes cannot be measured' do
      field # created before the stub: on MySQL the validation measures it
      allow(limits).to receive(:preview_bytes).and_raise(StandardError, 'boom')
      add_raising(value_too_long)
      expect(events.order(:id).last.changes_summary).to eq('ActiveRecord::ValueTooLong')
    end

    it 'maps a ValueTooLong of the success row insert and rolls the change back' do
      allow_any_instance_of(RedmineDependingCustomFields::AuditRecorder)
        .to receive(:record_success!).and_raise(value_too_long)

      error = nil
      expect { error = rejected { service('AddValueService', field, { value: 'C' }).call } }
        .to change(events, :count).by(1).and change(events.where(status: 'save_failed'), :count).by(1)
      expect(error.key).to eq(:error_dcf_value_too_long)
      expect(field.reload.possible_values).to eq(%w[A B])
    end

    it 'maps a ValueTooLong of a cascaded child without naming the child' do
      parent = dcf_list_field(name: "Parent-#{SecureRandom.hex(3)}", values: %w[A B])
      child = dcf_list_field(format: 'depending_list', name: 'Cascade-Child', values: %w[a1], parent: parent)
      dcf_set_dependencies(child, value_dependencies: { 'A' => %w[a1] })
      raw_child = column_value(child, 'format_store')
      allow_any_instance_of(IssueCustomField).to receive(:save!).and_wrap_original do |original, *args|
        raise value_too_long if original.receiver.id == child.id

        original.call(*args)
      end

      error = nil
      expect do
        error = rejected do
          service('RenameValueService', CustomField.find(parent.id),
                  { old_value: 'A', new_value: 'A2', confirm: '1' }).call
        end
      end.to change(events, :count).by(1)

      expect(error.key).to eq(:error_dcf_value_too_long)
      row = events.order(:id).last
      expect(row.custom_field_id).to eq(parent.id)
      expect(row.changes_summary).to include("field_id=#{parent.id}")
      expect(row_text(row)).not_to include('Cascade-Child')
      expect(CustomField.find(parent.id).possible_values).to eq(%w[A B])
      expect(column_value(child, 'format_store')).to eq(raw_child)
    end

    it 'does not map other statement errors (no broad rescue)' do
      allow(field).to receive(:save!)
        .and_raise(ActiveRecord::StatementInvalid.new('PG::UniqueViolation: DETAIL: Key (name)=(SECRET) already exists'))

      expect { service('AddValueService', field, { value: 'C' }).call }
        .to raise_error(ActiveRecord::StatementInvalid)
      expect(events.where('error_message LIKE ? OR changes_summary LIKE ?', '%SECRET%', '%SECRET%').count).to eq(0)
    end
  end

  describe 'other failures' do
    let(:field) { dcf_list_field(values: %w[A B], is_for_all: false, projects: [project]) }

    it 'keeps error_save_failed for a RecordInvalid without a record' do
      allow(field).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new)

      error = nil
      expect { error = rejected { service('AddValueService', field, { value: 'C' }).call } }
        .to change(events, :count).by(1).and change(events.where(status: 'save_failed'), :count).by(1)
      expect(error.key).to eq(:error_save_failed)
    end

    it 'keeps error_save_failed for a CustomField with other validation errors' do
      record = CustomField.find(field.id)
      record.errors.add(:name, :taken)
      allow(field).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(record))

      error = nil
      expect { error = rejected { service('AddValueService', field, { value: 'C' }).call } }
        .to change(events, :count).by(1)
      expect(error.key).to eq(:error_save_failed)
      row = events.order(:id).last
      expect([row.action, row.status]).to eq(%w[save_failed save_failed])
      expect(row.error_message).to start_with('Validation failed: ')
    end

    it 'caps the stored validation message at 4,000 characters (T-AUD-11)' do
      record = CustomFieldEnumeration.new
      record.errors.add(:base, 'x' * 9_000)
      allow(field).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(record))

      expect(rejected { service('AddValueService', field, { value: 'C' }).call }.key).to eq(:error_save_failed)
      message = events.order(:id).last.error_message
      expect(message.length).to eq(4_003)
      expect(message).to start_with('Validation failed: ').and end_with('...')
    end

    it 'stores the summary of an OperationError raised by a service (T-AUD-9)' do
      svc = service('AddValueService', field, { value: 'C' })
      allow(svc).to receive(:perform!)
        .and_raise(RedmineDependingCustomFields::OperationError.new(:error_value_blank, summary: 'x'))

      expect { rejected { svc.call } }.to change(events, :count).by(1)
      row = events.order(:id).last
      expect([row.status, row.error_message, row.changes_summary]).to eq(%w[validation_failed error_value_blank x])
    end

    it 'writes no row for a change that needs confirmation' do
      global = dcf_list_field(values: %w[A B], is_for_all: true)
      expect do
        expect { service('RenameValueService', global, { old_value: 'A', new_value: 'A2' }).call }
          .to raise_error(RedmineDependingCustomFields::ConfirmationRequired)
      end.not_to change(events, :count)
    end
  end

  describe 'texts (large_lists_i18n_registry.md)' do
    texts = {
      en: ['The values of field "F" would take 1 bytes, but at most 2 bytes can be stored for this field. ' \
           'Remove or shorten values, or ask an administrator.',
           'The dependency mapping of field "F" would take 1 bytes, but at most 2 bytes can be stored for this field. ' \
           'Remove links or default values, or ask an administrator.',
           'The database rejected the change because a value is too large to be stored. Ask an administrator.'],
      de: ['Die Werte des Feldes „F“ würden 1 Bytes belegen, für dieses Feld können jedoch höchstens 2 Bytes ' \
           'gespeichert werden. Entfernen oder kürzen Sie Werte oder wenden Sie sich an einen Administrator.',
           'Die Abhängigkeitszuordnung des Feldes „F“ würde 1 Bytes belegen, für dieses Feld können jedoch höchstens ' \
           '2 Bytes gespeichert werden. Entfernen Sie Verknüpfungen oder Standardwerte oder wenden Sie sich an einen ' \
           'Administrator.',
           'Die Datenbank hat die Änderung abgelehnt, weil ein Wert zu groß zum Speichern ist. ' \
           'Wenden Sie sich an einen Administrator.'],
      fr: ['Les valeurs du champ « F » occuperaient 1 octets, mais au maximum 2 octets peuvent être enregistrés ' \
           'pour ce champ. Supprimez ou raccourcissez des valeurs, ou contactez un administrateur.',
           'Le mappage des dépendances du champ « F » occuperait 1 octets, mais au maximum 2 octets peuvent être ' \
           'enregistrés pour ce champ. Supprimez des liens ou des valeurs par défaut, ou contactez un administrateur.',
           'La base de données a refusé la modification car une valeur est trop volumineuse pour être enregistrée. ' \
           'Contactez un administrateur.'],
      nl: ['De waarden van veld "F" zouden 1 bytes innemen, maar voor dit veld kunnen maximaal 2 bytes worden ' \
           'opgeslagen. Verwijder of verkort waarden, of vraag een beheerder om hulp.',
           'De afhankelijkheidskoppeling van veld "F" zou 1 bytes innemen, maar voor dit veld kunnen maximaal 2 bytes ' \
           'worden opgeslagen. Verwijder koppelingen of standaardwaarden, of vraag een beheerder om hulp.',
           'De database heeft de wijziging geweigerd omdat een waarde te groot is om op te slaan. ' \
           'Vraag een beheerder om hulp.']
    }

    texts.each do |locale, (values, mapping, too_long)|
      it "matches the registry in #{locale}" do
        sizes = { field: 'F', size: '1', limit: '2', locale: locale }
        expect(I18n.t(:error_dcf_values_too_large, **sizes)).to eq(values)
        expect(I18n.t(:error_dcf_mapping_too_large, **sizes)).to eq(mapping)
        expect(I18n.t(:error_dcf_value_too_long, locale: locale)).to eq(too_long)
      end
    end
  end

  describe 'successful saves above the audit cap (UN-51, PC-19)' do
    # Changed by WP-27 (was: the full mapping stored shrunk with payload_truncated,
    # payload_bytes and payload_sha256): the compact delta v2 of a mapping whose
    # full JSON is above the cap is stored byte-identical, without markers; the
    # marker case stays covered by the AddValueService example below.
    it 'saves a mapping whose full JSON is above 16,384 bytes and stores the compact delta unshrunk (T-AUD-10)' do
      parent = dcf_list_field(name: "Parent-#{SecureRandom.hex(3)}", values: DcfLargeList.names(10, prefix: 'P'))
      children = DcfLargeList.names(200)
      child = dcf_list_field(format: 'depending_list', name: "Child-#{SecureRandom.hex(3)}", values: children,
                             parent: parent)
      mapping = DcfLargeList.full(parent.possible_values, children)
      full_json = ActiveSupport::JSON.encode(value_dependencies: mapping, default_value_dependencies: {})
      expect(full_json.bytesize).to be > 16_384

      service('DependencyMappingService', child, { value_dependencies: mapping }).call

      expect(child.reload.value_dependencies).to eq(mapping)
      row = events.where(status: 'success').order(:id).last
      expect(row.after_value.bytesize).to be <= 16_384
      parsed = JSON.parse(row.after_value)
      expect(parsed.keys & %w[payload_truncated payload_bytes payload_sha256]).to eq([])
      expect(parsed.values_at('v', 'links', 'added', 'truncated')).to eq([2, 2_000, 2_000, true])
      expect(ActiveSupport::JSON.encode(parsed)).to eq(row.after_value)
    end

    it 'adds a value above the cap and stores a bounded row' do
      field = dcf_list_field(values: %w[A], is_for_all: false, projects: [project])
      service('AddValueService', field, { value: 'v' * 20_000 }).call

      expect(field.reload.possible_values.last.length).to eq(20_000)
      row = events.where(status: 'success').order(:id).last
      expect(row.after_value.bytesize).to be <= 16_384
      expect(JSON.parse(row.after_value)['payload_truncated']).to be(true)
    end
  end
end
