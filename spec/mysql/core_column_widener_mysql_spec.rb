# frozen_string_literal: true

require_relative '../rails_helper'
require 'stringio'

# WP-13 (limits design 10.3, V1, V2, V6 to V8): the widener and the report on
# a real MySQL/MariaDB server. Excluded on other adapters
# (spec/rails_helper.rb). custom_fields is never altered here, so the WP-11
# examples and the UD-38 skip keep seeing TEXT in any order: the real ALTER
# runs on a scratch table with the same two columns, without the fixture
# transaction (DDL commits implicitly), and the table is dropped afterwards.
RSpec.describe 'CoreColumnWidener and StorageReport on MySQL', :mysql do
  fixtures :users

  let(:connection) { CustomField.connection }
  let(:out) { StringIO.new }

  def column_facts(table)
    connection.select_rows(<<~SQL).to_h { |name, *rest| [name, rest] }
      SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_SET_NAME, COLLATION_NAME, IS_NULLABLE, COLUMN_COMMENT
      FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = #{connection.quote(table)}
        AND COLUMN_NAME IN ('format_store', 'possible_values')
    SQL
  end

  def expect_custom_fields_text
    expect(CustomField.columns_hash['possible_values'].limit).to eq(65_535)
    expect(CustomField.columns_hash['format_store'].limit).to eq(65_535)
    expect(column_facts(CustomField.table_name).values.map(&:first)).to eq(%w[text text])
  end

  it 'reads the real TEXT limit from the schema cache and from information_schema' do
    expect(RedmineDependingCustomFields::StorageLimits.column_limit('possible_values')).to eq(65_535)
    lengths = connection.select_rows(<<~SQL)
      SELECT CHARACTER_OCTET_LENGTH FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = #{connection.quote(CustomField.table_name)}
        AND COLUMN_NAME IN ('format_store', 'possible_values')
    SQL
    expect(lengths.flatten.map(&:to_i)).to eq([65_535, 65_535])
    expect_custom_fields_text
  end

  it 'prints a dry run of custom_fields with the real character set and collation and alters nothing' do
    facts = column_facts(CustomField.table_name)
    expected = facts.sort.map do |column, (_type, charset, collation, nullable, _comment)|
      "MODIFY `#{column}` MEDIUMTEXT CHARACTER SET #{charset} COLLATE #{collation} " \
        "#{nullable == 'YES' ? 'NULL' : 'NOT NULL'}"
    end
    statements = []
    callback = ->(*, payload) { statements << payload[:sql] }
    widener = RedmineDependingCustomFields::CoreColumnWidener.new(out: out)
    code = ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { widener.run }

    expect(code).to eq(0), out.string
    expect(widener.status).to eq(:dry_run)
    expect(widener.sql).to eq("ALTER TABLE #{connection.quote_table_name(CustomField.table_name)} #{expected.join(', ')}")
    expect(out.string).to include(widener.sql)
    expect(statements.grep(/\A\s*(ALTER|SET)\b/i)).to eq([])
    expect_custom_fields_text
  end

  it 'prints the session strictness in the report header' do
    expect(RedmineDependingCustomFields::StorageReport.new(out: out).run).to eq(0)

    mode = connection.select_value('SELECT @@SESSION.sql_mode').to_s
    expect(mode).to match(/STRICT_(ALL|TRANS)_TABLES/)
    expect(out.string).to include("Adapter: #{connection.adapter_name}", 'strict: yes', 'max_allowed_packet: ')
    expect(out.string).to include("#{CustomField.table_name}.possible_values: text, limit 65,535 bytes")
    expect_custom_fields_text
  end

  describe 'on a scratch table' do
    self.use_transactional_tests = false

    let(:table) { "dcf_widen_probe_#{SecureRandom.hex(3)}" }
    # Reads the columns through the schema cache, as a model does; no model
    # class, so nothing stays registered after the table is dropped.
    let(:probe) do
      cache = connection.schema_cache
      name = table
      Struct.new(:table_name) do
        define_method(:columns_hash) { cache.columns_hash(name) }
        define_method(:reset_column_information) { cache.clear_data_source_cache!(name) }
      end.new(name)
    end

    before do
      connection.execute(<<~SQL)
        CREATE TABLE #{connection.quote_table_name(table)} (
          id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
          format_store TEXT NOT NULL,
          possible_values TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NULL COMMENT 'it''s a probe'
        ) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
      SQL
    end

    after do
      connection.execute("DROP TABLE IF EXISTS #{connection.quote_table_name(table)}")
      expect_custom_fields_text
    end

    def widen(**options)
      widener = RedmineDependingCustomFields::CoreColumnWidener.new(out: out, table: table, **options)
      [widener.run, widener]
    end

    it 'widens, keeps the schema cache until reset_column_information, and reverts with the attributes kept' do
      before_facts = column_facts(table)
      limits = RedmineDependingCustomFields::StorageLimits
      expect(limits.column_limit('possible_values', probe)).to eq(65_535)

      code, widener = widen(confirm: true)
      expect(code).to eq(0), out.string
      expect(widener.status).to eq(:applied)
      expect(column_facts(table).transform_values(&:first)).to eq('format_store' => 'mediumtext',
                                                                  'possible_values' => 'mediumtext')
      expect(column_facts(table).transform_values { |f| f.drop(1) }).to eq(before_facts.transform_values { |f| f.drop(1) })
      expect(limits.column_limit('possible_values', probe)).to eq(65_535)
      probe.reset_column_information
      expect(limits.column_limit('possible_values', probe)).to eq(16_777_215)

      again, = widen(confirm: true)
      expect(again).to eq(0)

      connection.execute("INSERT INTO #{connection.quote_table_name(table)} (format_store, possible_values) " \
                         "VALUES ('', #{connection.quote('x' * 70_000)})")
      refused, refusal = widen(revert: true, confirm: true)
      expect(refused).to eq(1)
      expect(refusal.status).to eq(:refused)
      expect(column_facts(table).transform_values(&:first).values).to eq(%w[mediumtext mediumtext])

      connection.execute("DELETE FROM #{connection.quote_table_name(table)}")
      reverted, = widen(revert: true, confirm: true)
      expect(reverted).to eq(0), out.string
      expect(column_facts(table)).to eq(before_facts)
      probe.reset_column_information
      expect(limits.column_limit('possible_values', probe)).to eq(65_535)
    end
  end
end
