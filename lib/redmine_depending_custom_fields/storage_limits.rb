# frozen_string_literal: true

require_relative 'sanitizer'

module RedmineDependingCustomFields
  # Size checks of the two serialized CustomField columns against the database
  # column limit (MySQL/MariaDB TEXT: 65,535 bytes; limits design 4.2 to 4.9)
  # and, for writes from project settings, the project storage ceiling
  # (record.dcf_storage_ceiling, limits design 4.11). PostgreSQL and SQLite
  # report no column limit, so nothing is measured there without a ceiling.
  # Stateless: module functions only, called on the module (the spec seam).
  module StorageLimits
    MYSQL_TEXT_BYTES = 65_535
    WARN_PERCENT = 90
    # Column => attribute that carries its error, in check order.
    COLUMNS = { 'possible_values' => :possible_values, 'format_store' => :value_dependencies }.freeze
    # UD-25: the core list formats are checked too.
    GUARDED_FORMATS = %w[list enumeration depending_list depending_enumeration].freeze
    MAPPING_KEYS = %w[value_dependencies default_value_dependencies].freeze
    ERROR = :dcf_storage_too_large

    # source: 'column' or 'ceiling', the limit that applied.
    Violation = Struct.new(:custom_field_id, :custom_field_name, :column, :attribute, :bytes, :limit, :source,
                           keyword_init: true)
    Usage = Struct.new(:column, :attribute, :bytes, :limit, :percent, keyword_init: true)

    module_function

    def mysql?
      Redmine::Database.mysql?
    rescue StandardError
      false
    end

    # Byte limit of +column+, nil when the adapter reports none. A text column
    # without a reported limit counts as TEXT on MySQL.
    def column_limit(column, model = CustomField)
      col = model.columns_hash[column.to_s]
      return nil unless col

      limit = col.limit
      limit = MYSQL_TEXT_BYTES if limit.nil? && col.type == :text && mysql?
      limit
    end

    def guarded?(record)
      GUARDED_FORMATS.include?(record.field_format.to_s)
    end

    # New records are always checked, persisted ones only for changed columns.
    def check_column?(record, column)
      record.new_record? || record.will_save_change_to_attribute?(column)
    end

    # check_column?, or a format_store that the before_save of a depending
    # format rewrites (storage_preview differs from the store; compared as
    # Hashes, nothing is dumped). +changed+ takes a check_column? result.
    def writes_column?(record, column, changed = check_column?(record, column))
      return true if changed
      return false unless column.to_s == 'format_store' && record.format.respond_to?(:storage_preview)

      store = record.format_store
      record.format.storage_preview(record, store) !=
        ActiveRecord::Store::IndifferentCoder.as_indifferent_hash(store).to_hash
    end

    # True when a persisted record writes back the bytes the database holds
    # in +column+ (the raw stored value equals the dump of the preview), for
    # example an admin form save, which posts the parent id as a String and
    # so dirties format_store. Such a save is not refused (limits section 14,
    # V5); a save of a row stored in another YAML style is (PC-15). Only
    # called above the effective limit, so its one query runs only for a
    # refusal candidate.
    def writes_back?(record, column, bytes)
      return false unless record.persisted?

      model = record.class
      raw = model.connection.select_value(model.unscoped.where(id: record.id).select(column.to_s).to_sql)
      return false unless raw.is_a?(String) && raw.bytesize == bytes

      raw == model.type_for_attribute(column.to_s).serialize(preview_value(record, column))
    end

    # The value a save writes into +column+: possible_values= cleans the
    # values when they are assigned, the depending formats rewrite
    # format_store before save (storage_preview gives that result).
    def preview_value(record, column)
      return record.read_attribute(column.to_s) unless column.to_s == 'format_store'

      store = record.format_store
      format = record.format
      format.respond_to?(:storage_preview) ? format.storage_preview(record, store) : store
    end

    def serialized_bytesize(model, column, value)
      dumped = model.type_for_attribute(column.to_s).serialize(value)
      dumped.nil? ? 0 : dumped.to_s.bytesize
    end

    def preview_bytes(record, column)
      serialized_bytesize(record.class, column, preview_value(record, column))
    end

    # The project storage ceiling in bytes, or nil (the default: the admin
    # form, the APIs and imports never set it).
    def ceiling(record)
      record.respond_to?(:dcf_storage_ceiling) ? record.dcf_storage_ceiling : nil
    end

    # The stored value of +column+ as a save would dump it, 0 for a new
    # record: one serialize of attribute_in_database, the original value
    # (never the assigned one), so a no-op round trip measures equal.
    def persisted_bytes(record, column)
      return 0 unless record.persisted?

      serialized_bytesize(record.class, column, record.attribute_in_database(column.to_s))
    end

    # The bytes a save of the unchanged stored row writes into +column+:
    # persisted_bytes, or for a depending format_store whose stored
    # mappings a save rewrites (one stored without
    # default_value_dependencies) the larger of that and the dump of the
    # sanitized store, so a write that does not grow the row is never
    # measured as growth (UD-22). The stored value is read once; the
    # sanitized store is dumped only when it differs (compared as Hashes).
    def baseline_bytes(record, column)
      unless column.to_s == 'format_store' && record.persisted? && record.format.respond_to?(:storage_preview)
        return persisted_bytes(record, column)
      end

      stored = record.attribute_in_database('format_store')
      bytes = serialized_bytesize(record.class, column, stored)
      original = ActiveRecord::Store::IndifferentCoder.as_indifferent_hash(stored).to_hash
      sanitized = sanitized_store(original)
      sanitized == original ? bytes : [bytes, serialized_bytesize(record.class, column, sanitized)].max
    end

    # +store+ (a stored format_store Hash) with both mappings sanitized as
    # the before_save of a depending format writes them, a missing one as
    # {}. The parent id stays as stored: a save never makes it longer.
    def sanitized_store(store)
      store.merge('value_dependencies' => Sanitizer.sanitize_dependencies(store['value_dependencies']),
                  'default_value_dependencies' => Sanitizer.sanitize_default_dependencies(store['default_value_dependencies']))
    end

    # The bytes the row holds in +column+, read from the raw value of an
    # unassigned attribute (nothing parsed or dumped), else persisted_bytes.
    def stored_bytes(record, column)
      return 0 unless record.persisted?

      raw = record.read_attribute_before_type_cast(column.to_s)
      return raw.bytesize if raw.is_a?(String) && !record.public_send("#{column}_came_from_user?")

      persisted_bytes(record, column)
    end

    # [limit, source] for a write of +column+ (limits design 4.11). Without a
    # ceiling: the column limit, measuring nothing. With one: the smaller of
    # the column limit and max(ceiling, persisted bytes), so a field made
    # larger than the ceiling may shrink or keep its size but not grow; the
    # column wins a tie. A save measures the stored row (baseline_bytes)
    # only when its new +bytes+ exceed the ceiling; without +bytes+ (the
    # editor) the stored size is the raw column value when the attribute was
    # not assigned.
    def effective_limit(record, column, bytes = nil)
      column_max = column_limit(column)
      allowed = ceiling(record)
      return [column_max, 'column'] if allowed.nil? || (column_max && column_max <= allowed)

      if bytes.nil?
        allowed = [allowed, stored_bytes(record, column)].max
      elsif bytes > allowed
        allowed = [allowed, baseline_bytes(record, column)].max
      end
      column_max && column_max <= allowed ? [column_max, 'column'] : [allowed, 'ceiling']
    end

    # A limit (column or ceiling) is looked up first, so nothing is measured
    # without one. The ceiling applies only to a column the write itself
    # changes (UD-22): a format_store that only the before_save of a
    # depending format rewrites keeps the column limit alone.
    def violations(record)
      return [] unless guarded?(record)

      ceiling_set = !ceiling(record).nil?
      COLUMNS.each_with_object([]) do |(column, attribute), found|
        next if column_limit(column).nil? && !ceiling_set

        changed = check_column?(record, column)
        ceiled = ceiling_set && changed
        next if column_limit(column).nil? && !ceiled
        next unless writes_column?(record, column, changed)

        bytes = preview_bytes(record, column)
        limit, source = ceiled ? effective_limit(record, column, bytes) : [column_limit(column), 'column']
        next if bytes <= limit || writes_back?(record, column, bytes)

        found << Violation.new(custom_field_id: record.id, custom_field_name: record.name, column: column,
                               attribute: attribute, bytes: bytes, limit: limit, source: source)
      end
    end

    # Sizes are delimited in the current locale; the details keep the Integers.
    def validate(record)
      violations(record).each do |v|
        record.errors.add(v.attribute, ERROR,
                          size: delimited(v.bytes), limit: delimited(v.limit),
                          bytes: v.bytes, max_bytes: v.limit, column: v.column, source: v.source)
      end
    end

    # The first violation recorded on record.errors (COLUMNS order), or nil.
    def violation_in(record)
      COLUMNS.each do |column, attribute|
        detail = Array(record.errors.details[attribute]).detect { |d| d[:error] == ERROR }
        next unless detail

        return Violation.new(custom_field_id: record.id, custom_field_name: record.name, column: column,
                             attribute: attribute, bytes: detail[:bytes], limit: detail[:max_bytes],
                             source: detail[:source])
      end
      nil
    end

    # Stored columns at or above WARN_PERCENT of their limit, MySQL only
    # (UD-28). One query; MySQL LENGTH counts bytes. The percent is floored.
    def usage(record)
      return [] unless mysql? && record.persisted? && guarded?(record)

      limits = COLUMNS.keys.map { |column| column_limit(column) }
      return [] if limits.none? { |limit| limit.to_i.positive? }

      stored = CustomField.where(id: record.id)
                          .pick(Arel.sql('LENGTH(possible_values)'), Arel.sql('LENGTH(format_store)'))
      return [] unless stored

      rows = []
      COLUMNS.each_with_index do |(column, attribute), index|
        limit = limits[index]
        bytes = stored[index].to_i
        next unless limit.to_i.positive? && bytes * 100 >= limit * WARN_PERCENT

        rows << Usage.new(column: column, attribute: attribute, bytes: bytes, limit: limit,
                          percent: bytes * 100 / limit)
      end
      rows
    end

    # Bytes of the in-memory format_store without the two mappings.
    def base_bytes(record)
      store = ActiveRecord::Store::IndifferentCoder.as_indifferent_hash(record.format_store).to_hash
      serialized_bytesize(CustomField, 'format_store', store.except(*MAPPING_KEYS))
    end

    def delimited(number)
      ActiveSupport::NumberHelper.number_to_delimited(number)
    end
  end
end
