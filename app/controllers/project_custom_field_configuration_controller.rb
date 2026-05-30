# Project-scoped custom field configuration. HTML + CSRF only (no API auth in
# v1). Authorization: find_project + authorize (admins pass automatically) plus
# defense-in-depth re-checks inside each service. Archived projects are
# read-only via require_active_project. See the spec set under docs/specs/.
class ProjectCustomFieldConfigurationController < ApplicationController
  helper :project_custom_field_configuration

  before_action :find_project
  before_action :authorize
  before_action :ensure_audit_table
  before_action :find_field, only: %i[show add_value rename_value remove_value
                                       reorder_values set_default_value
                                       edit_dependencies update_dependencies]
  before_action :require_dependency_capable, only: %i[edit_dependencies update_dependencies]
  before_action :require_active_project, only: %i[add_value rename_value remove_value
                                                  reorder_values set_default_value
                                                  update_dependencies]

  # Overview lives inline in the Project → Settings tab; the canonical URL just
  # redirects there so there is a single overview surface (Integration §4).
  def index
    redirect_to settings_project_path(@project, tab: 'custom_field_configuration')
  end

  def show
    prepare_show
  end

  def add_value
    perform_value_operation(RedmineDependingCustomFields::AddValueService,
                            action: :add_value, notice: :notice_value_added)
  end

  def rename_value
    perform_value_operation(RedmineDependingCustomFields::RenameValueService,
                            action: :rename_value, notice: :notice_value_renamed)
  end

  def remove_value
    perform_value_operation(RedmineDependingCustomFields::RemoveValueService,
                            action: :remove_value, notice: :notice_value_removed)
  end

  def reorder_values
    perform_value_operation(RedmineDependingCustomFields::ReorderValuesService,
                            action: :reorder_values, notice: :notice_values_reordered)
  end

  def set_default_value
    perform_value_operation(RedmineDependingCustomFields::SetDefaultValueService,
                            action: :set_default_value, notice: :notice_default_value_set)
  end

  def edit_dependencies
    prepare_dependencies
  end

  def update_dependencies
    RedmineDependingCustomFields::DependencyMappingService.new(
      project: @project, field: @field, user: User.current,
      params: dependency_params, request: request
    ).call
    flash[:notice] = l(:notice_dependencies_saved)
    redirect_to custom_field_configuration_field_dependencies_path(@project, @field)
  rescue RedmineDependingCustomFields::OperationError => e
    case e.http_status
    when :forbidden then deny_access
    when :not_found then render_404
    else
      flash.now[:error] = translate_error(e.key)
      prepare_dependencies
      render :edit_dependencies, status: e.http_status
    end
  end

  def audit
    scope = RedmineDependingCustomFields::ConfigAuditEvent
            .where(project_id: @project.id).order(created_at: :desc, id: :desc)
    @event_count = scope.count
    @paginator = Redmine::Pagination::Paginator.new(@event_count, 25, params[:page])
    @events = scope.limit(@paginator.per_page).offset(@paginator.offset).to_a
  end

  private

  def find_project
    @project = Project.find(params[:project_id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def find_field
    @field = CustomField.find_by(id: params[:field_id])
    return render_field_error(:error_field_not_found, :not_found) unless @field
    unless RedmineDependingCustomFields::FieldRelevance.in_project?(@field, @project)
      return render_field_error(:error_field_not_found, :not_found)
    end
    unless RedmineDependingCustomFields::FieldRelevance.supported_format?(@field)
      render_field_error(:error_format_unsupported, :unprocessable_entity)
    end
  end

  def require_dependency_capable
    return if RedmineDependingCustomFields::FieldRelevance.dependency_capable?(@field)

    render_field_error(:error_format_unsupported, :unprocessable_entity)
  end

  def require_active_project
    return if @project.active?

    flash.now[:error] = translate_error(:error_project_archived)
    render_error(message: translate_error(:error_project_archived), status: :forbidden)
  end

  # Fail closed when the audit table is missing (migration not run) — never
  # apply an un-auditable change (Audit Spec §10, Product §16).
  def ensure_audit_table
    return if RedmineDependingCustomFields::ConfigAuditEvent.table_exists?

    render_error(message: l(:error_dcf_audit_table_missing), status: :internal_server_error)
  end

  def perform_value_operation(klass, action:, notice:)
    klass.new(project: @project, field: @field, user: User.current,
              params: value_params, request: request).call
    flash[:notice] = l(notice)
    redirect_to custom_field_configuration_field_path(@project, @field)
  rescue RedmineDependingCustomFields::ConfirmationRequired => e
    @impact = e.impact
    @pending_action = action
    @pending_params = value_params
    prepare_show
    render :show, status: :unprocessable_entity
  rescue RedmineDependingCustomFields::OperationError => e
    case e.http_status
    when :forbidden then deny_access
    when :not_found then render_404
    else
      flash.now[:error] = translate_error(e.key)
      prepare_show
      render :show, status: e.http_status
    end
  end

  def prepare_show
    @field.reload
    @state_hash = RedmineDependingCustomFields::BaseService.state_hash(@field)
    @show_usage = params[:show_usage].present?
    @dependency_capable = RedmineDependingCustomFields::FieldRelevance.dependency_capable?(@field)
    if RedmineDependingCustomFields::FieldRelevance.enum_family?(@field)
      @enumerations = @field.enumerations.order(:position).to_a
    else
      @list_values = Array(@field.possible_values)
    end
  end

  def prepare_dependencies
    @parent = CustomField.find_by(id: @field.parent_custom_field_id)
    @parent_keys = parent_value_options(@parent)
    @child_values = child_value_options(@field)
    @value_dependencies = @field.value_dependencies || {}
    @default_value_dependencies = @field.default_value_dependencies || {}
    @state_hash = RedmineDependingCustomFields::BaseService.state_hash(@field)
  end

  # [key, label] pairs for the matrix axes.
  def parent_value_options(cf)
    return [] unless cf

    value_options(cf)
  end

  def child_value_options(cf)
    value_options(cf)
  end

  def value_options(cf)
    if RedmineDependingCustomFields::FieldRelevance.enum_family?(cf)
      cf.enumerations.order(:position).map { |e| [e.id.to_s, e.name] }
    else
      Array(cf.possible_values).map { |v| [v.to_s, v.to_s] }
    end
  end

  def value_params
    params.permit(:value, :position, :old_value, :new_value, :enumeration_id,
                  :default_value, :confirm, :state_hash, ordered_values: []).to_h.symbolize_keys
  end

  def dependency_params
    {
      value_dependencies:         unsafe_hash(params[:value_dependencies]),
      default_value_dependencies: unsafe_hash(params[:default_value_dependencies]),
      state_hash:                 params[:state_hash]
    }
  end

  def unsafe_hash(value)
    value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value
  end

  def render_field_error(key, status)
    respond_to do |format|
      format.html { render_error(message: translate_error(key), status: status) }
      format.any  { render_error(message: translate_error(key), status: status) }
    end
  end

  def translate_error(key)
    l(key, default: key.to_s)
  end
end
