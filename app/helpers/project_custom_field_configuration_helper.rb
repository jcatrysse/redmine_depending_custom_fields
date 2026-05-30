module ProjectCustomFieldConfigurationHelper
  # Overview rows: supported, project-relevant fields with :projects/:enumerations
  # preloaded so the inline settings tab avoids N+1 (fix #13). Rendered via this
  # helper because ProjectsController#settings does not set this feature's ivars.
  def dcf_relevant_custom_fields(project)
    RedmineDependingCustomFields::FieldRelevance.relevant_fields(project)
  end

  def dcf_dependency_capable?(field)
    RedmineDependingCustomFields::FieldRelevance.dependency_capable?(field)
  end

  # Scope of a field relative to +project+: :global / :shared / :project.
  def dcf_field_scope(field, project)
    return :global if field.is_a?(ProjectCustomField) || field.is_for_all?

    others = field.projects.reject { |p| p.id == project.id }
    others.any? ? :shared : :project
  end

  def dcf_scope_badge(field, project)
    scope = dcf_field_scope(field, project)
    key = { global: :label_scope_global, shared: :label_scope_shared, project: :label_scope_project }[scope]
    css = { global: 'dcf-scope-global', shared: 'dcf-scope-shared', project: 'dcf-scope-project' }[scope]
    content_tag(:span, l(key), class: "dcf-scope-badge #{css}")
  end

  # Project-usage count, reusing a single cached Project.active.count for every
  # is_for_all / project-custom-field row (fix #13 / T-USE-6).
  def dcf_project_usage_count(field)
    if field.is_a?(ProjectCustomField) || field.is_for_all?
      @dcf_active_project_count ||= Project.active.count
    else
      field.projects.size
    end
  end

  def dcf_value_count(field)
    if RedmineDependingCustomFields::FieldRelevance.enum_family?(field)
      field.enumerations.size
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

  # Names of projects sharing the field, filtered to those the viewer can see;
  # the rest summarised as "+N other project(s)" (no name leakage — fix #3.8).
  def dcf_visible_project_names(field, viewer = User.current)
    projects = field.is_for_all? ? Project.active.to_a : field.projects.to_a
    visible = projects.select { |p| p.visible?(viewer) }
    hidden = projects.size - visible.size
    names = visible.map(&:name)
    names << l(:label_n_other_projects, count: hidden) if hidden.positive?
    names
  end

  # Icon helper guarded for Redmine 5.x (no sprite_icon) — falls back to icon-*.
  def dcf_icon(name, label = nil)
    if respond_to?(:sprite_icon)
      sprite_icon(name, label)
    else
      content_tag(:span, '', class: "icon icon-#{name}") + (label ? label.to_s : '')
    end
  end

  # URL + HTTP method to re-submit a pending destructive operation with confirm.
  def dcf_confirm_target(action)
    case action.to_sym
    when :rename_value
      [custom_field_configuration_rename_value_path(@project, @field), :patch]
    when :remove_value
      [custom_field_configuration_remove_value_path(@project, @field), :delete]
    else
      [custom_field_configuration_field_path(@project, @field), :patch]
    end
  end

  def dcf_audit_status_class(status)
    case status
    when 'success' then 'dcf-status-success'
    when 'authorization_failed', 'validation_failed', 'save_failed', 'forbidden', 'error' then 'dcf-status-failed'
    else 'dcf-status-neutral'
    end
  end
end
