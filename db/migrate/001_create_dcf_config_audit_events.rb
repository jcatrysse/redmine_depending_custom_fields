# First plugin migration: append-only audit log for project-level custom field
# configuration changes. See docs/specs/project_custom_field_configuration_audit_spec.md.
class CreateDcfConfigAuditEvents < ActiveRecord::Migration[6.1]
  def change
    create_table :dcf_config_audit_events do |t|
      t.integer :project_id
      t.integer :custom_field_id
      t.string  :custom_field_name, limit: 255
      t.integer :acting_user_id
      t.string  :acting_user_name, limit: 255
      t.string  :action, limit: 64, null: false
      t.string  :status, limit: 32, null: false, default: 'success'
      t.text    :before_value
      t.text    :after_value
      t.string  :changes_summary, limit: 1000
      t.integer :affected_projects_count
      t.integer :affected_values_count
      t.text    :affected_child_field_ids
      t.string  :ip_address, limit: 45
      t.string  :user_agent, limit: 512
      t.string  :request_id, limit: 64
      t.text    :error_message
      t.datetime :created_at, null: false
    end

    add_index :dcf_config_audit_events, [:project_id, :created_at],
              name: 'index_dcf_audit_on_project_created'
    add_index :dcf_config_audit_events, [:custom_field_id, :created_at],
              name: 'index_dcf_audit_on_cf_created'
    add_index :dcf_config_audit_events, :created_at,
              name: 'index_dcf_audit_on_created'
  end
end
