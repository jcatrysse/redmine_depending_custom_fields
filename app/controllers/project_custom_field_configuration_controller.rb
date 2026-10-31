# Project-scoped custom field configuration. HTML + CSRF only (no API auth in
# v1). Authorization: find_project + authorize (admins pass automatically) plus
# defense-in-depth re-checks inside each service. Archived projects are
# read-only via require_active_project. See the spec set under docs/specs/.
class ProjectCustomFieldConfigurationController < ApplicationController
  helper :project_custom_field_configuration

  AUDIT_COLUMNS = [:id, :project_id, :custom_field_id, :custom_field_name, :acting_user_id, :acting_user_name,
                   :action, :status, :changes_summary, :error_message, :created_at].freeze

  before_action :find_project
  before_action :authorize
  before_action :ensure_audit_table
  before_action :find_field, only: %i[show add_value rename_value remove_value
                                       reorder_values update_enumerations set_default_value
                                       edit_dependencies update_dependencies]
  before_action :require_dependency_capable, only: %i[edit_dependencies update_dependencies]
  before_action :require_active_project, only: %i[add_value rename_value remove_value
                                                  reorder_values update_enumerations
                                                  set_default_value update_dependencies]

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

  # Batch save of the enumeration table: names + positions + active flags in one
  # request, the way core's CustomFieldEnumerations#update_each works.
  def update_enumerations
    perform_value_operation(RedmineDependingCustomFields::UpdateEnumerationsService,
                            action: :update_enumerations, notice: :notice_values_saved)
  end

  def set_default_value
    perform_value_operation(RedmineDependingCustomFields::SetDefaultValueService,
                            action: :set_default_value, notice: :notice_default_value_set)
  end

  def edit_dependencies
    prepare_dependencies
  end

  # The service parses dependencies_json after its preamble authorized the
  # user (SP-20b); a 422 reuses its parse result, a 409 parses once here.
  def update_dependencies
    service = RedmineDependingCustomFields::DependencyMappingService.new(
      project: @project, field: @field, user: User.current,
      params: dependency_params, request: request
    )
    service.call
    flash[:notice] = translate_error(:notice_dependencies_saved)
    redirect_to custom_field_configuration_field_dependencies_path(@project, @field)
  rescue RedmineDependingCustomFields::OperationError => e
    case e.http_status
    when :forbidden then deny_access
    when :not_found then render_404
    else
      flash.now[:error] = translate_error(e)
      if e.http_status == :conflict
        prepare_dependencies(conflict: conflict_payload)
      else
        prepare_dependencies(posted: posted_payload(service))
      end
      render :edit_dependencies, status: dcf_status_code(e.http_status)
    end
  end

  # The page loads only the columns the view shows (project design 4); the
  # count stays on the unselected scope.
  def audit
    scope = RedmineDependingCustomFields::ConfigAuditEvent
            .where(project_id: @project.id).order(created_at: :desc, id: :desc)
    @event_count = scope.count
    page = RedmineDependingCustomFields::ValuesPage.coerce_page(params[:page])
    @paginator = Redmine::Pagination::Paginator.new(@event_count, 25, page)
    @events = scope.select(AUDIT_COLUMNS).limit(@paginator.per_page).offset(@paginator.offset).to_a
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

    render_error(message: translate_error(:error_dcf_audit_table_missing), status: :internal_server_error)
  end

  def perform_value_operation(klass, action:, notice:)
    klass.new(project: @project, field: @field, user: User.current,
              params: value_params, request: request).call
    flash[:notice] = translate_error(notice)
    redirect_to custom_field_configuration_field_path(@project, @field, redirect_state(action))
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
      flash.now[:error] = translate_error(e)
      prepare_show
      render :show, status: dcf_status_code(e.http_status)
    end
  end

  # Show and every re-render read q and page from the request (posted or
  # in the query string), so a refused operation shows the same page.
  def prepare_show
    @field.reload
    @state_hash = RedmineDependingCustomFields::BaseService.state_hash(@field)
    @show_usage = params[:show_usage].present?
    @dependency_capable = RedmineDependingCustomFields::FieldRelevance.dependency_capable?(@field)
    @values_page = RedmineDependingCustomFields::ValuesPage.new(@field, q: params[:q], page: params[:page],
                                                                         per_page: per_page_option)
    @rows = @values_page.rows
    @usage = if @show_usage && RedmineDependingCustomFields::FieldRelevance.list_family?(@field)
               RedmineDependingCustomFields::UsageCalculator.page_usage(@field, @rows.map(&:key), @project)
             end
    @default_options = @values_page.default_options
  end

  # Where a successful value operation returns (project design 5): the posted
  # q when it filters and page when above 1; add_value drops q and jumps to
  # the page of the new value. An empty Hash gives the bare field path.
  def redirect_state(action)
    return add_value_state if action == :add_value

    RedmineDependingCustomFields::ValuesPage.state_for(params[:q], params[:page])
  end

  # The page of the added value: its index among the reloaded list values
  # (the value normalized as AddValueService does), or the last row for an
  # enumeration (appended at the highest position). Only when paginated.
  def add_value_state
    @field.reload
    options = RedmineDependingCustomFields::DependencyRules.value_options(@field)
    index = if RedmineDependingCustomFields::FieldRelevance.enum_family?(@field)
              options.size - 1
            else
              added = value_params[:value].to_s.strip
              options.index { |(key, _label, _active)| key == added }
            end
    page = RedmineDependingCustomFields::ValuesPage.page_for_index(index, options.size, per_page_option)
    page > 1 ? { page: page } : {}
  end

  # R9: every render reloads the field, so the state hash and the editor never
  # come from an instance a failed save changed. +posted+ (a 422 after an ok
  # parse) and +conflict+ (a 409) are ok parse results or nil.
  def prepare_dependencies(posted: nil, conflict: nil)
    @field.reload
    @state_hash = RedmineDependingCustomFields::BaseService.state_hash(@field)
    @parent = RedmineDependingCustomFields::DependencyRules.parent_of(@field)
    @parent_available = @parent.present? &&
                        RedmineDependingCustomFields::FieldRelevance.relevant?(@parent, @project)
    @posted_payload = posted
    @conflict_payload = conflict
  end

  # The service's ok parse result (SP-17: no second parse); nil after a
  # parser error and on the legacy path.
  def posted_payload(service)
    result = service&.parsed_payload
    result&.ok? ? result : nil
  end

  # The 409 is raised in the service preamble before any parse, so this is
  # the request's only parse, after authorization. A String only.
  def conflict_payload
    raw = params[:dependencies_json]
    return nil unless raw.is_a?(String)

    result = RedmineDependingCustomFields::DependencyPayload.parse(raw)
    result&.ok? ? result : nil
  end

  def value_params
    # `enumerations` arrives as a hash of hashes keyed by enumeration id; permit
    # only the three editable attributes per row (same shape core permits in
    # CustomFieldEnumerationsController#update_each_params).
    params.permit(:value, :position, :old_value, :new_value, :enumeration_id,
                  :default_value, :confirm, :state_hash,
                  ordered_values: [],
                  enumerations: %i[name position active]).to_h.symbolize_keys
  end

  # dependencies_json is passed on as posted (the service refuses anything
  # but a String) and wins over the nested params, the deprecated fallback
  # when the key is absent.
  def dependency_params
    out = { state_hash: params[:state_hash] }
    if params.key?(:dependencies_json)
      out[:dependencies_json] = params[:dependencies_json]
    else
      out[:value_dependencies] = unsafe_hash(params[:value_dependencies])
      out[:default_value_dependencies] = unsafe_hash(params[:default_value_dependencies])
    end
    out
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

  # Every flash and error page text of this controller goes through here
  # (SP-06). Redmine renders flash messages with html_safe and I18n does not
  # escape, so each interpolation is escaped exactly once; the locale text is
  # not. The result is a plain String. I18n option keys are never passed on
  # (RESERVED_KEYS does not hold :locale, a keyword of I18n.t).
  # Interpolated texts go to flash only: the error page escapes its message.
  def translate_error(error_or_key)
    if error_or_key.is_a?(RedmineDependingCustomFields::OperationError)
      key = error_or_key.key
      values = error_or_key.interpolations || {}
    else
      key = error_or_key
      values = {}
    end
    escaped = values.each_with_object({}) do |(name, value), result|
      option = name.to_sym
      next if option == :locale || I18n::RESERVED_KEYS.include?(option)

      result[option] = ERB::Util.html_escape(String.new(value.to_s)).to_str
    end
    l(key, escaped.merge(default: key.to_s))
  end

  # Numeric statuses: no Rack 3.1 deprecation warning for :unprocessable_entity.
  def dcf_status_code(symbol)
    symbol == :conflict ? 409 : 422
  end
end
