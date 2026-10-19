# frozen_string_literal: true

module RedmineDependingCustomFields
  # Opt-in widening of the two serialized CustomField columns on MySQL/MariaDB
  # behind rake redmine:depending_custom_fields:widen_core_columns (limits
  # design 7.3 to 7.5, UD-26). A dry run unless confirmed. One ALTER keeps the
  # character set, collation, nullability and comment read from
  # information_schema; it never narrows except on REVERT, which is refused
  # while a row holds more than TEXT allows. A refusal runs no SET or ALTER
  # (only the reads that build the plan). Only the rake task calls it (never
  # a migration, init.rb or an install step). Uses select_all, select_value,
  # execute and the three quote methods of the connection only. One object
  # per run.
  class CoreColumnWidener
    # COLUMN_NAME order, as information_schema is read.
    COLUMNS = %w[format_store possible_values].freeze
    TYPES = { 'text' => 65_535, 'mediumtext' => 16_777_215, 'longtext' => 4_294_967_295 }.freeze
    KEYWORDS = { 'text' => 'TEXT', 'mediumtext' => 'MEDIUMTEXT', 'longtext' => 'LONGTEXT' }.freeze
    TARGETS = %w[mediumtext longtext].freeze
    DEFAULT_TYPE = 'mediumtext'
    # Interpolated into the ALTER unquoted, so plain identifiers only (SP-19).
    IDENTIFIER = /\A[A-Za-z0-9_]+\z/.freeze
    FACTS = %w[column_name data_type column_type character_set_name collation_name is_nullable column_default
               column_comment].freeze
    MIN_PACKET = 16 * 1024 * 1024
    PACKET_SQL = 'SELECT @@max_allowed_packet'
    STRICT_MODE_SQL = "SET SESSION sql_mode = CONCAT(@@SESSION.sql_mode, ',STRICT_ALL_TABLES')"
    NOT_MYSQL = 'Not a MySQL/MariaDB database: text columns are not size limited, nothing to do.'
    RESTART = 'Restart Redmine so running processes use the new limit.'
    # Running processes keep the wider limit from their schema cache.
    RESTART_REVERT = 'Start Redmine only now (restart it if it is running): running processes still accept ' \
                     'values up to the old limit, which TEXT cannot hold.'

    Step = Struct.new(:column, :from, :to, :action, :reason, keyword_init: true)

    attr_reader :status, :sql, :steps

    # Options as rake passes them (ENV strings).
    def self.from_env(env, **options)
      new(type: env['TYPE'], revert: env['REVERT'], confirm: env['CONFIRM'], **options)
    end

    def initialize(type: nil, revert: false, confirm: false, out: $stdout, connection: nil, mysql: nil, table: nil)
      @type = type
      @revert = revert
      @confirm = confirm
      @out = out
      @connection = connection
      @mysql = mysql
      @table = table
      @steps = []
    end

    # Exit code: 0 for not_mysql, up_to_date, dry_run and applied; 1 for an
    # invalid option or a refused plan.
    def run
      return finish(:not_mysql, 0, NOT_MYSQL) unless mysql?

      problem = option_problem
      return finish(:invalid_option, 1, problem) if problem

      check_packet
      facts = column_facts
      @steps = COLUMNS.map { |column| plan(column, facts[column]) }
      print_plan
      return finish(:refused, 1, 'Refused: nothing was changed.') if @steps.any? { |step| step.action == :refuse }

      changes = @steps.select { |step| step.action == :modify }
      return finish(:up_to_date, 0, 'Nothing to do: the columns already have the requested size.') if changes.empty?

      @sql = alter_sql(facts, changes)
      @out.puts 'SQL:'
      [STRICT_MODE_SQL, @sql].each { |statement| @out.puts "  #{statement}" }
      return finish(:dry_run, 0, dry_run_message) unless flag?(@confirm)

      apply
      finish(:applied, 0, flag?(@revert) ? RESTART_REVERT : RESTART)
    end

    private

    def connection
      @connection ||= CustomField.connection
    end

    def table
      @table || CustomField.table_name
    end

    def mysql?
      @mysql.nil? ? Redmine::Database.mysql? : @mysql
    end

    def flag?(value)
      [true, '1'].include?(value)
    end

    def flag_valid?(value)
      [nil, true, false, '', '0', '1'].include?(value)
    end

    def target
      return 'text' if flag?(@revert)

      type = @type.to_s.strip.downcase
      type.empty? ? DEFAULT_TYPE : type
    end

    def dry_run_message
      if flag?(@revert)
        return 'Dry run: nothing was changed. Back up the database and stop Redmine (or block writes), ' \
               'then run again with CONFIRM=1 to apply.'
      end

      'Dry run: nothing was changed. Run again with CONFIRM=1 to apply (back up the database first).'
    end

    def option_problem
      { 'CONFIRM' => @confirm, 'REVERT' => @revert }.each do |name, value|
        return "Invalid #{name}=#{value.inspect} (use #{name}=1)." unless flag_valid?(value)
      end
      type = @type.to_s.strip
      return nil if type.empty?
      return 'TYPE cannot be combined with REVERT=1 (REVERT=1 always goes back to TEXT).' if flag?(@revert)
      return nil if TARGETS.include?(type.downcase)

      "Invalid TYPE=#{@type.inspect} (use mediumtext or longtext)."
    end

    def check_packet
      packet = connection.select_value(PACKET_SQL).to_i
      @out.puts "max_allowed_packet: #{delimited(packet)} bytes"
      return if packet >= MIN_PACKET

      @out.puts 'Warning: max_allowed_packet is below 16 MB: values larger than max_allowed_packet cannot be ' \
                'written whatever the column type.'
    end

    # Column name => facts with lower-case keys (MySQL 8 returns the
    # information_schema labels in upper case, MariaDB as written).
    def column_facts
      select = FACTS.map { |name| "#{name.upcase} AS #{name}" }.join(', ')
      names = COLUMNS.map { |column| connection.quote(column) }.join(', ')
      sql = "SELECT #{select} FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() " \
            "AND TABLE_NAME = #{connection.quote(table)} AND COLUMN_NAME IN (#{names}) ORDER BY COLUMN_NAME"
      connection.select_all(sql).to_a.each_with_object({}) do |row, facts|
        fact = row.to_h.transform_keys { |key| key.to_s.downcase }
        facts[fact['column_name'].to_s] = fact
      end
    end

    def plan(column, fact)
      return refuse(column, nil, 'column not found') unless fact

      from = fact['data_type'].to_s.downcase
      return refuse(column, from, "unexpected type #{fact['data_type'].inspect}") unless TYPES.key?(from)

      problem = attribute_problem(fact, from)
      return refuse(column, from, problem) if problem

      size_step(column, from)
    end

    def attribute_problem(fact, from)
      unless fact['column_type'].to_s.strip.casecmp?(from)
        return "column type #{fact['column_type'].inspect} has attributes a MODIFY would drop"
      end

      %w[character_set_name collation_name].each do |key|
        value = fact[key]
        return "unexpected #{key.tr('_', ' ')} #{value.inspect}" unless value.is_a?(String) && value.match?(IDENTIFIER)
      end
      default = fact['column_default']
      return "default value #{default.inspect} would be lost" unless default.nil? || default.to_s.casecmp?('NULL')
      return "unexpected IS_NULLABLE #{fact['is_nullable'].inspect}" unless %w[YES NO].include?(fact['is_nullable'])

      nil
    end

    def size_step(column, from)
      to = target
      return Step.new(column: column, from: from, to: to, action: :skip, reason: "already #{from}") if from == to

      reverting = flag?(@revert)
      if TYPES[from] > TYPES[to] && !reverting
        return Step.new(column: column, from: from, to: to, action: :skip,
                        reason: "already wider (#{from}), never narrowed")
      end
      if reverting
        largest = connection.select_value("SELECT MAX(LENGTH(#{connection.quote_column_name(column)})) " \
                                          "FROM #{connection.quote_table_name(table)}").to_i
        if largest > TYPES['text']
          return refuse(column, from, "#{delimited(largest)} bytes stored in one row, " \
                                      "more than TEXT holds (#{delimited(TYPES['text'])})")
        end
      end
      Step.new(column: column, from: from, to: to, action: :modify)
    end

    def refuse(column, from, reason)
      Step.new(column: column, from: from, to: target, action: :refuse, reason: reason)
    end

    # One statement for every modified column: atomic, one table copy.
    def alter_sql(facts, changes)
      parts = changes.map do |step|
        fact = facts[step.column]
        part = "MODIFY #{connection.quote_column_name(step.column)} #{KEYWORDS.fetch(step.to)} " \
               "CHARACTER SET #{fact['character_set_name']} COLLATE #{fact['collation_name']} " \
               "#{fact['is_nullable'] == 'YES' ? 'NULL' : 'NOT NULL'}"
        comment = fact['column_comment'].to_s
        comment.empty? ? part : "#{part} COMMENT #{connection.quote(comment)}"
      end
      "ALTER TABLE #{connection.quote_table_name(table)} #{parts.join(', ')}"
    end

    # Strict mode first, so an oversized row fails the ALTER instead of being
    # cut (V7). Trailing white space is still cut, with a warning only, hence
    # the REVERT guard and a stopped Redmine.
    def apply
      connection.execute(STRICT_MODE_SQL)
      connection.execute(@sql)
      CustomField.reset_column_information
      @out.puts 'Applied. Columns now:'
      column_facts.each_value do |fact|
        @out.puts "  #{table}.#{fact['column_name']}: #{fact['data_type']}"
      end
    end

    def print_plan
      @out.puts "Plan for #{table} (target #{KEYWORDS.fetch(target, target.inspect)}):"
      @steps.each do |step|
        action = step.reason ? "#{step.action}: #{step.reason}" : step.action.to_s
        @out.puts format('  %-16s %-10s -> %-10s %s', step.column, step.from || '-', step.to, action)
      end
    end

    def finish(status, code, message)
      @status = status
      @out.puts message
      code
    end

    # Plain English CLI output: always a comma, whatever the locale.
    def delimited(number)
      ActiveSupport::NumberHelper.number_to_delimited(number, delimiter: ',')
    end
  end
end
