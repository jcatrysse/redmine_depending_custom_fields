module RedmineDependingCustomFields
  # Append-only audit record for project-level custom field configuration
  # operations. Rows are immutable: no update/destroy path is exposed through the
  # application. See docs/specs/project_custom_field_configuration_audit_spec.md.
  class ConfigAuditEvent < ActiveRecord::Base
    self.table_name = 'dcf_config_audit_events'

    STATUSES = %w[success validation_failed authorization_failed save_failed forbidden error].freeze

    validates :action, presence: true
    validates :status, presence: true, inclusion: { in: STATUSES }

    # Append-only: block updates and destroys at the model level so audit
    # integrity cannot be violated through application code.
    before_update { raise ActiveRecord::ReadOnlyRecord, 'ConfigAuditEvent is append-only' }
    before_destroy { raise ActiveRecord::ReadOnlyRecord, 'ConfigAuditEvent is append-only' }

    def readonly?
      !new_record?
    end

    def project
      @project ||= project_id && Project.find_by(id: project_id)
    end

    def custom_field
      @custom_field ||= custom_field_id && CustomField.find_by(id: custom_field_id)
    end

    def acting_user
      @acting_user ||= acting_user_id && User.find_by(id: acting_user_id)
    end

    def affected_child_field_ids_list
      return [] if affected_child_field_ids.blank?

      parsed = ActiveSupport::JSON.decode(affected_child_field_ids)
      parsed.is_a?(Array) ? parsed : []
    rescue ActiveSupport::JSON.parse_error
      []
    end
  end
end
