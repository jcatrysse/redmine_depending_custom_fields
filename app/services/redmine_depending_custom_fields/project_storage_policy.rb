# frozen_string_literal: true

module RedmineDependingCustomFields
  # The project storage ceiling (SP-03, UD-22, project design 2.4): the
  # plugin setting project_storage_ceiling_kib limits how far a write from a
  # project's settings may grow a custom field (StorageLimits.effective_limit).
  # The administration, the APIs and imports never set it. Stateless: module
  # functions only, called on the module (the spec seam); the setting is read
  # on every call.
  module ProjectStoragePolicy
    DEFAULT_CEILING_KIB = 2_048
    MIN_CEILING_KIB = 64
    # 1 GiB, above the largest PostgreSQL or SQLite text value, so the
    # editor's data-dcf-editor-storage-limit keeps at most 16 digits.
    MAX_CEILING_KIB = 1_048_576
    # New or renamed list values from project services (characters).
    LIST_VALUE_MAX_CHARS = 255
    SETTING = 'project_storage_ceiling_kib'

    module_function

    # Bytes. Only a plain non-negative integer counts (anything else, a
    # missing key included, gives the default); it is kept between the
    # minimum and the maximum.
    def ceiling_bytes
      settings = Setting.plugin_redmine_depending_custom_fields
      raw = settings.is_a?(Hash) ? settings[SETTING] : nil
      text = raw.is_a?(String) || raw.is_a?(Integer) ? raw.to_s.strip : ''
      kib = text.match?(/\A[0-9]+\z/) ? text.to_i : DEFAULT_CEILING_KIB
      kib.clamp(MIN_CEILING_KIB, MAX_CEILING_KIB) * 1024
    rescue StandardError
      DEFAULT_CEILING_KIB * 1024
    end

    # The effective format_store limit of a project write, for the editor's
    # client estimate (data-dcf-editor-storage-limit). The accessor is
    # restored afterwards.
    def format_store_limit(field)
      previous = field.dcf_storage_ceiling
      field.dcf_storage_ceiling = ceiling_bytes
      StorageLimits.effective_limit(field, 'format_store').first
    ensure
      field.dcf_storage_ceiling = previous
    end
  end
end
