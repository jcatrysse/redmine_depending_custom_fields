# frozen_string_literal: true

module RedmineDependingCustomFields
  # Size checks of the two serialized CustomField columns against the database
  # column limit (MySQL/MariaDB TEXT: 65,535 bytes; limits design 4.2 to 4.9).
  # PostgreSQL and SQLite report no limit, so nothing is measured there.
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

    Violation = Struct.new(:custom_field_id, :custom_field_name, :column, :attribute, :bytes, :limit,
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
    # Hashes, nothing is dumped).
    def writes_column?(record, column)
      return true if check_column?(record, column)
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
    # called above the limit, so the one query runs on MySQL only.
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

    # The limit is looked up first, so nothing is measured without one.
    def violations(record)
      return [] unless guarded?(record)

      COLUMNS.each_with_object([]) do |(column, attribute), found|
        limit = column_limit(column)
        next if limit.nil? || !writes_column?(record, column)

        bytes = preview_bytes(record, column)
        next if bytes <= limit || writes_back?(record, column, bytes)

        found << Violation.new(custom_field_id: record.id, custom_field_name: record.name, column: column,
                               attribute: attribute, bytes: bytes, limit: limit)
      end
    end

    # Sizes are delimited in the current locale; the details keep the Integers.
    def validate(record)
      violations(record).each do |v|
        record.errors.add(v.attribute, ERROR,
                          size: delimited(v.bytes), limit: delimited(v.limit),
                          bytes: v.bytes, max_bytes: v.limit, column: v.column)
      end
    end

    # The first violation recorded on record.errors (COLUMNS order), or nil.
    def violation_in(record)
      COLUMNS.each do |column, attribute|
        detail = Array(record.errors.details[attribute]).detect { |d| d[:error] == ERROR }
        next unless detail

        return Violation.new(custom_field_id: record.id, custom_field_name: record.name, column: column,
                             attribute: attribute, bytes: detail[:bytes], limit: detail[:max_bytes])
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
