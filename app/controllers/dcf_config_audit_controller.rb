# Admin-only, read-only global view of all configuration audit events across
# every project. This is a SEPARATE surface from the project-scoped audit
# action and is NOT gated by the project permission (independent-review fix #6,
# Audit Spec §8). Delegated users cannot reach it.
class DcfConfigAuditController < ApplicationController
  helper :project_custom_field_configuration
  before_action :require_admin
  before_action :ensure_audit_table

  def index
    scope = RedmineDependingCustomFields::ConfigAuditEvent.order(created_at: :desc, id: :desc)
    scope = scope.where(custom_field_id: params[:custom_field_id]) if params[:custom_field_id].present?
    scope = scope.where(action: params[:action_filter]) if params[:action_filter].present?
    scope = scope.where(project_id: params[:project_id]) if params[:project_id].present?

    @event_count = scope.count
    @paginator = Redmine::Pagination::Paginator.new(@event_count, 50, params[:page])
    @events = scope.limit(@paginator.per_page).offset(@paginator.offset).to_a
  end

  private

  def ensure_audit_table
    return if RedmineDependingCustomFields::ConfigAuditEvent.table_exists?

    render_error(message: l(:error_dcf_audit_table_missing), status: :internal_server_error)
  end
end
