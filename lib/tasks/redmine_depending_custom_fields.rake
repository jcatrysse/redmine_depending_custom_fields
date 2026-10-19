# frozen_string_literal: true

# Opt-in storage tools (limits design 7.1 to 7.3). Redmine loads this file on
# every rake run, before the environment exists, so only literals are used
# here; the classes are loaded and called inside the task bodies.
namespace :redmine do
  namespace :depending_custom_fields do
    desc 'Report the stored size of custom field values and dependency mappings against the database ' \
         'column limits (read-only). Options: FORMAT=table|csv, ALL=1 (all formats), WARN_AT=90 (percent), ' \
         'FAIL_ABOVE=<percent> (exit 1 when a field reaches it).'
    task report_sizes: :environment do
      require_relative '../redmine_depending_custom_fields/storage_report'
      status = RedmineDependingCustomFields::StorageReport.from_env(ENV, out: $stdout).run
      exit(status) if status.nonzero?
    end

    desc 'MySQL/MariaDB only: widen custom_fields.possible_values and custom_fields.format_store (a core table). ' \
         'Dry run unless CONFIRM=1. Options: TYPE=mediumtext (default) or longtext, REVERT=1 (back to TEXT, ' \
         'refused while a row holds more than 65,535 bytes; stop Redmine first). Back up the database first and ' \
         'restart Redmine after.'
    task widen_core_columns: :environment do
      require_relative '../redmine_depending_custom_fields/core_column_widener'
      status = RedmineDependingCustomFields::CoreColumnWidener.from_env(ENV, out: $stdout).run
      exit(status) if status.nonzero?
    end
  end
end
