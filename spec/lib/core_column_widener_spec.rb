# frozen_string_literal: true

require_relative '../rails_helper'
require 'stringio'

# WP-13 (limits design 7.3 to 7.5, V21, SP-19, UD-26): the opt-in widener
# behind rake redmine:depending_custom_fields:widen_core_columns, with a fake
# MySQL connection. The fake offers only the six methods the widener may use
# (no method_missing), so any other connection call raises NoMethodError.
# spec/mysql/core_column_widener_mysql_spec.rb runs it on a real server.
RSpec.describe 'RedmineDependingCustomFields::CoreColumnWidener' do
  let(:widener_class) { RedmineDependingCustomFields::CoreColumnWidener }
  let(:out) { StringIO.new }
  let(:strict_sql) { "SET SESSION sql_mode = CONCAT(@@SESSION.sql_mode, ',STRICT_ALL_TABLES')" }
  let(:facts_sql) do
    'SELECT COLUMN_NAME AS column_name, DATA_TYPE AS data_type, COLUMN_TYPE AS column_type, ' \
      'CHARACTER_SET_NAME AS character_set_name, COLLATION_NAME AS collation_name, ' \
      'IS_NULLABLE AS is_nullable, COLUMN_DEFAULT AS column_default, COLUMN_COMMENT AS column_comment ' \
      "FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'custom_fields' " \
      "AND COLUMN_NAME IN ('format_store', 'possible_values') ORDER BY COLUMN_NAME"
  end
  let(:medium_alter) do
    'ALTER TABLE `custom_fields` ' \
      'MODIFY `format_store` MEDIUMTEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NULL, ' \
      'MODIFY `possible_values` MEDIUMTEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NULL'
  end

  # A recording MySQL connection double. facts: the information_schema rows
  # of the first read; after: those of the read that follows an ALTER.
  def fake_connection(facts:, after: nil, packet: 16_777_216, max_lengths: {})
    Class.new do
      attr_reader :calls

      def initialize(facts, after, packet, max_lengths)
        @facts = facts
        @after = after
        @packet = packet
        @max_lengths = max_lengths
        @calls = []
      end

      def executed
        @calls.filter_map { |name, sql| sql if name == :execute }
      end

      def select_all(sql)
        @calls << [:select_all, sql]
        @after && executed.any? ? @after : @facts
      end

      def select_value(sql)
        @calls << [:select_value, sql]
        return @packet if sql == 'SELECT @@max_allowed_packet'

        column = sql[/\ASELECT MAX\(LENGTH\(`(\w+)`\)\) FROM `custom_fields`\z/, 1]
        raise ArgumentError, "unexpected select_value #{sql}" unless column

        @max_lengths[column]
      end

      def execute(sql)
        @calls << [:execute, sql]
        nil
      end

      def quote(value)
        @calls << [:quote, value]
        "'#{value.to_s.gsub('\\') { '\\\\' }.gsub("'") { "\\'" }}'"
      end

      def quote_column_name(name)
        @calls << [:quote_column_name, name]
        "`#{name.to_s.gsub('`', '``')}`"
      end

      def quote_table_name(name)
        @calls << [:quote_table_name, name]
        name.to_s.split('.').map { |part| "`#{part.gsub('`', '``')}`" }.join('.')
      end
    end.new(facts, after, packet, max_lengths)
  end

  # One information_schema row as MariaDB 10.11 returns it for a nullable
  # TEXT column (COLUMN_DEFAULT is the String 'NULL' there).
  def fact(column, data_type: 'text', column_type: nil, charset: 'utf8mb4', collation: 'utf8mb4_general_ci',
           nullable: 'YES', default: 'NULL', comment: '')
    { 'column_name' => column, 'data_type' => data_type, 'column_type' => column_type || data_type,
      'character_set_name' => charset, 'collation_name' => collation, 'is_nullable' => nullable,
      'column_default' => default, 'column_comment' => comment }
  end

  def facts(type = 'text', **options)
    %w[format_store possible_values].map { |column| fact(column, data_type: type, **options) }
  end

  def run_widener(connection, **options)
    widener = widener_class.new(out: out, connection: connection, mysql: true, **options)
    code = widener.run
    [code, widener]
  end

  def output_lines
    out.string.lines.map(&:strip)
  end

  describe 'not MySQL' do
    it 'prints the notice and exits 0 without any call on the connection' do
      connection = fake_connection(facts: facts)
      widener = widener_class.new(out: out, connection: connection, mysql: false, confirm: true, type: 'bogus')

      expect(widener.run).to eq(0)
      expect(widener.status).to eq(:not_mysql)
      expect(out.string).to eq("Not a MySQL/MariaDB database: text columns are not size limited, nothing to do.\n")
      expect(connection.calls).to eq([])
    end

    it 'asks Redmine whether the database is MySQL when mysql: is not given' do
      allow(Redmine::Database).to receive(:mysql?).and_return(false)
      connection = fake_connection(facts: facts)

      expect(widener_class.new(out: out, connection: connection).run).to eq(0)
      expect(Redmine::Database).to have_received(:mysql?)
      expect(connection.calls).to eq([])
    end
  end

  describe 'dry run' do
    it 'reads the column facts and prints the exact ALTER without executing anything' do
      connection = fake_connection(facts: facts)
      allow(CustomField).to receive(:reset_column_information)
      code, widener = run_widener(connection)

      expect(code).to eq(0)
      expect(widener.status).to eq(:dry_run)
      expect(widener.sql).to eq(medium_alter)
      expect(output_lines).to include(medium_alter, strict_sql)
      expect(connection.calls.filter_map { |name, sql| sql if name == :select_all }).to eq([facts_sql])
      expect(connection.executed).to eq([])
      expect(widener.steps.map { |s| [s.column, s.from, s.to, s.action] })
        .to eq([%w[format_store text mediumtext], %w[possible_values text mediumtext]].map { |r| r + [:modify] })
      expect(out.string).to include('Dry run: nothing was changed. Run again with CONFIRM=1')
      expect(out.string).not_to include('Restart Redmine')
      expect(CustomField).not_to have_received(:reset_column_information)
    end

    it 'reads the same plan from upper-case information_schema keys (MySQL 8)' do
      upper = facts.map { |row| row.transform_keys(&:upcase) }
      code, widener = run_widener(fake_connection(facts: upper))

      expect(code).to eq(0)
      expect(widener.sql).to eq(medium_alter)
    end

    it 'names the table of the model, so a table prefix is kept' do
      connection = fake_connection(facts: facts)
      allow(CustomField).to receive(:table_name).and_return('rm_custom_fields')
      _code, widener = run_widener(connection)

      expect(connection.calls).to include([:quote, 'rm_custom_fields'], [:quote_table_name, 'rm_custom_fields'])
      expect(widener.sql).to start_with('ALTER TABLE `rm_custom_fields` MODIFY `format_store` MEDIUMTEXT')
    end

    it 'builds one MODIFY clause when only one column needs it' do
      rows = [fact('format_store', data_type: 'mediumtext'), fact('possible_values')]
      code, widener = run_widener(fake_connection(facts: rows))

      expect(code).to eq(0)
      expect(widener.sql).to eq('ALTER TABLE `custom_fields` MODIFY `possible_values` MEDIUMTEXT ' \
                                'CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NULL')
    end

    it 'keeps the character set and collation of each column' do
      rows = [fact('format_store', charset: 'utf8mb3', collation: 'utf8mb3_unicode_ci'),
              fact('possible_values', collation: 'utf8mb4_bin')]
      _code, widener = run_widener(fake_connection(facts: rows))

      expect(widener.sql).to eq('ALTER TABLE `custom_fields` ' \
                                'MODIFY `format_store` MEDIUMTEXT CHARACTER SET utf8mb3 COLLATE utf8mb3_unicode_ci ' \
                                'NULL, MODIFY `possible_values` MEDIUMTEXT CHARACTER SET utf8mb4 COLLATE ' \
                                'utf8mb4_bin NULL')
    end

    it 'keeps NOT NULL and a quoted comment' do
      rows = [fact('format_store', nullable: 'NO', default: nil), fact('possible_values', comment: "it's")]
      _code, widener = run_widener(fake_connection(facts: rows))

      expect(widener.sql).to eq('ALTER TABLE `custom_fields` ' \
                                'MODIFY `format_store` MEDIUMTEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci ' \
                                'NOT NULL, MODIFY `possible_values` MEDIUMTEXT CHARACTER SET utf8mb4 COLLATE ' \
                                "utf8mb4_general_ci NULL COMMENT 'it\\'s'")
    end

    it 'puts LONGTEXT into the ALTER for TYPE=longtext in any case' do
      %w[longtext LongText].each do |type|
        _code, widener = run_widener(fake_connection(facts: facts), type: type)
        expect(widener.sql).to eq(medium_alter.gsub('MEDIUMTEXT', 'LONGTEXT'))
      end
    end

    [nil, 'NULL', 'null'].each do |default|
      it "accepts COLUMN_DEFAULT #{default.inspect} as no default" do
        code, widener = run_widener(fake_connection(facts: facts(default: default)))

        expect(code).to eq(0)
        expect(widener.steps.map(&:action)).to eq([:modify, :modify])
      end
    end
  end

  describe 'packet check' do
    { 4_194_304 => '4,194,304', 16_777_215 => '16,777,215' }.each do |packet, shown|
      it "prints max_allowed_packet and warns below 16 MB (#{shown} bytes)" do
        run_widener(fake_connection(facts: facts, packet: packet))

        expect(out.string).to include("max_allowed_packet: #{shown} bytes")
        expect(out.string).to include('values larger than max_allowed_packet cannot be written whatever the column type')
      end
    end

    [16_777_216, 67_108_864].each do |packet|
      it "does not warn at #{packet} bytes" do
        run_widener(fake_connection(facts: facts, packet: packet))

        expect(out.string).to include("max_allowed_packet: #{ActiveSupport::NumberHelper.number_to_delimited(packet, delimiter: ',')} bytes")
        expect(out.string).not_to include('cannot be written whatever the column type')
      end
    end
  end

  describe 'CONFIRM=1' do
    it 'sets strict mode, runs the one ALTER, resets the schema cache and prints the new types' do
      connection = fake_connection(facts: facts, after: facts('mediumtext'))
      allow(CustomField).to receive(:reset_column_information)
      code, widener = run_widener(connection, confirm: true)

      expect(code).to eq(0)
      expect(widener.status).to eq(:applied)
      expect(connection.executed).to eq([strict_sql, medium_alter])
      expect(CustomField).to have_received(:reset_column_information).once
      expect(connection.calls.count { |name, _| name == :select_all }).to eq(2)
      expect(out.string).to include('custom_fields.format_store: mediumtext', 'custom_fields.possible_values: mediumtext')
      expect(output_lines.last).to eq('Restart Redmine so running processes use the new limit.')
    end

    it 'accepts the rake flag strings' do
      connection = fake_connection(facts: facts, after: facts('mediumtext'))
      allow(CustomField).to receive(:reset_column_information)
      code, = run_widener(connection, confirm: '1', revert: '0', type: '')

      expect(code).to eq(0)
      expect(connection.executed).to eq([strict_sql, medium_alter])
    end

    it 'is idempotent: columns of the requested type are up to date and nothing runs' do
      connection = fake_connection(facts: facts('mediumtext'))
      code, widener = run_widener(connection, confirm: true)

      expect(code).to eq(0)
      expect(widener.status).to eq(:up_to_date)
      expect(widener.steps.map(&:action)).to eq([:skip, :skip])
      expect(widener.sql).to be_nil
      expect(connection.executed).to eq([])
    end

    it 'never narrows a wider column without REVERT' do
      connection = fake_connection(facts: facts('longtext'))
      code, widener = run_widener(connection, confirm: true)

      expect(code).to eq(0)
      expect(widener.status).to eq(:up_to_date)
      expect(widener.steps.map(&:reason)).to all(include('never narrowed'))
      expect(connection.executed).to eq([])
    end

    it 'runs nothing on a second run after an apply' do
      allow(CustomField).to receive(:reset_column_information)
      first = fake_connection(facts: facts, after: facts('mediumtext'))
      run_widener(first, confirm: true)
      second = fake_connection(facts: facts('mediumtext'))

      expect(run_widener(second, confirm: true).first).to eq(0)
      expect(first.executed.size).to eq(2)
      expect(second.executed).to eq([])
    end
  end

  describe 'refusals (exit 1, nothing executed)' do
    refusals = {
      'a missing column' => ->(spec) { [spec.fact('possible_values')] },
      'a VARCHAR column' => ->(spec) { [spec.fact('format_store', data_type: 'varchar'), spec.fact('possible_values')] },
      'a TINYTEXT column' => ->(spec) { [spec.fact('format_store', data_type: 'tinytext'), spec.fact('possible_values')] },
      'column attributes the ALTER would drop' => lambda do |spec|
        [spec.fact('format_store', column_type: 'text /*M!100301 COMPRESSED*/'), spec.fact('possible_values')]
      end,
      'a default value' => ->(spec) { [spec.fact('format_store', default: "'x'"), spec.fact('possible_values')] },
      'an empty default' => ->(spec) { [spec.fact('format_store', default: "''"), spec.fact('possible_values')] },
      'an unknown IS_NULLABLE' => ->(spec) { [spec.fact('format_store', nullable: 'maybe'), spec.fact('possible_values')] },
      'a collation with SQL in it (SP-19)' => lambda do |spec|
        [spec.fact('format_store'), spec.fact('possible_values', collation: 'utf8mb4_general_ci; DROP TABLE users')]
      end,
      'a collation with a trailing newline (SP-19)' => lambda do |spec|
        [spec.fact('format_store'), spec.fact('possible_values', collation: "utf8mb4_general_ci\n")]
      end,
      'a nil collation (SP-19)' => ->(spec) { [spec.fact('format_store'), spec.fact('possible_values', collation: nil)] },
      'a character set with a backtick (SP-19)' => lambda do |spec|
        [spec.fact('format_store', charset: 'utf8mb4`'), spec.fact('possible_values')]
      end
    }

    refusals.each do |label, rows|
      it "refuses #{label}" do
        connection = fake_connection(facts: rows.call(self))
        allow(CustomField).to receive(:reset_column_information)
        code, widener = run_widener(connection, confirm: true)

        expect(code).to eq(1)
        expect(widener.status).to eq(:refused)
        expect(widener.sql).to be_nil
        expect(connection.executed).to eq([])
        expect(out.string).not_to include('ALTER')
        expect(widener.steps.select { |s| s.action == :refuse }.map(&:column)).to eq([label.include?('collation') ? 'possible_values' : 'format_store'])
        expect(out.string).to match(/(format_store|possible_values).*refuse/)
        expect(CustomField).not_to have_received(:reset_column_information)
      end
    end

    %w[tinytext foo text].push('mediumtext; DROP TABLE users').each do |type|
      it "refuses TYPE=#{type} before reading anything" do
        connection = fake_connection(facts: facts)
        code, widener = run_widener(connection, type: type, confirm: true)

        expect(code).to eq(1)
        expect(widener.status).to eq(:invalid_option)
        expect(out.string).to include('Invalid TYPE=')
        expect(connection.calls).to eq([])
      end
    end

    it 'refuses TYPE together with REVERT=1' do
      connection = fake_connection(facts: facts('mediumtext'))
      code, = run_widener(connection, type: 'longtext', revert: true, confirm: true)

      expect(code).to eq(1)
      expect(connection.calls).to eq([])
    end

    [{ confirm: 'yes' }, { revert: 'true' }].each do |flags|
      it "refuses #{flags.keys.first.upcase}=#{flags.values.first}" do
        connection = fake_connection(facts: facts)
        code, widener = run_widener(connection, **flags)

        expect(code).to eq(1)
        expect(widener.status).to eq(:invalid_option)
        expect(connection.calls).to eq([])
      end
    end
  end

  describe 'REVERT=1' do
    let(:text_alter) { medium_alter.gsub('MEDIUMTEXT', 'TEXT') }

    it 'refuses while a row holds more than 65,535 bytes' do
      connection = fake_connection(facts: facts('mediumtext'), max_lengths: { 'format_store' => 100, 'possible_values' => 65_536 })
      code, widener = run_widener(connection, revert: true, confirm: true)

      expect(code).to eq(1)
      expect(widener.status).to eq(:refused)
      expect(widener.steps.map(&:action)).to eq([:modify, :refuse])
      expect(widener.steps.last.reason).to include('65,536')
      expect(connection.executed).to eq([])
    end

    it 'reverts to TEXT in strict mode at 65,535 bytes and keeps the collation' do
      connection = fake_connection(facts: facts('mediumtext'), after: facts,
                                   max_lengths: { 'format_store' => nil, 'possible_values' => 65_535 })
      allow(CustomField).to receive(:reset_column_information)
      code, widener = run_widener(connection, revert: '1', confirm: '1')

      expect(code).to eq(0)
      expect(widener.status).to eq(:applied)
      expect(connection.executed).to eq([strict_sql, text_alter])
      expect(CustomField).to have_received(:reset_column_information)
    end

    it 'asks to stop Redmine before the revert and to start it only after it' do
      allow(CustomField).to receive(:reset_column_information)
      run_widener(fake_connection(facts: facts('mediumtext')), revert: true)
      expect(output_lines.last).to eq('Dry run: nothing was changed. Back up the database and stop Redmine (or block ' \
                                      'writes), then run again with CONFIRM=1 to apply.')

      out.truncate(0)
      out.rewind
      code, = run_widener(fake_connection(facts: facts('mediumtext'), after: facts), revert: true, confirm: true)
      expect(code).to eq(0)
      expect(output_lines.last).to eq('Start Redmine only now (restart it if it is running): running processes ' \
                                      'still accept values up to the old limit, which TEXT cannot hold.')
      expect(out.string).not_to include('Restart Redmine so running processes use the new limit.')
    end

    it 'is a dry run without CONFIRM=1' do
      connection = fake_connection(facts: facts('longtext'), max_lengths: { 'format_store' => 0, 'possible_values' => 10 })
      code, widener = run_widener(connection, revert: true)

      expect(code).to eq(0)
      expect(widener.status).to eq(:dry_run)
      expect(widener.sql).to eq(medium_alter.gsub('MEDIUMTEXT', 'TEXT'))
      expect(connection.executed).to eq([])
    end

    it 'skips columns that are TEXT already' do
      connection = fake_connection(facts: facts)
      code, widener = run_widener(connection, revert: true, confirm: true)

      expect(code).to eq(0)
      expect(widener.status).to eq(:up_to_date)
      expect(connection.calls.map(&:first)).not_to include(:execute)
    end
  end

  it 'maps every outcome to its exit code' do
    allow(CustomField).to receive(:reset_column_information)
    scenarios = [
      [{ mysql: false }, facts, :not_mysql, 0],
      [{}, facts('mediumtext'), :up_to_date, 0],
      [{}, facts, :dry_run, 0],
      [{ confirm: true }, facts, :applied, 0],
      [{ type: 'foo' }, facts, :invalid_option, 1],
      [{}, facts(collation: 'x y'), :refused, 1]
    ]
    results = scenarios.map do |options, rows, _status, _code|
      arguments = { out: StringIO.new, connection: fake_connection(facts: rows), mysql: true }.merge(options)
      widener = widener_class.new(**arguments)
      code = widener.run
      [widener.status, code]
    end

    expect(results).to eq(scenarios.map { |*, status, code| [status, code] })
  end

  it 'reads TYPE and CONFIRM from the rake environment' do
    widener = widener_class.from_env({ 'TYPE' => 'longtext', 'CONFIRM' => '1' }, out: out,
                                     connection: fake_connection(facts: facts, after: facts('longtext')), mysql: true)
    allow(CustomField).to receive(:reset_column_information)

    expect(widener.run).to eq(0)
    expect(widener.sql).to include('LONGTEXT')
    expect(widener.status).to eq(:applied)
  end

  it 'reads REVERT from the rake environment' do
    connection = fake_connection(facts: facts('mediumtext'), after: facts)
    env = { 'REVERT' => '1', 'CONFIRM' => '1' }
    widener = widener_class.from_env(env, out: out, connection: connection, mysql: true)
    allow(CustomField).to receive(:reset_column_information)

    expect(widener.run).to eq(0)
    expect(widener.status).to eq(:applied)
    expect(connection.executed).to eq([strict_sql, medium_alter.gsub('MEDIUMTEXT', 'TEXT')])
  end
end
