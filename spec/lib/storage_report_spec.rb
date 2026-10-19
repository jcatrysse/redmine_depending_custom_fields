# frozen_string_literal: true

require_relative '../rails_helper'
require 'csv'
require 'stringio'

# WP-13 (limits design 7.2, V3, V9): the read-only size report behind rake
# redmine:depending_custom_fields:report_sizes. PostgreSQL and SQLite report
# no column limit, so the examples stub StorageLimits.column_limit after the
# records exist (on MySQL a limit stubbed before would refuse their saves).
# Broken rows are written with raw SQL: update_all would serialize again.
RSpec.describe 'RedmineDependingCustomFields::StorageReport' do
  include DcfFormatCharacterization

  fixtures :users

  let(:report_class) { RedmineDependingCustomFields::StorageReport }
  let(:limits) { RedmineDependingCustomFields::StorageLimits }
  let(:out) { StringIO.new }

  def stub_limit(limit)
    allow(limits).to receive(:column_limit).and_return(limit)
  end

  def run_report(**options)
    report = report_class.new(out: out, mysql: false, **options)
    code = report.run
    [code, report]
  end

  def row_of(report, field)
    report.rows.detect { |row| row.id == field.id }
  end

  def raw(field, column)
    CustomField.connection.select_value(CustomField.where(id: field.id).select(column).to_sql)
  end

  def write_raw(field, column, value)
    connection = CustomField.connection
    connection.exec_update("UPDATE custom_fields SET #{column} = #{connection.quote(value)} WHERE id = #{field.id}")
  end

  # A list field whose possible_values YAML is exactly +bytes+ long.
  def list_of_bytes(bytes, **options)
    dcf_list_field(values: DcfLargeList.values_of_yaml_bytes(bytes), **options)
  end

  # SQL the block runs; schema reads are left out unless +schema+.
  def sql_of(schema: false, &block)
    statements = []
    callback = ->(*, payload) { statements << payload[:sql] if schema || payload[:name] != 'SCHEMA' }
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &block)
    statements
  end

  describe 'rows' do
    it 'reports values, links, parents and the raw stored bytes of each column' do
      parent = dcf_list_field(values: %w[P1 P2 P3])
      child = dcf_list_field(format: 'depending_list', values: %w[a b c d e], parent: parent)
      child = dcf_set_dependencies(child, value_dependencies: { 'P1' => %w[a b], 'P2' => %w[c], 'P3' => %w[d e] })
      enum = dcf_enum_field(names: %w[X Y Z W])
      stub_limit(nil)
      code, report = run_report

      expect(code).to eq(0)
      row = row_of(report, child)
      expect([row.type, row.format, row.name]).to eq(['IssueCustomField', 'depending_list', child.name])
      expect([row.value_count, row.parents, row.links]).to eq([5, 3, 5])
      expect(row.pv_bytes).to eq(raw(child, 'possible_values').bytesize)
      expect(row.fs_bytes).to eq(raw(child, 'format_store').bytesize)
      expect([row.pv_pct, row.fs_pct]).to eq(['n/a', 'n/a'])
      expect(row.load_ms).to be_a(Float)
      expect(row_of(report, enum).value_count).to eq(4)
      expect(row_of(report, parent).parents).to be_nil
      expect(report.rows.map(&:id)).to eq(report.rows.map(&:id).sort)
    end

    it 'gives the floored percent of the column limit' do
      field = list_of_bytes(959)
      stub_limit(1_000)
      _code, report = run_report

      row = row_of(report, field)
      expect(row.pv_bytes).to eq(959)
      expect(row.pv_pct).to eq(95)
      expect(row.pv_pct).to be_an(Integer)
      expect(row.status).to eq('WARN')
    end

    it 'reports only the guarded formats unless ALL=1' do
      string = IssueCustomField.create!(name: "S-#{SecureRandom.hex(3)}", field_format: 'string', is_for_all: true)
      list = dcf_list_field
      stub_limit(nil)

      expect(run_report.last.rows.map(&:id)).to include(list.id)
      expect(run_report.last.rows.map(&:id)).not_to include(string.id)
      expect(run_report(all: '1').last.rows.map(&:id)).to include(list.id, string.id)
    end
  end

  describe 'status' do
    # Older Redmine versions dump format_store with the HashWithIndifferentAccess tag.
    it 'is ok for a normal field and for a format_store with the HashWithIndifferentAccess tag' do
      parent = dcf_list_field(values: %w[P])
      child = dcf_set_dependencies(dcf_list_field(format: 'depending_list', values: %w[a], parent: parent),
                                   value_dependencies: { 'P' => %w[a] })
      tagged = dcf_list_field(format: 'depending_list', values: %w[a b])
      write_raw(tagged, 'format_store', "--- !ruby/hash:ActiveSupport::HashWithIndifferentAccess\n" \
                                        "value_dependencies:\n  P:\n  - a\n  - b\n")
      stub_limit(65_535)
      report = run_report.last

      expect([row_of(report, child).status, row_of(report, tagged).status]).to eq(%w[ok ok])
      expect([row_of(report, tagged).parents, row_of(report, tagged).links]).to eq([1, 2])
    end

    it 'is n/a without a column limit' do
      field = dcf_list_field
      stub_limit(nil)

      expect(row_of(run_report.last, field).status).to eq('n/a (no column limit)')
    end

    {
      'invalid YAML' => ['possible_values', "--- [unclosed\n", 'CORRUPT'],
      'a nil entry' => ['possible_values', "---\n- a\n- \n", 'CORRUPT'],
      'an unreadable format_store' => ['format_store', "--- !ruby/object:Object {}\n", 'CORRUPT'],
      'a column without its final newline' => ['possible_values', "---\n- a\n- b", 'SUSPECT']
    }.each do |label, (column, value, status)|
      [nil, 65_535].each do |limit|
        it "is #{status} for #{label} (limit #{limit.inspect})" do
          field = dcf_list_field
          write_raw(field, column, value)
          stub_limit(limit)
          code, report = nil
          expect { code, report = run_report }.not_to raise_error

          expect(code).to eq(0)
          expect(row_of(report, field).status).to start_with("#{status}: ")
          expect(row_of(report, field).status).to include(column)
        end
      end
    end

    # A cut inside a quoted value is unreadable and lacks its final newline.
    it 'is CORRUPT before SUSPECT and keeps both reasons' do
      field = dcf_list_field
      write_raw(field, 'possible_values', "---\n- \"a")
      stub_limit(65_535)
      status = row_of(run_report.last, field).status

      expect(status).to start_with('CORRUPT: ')
      expect(status).to include('possible_values cannot be read', 'possible_values does not end with a newline')
    end

    it 'is SUSPECT for a column exactly at the limit' do
      field = list_of_bytes(1_000)
      stub_limit(1_000)

      expect(row_of(run_report.last, field).status).to eq('SUSPECT: possible_values is exactly at the column limit')
    end

    it 'is OVER above the limit and WARN at the threshold' do
      over = list_of_bytes(1_001)
      warn = list_of_bytes(950)
      fine = list_of_bytes(899)
      stub_limit(1_000)
      report = run_report.last

      expect([over, warn, fine].map { |f| row_of(report, f).status }).to eq(%w[OVER WARN ok])
    end

    it 'does not count a NULL or empty column as SUSPECT' do
      null = dcf_enum_field
      empty = dcf_list_field
      write_raw(null, 'possible_values', nil)
      write_raw(empty, 'possible_values', '')
      stub_limit(65_535)
      report = run_report.last

      expect(raw(null, 'possible_values')).to be_nil
      expect([row_of(report, null).status, row_of(report, empty).status]).to eq(%w[ok ok])
    end

    it 'uses WARN_AT as the threshold' do
      field = list_of_bytes(600)
      stub_limit(1_000)

      expect(row_of(run_report.last, field).status).to eq('ok')
      expect(row_of(run_report(warn_at: '50').last, field).status).to eq('WARN')
      expect(row_of(run_report(warn_at: '60').last, field).status).to eq('WARN')
      expect(row_of(run_report(warn_at: '60.5').last, field).status).to eq('ok')
    end
  end

  describe 'FAIL_ABOVE' do
    it 'exits 1 when a field reaches it' do
      list_of_bytes(800)
      stub_limit(1_000)

      expect(run_report(fail_above: '80').first).to eq(1)
      expect(run_report(fail_above: '81').first).to eq(0)
      expect(run_report.first).to eq(0)
    end

    it 'exits 0 without a column limit' do
      list_of_bytes(800)
      stub_limit(nil)

      expect(run_report(fail_above: '0').first).to eq(0)
    end
  end

  describe 'reading' do
    it 'reads raw rows only and never writes' do
      field = dcf_list_field
      write_raw(field, 'possible_values', "---\n- a\n- \n")
      stub_limit(65_535)
      classes = []
      callback = ->(*, payload) { classes << payload[:class_name] }
      statements = nil
      ActiveSupport::Notifications.subscribed(callback, 'instantiation.active_record') do
        statements = sql_of(schema: true) { run_report }
      end

      expect(statements.grep(/\A\s*(INSERT|UPDATE|DELETE|ALTER|CREATE|DROP)\b/i)).to eq([])
      expect(statements.grep(/@@/)).to eq([])
      expect(classes.grep(/CustomField\z/)).to eq([])
      ActiveSupport::Notifications.subscribed(callback, 'instantiation.active_record') { CustomField.find(field.id) }
      expect(classes).to include('CustomField')
    end

    it 'counts enumerations with one grouped query whatever the number of fields' do
      dcf_enum_field
      stub_limit(nil)
      one = dcf_count_queries { run_report }
      4.times { dcf_enum_field }
      five = dcf_count_queries { run_report }
      statements = sql_of { run_report }

      expect(five).to eq(one)
      expect(statements.grep(/COUNT\(/i)).to eq(statements.grep(/GROUP BY/i))
      expect(statements.grep(/COUNT\(/i).size).to eq(1)
    end
  end

  describe 'output' do
    it 'prints a table with the column limits' do
      field = dcf_list_field(name: "Tbl-#{SecureRandom.hex(3)}")
      stub_limit(nil)
      run_report

      expect(out.string).to include("Adapter: #{CustomField.connection.adapter_name}")
      expect(out.string).to include("#{CustomField.table_name}.possible_values: text, limit none")
      expect(out.string.lines.map(&:split)).to include(include('value_count', 'links', 'parents', 'pv_bytes', 'status'))
      expect(out.string).to include(field.name)
    end

    it 'prints CSV with one header row and one row per field' do
      tricky = dcf_list_field(name: %(a, "b" #{SecureRandom.hex(2)}))
      other = dcf_list_field
      stub_limit(nil)
      _code, report = run_report(format: 'csv')
      table = CSV.parse(out.string)

      expect(table.first).to eq(%w[id type format name value_count links parents pv_bytes pv_pct fs_bytes fs_pct
                                   load_ms status])
      expect(table.size).to eq(report.rows.size + 1)
      by_id = table.drop(1).index_by { |cells| cells.first.to_i }
      expect(by_id.fetch(tricky.id)[3]).to eq(tricky.name)
      expect(by_id.fetch(other.id).last).to eq('n/a (no column limit)')
    end

    it 'asks Redmine whether the database is MySQL when mysql: is not given' do
      dcf_list_field
      stub_limit(nil)
      allow(Redmine::Database).to receive(:mysql?).and_return(false)
      statements = sql_of { expect(report_class.new(out: out).run).to eq(0) }

      expect(Redmine::Database).to have_received(:mysql?)
      expect(statements.grep(/@@/)).to eq([])
      expect(out.string).not_to include('Session sql_mode')
    end

    it 'prints the MySQL header with the session strictness, the packet size and both columns' do
      stub_limit(65_535)
      connection = CustomField.connection
      allow(connection).to receive(:select_value).and_call_original
      allow(connection).to receive(:select_value).with('SELECT @@max_allowed_packet').and_return(16_777_216)
      {
        'STRICT_TRANS_TABLES,NO_ENGINE_SUBSTITUTION' => 'strict: yes',
        'STRICT_ALL_TABLES' => 'strict: yes',
        'NO_ENGINE_SUBSTITUTION' => 'strict: NO, oversized values are silently truncated',
        '' => 'strict: NO, oversized values are silently truncated'
      }.each do |mode, text|
        allow(connection).to receive(:select_value).with('SELECT @@SESSION.sql_mode').and_return(mode)
        report_out = StringIO.new
        expect(report_class.new(out: report_out, mysql: true).run).to eq(0)

        expect(report_out.string).to include("Session sql_mode: #{mode.empty? ? '(empty)' : mode} (#{text})")
        expect(report_out.string).to include('max_allowed_packet: 16,777,216 bytes')
        expect(report_out.string).to include("#{CustomField.table_name}.format_store: text, limit 65,535 bytes")
      end
    end
  end

  describe 'options' do
    [{ format: 'xml' }, { warn_at: 'abc' }, { fail_above: '-1' }, { all: 'yes' }].each do |option|
      it "refuses #{option.keys.first.upcase}=#{option.values.first} with exit 1 and no query" do
        code = nil
        statements = sql_of(schema: true) { code = run_report(**option).first }

        expect(code).to eq(1)
        expect(out.string).to include("Invalid #{option.keys.first.upcase}=")
        expect(statements).to eq([])
      end
    end

    it 'reads FORMAT, ALL, WARN_AT and FAIL_ABOVE from the rake environment' do
      list_of_bytes(800)
      string = IssueCustomField.create!(name: "S-#{SecureRandom.hex(3)}", field_format: 'string', is_for_all: true)
      stub_limit(1_000)
      env = { 'FORMAT' => 'csv', 'ALL' => '1', 'WARN_AT' => '70', 'FAIL_ABOVE' => '75' }
      report = report_class.from_env(env, out: out, mysql: false)

      expect(report.run).to eq(1)
      table = CSV.parse(out.string).drop(1)
      expect(table.map(&:last)).to include('WARN')
      expect(table.map { |cells| cells.first.to_i }).to include(string.id)
    end
  end
end
