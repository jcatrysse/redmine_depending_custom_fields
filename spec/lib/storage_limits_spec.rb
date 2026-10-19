# frozen_string_literal: true

require_relative '../rails_helper'

# WP-11 (UN-32, UD-25, limits design 4.1 to 4.9): StorageLimits measures the
# bytes a CustomField save writes into possible_values and format_store and
# refuses a value above the column limit (MySQL/MariaDB TEXT). PostgreSQL and
# SQLite report no limit, so the examples stub column_limit (and mysql? for
# the usage line); spec/mysql/storage_limits_mysql_spec.rb uses the real one.
RSpec.describe 'RedmineDependingCustomFields::StorageLimits' do
  include DcfFormatCharacterization

  fixtures :users

  let(:limits) { RedmineDependingCustomFields::StorageLimits }
  let(:patch) { RedmineDependingCustomFields::Patches::CustomFieldValidationPatch }

  # Bytes of +column+ as the database holds them (NULL counts as 0).
  def stored_bytes(field, column)
    raw = CustomField.connection.select_value(CustomField.where(id: field.id).select(column).to_sql)
    raw.nil? ? 0 : raw.to_s.bytesize
  end

  def stored_raw(field, column)
    CustomField.connection.select_value(CustomField.where(id: field.id).select(column).to_sql)
  end

  # Per-column limits; a column not given keeps no limit.
  def stub_limits(by_column)
    allow(limits).to receive(:column_limit).and_return(nil)
    by_column.each { |column, limit| allow(limits).to receive(:column_limit).with(column).and_return(limit) }
  end

  def storage_details(record, attribute)
    record.errors.details[attribute].select { |d| d[:error] == :dcf_storage_too_large }
  end

  def validate_callbacks(klass)
    klass._validate_callbacks.count { |c| c.filter == :dcf_validate_storage_limits }
  end

  def new_field(format, **attributes)
    IssueCustomField.new({ name: "F-#{SecureRandom.hex(4)}", field_format: format, is_for_all: true }.merge(attributes))
  end

  # One unsaved record per guarded format with bytes in every column it uses.
  def guarded_record(format)
    case format
    when 'list'
      new_field('list', possible_values: %w[A B C], url_pattern: 'http://example.test/%value%')
    when 'enumeration'
      new_field('enumeration', url_pattern: 'http://example.test/%value%')
    when 'depending_list'
      parent = dcf_list_field(values: %w[P Q])
      field = new_field('depending_list', possible_values: %w[a1 b1])
      field.parent_custom_field_id = parent.id.to_s
      field.value_dependencies = { 'P' => %w[a1], 'Q' => %w[b1] }
      field
    else
      parent = dcf_enum_field(names: %w[P Q])
      field = new_field('depending_enumeration')
      field.parent_custom_field_id = parent.id.to_s
      field.value_dependencies = { parent.enumerations.first.id.to_s => %w[1] }
      field
    end
  end

  # valid? (the measurement) right before save!, then the stored bytes.
  def expect_preview_equals_stored(field)
    expect(field.valid?).to be(true), field.errors.full_messages.inspect
    previews = %w[possible_values format_store].map { |column| [column, limits.preview_bytes(field, column)] }
    field.save!
    previews.each do |column, bytes|
      expect(bytes).to eq(stored_bytes(field, column)), column
    end
  end

  describe 'API' do
    it 'defines the constants and structs of limits design 4.2' do
      expect(limits::MYSQL_TEXT_BYTES).to eq(65_535)
      expect(limits::WARN_PERCENT).to eq(90)
      expect(limits::COLUMNS).to eq('possible_values' => :possible_values, 'format_store' => :value_dependencies)
      expect(limits::COLUMNS.keys).to eq(%w[possible_values format_store])
      expect(limits::COLUMNS).to be_frozen
      expect(limits::GUARDED_FORMATS).to eq(%w[list enumeration depending_list depending_enumeration])
      expect(limits::MAPPING_KEYS).to eq(%w[value_dependencies default_value_dependencies])
      expect(limits::ERROR).to eq(:dcf_storage_too_large)
      expect(limits::Violation.members).to eq([:custom_field_id, :custom_field_name, :column, :attribute, :bytes, :limit])
      expect(limits::Usage.members).to eq([:column, :attribute, :bytes, :limit, :percent])
      expect(limits::Violation.new(bytes: 2, limit: 1).bytes).to eq(2)
    end

    it 'has no too_large?, report or dcf_too_large key' do
      expect(limits).not_to respond_to(:too_large?)
      expect(limits).not_to respond_to(:report)
      expect(I18n.exists?('activerecord.errors.messages.dcf_too_large', :en)).to be(false)
      expect(defined?(RedmineDependingCustomFields::Patches::CustomFieldStoragePatch)).to be_nil
    end

    it 'keeps no state on the module or the hook singleton' do
      field = dcf_list_field(values: %w[A])
      limits.mysql?
      limits.column_limit('format_store')
      limits.violations(field)
      limits.validate(field)
      limits.violation_in(field)
      limits.usage(field)
      limits.base_bytes(field)
      limits.delimited(1)
      expect(limits.instance_variables).to eq([])
      hook = RedmineDependingCustomFields::Hooks::CustomFieldStorageHook.instance
      hook.view_custom_fields_form_upper_box(custom_field: field)
      # @_routes is the url_helpers cache every ViewListener gets from Rails.
      expect(hook.instance_variables - [:@_routes]).to eq([])
      lib = File.expand_path('../../lib/redmine_depending_custom_fields', __dir__)
      %w[storage_limits.rb patches/custom_field_validation_patch.rb hooks/custom_field_storage_hook.rb].each do |file|
        expect(File.read(File.join(lib, file))).not_to match(/@\w+\s*(\|\|)?=|@@/), file
      end
    end

    it 'loads its new files under the eager loader with the constants their names give' do
      lib = File.expand_path('../../lib', __dir__)
      expect { Rails.autoloaders.main.eager_load_dir(lib) }.not_to raise_error
      {
        'storage_limits.rb' => 'RedmineDependingCustomFields::StorageLimits',
        'patches/custom_field_validation_patch.rb' => 'RedmineDependingCustomFields::Patches::CustomFieldValidationPatch',
        'hooks/custom_field_storage_hook.rb' => 'RedmineDependingCustomFields::Hooks::CustomFieldStorageHook'
      }.each do |file, constant|
        path = File.join(lib, 'redmine_depending_custom_fields', file)
        expect(Rails.autoloaders.main.cpath_expected_at(path)).to eq(constant)
      end
    end
  end

  describe '.mysql?' do
    it 'is Redmine::Database.mysql? and false when that raises' do
      allow(Redmine::Database).to receive(:mysql?).and_return(true)
      expect(limits.mysql?).to be(true)
      allow(Redmine::Database).to receive(:mysql?).and_raise(StandardError)
      expect(limits.mysql?).to be(false)
    end

    it 'runs no SQL' do
      expect(dcf_plugin_overhead(with: -> { limits.mysql? }, without: -> {})).to eq(0)
    end
  end

  describe '.column_limit' do
    def fake_model(columns)
      double('model', columns_hash: columns)
    end

    it 'falls back to 65,535 for a text column without a limit on MySQL only' do
      model = fake_model('possible_values' => double('column', type: :text, limit: nil))
      allow(limits).to receive(:mysql?).and_return(true)
      expect(limits.column_limit('possible_values', model)).to eq(65_535)
      expect(limits.column_limit(:possible_values, model)).to eq(65_535)
      allow(limits).to receive(:mysql?).and_return(false)
      expect(limits.column_limit('possible_values', model)).to be_nil
    end

    it 'honours a reported limit and ignores other column types' do
      allow(limits).to receive(:mysql?).and_return(true)
      model = fake_model('format_store' => double('column', type: :text, limit: 16_777_215),
                         'name' => double('column', type: :string, limit: nil))
      expect(limits.column_limit('format_store', model)).to eq(16_777_215)
      expect(limits.column_limit('name', model)).to be_nil
      expect(limits.column_limit('missing', model)).to be_nil
    end

    it 'reads CustomField.columns_hash by default (stubbed schema, stubbed adapter)' do
      allow(CustomField).to receive(:columns_hash)
        .and_return('format_store' => double('column', type: :text, limit: nil))
      allow(Redmine::Database).to receive(:mysql?).and_return(true)
      expect(limits.column_limit('format_store')).to eq(65_535)
      allow(Redmine::Database).to receive(:mysql?).and_return(false)
      expect(limits.column_limit('format_store')).to be_nil
      expect(limits.column_limit('possible_values')).to be_nil
    end

    it 'gives the real limit of this database' do
      expected = Redmine::Database.mysql? ? 65_535 : nil
      expect(limits.column_limit('possible_values')).to eq(expected)
      expect(limits.column_limit('format_store')).to eq(expected)
    end
  end

  describe '.guarded? and .check_column?' do
    it 'guards the four list formats only (UD-25)' do
      %w[list enumeration depending_list depending_enumeration].each do |format|
        expect(limits.guarded?(new_field(format))).to be(true), format
      end
      %w[string text int float date bool link user version extended_user nope].each do |format|
        expect(limits.guarded?(new_field(format))).to be(false), format
      end
    end

    it 'checks every column of a new record and only changed columns of a persisted one' do
      expect(limits.check_column?(new_field('list'), 'format_store')).to be(true)
      field = CustomField.find(dcf_list_field(values: %w[A B]).id)
      field.name = "#{field.name}-x"
      expect(limits.check_column?(field, 'possible_values')).to be(false)
      expect(limits.check_column?(field, 'format_store')).to be(false)
      field.possible_values = %w[A B]
      expect(limits.check_column?(field, 'possible_values')).to be(false)
      field.possible_values = %w[A B C]
      expect(limits.check_column?(field, 'possible_values')).to be(true)
      field.url_pattern = 'http://example.test/%value%'
      expect(limits.check_column?(field, 'format_store')).to be(true)
    end
  end

  describe '.serialized_bytesize, .preview_value and .preview_bytes' do
    it 'measures the bytes the column serializer writes' do
      expect(limits.serialized_bytesize(CustomField, 'format_store', {})).to eq(0)
      expect(limits.serialized_bytesize(CustomField, 'format_store', nil)).to eq(0)
      expect(limits.serialized_bytesize(CustomField, 'possible_values', nil)).to eq(0)
      expect(limits.serialized_bytesize(CustomField, 'possible_values', [])).to eq(7)
      expect(limits.serialized_bytesize(CustomField, :possible_values, DcfLargeList.values_of_yaml_bytes(1_000)))
        .to eq(1_000)
    end

    it 'reads possible_values raw, so an enumeration field measures 0 bytes (NULL)' do
      field = dcf_enum_field(names: %w[X Y])
      expect(limits.preview_value(field, 'possible_values')).to be_nil
      expect(field.possible_values).to eq([])
      expect(limits.preview_bytes(field, 'possible_values')).to eq(0)
      expect(stored_raw(field, 'possible_values')).to be_nil
    end

    it 'takes the raw store of the core formats' do
      field = new_field('list', possible_values: %w[A], url_pattern: 'http://example.test/%value%')
      expect(limits.preview_value(field, 'format_store')).to equal(field.format_store)
      expect(Redmine::FieldFormat.find('list')).not_to respond_to(:storage_preview)
      expect(Redmine::FieldFormat.find('enumeration')).not_to respond_to(:storage_preview)
    end

    it 'takes storage_preview(record, store) of the depending formats' do
      [build_kit(:list).last, build_kit(:enumeration).last].each do |child|
        field = CustomField.find(child.id)
        field.parent_custom_field_id = field.parent_custom_field_id.to_s
        expect(field.format).to receive(:storage_preview).with(field, field.format_store).and_call_original
        expect(limits.preview_value(field, 'format_store')['parent_custom_field_id']).to be_a(Integer)
      end
    end
  end

  describe 'preview bytes equal the stored bytes (V4)' do
    it 'for a core list, new and changed' do
      field = new_field('list', possible_values: ['A', ' B ', '', 'Ünïcødé ñ', 'a: b'],
                                url_pattern: 'http://example.test/%value%')
      expect_preview_equals_stored(field)
      field = CustomField.find(field.id)
      field.possible_values = "A\nC\n\n D "
      field.edit_tag_style = 'check_box'
      expect_preview_equals_stored(field)
    end

    it 'for a core enumeration (possible_values stays NULL)' do
      field = new_field('enumeration', url_pattern: 'http://example.test/%value%')
      expect_preview_equals_stored(field)
      expect(stored_raw(field, 'possible_values')).to be_nil
      field = CustomField.find(field.id)
      field.url_pattern = 'http://example.test/other/%value%'
      expect_preview_equals_stored(field)
    end

    [:list, :enumeration].each do |kind|
      context "for a depending #{kind}" do
        let(:kit) { build_kit(kind) }
        let(:parent) { kit.first }
        let(:child) { kit.last }

        it 'with a parent id given as a String' do
          field = CustomField.find(child.id)
          field.parent_custom_field_id = parent.id.to_s
          field.value_dependencies = { kit_key(parent, 'A') => [kit_key(child, 'a1')] }
          expect_preview_equals_stored(field)
          expect(CustomField.find(child.id).parent_custom_field_id).to eq(parent.id)
        end

        it 'with parent ids that resolve to nothing and a blank parent' do
          child
          other_type = kind == :list ? dcf_list_field(type: ProjectCustomField) : dcf_enum_field(type: ProjectCustomField)
          other_family = kind == :list ? dcf_enum_field : dcf_list_field
          missing = CustomField.maximum(:id).to_i + 1_000
          [0, 'abc', missing, other_type.id, other_family.id, ''].each do |raw|
            field = CustomField.find(child.id)
            field.parent_custom_field_id = raw
            expect_preview_equals_stored(field)
          end
        end

        it 'with blank keys, blank values and defaults with blanks' do
          a1 = kit_key(child, 'a1')
          field = CustomField.find(child.id)
          field.value_dependencies = { '' => [a1], 'A' => [a1, '', nil], 'X' => ['', nil], 'ZZ' => ['nope'] }
          field.default_value_dependencies = { '' => a1, 'B' => '', 'C' => [a1, ''] }
          expect_preview_equals_stored(field)
        end

        it 'for an unchanged record and for a new record' do
          field = CustomField.find(child.id)
          field.name = "#{field.name}-renamed"
          expect_preview_equals_stored(field)

          format = kind == :list ? 'depending_list' : 'depending_enumeration'
          field = new_field(format)
          field.possible_values = %w[a1 a2] if kind == :list
          field.hide_when_disabled = '1'
          field.value_dependencies = { kit_key(parent, 'A') => ['a1'] }
          field.parent_custom_field_id = parent.id.to_s
          expect_preview_equals_stored(field)
        end
      end
    end
  end

  describe '.validate (through CustomField#valid?)' do
    limits_columns = { 'possible_values' => :possible_values, 'format_store' => :value_dependencies }

    %w[list enumeration depending_list depending_enumeration].each do |format|
      limits_columns.each do |column, attribute|
        next if column == 'possible_values' && format.end_with?('enumeration')

        it "accepts #{column} of a new #{format} field at the limit and refuses one byte less" do
          field = guarded_record(format)
          bytes = limits.preview_bytes(field, column)
          expect(bytes).to be_between(1, 999)

          stub_limits(column => bytes)
          expect(field.valid?).to be(true), field.errors.full_messages.inspect

          stub_limits(column => bytes - 1)
          expect(field.valid?).to be(false)
          expect(field.errors.details[attribute]).to eq([{ error: :dcf_storage_too_large,
                                                           size: limits.delimited(bytes),
                                                           limit: limits.delimited(bytes - 1),
                                                           bytes: bytes, max_bytes: bytes - 1, column: column }])
          expect(field.errors.of_kind?(attribute, :dcf_storage_too_large)).to be(true)
          expect(field.errors.details.keys).to eq([attribute])
          expect(field.save).to be(false)
          expect(field).to be_new_record
        end
      end
    end

    it 'adds one error per column, possible_values first, and violation_in reads the first' do
      field = guarded_record('depending_list')
      stub_limits('possible_values' => 1, 'format_store' => 1)
      pv = limits.preview_bytes(field, 'possible_values')
      fs = limits.preview_bytes(field, 'format_store')

      found = limits.violations(field)
      expect(found.map(&:column)).to eq(%w[possible_values format_store])
      expect(found.map(&:attribute)).to eq([:possible_values, :value_dependencies])
      expect(found.map(&:bytes)).to eq([pv, fs])
      expect(found.map(&:limit)).to eq([1, 1])

      expect(field.valid?).to be(false)
      expect(field.errors.details.keys).to eq([:possible_values, :value_dependencies])
      violation = limits.violation_in(field)
      expect(violation.to_h).to eq(custom_field_id: nil, custom_field_name: field.name, column: 'possible_values',
                                   attribute: :possible_values, bytes: pv, limit: 1)

      field.errors.delete(:possible_values)
      expect(limits.violation_in(field).column).to eq('format_store')
      expect(limits.violation_in(field).bytes).to eq(fs)
    end

    it 'gives violation_in nil without a storage error' do
      field = new_field('list', name: '', possible_values: %w[A])
      stub_limits('possible_values' => 1_000)
      expect(field.valid?).to be(false)
      expect(limits.violation_in(field)).to be_nil
    end

    it 'checks a persisted record only for the columns the save changes' do
      parent = dcf_list_field(values: %w[A B])
      child = dcf_list_field(format: 'depending_list', values: %w[a1 b1], parent: parent)
      dcf_set_dependencies(child, value_dependencies: { 'A' => %w[a1], 'B' => %w[b1] })
      stub_limits('possible_values' => 1, 'format_store' => 1)
      allow(limits).to receive(:preview_value).and_call_original
      allow(child.format).to receive(:storage_preview).and_call_original

      field = CustomField.find(child.id)
      field.name = "#{field.name}-renamed"
      field.description = 'unrelated'
      expect(field.save).to be(true), field.errors.full_messages.inspect
      expect(limits).not_to have_received(:preview_value)
      # Only the Hash comparison of the before_save normalization, no dump.
      expect(child.format).to have_received(:storage_preview).once

      field = CustomField.find(child.id)
      field.possible_values = %w[a1 b1 c1]
      expect(field.valid?).to be(false)
      expect(field.errors.details.keys).to eq([:possible_values])

      field = CustomField.find(child.id)
      field.value_dependencies = { 'A' => %w[a1 b1] }
      expect(field.valid?).to be(false)
      expect(field.errors.details.keys).to eq([:value_dependencies])
    end

    [:list, :enumeration].each do |kind|
      it "saves a depending #{kind} that writes its stored columns back, although a String parent id dirties format_store" do
        parent, child = build_kit(kind)
        before = %w[possible_values format_store].map { |column| stored_raw(child, column) }
        stub_limits('possible_values' => 1, 'format_store' => 1)

        field = CustomField.find(child.id)
        field.name = "#{field.name}-renamed"
        field.parent_custom_field_id = parent.id.to_s
        field.value_dependencies = field.value_dependencies.to_hash
        field.default_value_dependencies = field.default_value_dependencies.to_hash.merge(kit_key(parent, 'C') => '')
        expect(field.will_save_change_to_attribute?('format_store')).to be(true)
        expect(field.save).to be(true), field.errors.full_messages.inspect
        expect(CustomField.find(child.id).name).to eq(field.name)
        expect(%w[possible_values format_store].map { |column| stored_raw(child, column) }).to eq(before)

        field = CustomField.find(child.id)
        field.parent_custom_field_id = parent.id.to_s
        field.value_dependencies = { kit_key(parent, 'A') => [kit_key(child, 'a1')] }
        expect(field.valid?).to be(false)
        expect(field.errors.details.keys).to eq([:value_dependencies])

        # Same bytes, other content: not a write-back.
        field = CustomField.find(child.id)
        field.value_dependencies = { kit_key(parent, 'A') => [kit_key(child, 'a2'), kit_key(child, 'a1')],
                                     kit_key(parent, 'B') => [kit_key(child, 'b1')] }
        expect(limits.preview_bytes(field, 'format_store')).to eq(before.last.bytesize)
        expect(field.valid?).to be(false)
        expect(field.errors.details.keys).to eq([:value_dependencies])
      end
    end

    it 'measures an unchanged format_store that the before_save normalization rewrites (row without a mapping key)' do
      child = build_kit(:list).last
      store = CustomField.find(child.id).format_store.to_hash.except('default_value_dependencies')
      yaml = CustomField.type_for_attribute('format_store').serialize(store)
      CustomField.connection.exec_update(
        "UPDATE custom_fields SET format_store = #{CustomField.connection.quote(yaml)} WHERE id = #{child.id}"
      )
      stored = stored_bytes(child, 'format_store')
      stub_limits('format_store' => stored)

      field = CustomField.find(child.id)
      field.name = "#{field.name}-renamed"
      expect(field.will_save_change_to_attribute?('format_store')).to be(false)
      bytes = limits.preview_bytes(field, 'format_store')
      expect(bytes).to be > stored
      expect(field.save).to be(false)
      expect(field.errors.details[:value_dependencies]).to eq([{ error: :dcf_storage_too_large,
                                                                 size: limits.delimited(bytes),
                                                                 limit: limits.delimited(stored),
                                                                 bytes: bytes, max_bytes: stored,
                                                                 column: 'format_store' }])
      expect(stored_raw(child, 'format_store')).to eq(yaml)

      stub_limits('format_store' => bytes)
      expect(field.save).to be(true), field.errors.full_messages.inspect
      expect(stored_bytes(child, 'format_store')).to eq(bytes)
    end

    # PC-15: a row whose stored YAML is not the Rails dump (here without its
    # final newline, as MariaDB stores a list one byte over TEXT) is dirty on
    # every save; only a save that writes the stored bytes back is let through.
    it 'refuses any save of a possible_values whose stored YAML is not the Rails dump and whose dump is too large' do
      field = dcf_list_field(values: %w[A B])
      name = field.name
      yaml = CustomField.type_for_attribute('possible_values').serialize(%w[A B])
      CustomField.connection.exec_update(
        "UPDATE custom_fields SET possible_values = #{CustomField.connection.quote(yaml.chomp)} WHERE id = #{field.id}"
      )
      stub_limits('possible_values' => yaml.chomp.bytesize)

      field = CustomField.find(field.id)
      expect(field.possible_values).to eq(%w[A B])
      expect(field.will_save_change_to_attribute?('possible_values')).to be(true)
      field.name = "#{name}-renamed"
      expect(field.save).to be(false)
      expect(field.errors.details[:possible_values]).to eq([{ error: :dcf_storage_too_large,
                                                              size: limits.delimited(yaml.bytesize),
                                                              limit: limits.delimited(yaml.chomp.bytesize),
                                                              bytes: yaml.bytesize, max_bytes: yaml.chomp.bytesize,
                                                              column: 'possible_values' }])
      expect(field.errors.details.keys).to eq([:possible_values])
      expect(stored_raw(field, 'possible_values')).to eq(yaml.chomp)
      expect(CustomField.find(field.id).name).to eq(name)

      stub_limits('possible_values' => yaml.bytesize)
      expect(field.save).to be(true), field.errors.full_messages.inspect
      expect(stored_raw(field, 'possible_values')).to eq(yaml)

      # The Rails dump is stored now: writing it back is not refused.
      stub_limits('possible_values' => 1)
      field = CustomField.find(field.id)
      field.possible_values_will_change!
      expect(field.will_save_change_to_attribute?('possible_values')).to be(true)
      expect(field.save).to be(true), field.errors.full_messages.inspect

      field = CustomField.find(field.id)
      field.possible_values = %w[A B C]
      expect(field.valid?).to be(false)
      expect(field.errors.details.keys).to eq([:possible_values])
      expect(storage_details(field, :possible_values).size).to eq(1)
    end

    it 'names the persisted field in violations and violation_in' do
      field = CustomField.find(dcf_list_field(values: %w[A]).id)
      field.possible_values = %w[A B]
      stub_limits('possible_values' => 1)
      expect(limits.violations(field).map(&:custom_field_id)).to eq([field.id])
      expect(field.valid?).to be(false)
      expect(limits.violation_in(field).custom_field_id).to eq(field.id)
      expect(limits.violation_in(field).custom_field_name).to eq(field.name)
    end

    it 'never checks or measures the other formats' do
      stub_limits('possible_values' => 1, 'format_store' => 1)
      allow(limits).to receive(:preview_value).and_call_original
      %w[string text int float date bool link user version extended_user].each do |format|
        field = new_field(format, url_pattern: 'http://example.test/%value%')
        field.valid?
        expect(storage_details(field, :possible_values) + storage_details(field, :value_dependencies)).to eq([]), format
      end
      field = new_field('nope')
      expect(field.valid?).to be(false)
      expect(field.errors.details.keys).to eq([:field_format])
      expect(limits).not_to have_received(:preview_value)
      expect(limits).not_to have_received(:column_limit)
    end

    it 'runs after the core and format checks, the circular parent error first' do
      field = CustomField.find(build_kit(:list).last.id)
      field.parent_custom_field_id = field.id.to_s
      field.value_dependencies = { 'A' => %w[a1 a2 b1] }
      stub_limits('format_store' => 1)
      expect(field.valid?).to be(false)
      expect(field.errors.details.keys).to eq([:parent_custom_field_id, :value_dependencies])
      expect(field.errors.details[:parent_custom_field_id]).to eq([{ error: :dcf_circular_dependency }])
      expect(storage_details(field, :value_dependencies).first[:bytes]).to be_a(Integer)
      expect(field.errors.full_messages.first).to start_with(IssueCustomField.human_attribute_name(:parent_custom_field_id))
    end

    it 'measures nothing when no limit is known' do
      stub_limits({})
      allow(limits).to receive(:preview_bytes).and_call_original
      field = guarded_record('depending_list')
      expect(field.valid?).to be(true)
      expect(limits).not_to have_received(:preview_bytes)
    end

    it 'neither previews nor resolves the store of a persisted depending field when no limit is known' do
      field = CustomField.find(build_kit(:list).last.id)
      field.name = "#{field.name}-x"
      stub_limits({})
      allow(field.format).to receive(:storage_preview).and_call_original
      allow(limits).to receive(:writes_column?).and_call_original

      expect(field.save).to be(true), field.errors.full_messages.inspect
      expect(field.format).not_to have_received(:storage_preview)
      expect(limits).not_to have_received(:writes_column?)
    end
  end

  describe 'registration' do
    it 'registers one Symbol validation from CustomFieldValidationPatch, prepended after CustomFieldPatch' do
      expect(validate_callbacks(CustomField)).to eq(1)
      expect(validate_callbacks(IssueCustomField)).to eq(1)
      expect(patch.private_instance_methods(false)).to eq([:dcf_validate_storage_limits])
      expect(patch.instance_methods(false)).to eq([])
      ancestors = CustomField.ancestors
      expect(ancestors.index(patch)).to be < ancestors.index(CustomField)
      expect(ancestors.index(RedmineDependingCustomFields::Patches::CustomFieldPatch)).to be < ancestors.index(CustomField)

      lines = File.readlines(File.expand_path('../../init.rb', __dir__)).map(&:strip)
      at = lines.index('CustomField.prepend RedmineDependingCustomFields::Patches::CustomFieldPatch')
      expect(lines[at + 1]).to eq('CustomField.prepend RedmineDependingCustomFields::Patches::CustomFieldValidationPatch')
      expect(lines.count { |l| l.include?('CustomFieldValidationPatch') }).to eq(1)
    end

    it 'keeps one callback and one error per column when the patch is prepended again (init.rb run twice)',
       :aggregate_failures do
      # The second prepend runs self.prepended again, which moves the callback
      # to the end of every validate chain; the chains are put back afterwards.
      saved = ([CustomField] + CustomField.descendants).map { |klass| [klass, klass.send(:get_callbacks, :validate)] }
      begin
        CustomField.prepend(patch)
        expect(validate_callbacks(CustomField)).to eq(1)
        expect(validate_callbacks(IssueCustomField)).to eq(1)

        field = guarded_record('depending_list')
        stub_limits('possible_values' => 1, 'format_store' => 1)
        # Rails merges identical errors (autosave errors.uniq!), so the
        # measurement itself must run once.
        allow(limits).to receive(:validate).and_call_original
        expect(field.valid?).to be(false)
        expect(limits).to have_received(:validate).once
        expect(storage_details(field, :possible_values).size).to eq(1)
        expect(storage_details(field, :value_dependencies).size).to eq(1)
      ensure
        saved.each { |klass, chain| klass.send(:set_callbacks, :validate, chain) }
      end
      saved.each { |klass, chain| expect(klass.send(:get_callbacks, :validate)).to equal(chain), klass.name }
    end
  end

  describe 'messages' do
    let(:registry) do
      {
        en: { label: 'Dependency mapping',
              error: 'is too large to store (%{size} bytes, the database allows at most %{limit} bytes)',
              usage: '%{label}: %{size} of %{limit} bytes used in the database (%{percent}%).',
              help: 'For very large lists use the Key/Value list (depending) format, or widen the database columns ' \
                    '(see the plugin README, section "MySQL / MariaDB and large lists").' },
        de: { label: 'Abhängigkeitszuordnung',
              error: 'ist zu groß zum Speichern (%{size} Bytes, die Datenbank erlaubt höchstens %{limit} Bytes)',
              usage: '%{label}: %{size} von %{limit} Bytes in der Datenbank belegt (%{percent} %).',
              help: 'Verwenden Sie für sehr große Listen das Format Schlüssel/Wert-Liste (abhängig) oder vergrößern ' \
                    'Sie die Datenbankspalten (siehe Plugin-README, Abschnitt „MySQL / MariaDB and large lists“).' },
        fr: { label: 'Mappage des dépendances',
              error: 'est trop volumineux pour être enregistré (%{size} octets, la base de données autorise au plus ' \
                     '%{limit} octets)',
              usage: '%{label} : %{size} octets utilisés sur %{limit} dans la base de données (%{percent} %).',
              help: 'Pour les très grandes listes, utilisez le format Liste clé/valeur (dépendante) ou agrandissez les ' \
                    'colonnes de la base de données (voir le README du plugin, section « MySQL / MariaDB and large ' \
                    'lists »).' },
        nl: { label: 'Afhankelijkheidskoppeling',
              error: 'is te groot om op te slaan (%{size} bytes, de database staat maximaal %{limit} bytes toe)',
              usage: '%{label}: %{size} van %{limit} bytes gebruikt in de database (%{percent}%).',
              help: 'Gebruik voor zeer grote lijsten het formaat Sleutel/Waarde-lijst (afhankelijk) of vergroot de ' \
                    'databasekolommen (zie de README van de plugin, sectie "MySQL / MariaDB and large lists").' }
      }
    end

    it 'has the registry texts in en, de, fr and nl' do
      registry.each do |locale, texts|
        I18n.with_locale(locale) do
          expect(I18n.t(:field_value_dependencies)).to eq(texts[:label]), locale.to_s
          expect(IssueCustomField.human_attribute_name(:value_dependencies)).to eq(texts[:label]), locale.to_s
          expect(I18n.t('activerecord.errors.messages.dcf_storage_too_large', size: '%{size}', limit: '%{limit}'))
            .to eq(texts[:error]), locale.to_s
          expect(I18n.t(:text_dcf_storage_usage, label: '%{label}', size: '%{size}', limit: '%{limit}', percent: '%{percent}'))
            .to eq(texts[:usage]), locale.to_s
          expect(I18n.t(:text_dcf_storage_admin_help)).to eq(texts[:help]), locale.to_s
        end
      end
      expect(I18n.t(:text_dcf_storage_usage, label: 'Dependency mapping', size: '61,062', limit: '65,535', percent: 93))
        .to eq('Dependency mapping: 61,062 of 65,535 bytes used in the database (93%).')
    end

    it 'builds full messages with locale-delimited numbers at validation time' do
      values = DcfLargeList.values_of_yaml_bytes(1_234)
      registry.each do |locale, texts|
        I18n.with_locale(locale) do
          field = new_field('list', possible_values: values)
          stub_limits('possible_values' => 1_233)
          field.valid?
          delimiter = I18n.t('number.format.delimiter')
          label = IssueCustomField.human_attribute_name(:possible_values)
          message = texts[:error].sub('%{size}', "1#{delimiter}234").sub('%{limit}', "1#{delimiter}233")
          expect(field.errors.full_messages).to eq(["#{label} #{message}"]), locale.to_s
        end
      end
    end

    it 'names the dependency mapping in German' do
      I18n.with_locale(:de) do
        field = guarded_record('depending_list')
        bytes = limits.preview_bytes(field, 'format_store')
        stub_limits('format_store' => bytes - 1)
        field.valid?
        expect(field.errors.full_messages).to eq(["Abhängigkeitszuordnung ist zu groß zum Speichern (#{bytes} Bytes, " \
                                                  "die Datenbank erlaubt höchstens #{bytes - 1} Bytes)"])
      end
    end

    it 'delimits numbers in the current locale' do
      I18n.with_locale(:de) { expect(limits.delimited(65_535)).to eq('65.535') }
      [:en, :fr, :nl].each do |locale|
        I18n.with_locale(locale) do
          expect(limits.delimited(65_535)).to eq("65#{I18n.t('number.format.delimiter')}535"), locale.to_s
          expect(limits.delimited(999)).to eq('999')
        end
      end
    end
  end

  describe '.usage' do
    # A list field whose stored possible_values are exactly +bytes+ ASCII bytes
    # (LENGTH counts characters on PostgreSQL and SQLite).
    def ascii_list(bytes)
      field = dcf_list_field(values: ['x' * (bytes - 7)])
      expect(stored_bytes(field, 'possible_values')).to eq(bytes)
      field
    end

    # Query overhead of usage(record) (G6 differential form), with its rows.
    def usage_overhead(record)
      rows = nil
      overhead = dcf_plugin_overhead(with: -> { rows = limits.usage(record) }, without: -> {})
      [overhead, rows]
    end

    it 'is empty without a query when the database is not MySQL' do
      field = ascii_list(100)
      allow(limits).to receive(:mysql?).and_return(false)
      stub_limits('possible_values' => 100, 'format_store' => 100)
      expect(usage_overhead(field)).to eq([0, []])
      expect(limits).not_to have_received(:column_limit)
    end

    it 'is empty without a query for a new record and for a format it does not guard' do
      allow(limits).to receive(:mysql?).and_return(true)
      stub_limits('possible_values' => 1, 'format_store' => 1)
      record = new_field('list', possible_values: %w[A])
      expect(usage_overhead(record)).to eq([0, []])
      string = new_field('string', url_pattern: 'http://example.test/%value%')
      string.save!
      expect(usage_overhead(string)).to eq([0, []])
    end

    it 'is empty without a query when no limit is known' do
      allow(limits).to receive(:mysql?).and_return(true)
      stub_limits({})
      field = ascii_list(100)
      expect(usage_overhead(field)).to eq([0, []])
    end

    it 'reports a column at 90 percent of its limit, and nothing one byte lower with the same queries' do
      allow(limits).to receive(:mysql?).and_return(true)
      stub_limits('possible_values' => 1_000)
      at = ascii_list(900)
      below = ascii_list(899)

      shown, rows = usage_overhead(at)
      hidden, none = usage_overhead(below)
      expect(rows.map(&:to_h)).to eq([{ column: 'possible_values', attribute: :possible_values, bytes: 900,
                                        limit: 1_000, percent: 90 }])
      expect(none).to eq([])
      expect(shown).to eq(hidden)
    end

    it 'shows a column above its limit as measured (after a limit drop)' do
      allow(limits).to receive(:mysql?).and_return(true)
      field = ascii_list(150)
      stub_limits('possible_values' => 100)
      expect(limits.usage(field).map(&:to_h)).to eq([{ column: 'possible_values', attribute: :possible_values,
                                                       bytes: 150, limit: 100, percent: 150 }])
    end

    it 'floors the percent, reports format_store and counts NULL as 0 bytes' do
      allow(limits).to receive(:mysql?).and_return(true)
      field = dcf_enum_field(names: %w[X])
      field.update!(url_pattern: "http://example.test/#{'p' * 200}/%value%")
      bytes = stored_bytes(field, 'format_store')
      expect(bytes).to be > 200
      expect(stored_raw(field, 'possible_values')).to be_nil
      stub_limits('possible_values' => 1, 'format_store' => bytes + 1)
      expect(limits.usage(field).map(&:to_h)).to eq([{ column: 'format_store', attribute: :value_dependencies,
                                                       bytes: bytes, limit: bytes + 1, percent: 99 }])
    end

    it 'reads the stored bytes, not the unsaved value' do
      allow(limits).to receive(:mysql?).and_return(true)
      stub_limits('possible_values' => 1_000)
      field = ascii_list(100)
      field.possible_values = ['x' * 990]
      expect(limits.usage(field)).to eq([])
    end
  end

  describe '.base_bytes' do
    it 'measures the in-memory store without the two mappings' do
      field = CustomField.find(build_kit(:list).last.id)
      field.value_dependencies = { 'A' => %w[a1 a2] }
      field.default_value_dependencies = { 'A' => 'a1' }
      store = field.format_store.to_hash
      expected = limits.serialized_bytesize(CustomField, 'format_store',
                                            store.except('value_dependencies', 'default_value_dependencies'))
      expect(limits.base_bytes(field)).to eq(expected)
      expect(expected).to be_between(1, limits.preview_bytes(field, 'format_store') - 1)
      expect(field.format_store.to_hash).to eq(store)
    end
  end
end
