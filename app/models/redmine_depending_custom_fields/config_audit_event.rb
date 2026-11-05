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
  end
end
