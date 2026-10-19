# frozen_string_literal: true

require 'csv'

module RedmineDependingCustomFields
  # Read-only size report of the two serialized CustomField columns behind
  # rake redmine:depending_custom_fields:report_sizes (limits design 7.2).
  # Rows are read raw, no CustomField is instantiated, so a corrupt row
  # cannot raise; nothing is written. Limits come from
  # StorageLimits.column_limit. One object per run.
  class StorageReport
    COLUMNS = %w[possible_values format_store].freeze
    PREFIX = { 'possible_values' => 'pv', 'format_store' => 'fs' }.freeze
    HEADERS = %w[id type format name value_count links parents pv_bytes pv_pct fs_bytes fs_pct load_ms status].freeze
    FORMATS = %w[table csv].freeze
    NO_LIMIT = 'n/a (no column limit)'
    NUMBER = /\A\d+(?:\.\d+)?\z/.freeze
    SQL_MODE_SQL = 'SELECT @@SESSION.sql_mode'
    PACKET_SQL = 'SELECT @@max_allowed_packet'
    NAME_WIDTH = 40

    Row = Struct.new(*HEADERS.map(&:to_sym), keyword_init: true)

    attr_reader :rows

    # Options as rake passes them (ENV strings).
    def self.from_env(env, **options)
      new(format: env['FORMAT'], all: env['ALL'], warn_at: env['WARN_AT'], fail_above: env['FAIL_ABOVE'], **options)
    end

    def initialize(format: nil, all: false, warn_at: nil, fail_above: nil, out: $stdout, connection: nil, mysql: nil)
      @format = format.to_s.strip.downcase
      @all = all
      @warn_at = warn_at
      @fail_above = fail_above
      @out = out
      @connection = connection
      @mysql = mysql
      @rows = []
    end

    # Prints the report; 1 when FAIL_ABOVE is reached or an option is
    # invalid, otherwise 0.
    def run
      problems = option_problems
      if problems.any?
        problems.each { |problem| @out.puts problem }
        return 1
      end

      @limits = COLUMNS.to_h { |column| [column, StorageLimits.column_limit(column)] }
      @bytes = {}
      @rows = read_rows
      failing = @rows.select { |row| reached?(row, fail_above) }
      csv? ? @out.puts(to_csv) : print_table(failing)
      failing.any? ? 1 : 0
    end

    private

    def connection
      @connection ||= CustomField.connection
    end

    def mysql?
      @mysql.nil? ? Redmine::Database.mysql? : @mysql
    end

    def csv?
      @format == 'csv'
    end

    def all?
      [true, '1'].include?(@all)
    end

    def warn_at
      percent(@warn_at) || StorageLimits::WARN_PERCENT
    end

    def fail_above
      percent(@fail_above)
    end

    # A non-negative percent as a Rational, nil when blank.
    def percent(value)
      return nil if value.nil? || value.to_s.strip.empty?

      value.is_a?(Numeric) ? Rational(value) : Rational(value.to_s.strip)
    end

    def option_problems
      problems = []
      problems << "Invalid FORMAT=#{@format.inspect} (use table or csv)." unless @format.empty? || FORMATS.include?(@format)
      problems << "Invalid ALL=#{@all.inspect} (use ALL=1)." unless [nil, true, false, '', '0', '1'].include?(@all)
      { 'WARN_AT' => @warn_at, 'FAIL_ABOVE' => @fail_above }.each do |name, value|
        next if value.nil? || value.to_s.strip.empty?
        next if value.is_a?(Numeric) ? value >= 0 : value.to_s.strip.match?(NUMBER)

        problems << "Invalid #{name}=#{value.inspect} (use a percent such as 90)."
      end
      problems
    end

    def read_rows
      scope = CustomField.unscoped.select(:id, :type, :name, :field_format, :possible_values, :format_store).order(:id)
      scope = scope.where(field_format: StorageLimits::GUARDED_FORMATS) unless all?
      raw_rows = connection.select_all(scope.to_sql).to_a
      enumerations = CustomFieldEnumeration.group(:custom_field_id).count
      raw_rows.map { |raw| build_row(raw, enumerations) }
    end

    def build_row(raw, enumerations)
      id = raw['id'].to_i
      values = COLUMNS.to_h { |column| [column, raw[column]] }
      @bytes[id] = values.transform_values { |value| value.to_s.bytesize }
      corrupt = []
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      loaded = values.to_h { |column, value| [column, deserialize(column, value, corrupt)] }
      load_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(1)
      pv = loaded['possible_values']
      corrupt << 'possible_values has a nil entry' if pv.is_a?(Array) && pv.any?(&:nil?)
      mapping = loaded['format_store'].is_a?(Hash) ? loaded['format_store']['value_dependencies'] : nil
      row = Row.new(id: id, type: raw['type'], format: raw['field_format'], name: raw['name'],
                    value_count: value_count(raw['field_format'], pv, enumerations[id]),
                    parents: mapping.is_a?(Hash) ? mapping.size : nil,
                    links: mapping.is_a?(Hash) ? mapping.values.sum { |list| Array(list).size } : nil,
                    load_ms: load_ms)
      COLUMNS.each do |column|
        row["#{PREFIX[column]}_bytes"] = @bytes[id][column]
        row["#{PREFIX[column]}_pct"] = @limits[column] ? @bytes[id][column] * 100 / @limits[column] : 'n/a'
      end
      row.status = status(id, corrupt, suspicions(values))
      row
    end

    # The model's own attribute types (permitted classes, IndifferentCoder).
    def deserialize(column, value, corrupt)
      return nil if value.nil?

      CustomField.type_for_attribute(column).deserialize(value)
    rescue StandardError => e
      corrupt << "#{column} cannot be read (#{e.class})"
      nil
    end

    def value_count(format, values, enumerations)
      return enumerations.to_i if format.to_s.end_with?('enumeration')

      values.is_a?(Array) ? values.size : nil
    end

    # Psych always ends a dump with a newline; a missing one, or a value at
    # exactly the limit, points to a cut by a non-strict server.
    def suspicions(values)
      values.each_with_object([]) do |(column, value), found|
        next if value.to_s.empty?

        found << "#{column} does not end with a newline" unless value.end_with?("\n")
        found << "#{column} is exactly at the column limit" if @limits[column] && value.bytesize == @limits[column]
      end
    end

    def status(id, corrupt, suspect)
      return "CORRUPT: #{(corrupt + suspect).join('; ')}" if corrupt.any?
      return "SUSPECT: #{suspect.join('; ')}" if suspect.any?
      return NO_LIMIT if @limits.values.none?
      return 'OVER' if COLUMNS.any? { |column| @limits[column] && @bytes[id][column] > @limits[column] }
      return 'WARN' if COLUMNS.any? { |column| at_or_above?(@bytes[id][column], @limits[column], warn_at) }

      'ok'
    end

    def at_or_above?(bytes, limit, threshold)
      limit && threshold && bytes * 100 >= limit * threshold
    end

    def reached?(row, threshold)
      COLUMNS.any? { |column| at_or_above?(@bytes[row.id][column], @limits[column], threshold) }
    end

    def to_csv
      CSV.generate do |csv|
        csv << HEADERS
        @rows.each { |row| csv << HEADERS.map { |header| row[header] } }
      end
    end

    def print_table(failing)
      header_lines.each { |line| @out.puts line }
      @out.puts
      cells = [HEADERS] + @rows.map { |row| HEADERS.map { |header| cell(row, header) } }
      widths = HEADERS.each_index.map { |index| cells.map { |line| line[index].size }.max }
      cells.each { |line| @out.puts table_line(line, widths) }
      @out.puts
      @out.puts summary
      notes(failing).each { |line| @out.puts line }
    end

    def cell(row, header)
      value = row[header].to_s
      header == 'name' && value.size > NAME_WIDTH ? "#{value[0, NAME_WIDTH - 3]}..." : value
    end

    # Text columns left aligned, numbers right aligned; status unpadded.
    def table_line(line, widths)
      line.each_with_index.map do |value, index|
        next value if index == line.size - 1

        index.between?(1, 3) ? value.ljust(widths[index]) : value.rjust(widths[index])
      end.join('  ')
    end

    def header_lines
      lines = ["Adapter: #{connection.adapter_name}"]
      if mysql?
        mode = connection.select_value(SQL_MODE_SQL).to_s
        lines << "Session sql_mode: #{mode.empty? ? '(empty)' : mode} (#{strict?(mode) ? 'strict: yes' : 'strict: NO, oversized values are silently truncated'})"
        lines << "max_allowed_packet: #{delimited(connection.select_value(PACKET_SQL).to_i)} bytes"
      end
      COLUMNS.each do |column|
        limit = @limits[column]
        type = CustomField.columns_hash[column]&.sql_type || 'missing'
        lines << "#{CustomField.table_name}.#{column}: #{type}, limit #{limit ? "#{delimited(limit)} bytes" : 'none'}"
      end
      lines
    end

    def strict?(mode)
      tokens = mode.split(',').map { |token| token.strip.upcase }
      tokens.include?('STRICT_TRANS_TABLES') || tokens.include?('STRICT_ALL_TABLES')
    end

    def summary
      counts = @rows.group_by { |row| row.status.split(':').first }.map { |status, list| "#{status}: #{list.size}" }
      "Fields: #{@rows.size}#{counts.any? ? " (#{counts.join(', ')})" : ''}"
    end

    def notes(failing)
      lines = []
      if @rows.any? { |row| row.status.start_with?('CORRUPT', 'SUSPECT') }
        lines << 'CORRUPT and SUSPECT fields were probably truncated in the past: restore their values from a backup.'
      end
      threshold = fail_above
      return lines unless threshold

      lines << if @limits.values.none?
                 "FAIL_ABOVE=#{@fail_above}: no column limit, nothing to compare."
               elsif failing.any?
                 "FAIL_ABOVE=#{@fail_above} reached by field #{failing.map(&:id).join(', ')}."
               else
                 "FAIL_ABOVE=#{@fail_above}: no field reaches it."
               end
      lines
    end

    # Plain English CLI output: always a comma, whatever the locale.
    def delimited(number)
      ActiveSupport::NumberHelper.number_to_delimited(number, delimiter: ',')
    end
  end
end
