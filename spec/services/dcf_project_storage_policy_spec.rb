# frozen_string_literal: true

require_relative '../rails_helper'

# WP-31 (UD-22, project design 2.4 and 9, limits design 4.11): the project
# storage ceiling. ProjectStoragePolicy reads the plugin setting
# project_storage_ceiling_kib; StorageLimits.effective_limit applies it only
# while the non-persisted CustomField#dcf_storage_ceiling is set, which only
# BaseService#save_field! and ProjectStoragePolicy.format_store_limit do.
# The column limit is stubbed where an example models PostgreSQL, so the
# file runs unchanged on MariaDB.
RSpec.describe 'RedmineDependingCustomFields::ProjectStoragePolicy' do
  fixtures :users

  let(:policy) { RedmineDependingCustomFields::ProjectStoragePolicy }
  let(:limits) { RedmineDependingCustomFields::StorageLimits }
  let(:project) { dcf_create_project }
  let(:services_dir) { File.expand_path('../../app/services/redmine_depending_custom_fields', __dir__) }

  def stub_setting(value)
    allow(Setting).to receive(:plugin_redmine_depending_custom_fields).and_return(value)
  end

  def stub_kib(raw)
    stub_setting('project_storage_ceiling_kib' => raw)
  end

  def no_column_limit
    allow(limits).to receive(:column_limit).and_return(nil)
  end

  # One column with a limit, the other without.
  def stub_column(column, value)
    no_column_limit
    allow(limits).to receive(:column_limit).with(column).and_return(value)
  end

  def raw(field, column)
    CustomField.connection.select_value(CustomField.where(id: field.id).select(column).to_sql)
  end

  def yaml_bytes(column, value)
    limits.serialized_bytesize(CustomField, column, value)
  end

  def service_for(field)
    RedmineDependingCustomFields::AddValueService.new(project: project, field: field, user: dcf_admin, params: {})
  end

  describe 'constants and state' do
    it 'defines the default, the minimum, the maximum and the list value cap' do
      expect(policy::DEFAULT_CEILING_KIB).to eq(2_048)
      expect(policy::MIN_CEILING_KIB).to eq(64)
      expect(policy::MAX_CEILING_KIB).to eq(1_048_576)
      expect(policy::LIST_VALUE_MAX_CHARS).to eq(255)
    end

    it 'keeps no state on the module and reads the setting on every call' do
      field = dcf_list_field(values: %w[A])
      stub_kib('128')
      expect(policy.ceiling_bytes).to eq(131_072)
      stub_kib('256')
      expect(policy.ceiling_bytes).to eq(262_144)
      policy.format_store_limit(field)
      expect(policy.instance_variables).to eq([])
      expect(policy.class_variables).to eq([])
      source = File.read(File.join(services_dir, 'project_storage_policy.rb'))
      expect(source).not_to match(/@\w+\s*(\|\|)?=|@@|Thread\.current/)
    end

    it 'is a module of the services directory with the constant its name gives' do
      path = File.join(services_dir, 'project_storage_policy.rb')
      expect(Rails.autoloaders.main.cpath_expected_at(path)).to eq('RedmineDependingCustomFields::ProjectStoragePolicy')
      expect(policy).to be_a(Module)
      expect(policy).not_to be_a(Class)
    end
  end

  describe '.ceiling_bytes' do
    {
      '2048' => 2_097_152, '4096' => 4_194_304, '64' => 65_536, '63' => 65_536, '10' => 65_536, '0' => 65_536,
      ' 128 ' => 131_072, '0128' => 131_072, "128\n" => 131_072,
      'abc' => 2_097_152, '-5' => 2_097_152, '1.5' => 2_097_152, '1e3' => 2_097_152, '0x80' => 2_097_152,
      '1_000' => 2_097_152, '+128' => 2_097_152, '' => 2_097_152, '   ' => 2_097_152,
      "１２８" => 2_097_152, '12 8' => 2_097_152,
      '1048576' => 1_073_741_824, '1048577' => 1_073_741_824, '9765625000000' => 1_073_741_824
    }.each do |raw_value, expected|
      it "gives #{expected} bytes for #{raw_value.inspect}" do
        stub_kib(raw_value)
        expect(policy.ceiling_bytes).to eq(expected)
        expect(policy.ceiling_bytes).to be_a(Integer)
      end
    end

    it 'accepts an Integer and falls back for every other non-String value' do
      { 4_096 => 4_194_304, 10 => 65_536, 2**70 => 1_073_741_824, nil => 2_097_152, 100.0 => 2_097_152,
        ['100'] => 2_097_152, { 'a' => '1' } => 2_097_152, true => 2_097_152 }.each do |raw_value, expected|
        stub_kib(raw_value)
        expect(policy.ceiling_bytes).to eq(expected), raw_value.inspect
      end
    end

    # The editor parses data-dcf-editor-storage-limit as at most 16 digits
    # (dcf_dependency_editor.js INT_RE): 1 GiB keeps every limit within it.
    it 'clamps a 30-digit value to the maximum of 1 GiB, an Integer, never a Float or Infinity' do
      stub_kib('1' + ('0' * 29))
      expect(policy.ceiling_bytes).to eq(1_073_741_824)
      expect(policy.ceiling_bytes).to be_a(Integer)
      expect(policy::MAX_CEILING_KIB * 1024).to be <= 9_007_199_254_740_991
    end

    it 'falls back to 2,048 KiB for a settings Hash without the key, a missing or odd settings value, and a raise' do
      [{}, { 'block_removal_when_used' => '0' }, nil, 'x', [], 5].each do |settings|
        stub_setting(settings)
        expect(policy.ceiling_bytes).to eq(2_097_152), settings.inspect
      end
      allow(Setting).to receive(:plugin_redmine_depending_custom_fields).and_raise(StandardError, 'boom')
      expect(policy.ceiling_bytes).to eq(2_097_152)
    end

    describe 'with the stored setting' do
      after { Setting.clear_cache }

      it 'reads a settings row saved before WP-31 (no key) as the default and a saved value as KiB' do
        Setting.plugin_redmine_depending_custom_fields = { 'manage_standard_custom_fields' => '1',
                                                           'block_removal_when_used' => '0' }
        expect(policy.ceiling_bytes).to eq(2_097_152)
        Setting.plugin_redmine_depending_custom_fields = { 'project_storage_ceiling_kib' => '100' }
        expect(policy.ceiling_bytes).to eq(102_400)
      end

      it 'uses the init.rb default without a settings row' do
        Setting.where(name: 'plugin_redmine_depending_custom_fields').delete_all
        Setting.clear_cache
        expect(Setting.plugin_redmine_depending_custom_fields['project_storage_ceiling_kib']).to eq('2048')
        expect(policy.ceiling_bytes).to eq(2_097_152)
      end
    end
  end

  describe 'init.rb settings default' do
    it 'adds project_storage_ceiling_kib as the String 2048 and keeps the other two settings and the partial' do
      settings = Redmine::Plugin.find(:redmine_depending_custom_fields).settings
      expect(settings[:default]).to eq('manage_standard_custom_fields' => true, 'block_removal_when_used' => false,
                                       'project_storage_ceiling_kib' => '2048')
      expect(settings[:partial]).to eq('settings/dcf_project_config')
    end
  end

  describe 'CustomField#dcf_storage_ceiling' do
    it 'is nil by default on every custom field class' do
      [CustomField.new, IssueCustomField.new, ProjectCustomField.new].each do |field|
        expect(field.dcf_storage_ceiling).to be_nil
      end
    end

    it 'is no safe attribute, so mass assignment never sets it' do
      field = IssueCustomField.new
      expect(CustomField.new.safe_attribute_names(dcf_admin)).not_to include('dcf_storage_ceiling')
      expect(field.safe_attribute_names(dcf_admin)).not_to include('dcf_storage_ceiling')
      field.safe_attributes = { 'name' => 'Safe', 'dcf_storage_ceiling' => '1' }
      expect(field.name).to eq('Safe')
      expect(field.dcf_storage_ceiling).to be_nil
    end

    # Why save_field! and format_store_limit reset it in ensure.
    it 'survives reload and is held per instance' do
      field = dcf_list_field(values: %w[A])
      field.dcf_storage_ceiling = 5
      field.reload
      expect(field.dcf_storage_ceiling).to eq(5)
      other = CustomField.find(field.id)
      expect(other.dcf_storage_ceiling).to be_nil
      field.dcf_storage_ceiling = nil
    end

    it 'never limits another instance of the same row' do
      no_column_limit
      field = dcf_list_field(values: %w[A B])
      first = CustomField.find(field.id)
      second = CustomField.find(field.id)
      first.dcf_storage_ceiling = 1
      second.possible_values = %w[A B C D]
      expect(limits.violations(second)).to eq([])
      first.possible_values = %w[A B C D]
      expect(limits.violations(first).map(&:source)).to eq(['ceiling'])
    end
  end

  describe 'StorageLimits.effective_limit' do
    let!(:field) { dcf_list_field(values: %w[Alpha Beta Gamma]) }
    let!(:stored) { raw(field, 'possible_values').bytesize }

    before { allow(limits).to receive(:persisted_bytes).and_call_original }

    it 'is the column limit, measuring nothing, without a ceiling' do
      allow(limits).to receive(:serialized_bytesize).and_call_original
      [nil, 65_535].each do |column|
        stub_column('possible_values', column)
        expect(limits.effective_limit(field, 'possible_values')).to eq([column, 'column'])
        expect(limits.effective_limit(field, 'possible_values', 10**9)).to eq([column, 'column'])
      end
      expect(limits).not_to have_received(:serialized_bytesize)
      expect(limits).not_to have_received(:persisted_bytes)
    end

    it 'is the ceiling without the persisted bytes while the new bytes fit it' do
      no_column_limit
      field.dcf_storage_ceiling = 1_000
      expect(limits.effective_limit(field, 'possible_values', 1_000)).to eq([1_000, 'ceiling'])
      expect(limits.effective_limit(field, 'possible_values', 1)).to eq([1_000, 'ceiling'])
      expect(limits).not_to have_received(:persisted_bytes)
    end

    it 'is max(ceiling, persisted bytes) above the ceiling, read from the database, not the assigned value' do
      no_column_limit
      record = CustomField.find(field.id)
      record.possible_values = %w[Alpha Beta Gamma Delta Epsilon]
      grown = limits.preview_bytes(record, 'possible_values')
      record.dcf_storage_ceiling = 5
      expect(limits.effective_limit(record, 'possible_values', grown)).to eq([stored, 'ceiling'])
      expect(limits.effective_limit(record, 'possible_values')).to eq([stored, 'ceiling'])
      expect(limits).to have_received(:persisted_bytes).twice
      record.dcf_storage_ceiling = stored + 50
      expect(limits.effective_limit(record, 'possible_values', grown)).to eq([stored + 50, 'ceiling'])
    end

    it 'takes the size the last save stored, also on the same instance' do
      no_column_limit
      record = CustomField.find(field.id)
      record.possible_values = %w[Alpha]
      record.save!
      shrunk = raw(field, 'possible_values').bytesize
      expect(shrunk).to be < stored
      record.possible_values = %w[Alpha Beta]
      record.dcf_storage_ceiling = 1
      expect(limits.effective_limit(record, 'possible_values', stored)).to eq([shrunk, 'ceiling'])
    end

    it 'counts a new record as 0 persisted bytes' do
      no_column_limit
      record = IssueCustomField.new(name: 'New', field_format: 'list', possible_values: %w[A B])
      record.dcf_storage_ceiling = 3
      expect(limits.effective_limit(record, 'possible_values', 100)).to eq([3, 'ceiling'])
    end

    it 'gives the column limit when it is not larger than the ceiling, without measuring (MySQL TEXT, ties)' do
      stub_column('possible_values', 65_535)
      field.dcf_storage_ceiling = 65_536
      expect(limits.effective_limit(field, 'possible_values', 10**9)).to eq([65_535, 'column'])
      field.dcf_storage_ceiling = 65_535
      expect(limits.effective_limit(field, 'possible_values', 10**9)).to eq([65_535, 'column'])
      expect(limits).not_to have_received(:persisted_bytes)
    end

    it 'gives the smaller of a widened column and max(ceiling, persisted bytes)' do
      stub_column('possible_values', 16_777_215)
      field.dcf_storage_ceiling = 2_097_152
      expect(limits.effective_limit(field, 'possible_values', 10)).to eq([2_097_152, 'ceiling'])
      field.dcf_storage_ceiling = 1
      expect(limits.effective_limit(field, 'possible_values', 10**9)).to eq([stored, 'ceiling'])
      stub_column('possible_values', stored - 1)
      expect(limits.effective_limit(field, 'possible_values', 10**9)).to eq([stored - 1, 'column'])
    end

    it 'measures an in-memory format_store change against the stored mapping (Rails 6.1 and 7)' do
      no_column_limit
      parent = dcf_list_field(values: %w[P Q])
      child = dcf_list_field(format: 'depending_list', values: %w[a b], parent: parent)
      dcf_set_dependencies(child, value_dependencies: { 'P' => %w[a] })
      record = CustomField.find(child.id)
      record.value_dependencies = { 'P' => %w[a b], 'Q' => %w[a b] }
      expect(record.will_save_change_to_attribute?('format_store')).to be(true)
      record.dcf_storage_ceiling = 1
      expected = yaml_bytes('format_store', CustomField.find(child.id).format_store)
      expect(expected).to eq(raw(child, 'format_store').bytesize)
      expect(limits.effective_limit(record, 'format_store', 10**9)).to eq([expected, 'ceiling'])
    end

    # Review round 2 (semantics-r2-1): a save adds default_value_dependencies
    # to a mapping stored without it, so the stored row counts as a save of
    # it would write it; the normalized store is dumped only when it differs.
    it 'measures a stored mapping without its per-parent defaults as a save of it writes it' do
      no_column_limit
      parent = dcf_list_field(values: %w[P Q])
      child = dcf_list_field(format: 'depending_list', values: %w[a b], parent: parent)
      dcf_set_dependencies(child, value_dependencies: { 'P' => %w[a b] })
      normal = raw(child, 'format_store').bytesize
      allow(limits).to receive(:serialized_bytesize).and_call_original
      record = CustomField.find(child.id)
      record.value_dependencies = { 'P' => %w[a] }
      record.dcf_storage_ceiling = 1
      expect(limits.effective_limit(record, 'format_store', 10**9)).to eq([normal, 'ceiling'])
      expect(limits).to have_received(:serialized_bytesize).once

      stale = CustomField.find(child.id).format_store.to_hash.except('default_value_dependencies')
      child.update_column(:format_store, stale)
      expect(raw(child, 'format_store').bytesize).to be < normal
      record = CustomField.find(child.id)
      record.value_dependencies = { 'P' => %w[a] }
      record.dcf_storage_ceiling = 1
      expect(limits.effective_limit(record, 'format_store', 10**9)).to eq([normal, 'ceiling'])
      expect(limits).to have_received(:serialized_bytesize).exactly(3).times
      expect(limits.effective_limit(record, 'format_store')).to eq([raw(child, 'format_store').bytesize, 'ceiling'])
    end

    # Without new bytes (the editor) an unassigned column is not parsed again:
    # its stored size is the raw column value.
    it 'takes the raw stored size of an unassigned column without new bytes, parsing and dumping nothing' do
      no_column_limit
      parent = dcf_list_field(values: %w[P Q])
      child = dcf_list_field(format: 'depending_list', values: %w[a b], parent: parent)
      dcf_set_dependencies(child, value_dependencies: { 'P' => %w[a b], 'Q' => %w[b] })
      record = CustomField.find(child.id)
      record.value_dependencies = { 'P' => %w[a] }
      record.dcf_storage_ceiling = 1
      allow(record).to receive(:attribute_in_database).and_call_original
      allow(limits).to receive(:serialized_bytesize).and_call_original
      expect(limits.effective_limit(record, 'format_store')).to eq([raw(child, 'format_store').bytesize, 'ceiling'])
      expect(record).not_to have_received(:attribute_in_database)
      expect(limits).not_to have_received(:serialized_bytesize)
      expect(limits).not_to have_received(:persisted_bytes)
    end

    it 'measures an assigned column without new bytes with one serialize of the stored value' do
      no_column_limit
      record = CustomField.find(field.id)
      record.possible_values = %w[Alpha]
      record.dcf_storage_ceiling = 1
      expect(limits.effective_limit(record, 'possible_values')).to eq([stored, 'ceiling'])
      expect(limits).to have_received(:persisted_bytes).once
    end
  end

  describe 'StorageLimits.violations and validate with a ceiling' do
    def new_list(values)
      IssueCustomField.new(name: "N-#{SecureRandom.hex(3)}", field_format: 'list', possible_values: values,
                           is_for_all: true)
    end

    it 'accepts the bytes of the ceiling and refuses one byte less, with source ceiling' do
      no_column_limit
      record = new_list(%w[A B C])
      bytes = limits.preview_bytes(record, 'possible_values')
      record.dcf_storage_ceiling = bytes
      expect(record.valid?).to be(true), record.errors.full_messages.inspect
      record.dcf_storage_ceiling = bytes - 1
      expect(record.valid?).to be(false)
      expect(record.errors.details[:possible_values])
        .to eq([{ error: :dcf_storage_too_large, size: limits.delimited(bytes), limit: limits.delimited(bytes - 1),
                  bytes: bytes, max_bytes: bytes - 1, column: 'possible_values', source: 'ceiling' }])
      violation = limits.violation_in(record)
      expect([violation.source, violation.limit, violation.bytes]).to eq(['ceiling', bytes - 1, bytes])
    end

    it 'reports source column when the column limit is the smaller one' do
      record = new_list(%w[A B C])
      bytes = limits.preview_bytes(record, 'possible_values')
      stub_column('possible_values', bytes - 1)
      record.dcf_storage_ceiling = bytes - 1 + 100
      expect(limits.violations(record).map { |v| [v.limit, v.source] }).to eq([[bytes - 1, 'column']])
    end

    # Changed by the WP-31 review (contracts-r1-2): a name change writes no
    # mapping, so the ceiling no longer measures format_store for it.
    it 'measures a depending format_store on PostgreSQL only while a ceiling is set and the write changes it' do
      no_column_limit
      parent = dcf_list_field(values: %w[P])
      child = CustomField.find(dcf_list_field(format: 'depending_list', values: %w[a], parent: parent).id)
      child.name = "#{child.name}-x"
      allow(child.format).to receive(:storage_preview).and_call_original
      expect(limits.violations(child)).to eq([])
      child.dcf_storage_ceiling = 65_536
      expect(limits.violations(child)).to eq([])
      expect(child.format).not_to have_received(:storage_preview)
      child.value_dependencies = { 'P' => %w[a] }
      expect(limits.violations(child)).to eq([])
      expect(child.format).to have_received(:storage_preview).at_least(:once)
    end

    # UD-22: the ceiling never refuses a write that does not grow a field. A
    # format_store that only the before_save of a depending format rewrites
    # (a mapping stored without default_value_dependencies) keeps the column
    # limit alone.
    it 'applies the ceiling only to a column the write changes, never to a mapping only the save rewrites' do
      no_column_limit
      parent = dcf_list_field(values: %w[P Q])
      child = dcf_list_field(format: 'depending_list', values: %w[a b], parent: parent)
      dcf_set_dependencies(child, value_dependencies: { 'P' => %w[a b] })
      stale = CustomField.find(child.id).format_store.to_hash.except('default_value_dependencies')
      child.update_column(:format_store, stale)
      record = CustomField.find(child.id)
      record.possible_values = %w[b a]
      record.dcf_storage_ceiling = 1
      expect(limits.writes_column?(record, 'format_store')).to be(true)
      expect(limits.check_column?(record, 'format_store')).to be(false)
      expect(limits.violations(record)).to eq([])

      stub_column('format_store', 10)
      expect(limits.violations(record).map { |v| [v.column, v.limit, v.source] }).to eq([['format_store', 10, 'column']])

      no_column_limit
      record.value_dependencies = { 'P' => %w[a b], 'Q' => %w[a] }
      expect(limits.violations(record).map { |v| [v.column, v.source] }).to eq([%w[format_store ceiling]])
    end

    it 'leaves usage (the MySQL hint) column-only' do
      allow(limits).to receive(:mysql?).and_return(false)
      field = dcf_list_field(values: %w[A])
      field.dcf_storage_ceiling = 1
      expect(limits.usage(field)).to eq([])
    end
  end

  describe '.format_store_limit' do
    let(:parent) { dcf_list_field(values: %w[P Q]) }
    let(:child) do
      field = dcf_list_field(format: 'depending_list', values: %w[a b], parent: parent)
      dcf_set_dependencies(field, value_dependencies: { 'P' => %w[a], 'Q' => %w[b] })
    end

    it 'is the ceiling for a small field without a column limit (PostgreSQL, SQLite)' do
      no_column_limit
      expect(policy.format_store_limit(CustomField.find(child.id))).to eq(2_097_152)
    end

    it 'is the persisted format_store bytes of a field stored above the ceiling' do
      no_column_limit
      allow(policy).to receive(:ceiling_bytes).and_return(10)
      expect(policy.format_store_limit(CustomField.find(child.id))).to eq(raw(child, 'format_store').bytesize)
    end

    it 'is the column limit without measuring when it is the smaller one (MySQL TEXT)' do
      field = CustomField.find(child.id)
      stub_column('format_store', 65_535)
      allow(limits).to receive(:serialized_bytesize).and_call_original
      expect(policy.format_store_limit(field)).to eq(65_535)
      expect(limits).not_to have_received(:serialized_bytesize)
    end

    it 'is the ceiling below a widened column' do
      field = CustomField.find(child.id)
      stub_column('format_store', 16_777_215)
      expect(policy.format_store_limit(field)).to eq(2_097_152)
    end

    it 'restores the accessor afterwards, also when the measurement raises' do
      field = CustomField.find(child.id)
      policy.format_store_limit(field)
      expect(field.dcf_storage_ceiling).to be_nil
      field.dcf_storage_ceiling = 7
      policy.format_store_limit(field)
      expect(field.dcf_storage_ceiling).to eq(7)
      field.dcf_storage_ceiling = nil
      allow(limits).to receive(:effective_limit).and_raise(StandardError, 'boom')
      expect { policy.format_store_limit(field) }.to raise_error(StandardError, 'boom')
      expect(field.dcf_storage_ceiling).to be_nil
    end

    # Changed by the WP-31 review (semantics-r1-2, was: one dump): the
    # stored size comes from the raw column, so the page parses nothing again.
    it 'runs no query and no YAML parse or dump, below and above the ceiling' do
      no_column_limit
      policy.ceiling_bytes
      allow(limits).to receive(:serialized_bytesize).and_call_original
      [nil, 10].each do |ceiling|
        allow(policy).to receive(:ceiling_bytes).and_return(ceiling) if ceiling
        field = CustomField.find(child.id)
        allow(field).to receive(:attribute_in_database).and_call_original
        expect(dcf_count_queries { policy.format_store_limit(field) }).to eq(0)
        expect(field).not_to have_received(:attribute_in_database)
      end
      expect(limits).not_to have_received(:serialized_bytesize)
    end
  end

  describe 'BaseService#save_field! (T-SIZE-7)' do
    let(:field) { CustomField.find(dcf_list_field(values: %w[A B]).id) }

    before { allow(policy).to receive(:ceiling_bytes).and_return(123_456) }

    it 'sets the ceiling for the save only and leaves nil' do
      seen = []
      allow(field).to receive(:save!).and_wrap_original do |original, *args|
        seen << original.receiver.dcf_storage_ceiling
        original.call(*args)
      end
      field.possible_values = %w[A B C]
      service_for(field).send(:save_field!, field)
      expect(seen).to eq([123_456])
      expect(field.dcf_storage_ceiling).to be_nil
      expect(CustomField.find(field.id).possible_values).to eq(%w[A B C])
    end

    { RuntimeError => -> { RuntimeError.new('boom') },
      ActiveRecord::RecordInvalid => -> { ActiveRecord::RecordInvalid.new(CustomField.new) },
      ActiveRecord::ValueTooLong => -> { ActiveRecord::ValueTooLong.new('too long') } }.each do |klass, build|
      it "resets the ceiling after save! raises #{klass}" do
        allow(field).to receive(:save!).and_raise(build.call)
        expect { service_for(field).send(:save_field!, field) }.to raise_error(klass)
        expect(field.dcf_storage_ceiling).to be_nil
      end
    end

    # Changed by the WP-31 review round 2 (tests-r2-4): the raise comes
    # before the assignment, so only a previous value other than nil shows
    # that it is restored.
    it 'resets the ceiling after a refused save and restores the previous value when the policy raises' do
      field.possible_values = %w[A B C]
      allow(policy).to receive(:ceiling_bytes).and_return(1)
      no_column_limit
      expect { service_for(field).send(:save_field!, field) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(field.dcf_storage_ceiling).to be_nil
      field.dcf_storage_ceiling = 7
      allow(policy).to receive(:ceiling_bytes).and_raise(StandardError, 'policy')
      expect { service_for(field).send(:save_field!, field) }.to raise_error(StandardError, 'policy')
      expect(field.dcf_storage_ceiling).to eq(7)
    end

    it 'keeps the outer ceiling across a nested call on the same record' do
      svc = service_for(field)
      trace = []
      calls = 0
      allow(field).to receive(:save!).and_wrap_original do |original, *args|
        calls += 1
        if calls == 1
          trace << field.dcf_storage_ceiling
          svc.send(:save_field!, field)
          trace << field.dcf_storage_ceiling
        end
        original.call(*args)
      end
      svc.send(:save_field!, field)
      expect(trace).to eq([123_456, 123_456])
      expect(field.dcf_storage_ceiling).to be_nil
    end
  end

  describe 'grep proof: every custom field save of a project service goes through save_field!' do
    def service_sources
      Dir[File.join(services_dir, '*.rb')].sort.to_h { |path| [File.basename(path), File.read(path)] }
    end

    it 'has one save of a custom field record, record.save! inside BaseService#save_field!' do
      found = service_sources.flat_map do |name, source|
        source.scan(/\b(?:field|child|cf|custom_field|record|parent)\.(?:save|update|update_attribute|update_columns?)\b!?/)
              .map { |call| [name, call] }
      end
      expect(found).to eq([['base_service.rb', 'record.save!']])
      base = service_sources.fetch('base_service.rb')
      expect(base[/def save_field!\(record\).*?\n    end\n/m]).to include('record.save!')
      expect(service_sources.values.join).not_to match(/save\(validate: false\)|CustomField\.where[^\n]*update_all/)
    end

    it 'calls save_field! where each WP-31 service used to save the field' do
      expected = { 'add_value_service.rb' => 1, 'rename_value_service.rb' => 1, 'remove_value_service.rb' => 2,
                   'reorder_values_service.rb' => 1, 'set_default_value_service.rb' => 1,
                   'update_enumerations_service.rb' => 1, 'dependency_mapping_service.rb' => 1,
                   'sort_values_service.rb' => 1, 'base_service.rb' => 1 }
      counts = service_sources.transform_values { |source| source.scan(/\bsave_field!\((?:field|child)\)/).size }
      expect(counts.select { |_name, count| count.positive? }).to eq(expected)
      expect(service_sources.values.join.scan('.save!').size).to eq(1)
    end

    it 'keeps DELTA_CAP and capped in BaseService, reachable as UpdateEnumerationsService::DELTA_CAP' do
      base = RedmineDependingCustomFields::BaseService
      update = RedmineDependingCustomFields::UpdateEnumerationsService
      expect(base::DELTA_CAP).to eq(20)
      expect(update::DELTA_CAP).to eq(20)
      expect(update.const_defined?(:DELTA_CAP, false)).to be(false)
      expect(base.private_instance_methods(false)).to include(:capped, :save_field!, :check_value_length!)
    end
  end

  # MariaDB TEXT: 65,535 is below the 64 KiB minimum ceiling, so the column
  # limit always wins with real settings; a widened column shows the ceiling.
  describe 'on MySQL / MariaDB', :mysql do
    it 'gives the TEXT column limit for every real setting and the ceiling for a widened column' do
      field = dcf_list_field(values: %w[A B])
      [65_536, 2_097_152].each do |ceiling|
        field.dcf_storage_ceiling = ceiling
        expect(limits.effective_limit(field, 'possible_values', 70_000)).to eq([65_535, 'column'])
      end
      allow(limits).to receive(:column_limit).and_call_original
      allow(limits).to receive(:column_limit).with('possible_values').and_return(16_777_215)
      field.dcf_storage_ceiling = 2_097_152
      expect(limits.effective_limit(field, 'possible_values', 10)).to eq([2_097_152, 'ceiling'])
      field.dcf_storage_ceiling = nil
      expect(policy.format_store_limit(CustomField.find(field.id))).to eq(65_535)
    end
  end
end
