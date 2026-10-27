# frozen_string_literal: true

require_relative '../rails_helper'
require 'stringio'
require 'logger'

# WP-22 (editor design 3.1 to 3.4, AD-2 to AD-6, UD-15, UD-17): the admin JSON
# transport on the model. dependencies_json= only stores the raw value;
# before_validation parses it once per assigned value, refuses a stale base,
# prunes against the parent and the field itself (D6) and assigns both
# mappings; validate adds the payload errors on :value_dependencies; after_save
# resets it. Nothing else prunes (BC-02).
RSpec.describe 'CustomField dependencies_json transport (WP-22)' do
  fixtures :users

  let(:payload) { RedmineDependingCustomFields::DependencyPayload }
  let(:rules) { RedmineDependingCustomFields::DependencyRules }
  let(:limits) { RedmineDependingCustomFields::StorageLimits }
  let(:patch) { RedmineDependingCustomFields::Patches::CustomFieldValidationPatch }
  let(:parent) { dcf_list_field(name: "Parent-#{SecureRandom.hex(3)}", values: %w[A B C]) }
  let(:child) { depending_child(parent) }

  unreadable = 'Dependency mapping could not be read. Reload the page and try again.'
  stale = 'Dependency mapping was changed by someone else after you opened this page. Your changes were not ' \
          'saved. The editor shows the current version and your version so that you can choose which one to keep.'
  max_bytes = 4 * 1024 * 1024

  def depending_child(parent, values: %w[a1 b1 c1], multiple: false)
    field = dcf_list_field(format: 'depending_list', name: "Child-#{SecureRandom.hex(3)}", values: values,
                           parent: parent, multiple: multiple)
    dcf_set_dependencies(field, value_dependencies: { 'A' => %w[a1], 'B' => %w[b1] },
                                default_value_dependencies: { 'A' => 'a1' })
  end

  # A v1 payload; extra top-level keys (base, source, import, version) as given.
  def json(links = {}, defaults = nil, extra = {})
    body = {}
    extra.each { |key, value| body[key.to_s] = value }
    body['value_dependencies'] = links
    body['default_value_dependencies'] = defaults unless defaults.nil?
    JSON.generate(body)
  end

  def raw_store(field)
    CustomField.connection.select_value(CustomField.where(id: field.id).select(:format_store).to_sql)
  end

  def stored(field)
    record = CustomField.find(field.id)
    [record.value_dependencies.to_hash, record.default_value_dependencies.to_hash]
  end

  def mapping(field)
    [field.value_dependencies.to_hash, field.default_value_dependencies.to_hash]
  end

  def payload_errors(field)
    field.errors.details[:value_dependencies].map { |detail| detail[:error] }
  end

  def spy(object, *names)
    names.each { |name| allow(object).to receive(name).and_call_original }
  end

  def capture_log
    io = StringIO.new
    allow(Rails).to receive(:logger).and_return(Logger.new(io))
    io
  end

  def log_lines(io)
    io.string.lines.map(&:chomp).select { |line| line.include?('dependencies_json') }
  end

  describe 'registration (quality S1)' do
    [CustomField, IssueCustomField].each do |klass|
      it "runs the transport after core before_validation and validates it between the core and storage checks " \
         "on #{klass.name}" do
        validation = klass._validation_callbacks.map { |c| [c.kind, c.filter] }
        expect(validation.count([:before, :dcf_apply_dependencies_json])).to eq(1)
        expect(validation.index([:before, :set_searchable]))
          .to be < validation.index([:before, :dcf_apply_dependencies_json])

        validate = klass._validate_callbacks.map(&:filter)
        expect(validate.count(:dcf_validate_dependencies_json)).to eq(1)
        expect(validate.count(:dcf_validate_storage_limits)).to eq(1)
        expect(validate.index(:validate_custom_field)).to be < validate.index(:dcf_validate_dependencies_json)
        expect(validate.index(:dcf_validate_dependencies_json)).to be < validate.index(:dcf_validate_storage_limits)

        save = klass._save_callbacks.map { |c| [c.kind, c.filter] }
        expect(save.count([:after, :dcf_reset_dependencies_json])).to eq(1)
      end
    end
  end

  describe 'virtual attribute' do
    it 'only stores the raw value: nothing is parsed or changed, and the reader returns nil' do
      field = CustomField.find(child.id)
      spy(payload, :parse)

      field.dependencies_json = json('C' => %w[c1])

      expect(field.dependencies_json).to be_nil
      expect(payload).not_to have_received(:parse)
      expect(mapping(field)).to eq([{ 'A' => %w[a1], 'B' => %w[b1] }, { 'A' => 'a1' }])
      expect(field.changed?).to be(false)
      expect(field.dcf_dependencies_conflict).to be_nil
    end

    it 'is no model attribute, so the submitted value never appears in attributes, JSON, inspect or changes' do
      marker = "MARK-#{SecureRandom.hex(8)}"
      field = CustomField.find(child.id)
      field.dependencies_json = json(marker => [marker])

      expect(field.has_attribute?(:dependencies_json)).to be(false)
      expect(field.attributes).not_to have_key('dependencies_json')
      expect(field).not_to respond_to(:dependencies_json_before_type_cast)
      [field.to_json, field.inspect, field.serializable_hash.to_s, field.changes.to_s].each do |text|
        expect(text).not_to include(marker)
      end
      field.valid?
      expect(field.dependencies_json).to be_nil
      expect([field.to_json, field.inspect, field.changes.to_s].join).not_to include(marker)
    end

    it 'lists value_dependencies, default_value_dependencies and dependencies_json as safe attributes (BC-04, UD-15)' do
      names = %w[value_dependencies default_value_dependencies dependencies_json]
      expect(CustomField.safe_attributes.flat_map(&:first).map(&:to_s)).to include(*names)
      [CustomField, IssueCustomField, ProjectCustomField, TimeEntryCustomField].each do |klass|
        [dcf_admin, User.anonymous].each do |user|
          expect(klass.new.safe_attribute_names(user)).to include(*names), "#{klass.name} #{user.login.inspect}"
        end
      end
    end
  end

  describe 'nothing posted (AD-2)' do
    it 'does not parse, prune or read the stored digest when nothing is assigned' do
      raw_before = raw_store(child)
      field = CustomField.find(child.id)
      spy(payload, :parse, :stored_digest)
      spy(rules, :prune_mapping, :value_keys)

      field.name = "#{field.name}-x"
      expect(field.save).to be(true), field.errors.full_messages.inspect

      expect(raw_store(child)).to eq(raw_before)
      expect(payload).not_to have_received(:parse)
      expect(payload).not_to have_received(:stored_digest)
      expect(rules).not_to have_received(:prune_mapping)
      expect(rules).not_to have_received(:value_keys)
    end

    it 'treats nil and JSON white space as nothing posted' do
      raw_before = raw_store(child)
      spy(payload, :stored_digest)
      spy(rules, :prune_mapping, :value_keys)

      [nil, '', "  \t\r\n"].each do |raw|
        field = CustomField.find(child.id)
        field.dependencies_json = raw
        expect(field.save).to be(true), field.errors.full_messages.inspect
        expect(raw_store(child)).to eq(raw_before), raw.inspect
      end
      expect(payload).not_to have_received(:stored_digest)
      expect(rules).not_to have_received(:prune_mapping)
      expect(rules).not_to have_received(:value_keys)
    end

    it 'refuses NUL, U+00A0 and other Unicode spaces as unreadable' do
      raw_before = raw_store(child)
      ["\u0000", "\u00a0", " \u2003 ", "\u3000"].each do |raw|
        field = CustomField.find(child.id)
        field.dependencies_json = raw
        expect(field.save).to be(false)
        expect(field.errors.details[:value_dependencies]).to eq([{ error: :dcf_invalid_dependencies_payload }])
        expect(raw_store(child)).to eq(raw_before)
      end
    end
  end

  describe 'applying an ok payload' do
    it "clears both mappings with '{}' and with empty objects; a payload with links only clears the defaults" do
      ['{}', '{"version":1}', '{"value_dependencies":{},"default_value_dependencies":{}}'].each do |raw|
        field = CustomField.find(depending_child(parent).id)
        field.dependencies_json = raw
        expect(field.save).to be(true), field.errors.full_messages.inspect
        expect(stored(field)).to eq([{}, {}]), raw
      end

      field = CustomField.find(child.id)
      field.dependencies_json = json('B' => %w[b1])
      expect(field.save).to be(true)
      expect(stored(field)).to eq([{ 'B' => %w[b1] }, {}])
    end

    it 'prunes unknown parent keys and child values, orders by parent then child value and shapes the defaults' do
      field = CustomField.find(child.id)
      field.dependencies_json = json({ 'ZZ' => %w[a1], 'C' => %w[c1 zz c1], 'A' => %w[b1 a1], 'B' => ['', 'zz'] },
                                     { 'A' => %w[b1 a1], 'C' => 'zz', 'ZZ' => 'a1' })

      expect(field.save).to be(true), field.errors.full_messages.inspect

      links, defaults = stored(field)
      expect(links).to eq('A' => %w[a1 b1], 'C' => %w[c1])
      expect(links.keys).to eq(%w[A C])
      expect(defaults).to eq('A' => 'a1')
      expect(rules.mapping_problems(links, defaults, parent_keys: %w[A B C], child_keys: %w[a1 b1 c1])).to eq([])
    end

    it 'stores the defaults of a multiple field as Arrays' do
      field = CustomField.find(depending_child(parent, multiple: true).id)
      field.dependencies_json = json({ 'A' => %w[a1 b1], 'B' => %w[b1] }, { 'A' => 'b1', 'B' => %w[b1 zz] })

      expect(field.save).to be(true), field.errors.full_messages.inspect
      expect(stored(field)).to eq([{ 'A' => %w[a1 b1], 'B' => %w[b1] }, { 'A' => %w[b1], 'B' => %w[b1] }])
    end

    it 'keeps the submitted keys and prunes child values when no valid parent resolves; the save stores no parent (D9)' do
      other_type = dcf_list_field(type: TimeEntryCustomField, values: %w[K1 K2])
      other_family = dcf_enum_field(names: %w[K1 K2])
      [(CustomField.maximum(:id).to_i + 1_000).to_s, other_type.id.to_s, other_family.id.to_s, ''].each do |pid|
        field = CustomField.find(depending_child(parent).id)
        field.parent_custom_field_id = pid
        field.dependencies_json = json({ 'K2' => %w[a1 zz], 'K9' => %w[b1] }, { 'K2' => 'a1' })

        expect(field.save).to be(true), "#{pid.inspect}: #{field.errors.full_messages.inspect}"
        links, defaults = stored(field)
        expect(links).to eq('K2' => %w[a1], 'K9' => %w[b1])
        expect(links.keys).to eq(%w[K2 K9])
        expect(defaults).to eq('K2' => 'a1')
        expect(CustomField.find(field.id).parent_custom_field_id).to be_blank
      end
    end

    it 'prunes to the parent assigned in the same save, in either assignment order' do
      second = dcf_list_field(name: "Second-#{SecureRandom.hex(3)}", values: %w[C B])
      body = json({ 'A' => %w[a1], 'B' => %w[b1], 'C' => %w[c1] }, { 'A' => 'a1', 'C' => 'c1' })
      [{ 'parent_custom_field_id' => second.id.to_s, 'dependencies_json' => body },
       { 'dependencies_json' => body, 'parent_custom_field_id' => second.id.to_s }].each do |attributes|
        field = CustomField.find(depending_child(parent).id)
        field.safe_attributes = attributes
        expect(field.save).to be(true), field.errors.full_messages.inspect

        links, defaults = stored(field)
        expect(links).to eq('C' => %w[c1], 'B' => %w[b1])
        expect(links.keys).to eq(%w[C B])
        expect(defaults).to eq('C' => 'c1')
        expect(CustomField.find(field.id).parent_custom_field_id).to eq(second.id)
      end
    end

    it 'prunes child values against the possible values assigned in the same save' do
      field = CustomField.find(child.id)
      field.safe_attributes = { 'dependencies_json' => json({ 'A' => %w[c9 a1], 'C' => %w[c1] }, { 'C' => 'c1' }),
                                'possible_values' => "a1\nc9\nb1" }

      expect(field.save).to be(true), field.errors.full_messages.inspect
      expect(stored(field)).to eq([{ 'A' => %w[a1 c9] }, {}])
    end

    it 'keeps links from and to inactive enumeration entries and drops ids of another field (D6)' do
      enum_parent = dcf_enum_field(names: %w[X Y Z])
      enum_child = dcf_enum_field(format: 'depending_enumeration', names: %w[x1 y1 z1], parent: enum_parent)
      foreign = dcf_enum_field(names: %w[F]).enumerations.first.id
      x, y, z = enum_parent.enumerations.order(:position).map(&:id)
      x1, y1, z1 = enum_child.enumerations.order(:position).map(&:id)
      CustomFieldEnumeration.where(id: [z, z1]).update_all(active: false)

      field = CustomField.find(enum_child.id)
      field.dependencies_json = json({ z.to_s => [z1, x1], x.to_s => [x1, z1, foreign], y.to_s => [y1],
                                       foreign.to_s => [x1] },
                                     { x.to_s => z1, z.to_s => x1.to_s })
      expect(field.save).to be(true), field.errors.full_messages.inspect

      links, defaults = stored(field)
      expect(links).to eq(x.to_s => [x1.to_s, z1.to_s], y.to_s => [y1.to_s], z.to_s => [x1.to_s, z1.to_s])
      expect(links.keys).to eq([x, y, z].map(&:to_s))
      expect(defaults).to eq(x.to_s => z1.to_s, z.to_s => x1.to_s)
    end

    it 'prunes every link of a new Key/Value list (depending) field, which has no values yet' do
      enum_parent = dcf_enum_field(names: %w[X])
      field = IssueCustomField.new(name: "New-#{SecureRandom.hex(3)}", field_format: 'depending_enumeration',
                                   is_for_all: true)
      field.parent_custom_field_id = enum_parent.id.to_s
      field.dependencies_json = json({ enum_parent.enumerations.first.id.to_s => [1] },
                                     { enum_parent.enumerations.first.id.to_s => 1 })

      expect(field.save).to be(true), field.errors.full_messages.inspect
      expect(stored(field)).to eq([{}, {}])
    end

    it 'lets the JSON replace nested mapping params of the same assignment, in either order' do
      nested = { 'value_dependencies' => { 'A' => %w[a1 b1] }, 'default_value_dependencies' => { 'A' => 'b1' } }
      body = json('B' => %w[b1])
      [nested.merge('dependencies_json' => body), { 'dependencies_json' => body }.merge(nested)].each do |attributes|
        field = CustomField.find(depending_child(parent).id)
        field.safe_attributes = attributes
        expect(field.save).to be(true), field.errors.full_messages.inspect
        expect(stored(field)).to eq([{ 'B' => %w[b1] }, {}])
      end
    end

    it 'accepts Integer ids, an import source with its details and a base equal to the stored digest' do
      enum_parent = dcf_enum_field(names: %w[X Y])
      enum_child = dcf_enum_field(format: 'depending_enumeration', names: %w[x1 y1], parent: enum_parent)
      x, y = enum_parent.enumerations.order(:position).map(&:id)
      x1, y1 = enum_child.enumerations.order(:position).map(&:id)
      field = CustomField.find(enum_child.id)
      field.dependencies_json = json({ y.to_s => [y1], x.to_s => [y1, x1] }, { x.to_s => x1 },
                                     'version' => 1, 'source' => 'import',
                                     'import' => { 'mode' => 'replace', 'rows' => 3 },
                                     'base' => payload.stored_digest(field))

      expect(field.save).to be(true), field.errors.full_messages.inspect
      expect(stored(field)).to eq([{ x.to_s => [x1.to_s, y1.to_s], y.to_s => [y1.to_s] }, { x.to_s => x1.to_s }])
    end

    it 'writes only the two mappings and no audit row' do
      field = CustomField.find(child.id)
      field.update!(hide_when_disabled: '1')
      field = CustomField.find(child.id)
      store_before = field.format_store.to_hash.except('value_dependencies', 'default_value_dependencies')
      field.dependencies_json = json('C' => %w[c1])

      expect { expect(field.save).to be(true) }.not_to change(RedmineDependingCustomFields::ConfigAuditEvent, :count)
      after = CustomField.find(child.id)
      expect(after.format_store.to_hash.except('value_dependencies', 'default_value_dependencies')).to eq(store_before)
      expect(after.possible_values).to eq(%w[a1 b1 c1])
    end
  end

  describe 'refused payloads (AD-4, G5)' do
    hostile = {
      'not JSON' => 'not json',
      'an unterminated object' => '{',
      'a top-level Array' => '[]',
      'a top-level String' => '"x"',
      'an unknown top-level key' => '{"meta":{}}',
      'an unsupported version' => '{"version":2}',
      'an unknown source' => '{"source":"api"}',
      'import details without source import' => '{"import":{"mode":"merge","rows":1}}',
      'a short base' => '{"base":"abc"}',
      'an upper-case base' => %({"base":"#{'A' * 64}"}),
      'links as an Array' => '{"value_dependencies":[]}',
      'a float' => '{"value_dependencies":{"A":[1.5]}}',
      'a boolean' => '{"value_dependencies":{"A":[true]}}',
      'null' => '{"value_dependencies":{"A":[null]}}',
      'a negative integer' => '{"value_dependencies":{"A":[-1]}}',
      'a 20-digit integer' => '{"value_dependencies":{"A":[12345678901234567890]}}',
      'nesting deeper than 3' => '{"value_dependencies":{"A":[["a1"]]}}',
      'an object as a default' => '{"default_value_dependencies":{"A":{"x":"a1"}}}',
      'a comment' => '{"value_dependencies":{} /* x */}'
    }
    non_strings = {
      'a Hash' => -> { { 'value_dependencies' => {} } },
      'an Array' => -> { ['{}'] },
      'ActionController::Parameters' => -> { ActionController::Parameters.new('value_dependencies' => {}) },
      'an Integer' => -> { 1 },
      'true' => -> { true },
      'a BasicObject' => -> { BasicObject.new }
    }

    def expect_refused(field, raw_before, message)
      expect(field.save).to be(false)
      expect(field.errors.details[:value_dependencies]).to eq([{ error: :dcf_invalid_dependencies_payload }])
      expect(field.errors.attribute_names).to eq([:value_dependencies])
      expect(field.errors.full_messages).to eq([message])
      expect(mapping(field)).to eq([{ 'A' => %w[a1], 'B' => %w[b1] }, { 'A' => 'a1' }])
      expect(raw_store(field)).to eq(raw_before)
    end

    hostile.each do |label, raw|
      it "refuses #{label} as unreadable on :value_dependencies only and keeps the row" do
        raw_before = raw_store(child)
        field = CustomField.find(child.id)
        field.dependencies_json = raw
        expect_refused(field, raw_before, unreadable)
      end
    end

    non_strings.each do |label, raw|
      it "refuses #{label} without reading it" do
        raw_before = raw_store(child)
        field = CustomField.find(child.id)
        field.dependencies_json = raw.call
        expect_refused(field, raw_before, unreadable)
      end
    end

    it 'rejects a 1,000,000-digit and a 20-digit integer before JSON.parse, in under a second' do
      raw_before = raw_store(child)
      expect(JSON).not_to receive(:parse)
      ["{\"value_dependencies\":{\"A\":[#{'9' * 1_000_000}]}}", '{"value_dependencies":{"A":[99999999999999999999]}}']
        .each do |raw|
        field = CustomField.find(child.id)
        field.dependencies_json = raw
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        expect(field.valid?).to be(false)
        expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 1.0
        expect(payload_errors(field)).to eq([:dcf_invalid_dependencies_payload])
      end
      expect(raw_store(child)).to eq(raw_before)
    end

    it 'gives the size message above 4 MiB, never the unreadable one, and accepts exactly 4 MiB' do
      body = json('C' => %w[c1])
      at_limit = body + (' ' * (max_bytes - body.bytesize))
      above = "#{at_limit} "
      raw_before = raw_store(child)

      field = CustomField.find(child.id)
      field.dependencies_json = above
      allow(JSON).to receive(:parse).and_call_original
      expect(field.save).to be(false)
      expect(JSON).not_to have_received(:parse)
      expect(field.errors.details[:value_dependencies])
        .to eq([{ error: :dcf_dependencies_too_large_to_send, size: limits.delimited(max_bytes + 1),
                  limit: limits.delimited(max_bytes), bytes: max_bytes + 1, max_bytes: max_bytes }])
      expect(field.errors.full_messages)
        .to eq(["Dependency mapping is too large to be sent (#{limits.delimited(max_bytes + 1)} bytes, at most " \
                "#{limits.delimited(max_bytes)} bytes). Remove links and try again."])
      expect(raw_store(child)).to eq(raw_before)

      field = CustomField.find(child.id)
      field.dependencies_json = at_limit
      expect(field.save).to be(true), field.errors.full_messages.inspect
      expect(stored(field)).to eq([{ 'C' => %w[c1] }, {}])
    end

    {
      de: ['Abhängigkeitszuordnung ist zu groß zum Senden (%<size>s Bytes, höchstens %<limit>s Bytes). Entfernen Sie ' \
           'Verknüpfungen und versuchen Sie es erneut.',
           'Abhängigkeitszuordnung konnte nicht gelesen werden. Laden Sie die Seite neu und versuchen Sie es erneut.'],
      fr: ["Mappage des dépendances est trop volumineux pour être envoyé (%<size>s octets, au maximum %<limit>s " \
           'octets). Supprimez des liens et réessayez.',
           "Mappage des dépendances n'a pas pu être lu. Rechargez la page et réessayez."],
      nl: ['Afhankelijkheidskoppeling is te groot om te verzenden (%<size>s bytes, maximaal %<limit>s bytes). ' \
           'Verwijder koppelingen en probeer het opnieuw.',
           'Afhankelijkheidskoppeling kon niet worden gelezen. Herlaad de pagina en probeer het opnieuw.']
    }.each do |locale, (too_large, invalid)|
      it "delimits the sizes in the locale of the validation (#{locale})" do
        I18n.with_locale(locale) do
          field = CustomField.find(child.id)
          field.dependencies_json = 'x' * (max_bytes + 1)
          expect(field.valid?).to be(false)
          size = ActiveSupport::NumberHelper.number_to_delimited(max_bytes + 1)
          limit = ActiveSupport::NumberHelper.number_to_delimited(max_bytes)
          expect(field.errors.full_messages).to eq([format(too_large, size: size, limit: limit)])

          field.dependencies_json = '{'
          expect(field.valid?).to be(false)
          expect(field.errors.full_messages).to eq([invalid])
        end
      end
    end

    it 'logs a refused payload once, with the field, the code and the size only' do
      marker = "MARK-#{SecureRandom.hex(8)}"
      line = /\A.*\[DCF\] custom field #(\d+|new) dependencies_json rejected: ([a-z_]+) \((\d+) bytes\)\z/
      cases = {
        %({"value_dependencies":{"#{marker}":[}) => 'invalid_json',
        "{\"#{marker}\":[#{'9' * 1_000_000}]}" => 'number_too_long',
        "\"#{marker}\"#{' ' * max_bytes}" => 'too_large',
        { marker => [marker] } => 'not_a_string',
        "\u00a0#{marker}" => 'invalid_json',
        %({"meta":{"#{marker}":1}}) => 'unknown_key'
      }
      cases.each do |raw, code|
        io = capture_log
        field = CustomField.find(child.id)
        field.dependencies_json = raw
        2.times { expect(field.valid?).to be(false) }

        lines = log_lines(io)
        expect(lines.size).to eq(1), lines.inspect
        expect(lines.first).to match(line)
        expect(lines.first[line, 1]).to eq(child.id.to_s)
        expect(lines.first[line, 2]).to eq(code)
        expect(lines.first[line, 3]).to eq(raw.is_a?(String) ? raw.bytesize.to_s : '0')
        expect(io.string).not_to include(marker)
      end
    end

    it 'logs nothing for nothing posted and for an ok payload' do
      io = capture_log
      [nil, '', ' ', json('C' => %w[c1])].each do |raw|
        field = CustomField.find(depending_child(parent).id)
        field.dependencies_json = raw
        expect(field.save).to be(true), field.errors.full_messages.inspect
      end
      expect(log_lines(io)).to eq([])
    end
  end

  describe 'lost-update guard (UD-17, AD-6)' do
    let(:posted) do
      [{ 'C' => %w[c1 zz], 'ZZ' => %w[a1] }, { 'C' => 'c1' }]
    end

    it 'refuses a well-formed base that differs from the stored mapping, applies nothing and keeps the posted version' do
      raw_before = raw_store(child)
      field = CustomField.find(child.id)
      spy(rules, :prune_mapping, :value_keys)
      field.dependencies_json = json(posted[0], posted[1], 'base' => '0' * 64, 'source' => 'editor')

      expect(field.save).to be(false)
      expect(field.errors.details[:value_dependencies]).to eq([{ error: :dcf_stale_dependencies }])
      expect(field.errors.full_messages).to eq([stale])
      expect(mapping(field)).to eq([{ 'A' => %w[a1], 'B' => %w[b1] }, { 'A' => 'a1' }])
      expect(field.dcf_dependencies_conflict)
        .to eq('value_dependencies' => posted[0], 'default_value_dependencies' => posted[1],
               'source' => 'editor', 'import' => nil)
      expect(rules).not_to have_received(:prune_mapping)
      expect(rules).not_to have_received(:value_keys)
      expect(raw_store(child)).to eq(raw_before)
    end

    it 'reports the import details of a refused import' do
      field = CustomField.find(child.id)
      field.dependencies_json = json(posted[0], nil, 'base' => '1' * 64, 'source' => 'import',
                                                     'import' => { 'mode' => 'merge', 'rows' => 2 })

      expect(field.valid?).to be(false)
      expect(field.dcf_dependencies_conflict)
        .to eq('value_dependencies' => posted[0], 'default_value_dependencies' => {},
               'source' => 'import', 'import' => { 'mode' => 'merge', 'rows' => 2 })
    end

    it 'compares with the stored mapping only: unsaved assignments and other store keys do not count' do
      field = CustomField.find(child.id)
      base = payload.stored_digest(field)
      field.value_dependencies = { 'C' => %w[c1] }
      field.hide_when_disabled = '1'
      field.name = "#{field.name}-x"
      field.dependencies_json = json({ 'B' => %w[b1] }, nil, 'base' => base)

      expect(field.save).to be(true), field.errors.full_messages.inspect
      expect(stored(field)).to eq([{ 'B' => %w[b1] }, {}])
    end

    it 'checks no base on a new record and reads no digest without a base' do
      spy(payload, :stored_digest)
      field = IssueCustomField.new(name: "New-#{SecureRandom.hex(3)}", field_format: 'depending_list',
                                   possible_values: %w[a1 b1], is_for_all: true)
      field.parent_custom_field_id = parent.id.to_s
      field.dependencies_json = json({ 'A' => %w[a1] }, nil, 'base' => '0' * 64)
      expect(field.save).to be(true), field.errors.full_messages.inspect
      expect(stored(field)).to eq([{ 'A' => %w[a1] }, {}])

      persisted = CustomField.find(child.id)
      persisted.dependencies_json = json('B' => %w[b1])
      expect(persisted.save).to be(true), persisted.errors.full_messages.inspect
      expect(payload).not_to have_received(:stored_digest)
    end

    it 'returns the conflict only after a stale refusal, as a new copy on every call' do
      field = CustomField.find(child.id)
      field.dependencies_json = json(posted[0], posted[1], 'base' => '0' * 64)
      expect(field.dcf_dependencies_conflict).to be_nil

      expect(field.valid?).to be(false)
      conflict = field.dcf_dependencies_conflict
      expect(conflict.keys).to eq(%w[value_dependencies default_value_dependencies source import])
      expect(conflict.values_at('source', 'import')).to eq(['editor', nil])
      conflict['value_dependencies']['C'] << 'mutated'
      conflict['value_dependencies']['NEW'] = %w[x]
      conflict['default_value_dependencies']['C'] << '!'
      expect(field.valid?).to be(false)
      expect(field.dcf_dependencies_conflict['value_dependencies']).to eq(posted[0])
      expect(field.dcf_dependencies_conflict['default_value_dependencies']).to eq(posted[1])

      field.dependencies_json = '{'
      expect(field.dcf_dependencies_conflict).to be_nil
      expect(field.valid?).to be(false)
      expect(field.dcf_dependencies_conflict).to be_nil

      field.dependencies_json = json({ 'C' => %w[c1] }, nil, 'base' => payload.stored_digest(field))
      expect(field.save).to be(true)
      expect(field.dcf_dependencies_conflict).to be_nil
    end

    it 'returns a new copy of a posted source and import details on every call' do
      [['editor', nil], ['import', { 'mode' => 'merge', 'rows' => 2 }]].each do |source, import|
        field = CustomField.find(child.id)
        extra = { 'base' => '0' * 64, 'source' => source }
        extra['import'] = import if import
        field.dependencies_json = json(posted[0], posted[1], extra)
        expect(field.valid?).to be(false)

        conflict = field.dcf_dependencies_conflict
        conflict['source'] << '!'
        conflict['import']['mode'] << '!' if import
        expect(field.dcf_dependencies_conflict.values_at('source', 'import')).to eq([source, import])
      end
    end
  end

  describe 'memoization and repeated saves (SP-17)' do
    it 'parses once and reads the stored digest once across repeated validations and the save' do
      field = CustomField.find(child.id)
      base = payload.stored_digest(field)
      spy(payload, :parse, :stored_digest)
      field.dependencies_json = json({ 'C' => %w[c1] }, nil, 'base' => base)

      2.times { expect(field.valid?).to be(true) }
      expect(field.save).to be(true)

      expect(payload).to have_received(:parse).once
      expect(payload).to have_received(:stored_digest).once
      expect(stored(field)).to eq([{ 'C' => %w[c1] }, {}])
    end

    it 'does not re-apply the payload or trip the guard on a second save of the same instance' do
      field = CustomField.find(child.id)
      field.dependencies_json = json({ 'C' => %w[c1] }, nil, 'base' => payload.stored_digest(field))
      expect(field.save).to be(true)

      field.value_dependencies = { 'B' => %w[b1] }
      expect(field.save).to be(true), field.errors.full_messages.inspect
      expect(stored(field)).to eq([{ 'B' => %w[b1] }, {}])
      field.name = "#{field.name}-again"
      expect(field.save).to be(true), field.errors.full_messages.inspect
      expect(stored(field)).to eq([{ 'B' => %w[b1] }, {}])
    end

    it 'accepts a new payload on the same instance whose base is the digest of the mapping it just saved' do
      field = CustomField.find(child.id)
      spy(payload, :stored_digest)
      field.dependencies_json = json({ 'C' => %w[c1] }, nil, 'base' => payload.digest(*mapping(field)))
      expect(field.save).to be(true), field.errors.full_messages.inspect

      field.dependencies_json = json({ 'B' => %w[b1] }, nil, 'base' => payload.digest({ 'C' => %w[c1] }, {}))
      expect(field.save).to be(true), field.errors.full_messages.inspect
      expect(stored(field)).to eq([{ 'B' => %w[b1] }, {}])
      expect(payload).to have_received(:stored_digest).twice

      field.dependencies_json = json({ 'A' => %w[a1] }, nil, 'base' => payload.digest({ 'C' => %w[c1] }, {}))
      expect(field.save).to be(false)
      expect(payload_errors(field)).to eq([:dcf_stale_dependencies])
    end

    it 're-validates a failed save without parsing again' do
      field = CustomField.find(child.id)
      spy(payload, :parse)
      field.name = ''
      field.dependencies_json = json('C' => %w[c1])
      expect(field.save).to be(false)
      field.name = "Child-#{SecureRandom.hex(3)}"
      expect(field.save).to be(true), field.errors.full_messages.inspect
      expect(payload).to have_received(:parse).once
      expect(stored(field)).to eq([{ 'C' => %w[c1] }, {}])
    end

    it 'keeps no reference to the payload after a save and leaves the other memo entries alone' do
      field = CustomField.find(child.id)
      raw = json({ 'C' => %w[c1] }, nil, 'base' => payload.stored_digest(field))
      rules.effective_parent_id(field)
      before = field.instance_variable_get(:@dcf_memo).keys
      field.dependencies_json = raw
      expect(field.save).to be(true)

      memo = field.instance_variable_get(:@dcf_memo)
      expect(memo.keys).to include(*before)
      expect(memo.values.grep(payload::Result)).to eq([])
      held = field.instance_variables.map { |name| field.instance_variable_get(name) }
      expect(held.any? { |value| value.equal?(raw) }).to be(false)
      expect(patch.instance_variables).to eq([])
    end
  end

  describe 'interplay' do
    it 'clears the previous error when a new value is assigned' do
      field = CustomField.find(child.id)
      field.dependencies_json = '{'
      expect(field.valid?).to be(false)
      field.dependencies_json = json('C' => %w[c1])
      expect(field.valid?).to be(true)
      field.dependencies_json = '{'
      expect(field.valid?).to be(false)
      field.dependencies_json = nil
      expect(field.valid?).to be(true)
    end

    it 'is idempotent: a second validation gives the same mapping, one error and no further query' do
      field = CustomField.find(child.id)
      field.dependencies_json = json({ 'C' => %w[c1 zz], 'ZZ' => %w[a1] }, { 'C' => 'c1' })
      expect(field.valid?).to be(true)
      first = mapping(field)
      plain = CustomField.find(child.id)
      plain.value_dependencies = first[0]
      plain.default_value_dependencies = first[1]
      expect(plain.valid?).to be(true)

      expect(dcf_count_queries { expect(field.valid?).to be(true) })
        .to eq(dcf_count_queries { expect(plain.valid?).to be(true) })
      expect(mapping(field)).to eq(first)

      invalid = CustomField.find(child.id)
      invalid.dependencies_json = '{'
      2.times do
        expect(invalid.valid?).to be(false)
        expect(payload_errors(invalid)).to eq([:dcf_invalid_dependencies_payload])
      end
    end

    it 'measures the storage limit on the pruned mapping (limits 4.1)' do
      orphans = (1..300).to_h { |i| ["orphan-#{i}-#{'x' * 40}", %w[a1 b1]] }
      body = json({ 'C' => %w[c1] }.merge(orphans))
      probe = CustomField.find(child.id)
      probe.dependencies_json = body
      expect(probe.valid?).to be(true)
      pruned = limits.preview_bytes(probe, 'format_store')
      unpruned = limits.serialized_bytesize(CustomField, 'format_store',
                                            probe.format_store.to_hash.merge('value_dependencies' => orphans))
      expect(unpruned).to be > pruned
      allow(limits).to receive(:column_limit).and_return(nil)

      allow(limits).to receive(:column_limit).with('format_store').and_return(pruned - 1)
      field = CustomField.find(child.id)
      field.dependencies_json = body
      expect(field.save).to be(false)
      detail = field.errors.details[:value_dependencies].detect { |d| d[:error] == :dcf_storage_too_large }
      expect(detail[:bytes]).to eq(pruned)
      expect(payload_errors(field)).to eq([:dcf_storage_too_large])

      allow(limits).to receive(:column_limit).with('format_store').and_return(pruned)
      field = CustomField.find(child.id)
      field.dependencies_json = body
      expect(field.save).to be(true), field.errors.full_messages.inspect
      expect(CustomField.connection.select_value(CustomField.where(id: child.id).select(:format_store).to_sql).bytesize)
        .to eq(pruned)
    end

    it 'keeps the pruned posted mapping in memory when the save fails for another reason (gap 1)' do
      raw_before = raw_store(child)
      marker = "MARK-#{SecureRandom.hex(8)}"
      field = CustomField.find(child.id)
      field.name = ''
      field.dependencies_json = json({ 'A' => %w[a1 c1], 'C' => %w[b1], marker => %w[a1] }, { 'C' => 'b1' })

      expect(field.save).to be(false)
      expect(field.errors.attribute_names).to eq([:name])
      expect(mapping(field)).to eq([{ 'A' => %w[a1 c1], 'C' => %w[b1] }, { 'C' => 'b1' }])
      expect(payload.digest(*mapping(field))).not_to eq(payload.stored_digest(field))
      expect(field.dependencies_json).to be_nil
      expect(field.dcf_dependencies_conflict).to be_nil
      expect(raw_store(child)).to eq(raw_before)
    end

    it 'keeps the circular parent error next to the transport and its own errors' do
      descendant = dcf_list_field(format: 'depending_list', values: %w[d1], parent: child)
      raw_before = raw_store(child)

      field = CustomField.find(child.id)
      field.parent_custom_field_id = descendant.id.to_s
      field.dependencies_json = json('d1' => %w[a1])
      expect(field.save).to be(false)
      expect(field.errors.details[:parent_custom_field_id]).to include(error: :dcf_circular_dependency)
      expect(field.errors.details[:value_dependencies]).to eq([])

      field = CustomField.find(child.id)
      field.parent_custom_field_id = descendant.id.to_s
      field.dependencies_json = '{'
      expect(field.save).to be(false)
      expect(field.errors.details[:parent_custom_field_id]).to include(error: :dcf_circular_dependency)
      expect(payload_errors(field)).to eq([:dcf_invalid_dependencies_payload])
      expect(field.errors.attribute_names).to contain_exactly(:parent_custom_field_id, :value_dependencies)
      expect(raw_store(child)).to eq(raw_before)
    end

    it 'aborts the save when a lookup of the transport raises (fail closed)' do
      raw_before = raw_store(child)
      allow(payload).to receive(:stored_digest).and_raise(RuntimeError, 'SECRET-SQL')
      field = CustomField.find(child.id)
      field.dependencies_json = json({ 'C' => %w[c1] }, nil, 'base' => '0' * 64)

      expect { field.save }.to raise_error(RuntimeError, 'SECRET-SQL')
      expect(field.errors.full_messages.join).not_to include('SECRET')
      expect(raw_store(child)).to eq(raw_before)
      source = File.read(File.expand_path(
                           '../../lib/redmine_depending_custom_fields/patches/custom_field_validation_patch.rb', __dir__
                         ))
      expect(source).not_to match(/\brescue\b/)
    end

    it 'writes no audit row for an ok, a stale or an unreadable payload (D6)' do
      expect do
        [json('C' => %w[c1]), json({ 'B' => %w[b1] }, nil, 'base' => '0' * 64), '{'].each do |raw|
          field = CustomField.find(child.id)
          field.dependencies_json = raw
          field.save
        end
      end.not_to change(RedmineDependingCustomFields::ConfigAuditEvent, :count)
    end

    it 'ignores dependencies_json on fields that depend on no other field' do
      spy(payload, :parse)
      [dcf_list_field(values: %w[A B]), IssueCustomField.create!(name: "S-#{SecureRandom.hex(3)}",
                                                                 field_format: 'string')].each do |plain|
        raw_before = raw_store(plain)
        ['{', 'x' * (max_bytes + 1), '{}', json({ 'A' => %w[x] }, nil, 'base' => '0' * 64)].each do |raw|
          field = CustomField.find(plain.id)
          field.dependencies_json = raw
          expect(field.save).to be(true), field.errors.full_messages.inspect
          expect(raw_store(plain)).to eq(raw_before)
          expect(raw_store(plain).to_s).not_to include('value_dependencies')
        end
      end
      expect(payload).not_to have_received(:parse)
    end

    it 'adds no query and no format_store read to a save that posts nothing' do
      counts = [false, true].map do |stubbed|
        field = CustomField.find(depending_child(parent).id)
        allow(field).to receive(:dcf_apply_dependencies_json) if stubbed
        field.name = "#{field.name}-x"
        loads = nil
        queries = dcf_count_queries { loads = dcf_count_yaml_loads { expect(field.save).to be(true) } }
        [queries, loads]
      end
      expect(counts[0]).to eq(counts[1])
    end

    it 'costs the same queries for 10 and 5,000 links and nothing beyond a nested save of the same mapping' do
      big_parent = dcf_list_field(values: (1..100).map { |i| "P#{i}" })
      children = (1..50).map { |i| "c#{i}" }
      counts = { 10 => nil, 5_000 => nil }
      counts.each_key do |size|
        links = {}
        (1..100).each { |i| links["P#{i}"] = children } if size == 5_000
        (1..10).each { |i| links["P#{i}"] = %w[c1] } if size == 10
        field = CustomField.find(dcf_list_field(format: 'depending_list', values: children, parent: big_parent).id)
        field.dependencies_json = json(links)
        counts[size] = dcf_count_queries { expect(field.save).to be(true) }
        expect(stored(field)[0].values.sum(&:size)).to eq(size)
      end
      expect(counts[10]).to eq(counts[5_000])

      nested = CustomField.find(dcf_list_field(format: 'depending_list', values: children, parent: big_parent).id)
      nested.value_dependencies = (1..10).to_h { |i| ["P#{i}", %w[c1]] }
      expect(dcf_count_queries { expect(nested.save).to be(true) }).to eq(counts[10])
    end

    it 'costs the same queries for 10 and 5,000 Key/Value links: a nested save plus the two enumeration loads' do
      enum_parent = dcf_enum_field(names: (1..100).map { |i| "P#{i}" })
      parent_ids = enum_parent.enumerations.order(:position).map { |e| e.id.to_s }
      new_child = lambda do
        id = dcf_enum_field(format: 'depending_enumeration', names: (1..50).map { |i| "c#{i}" }, parent: enum_parent).id
        [CustomField.find(id), CustomFieldEnumeration.where(custom_field_id: id).order(:position).map { |e| e.id.to_s }]
      end
      counts = [10, 5_000].map do |size|
        field, child_ids = new_child.call
        links = if size == 10
                  parent_ids.first(10).to_h { |key| [key, [child_ids.first]] }
                else
                  parent_ids.to_h { |key| [key, child_ids] }
                end
        field.dependencies_json = json(links)
        count = dcf_count_queries { expect(field.save).to be(true), field.errors.full_messages.inspect }
        expect(stored(field)[0].values.sum(&:size)).to eq(size)
        count
      end
      expect(counts[0]).to eq(counts[1])

      # Differential: value_keys loads the field's and the parent's enumerations.
      nested, child_ids = new_child.call
      nested.value_dependencies = parent_ids.first(10).to_h { |key| [key, [child_ids.first]] }
      expect(counts[0] - dcf_count_queries { expect(nested.save).to be(true) }).to eq(2)
    end
  end

  # G6: counts for the worst realistic payload; wall clock only for the pure
  # prune with a loose bound (measured 1.2 to 2.1 s on Ruby 3.2.6 and 3.3.6,
  # so 30 s keeps 10x headroom), printed as DCF PERF lines.
  describe 'cost of a 4 MiB payload (G6)' do
    def perf(text)
      RSpec.configuration.reporter.message("DCF PERF #{text} (Ruby #{RUBY_VERSION})")
    end

    def timed
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
      Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    end

    let(:big_mapping) { (1..100_000).to_h { |i| ["parent #{i} \"q\"/\u00e9", ["c#{i}", i]] } }

    it 'parses once, reads the stored digest once and prunes once per validation for 100,000 keys' do
      field = CustomField.find(child.id)
      raw = json(big_mapping.merge('A' => %w[a1 c1]), nil, 'base' => payload.stored_digest(field))
      expect(raw.bytesize).to be_between(4_000_000, max_bytes)
      allow(JSON).to receive(:parse).and_call_original
      spy(payload, :parse, :stored_digest)
      spy(rules, :prune_mapping)
      field.dependencies_json = raw

      seconds = timed { 2.times { expect(field.valid?).to be(true) } }

      expect(JSON).to have_received(:parse).once
      expect(payload).to have_received(:parse).once
      expect(payload).to have_received(:stored_digest).once
      expect(rules).to have_received(:prune_mapping).twice
      expect(mapping(field)).to eq([{ 'A' => %w[a1 c1] }, {}])
      perf(format('transport %<bytes>d bytes, 100,000 keys, two validations: %<ms>.0f ms',
                  bytes: raw.bytesize, ms: seconds * 1000))
    end

    it 'prunes 100,000 known keys and one key with 500,000 values within a loose bound' do
      result = payload.parse(json(big_mapping))
      children = (1..100_000).flat_map { |i| ["c#{i}", i.to_s] }
      links = nil
      wide = (1..500_000).map { |i| "v#{i}" }
      seconds = timed do
        links, = rules.prune_mapping(result.value_dependencies, result.default_value_dependencies,
                                     parent_keys: big_mapping.keys, child_keys: children, multiple: false)
      end
      wide_seconds = timed do
        expect(rules.prune_mapping({ 'A' => wide.reverse }, { 'A' => 'v2' }, parent_keys: ['A'], child_keys: wide,
                                                                               multiple: true))
          .to eq([{ 'A' => wide }, { 'A' => %w[v2] }])
      end

      expect(links.size).to eq(100_000)
      expect(seconds).to be < 30.0
      expect(wide_seconds).to be < 30.0
      perf(format('prune_mapping 100,000 keys: %<a>.0f ms; one key, 500,000 values: %<b>.0f ms',
                  a: seconds * 1000, b: wide_seconds * 1000))
    end
  end
end
