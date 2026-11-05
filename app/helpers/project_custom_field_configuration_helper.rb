module ProjectCustomFieldConfigurationHelper
  # Overview rows: supported, project-relevant fields. Rendered via this
  # helper because ProjectsController#settings does not set this feature's
  # ivars. Their counts come from dcf_overview_counts (three grouped
  # queries, full review of 2026-11-05: no rows preloaded).
  def dcf_relevant_custom_fields(project)
    RedmineDependingCustomFields::FieldRelevance.relevant_fields(project)
  end

  def dcf_overview_counts(fields, project)
    RedmineDependingCustomFields::FieldRelevance.overview_counts(fields, project)
  end

  def dcf_dependency_capable?(field)
    RedmineDependingCustomFields::FieldRelevance.dependency_capable?(field)
  end

  # Scope of a field relative to +project+: :global / :shared / :project
  # (the one rule, FieldRelevance.scope); +counts+ from dcf_overview_counts.
  def dcf_field_scope(field, project, counts = nil)
    RedmineDependingCustomFields::FieldRelevance.scope(field, project, shared_ids: counts&.shared)
  end

  def dcf_scope_badge(field, project, counts = nil)
    scope = dcf_field_scope(field, project, counts)
    key = { global: :label_scope_global, shared: :label_scope_shared, project: :label_scope_project }[scope]
    css = { global: 'dcf-scope-global', shared: 'dcf-scope-shared', project: 'dcf-scope-project' }[scope]
    content_tag(:span, l(key), class: "dcf-scope-badge #{css}")
  end

  # Project-usage count, reusing a single cached Project.active.count for every
  # is_for_all / project-custom-field row (fix #13 / T-USE-6).
  def dcf_project_usage_count(field, counts = nil)
    if field.is_a?(ProjectCustomField) || field.is_for_all?
      @dcf_active_project_count ||= Project.active.count
    else
      counts ? counts.project_counts.fetch(field.id, 0) : field.projects.count
    end
  end

  def dcf_value_count(field, counts = nil)
    if RedmineDependingCustomFields::FieldRelevance.enum_family?(field)
      counts ? counts.value_counts.fetch(field.id, 0) : field.enumerations.count
    else
      Array(field.possible_values).size
    end
  end

  # Prefer the registered field-format label (works for every format and avoids
  # version-specific core label-key drift — fix #14).
  def dcf_format_label(field)
    label = field.format.respond_to?(:label) ? field.format.label : nil
    return field.field_format if label.blank?

    # Core list/enumeration expose a String i18n key; the plugin formats expose a
    # Symbol. l() resolves both; default keeps any already-human label.
    l(label, default: label.to_s)
  end

  # A core-like flash box for a page banner (UX-10): core's notice_icon on
  # 6.0 and later (it takes the type as a String), the class background
  # icon on 5.1. The text is escaped once; no id, core's own boxes carry
  # flash_<type>.
  def dcf_flash_box(type, text)
    icon = respond_to?(:notice_icon) ? notice_icon(type.to_s) : ''.html_safe
    content_tag(:div, icon + text, class: "flash #{type}")
  end

  # Drag handle for the values table, markup-identical to core's
  # +reorder_handle+ / custom_field_enumerations#index so the existing Redmine
  # icon and cursor styling applies on 5.1 through 7.0. Empty content on 5.x
  # (the .icon-sort-handle background image supplies the glyph there).
  def dcf_sort_handle
    icon = respond_to?(:sprite_icon) ? sprite_icon('reorder', '') : ''.html_safe
    content_tag(:span, icon,
                class: 'icon-only icon-sort-handle sort-handle dcf-sort-handle',
                title: l(:button_sort))
  end

  # URL + HTTP method to re-submit a pending destructive operation with confirm.
  def dcf_confirm_target(action)
    case action.to_sym
    when :rename_value
      [custom_field_configuration_rename_value_path(@project, @field), :patch]
    when :remove_value
      [custom_field_configuration_remove_value_path(@project, @field), :delete]
    when :sort_values
      [custom_field_configuration_sort_values_path(@project, @field), :patch]
    else
      [custom_field_configuration_field_path(@project, @field), :patch]
    end
  end

  # Storage usage line of the values and dependency pages at 90 percent of a
  # column limit, MySQL only (UD-28); no README line here. A hint never
  # breaks the page.
  def dcf_storage_usage_hint(field)
    usage = RedmineDependingCustomFields::StorageLimits.usage(field)
    return '' if usage.empty?

    render(partial: 'custom_fields/dcf_storage_usage', locals: { usage: usage, admin: false })
  rescue StandardError
    ''
  end

  def dcf_audit_status_class(status)
    case status
    when 'success' then 'dcf-status-success'
    when 'authorization_failed', 'validation_failed', 'save_failed', 'forbidden', 'error' then 'dcf-status-failed'
    else 'dcf-status-neutral'
    end
  end
end
