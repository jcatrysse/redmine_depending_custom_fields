module RedmineDependingCustomFields
  # Single source of truth for which custom fields a project may configure, the
  # supported-format set, the standard-format kill-switch read rule, and the
  # parent/child relationship lookup used by the cascade.
  #
  # See docs/specs/project_custom_field_configuration_feasibility.md and
  # docs/specs/project_custom_field_configuration_operations_spec.md.
  module FieldRelevance
    SUPPORTED_VALUE_FORMATS      = %w[list enumeration depending_list depending_enumeration].freeze
    SUPPORTED_DEPENDENCY_FORMATS = %w[depending_list depending_enumeration].freeze
    STANDARD_FORMATS             = %w[list enumeration].freeze
    LIST_FAMILY                  = %w[list depending_list].freeze
    ENUM_FAMILY                  = %w[enumeration depending_enumeration].freeze

    module_function

    # Exact, version-safe read of the admin kill-switch. Plugin settings are
    # stored as strings ('0'/'1'); a missing key means enabled (default true).
    def standard_enabled?
      raw = Setting.plugin_redmine_depending_custom_fields['manage_standard_custom_fields']
      raw.nil? ? true : ActiveModel::Type::Boolean.new.cast(raw)
    end

    # A format is supported when it is in the value-format set; standard
    # list/enumeration additionally require the kill-switch to be enabled.
    def supported_format?(field)
      fmt = field.field_format
      return false unless SUPPORTED_VALUE_FORMATS.include?(fmt)
      return standard_enabled? if STANDARD_FORMATS.include?(fmt)

      true
    end

    def dependency_capable?(field)
      SUPPORTED_DEPENDENCY_FORMATS.include?(field.field_format) &&
        field.parent_custom_field_id.present?
    end

    def list_family?(field)
      LIST_FAMILY.include?(field.field_format)
    end

    def enum_family?(field)
      ENUM_FAMILY.include?(field.field_format)
    end

    def depending_format?(field)
      SUPPORTED_DEPENDENCY_FORMATS.include?(field.field_format)
    end

    # Type + project-scope membership, ignoring format. Used by the controller
    # to distinguish 404 (not in project) from 422 (unsupported format).
    def in_project?(field, project)
      return false unless field.is_a?(IssueCustomField) || field.is_a?(ProjectCustomField)
      return true if field.is_a?(ProjectCustomField) # not per-project scoped: always relevant

      project.all_issue_custom_fields.to_a.any? { |f| f.id == field.id }
    end

    # Is +field+ relevant to +project+ for this feature? (Feasibility §2.3)
    def relevant?(field, project)
      in_project?(field, project) && supported_format?(field)
    end

    # All supported, project-relevant fields, with :projects and :enumerations
    # preloaded so the overview avoids N+1 (independent-review fix #13).
    def relevant_fields(project)
      issue_ids   = project.all_issue_custom_fields.map(&:id)
      project_ids = ProjectCustomField.pluck(:id)
      ids = (issue_ids + project_ids).uniq
      return [] if ids.empty?

      CustomField.where(id: ids)
                 .where(field_format: SUPPORTED_VALUE_FORMATS)
                 .includes(:projects, :enumerations)
                 .select { |f| supported_format?(f) }
                 .sort_by { |f| [f.position || 0, f.id] }
    end

    # Depending child fields that name +field+ as their parent. Applies to
    # every supported format, since standard lists are commonly used as parents.
    def children_of(field)
      CustomField.where(field_format: SUPPORTED_DEPENDENCY_FORMATS)
                 .select { |c| c.parent_custom_field_id.to_i == field.id }
    end
  end
end
