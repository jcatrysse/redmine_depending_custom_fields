# frozen_string_literal: true

module RedmineDependingCustomFields
  # The one presenter of the shared dependency editor partial
  # (depending_custom_fields/_dependency_editor; editor design 4.1, 5.2 and
  # 5.3, WP-24): the data-dcf-editor-* attributes of the editor root, the
  # name and id of its hidden input, the parent and the required warning, for
  # the admin custom field form (for_admin) and the project dependency page
  # (for_project). wire_values is the only producer of the compact value wire
  # shape (values endpoint, both modes, test/js/fixtures/value_options.json).
  # Core sets include_all_helpers = false, hence a plain module that takes the
  # view.
  #
  # module_function and stateless: every call builds a new Editor, and reads
  # the stored digest at most once.
  module DependencyEditorConfig
    # JS key => locale key, sent as data-dcf-editor-i18n. Its own map, never
    # merged with ClientConfig::I18N; WP-25 and WP-26 extend it together with
    # their locale entries (gap 8).
    I18N = { 'storageEstimate' => :text_dcf_storage_estimate }.freeze
    # Rack request body limits minus margins (multipart buffer 16 MiB,
    # urlencoded body 4 MiB; editor design 0.3, P6).
    MAX_FORM_BYTES = { 'multipart' => 16_252_928, 'urlencoded' => 4_128_768 }.freeze
    ADMIN_INPUT = %w[custom_field[dependencies_json] custom_field_dependencies_json].freeze
    PROJECT_INPUT = %w[dependencies_json dcf_dependencies_json].freeze

    # data_attributes is the Hash for content_tag data: (Rails JSON-encodes
    # Hash and Array values, escapes every value once and omits nil).
    Editor = Struct.new(:data_attributes, :input_name, :input_id, :parent, :required_warning,
                        :required_warning_html, keyword_init: true) do
      def required_warning?
        required_warning == true
      end
    end

    module_function

    # [key, label, active] tuples (DependencyRules.value_options) as Hashes
    # with 'key', plus 'label' when it differs from the key, plus 'active'
    # (the literal false) only for an inactive value.
    def wire_values(options)
      options.map do |key, label, active|
        entry = { 'key' => key.to_s }
        entry['label'] = label.to_s unless label.to_s == key.to_s
        entry['active'] = false if active == false
        entry
      end
    end

    # The admin form: the in-memory record (a failed save shows the mapping
    # the transport applied, dirty against the stored digest); after a stale
    # refusal the stored row and the refused version (conflict-mapping). The
    # parent is the raw lookup DependencyRules.parent_of (nil for a blank,
    # dangling, own, other type or other family pointer).
    def for_admin(field, view)
      parent = DependencyRules.parent_of(field)
      list = DependencyRules.kind(field) == 'list'
      parent_options = parent ? DependencyRules.value_options(parent) : []
      stored = DependencyPayload.stored_digest(field)
      conflict = field.dcf_dependencies_conflict
      mapping = conflict ? stored_mapping(field) : current_mapping(field)
      dirty = conflict.nil? &&
              DependencyPayload.digest(field.value_dependencies, field.default_value_dependencies) != stored

      data = identity(field, 'admin', parent, parent_options)
      data[:dcf_editor_child_values] = wire_values(DependencyRules.value_options(field)) unless list
      data[:dcf_editor_mapping] = mapping
      data[:dcf_editor_dirty] = '1' if dirty
      data[:dcf_editor_conflict_mapping] = conflict if conflict
      data[:dcf_editor_base] = stored if field.persisted?
      data.update(flags(field))
      data[:dcf_editor_values_url] = view.dcf_dependency_editor_values_path
      data[:dcf_editor_parent_source] = '#custom_field_parent_custom_field_id'
      data[:dcf_editor_values_source] = '#custom_field_possible_values' if list
      data[:dcf_editor_multiple_source] = '#custom_field_multiple'
      data[:dcf_editor_required_source] = '#custom_field_is_required'
      data[:dcf_editor_format_source] = '#custom_field_field_format'
      data[:dcf_editor_default_value_row] = '[data-dcf-default-value-row]'
      data[:dcf_editor_allow_add_values] = '1' if list
      values_limit = list ? StorageLimits.column_limit('possible_values') : nil
      data.update(shared(field, StorageLimits.column_limit('format_store'), values_limit))
      editor(data, ADMIN_INPUT, field, parent, parent_options, mapping, view)
    end

    # The project page (WP-27): +parent+ is the caller's decision (never
    # looked up here); +posted+ (a 422 re-render) and +conflict+ (a 409) are
    # ok DependencyPayload::Result objects or nil, anything else is ignored.
    # A conflict shows the stored mapping and wins over +posted+.
    def for_project(field:, parent:, view:, posted: nil, conflict: nil)
      conflict = nil unless ok_result?(conflict)
      posted = nil if conflict || !ok_result?(posted)
      parent_options = parent ? DependencyRules.value_options(parent) : []
      mapping = posted ? result_mapping(posted) : current_mapping(field)

      data = identity(field, 'project', parent, parent_options)
      data[:dcf_editor_child_values] = wire_values(DependencyRules.value_options(field))
      data[:dcf_editor_mapping] = mapping
      data[:dcf_editor_dirty] = '1' if posted
      if conflict
        data[:dcf_editor_conflict_mapping] = result_mapping(conflict).merge('source' => conflict.source,
                                                                            'import' => conflict.import)
      end
      data.update(flags(field))
      data[:dcf_editor_always_submit] = '1'
      data.update(shared(field, project_storage_limit(field), nil))
      editor(data, PROJECT_INPUT, field, parent, parent_options, mapping, view)
    end

    def identity(field, mode, parent, parent_options)
      data = { dcf_editor: '1', dcf_editor_mode: mode, dcf_editor_kind: DependencyRules.kind(field) }
      data[:dcf_editor_field_id] = field.id.to_s if field.persisted?
      data[:dcf_editor_field_type] = field.type.to_s
      data[:dcf_editor_field_name] = field.name.to_s
      if parent
        data[:dcf_editor_parent_id] = parent.id.to_s
        data[:dcf_editor_parent_name] = parent.name.to_s
      end
      data[:dcf_editor_parent_values] = wire_values(parent_options)
      data
    end

    def flags(field)
      { dcf_editor_multiple: field.multiple? ? '1' : '0', dcf_editor_required: field.is_required? ? '1' : '0' }
    end

    # Both modes: payload and form limits, CSV defaults, the storage
    # attributes (limits design 4.10: only with a column limit), the unsaved
    # warning preference and the texts of I18N in the current locale.
    def shared(field, limit, values_limit)
      data = { dcf_editor_max_payload_bytes: DependencyPayload::MAX_BYTES.to_s,
               dcf_editor_max_form_bytes: MAX_FORM_BYTES,
               dcf_editor_csv_separator: ::I18n.t(:general_csv_separator),
               dcf_editor_csv_encoding: ::I18n.t(:general_csv_encoding) }
      if limit
        data[:dcf_editor_storage_limit] = limit.to_s
        data[:dcf_editor_storage_base] = StorageLimits.base_bytes(field).to_s
      end
      data[:dcf_editor_values_limit] = values_limit.to_s if values_limit
      data[:dcf_editor_storage_warn] = StorageLimits::WARN_PERCENT.to_s if limit || values_limit
      data[:dcf_editor_warn_unsaved] = User.current.pref.warn_on_leaving_unsaved == '0' ? '0' : '1'
      data[:dcf_editor_i18n] = I18N.transform_values { |key| ::I18n.t(key) }
      data
    end

    def editor(data, input, field, parent, parent_options, mapping, view)
      Editor.new(data_attributes: data, input_name: input[0], input_id: input[1], parent: parent,
                 required_warning: required_warning?(field, parent, parent_options, mapping),
                 required_warning_html: required_warning_html(view))
    end

    # The rule of the current format partials: a required field whose
    # effective parent (not in or below a stored cycle) has an active value
    # without links in the rendered mapping.
    def required_warning?(field, parent, parent_options, mapping)
      return false unless field.is_required? && parent
      return false unless DependencyRules.effective_parent_id(field, { parent.id => parent }) == parent.id

      links = mapping['value_dependencies']
      parent_options.any? { |key, _label, active| active && Array(links[key]).empty? }
    end

    # Always rendered (the partial hides it), so the editor can toggle it.
    def required_warning_html(view)
      text = ::I18n.t(:warning_required_child_no_options)
      view.content_tag(:span, view.respond_to?(:sprite_icon) ? view.sprite_icon('warning', text) : text,
                       class: 'icon icon-warning')
    end

    # The mapping of the in-memory record, sanitized, not pruned.
    def current_mapping(field)
      { 'value_dependencies' => DependencyRules.mapping(field),
        'default_value_dependencies' => DependencyRules.defaults(field) }
    end

    # The mapping of the stored row (as DependencyPayload.stored_digest reads it).
    def stored_mapping(field)
      store = field.attribute_in_database('format_store')
      store = {} unless store.is_a?(Hash)
      { 'value_dependencies' => Sanitizer.sanitize_dependencies(store['value_dependencies']),
        'default_value_dependencies' => Sanitizer.sanitize_default_dependencies(store['default_value_dependencies']) }
    end

    def result_mapping(result)
      { 'value_dependencies' => Sanitizer.sanitize_dependencies(result.value_dependencies),
        'default_value_dependencies' => Sanitizer.sanitize_default_dependencies(result.default_value_dependencies) }
    end

    def ok_result?(result)
      result.is_a?(DependencyPayload::Result) && result.ok?
    end

    # The project storage limit; WP-31 makes it
    # ProjectStoragePolicy.format_store_limit(field).
    def project_storage_limit(_field)
      StorageLimits.column_limit('format_store')
    end

    private_class_method :identity, :flags, :shared, :editor, :required_warning?, :required_warning_html,
                         :current_mapping, :stored_mapping, :result_mapping, :ok_result?, :project_storage_limit
  end
end
