# Saves the values chosen in the context menu wizard. The former 'options'
# action is removed (SD-14): no client used it and it had no visibility check.
#
# WP-36 (UD-13 changed by the owner): show answers the wizard body that
# context_menu_wizard.js fetches when the wizard opens, with the rules of the
# context menu: login (session only, no API key), every selected issue
# visible (403, core find_issues), the edit permission for the attributes of
# every issue (core's attributes_editable?, tracker permissions included, the
# ContextMenuHook gate, 403), one SelectionGraph and ParentDetector for the
# current user. A root it does not offer (not a root, hidden, unknown, no
# levels) and malformed parameters get the same generic 404, so a hidden
# field cannot be told from a missing one. Never cached (no-store).
class ContextMenuWizardController < ApplicationController
  # Prepended: run before Redmine's own callbacks, so a format extension of
  # the body path is refused before a session or an API key is read, and
  # every answer of show (errors and the login redirect included) is no-store.
  prepend_before_action :refuse_format, only: :show
  prepend_before_action :no_store, only: :show
  before_action :require_login
  before_action :find_issues, only: :save
  before_action :check_edit_permission, only: :save

  helper :custom_fields
  helper :context_menu_wizard

  # Issue ids are integer columns.
  MAX_ID = 2_147_483_647

  def show
    ids = requested_ids
    root_id = requested_parent_id
    return render_404 unless ids && root_id

    issues = Issue.where(id: ids).preload(:project, :tracker, :status).to_a
    return render_404 if issues.empty?

    # The requested order (the menu entry's data-issue-ids), not the database's.
    position = ids.each_with_index.to_h
    issues.sort_by! { |issue| position[issue.id] }
    return deny_access unless issues.all?(&:visible?)

    user = User.current
    return deny_access unless issues.all? { |issue| issue.attributes_editable?(user) }

    detector = RedmineDependingCustomFields::ParentDetector
    graph = RedmineDependingCustomFields::SelectionGraph.new(issues)
    root = detector.for_issues(issues, graph: graph, user: user).detect { |cf| cf.id == root_id }
    levels = root ? detector.wizard_levels(root, issues, graph: graph, user: user) : []
    return render_404 if levels.empty?

    render partial: 'depending_custom_fields/context_menu_wizard_form', formats: [:html], layout: false,
           content_type: 'text/html',
           locals: { parent_field: root, issues: issues, fields_hierarchy: levels }
  rescue StandardError => e
    # Fail closed as the menu hook does: the class only, never the message.
    Rails.logger.warn("[DCF] context menu wizard failed: #{e.class}")
    head :internal_server_error unless performed?
  end

  def save
    values = extract_custom_field_values
    return head :ok if values.blank?

    unless issues_all? do |issue|
      !issue.respond_to?(:safe_attribute?) ||
        issue.safe_attribute?("custom_field_values", User.current)
    end
      return deny_access
    end

    failed = Hash.new { |hash, message| hash[message] = [] }
    @issues.find_each do |issue|
      # As core bulk_update does: a journal for the history and the
      # notifications (full review of 2026-11-05, context-menu-2), then
      # safe_attributes=, which keeps only the custom fields the current user
      # may edit on this issue (visible for the user's roles and not
      # read-only by workflow).
      issue.init_journal(User.current)
      issue.safe_attributes = { 'custom_field_values' => values }
      issue.save
      issue.errors.full_messages.uniq.each { |message| failed[message] << issue.id }
    end

    if failed.any?
      # One line per message with its issues, as core's bulk edit
      # (bulk_edit_error_messages): 'City is invalid: #41, #42' (context-menu-4,
      # Chromium walkthrough of 2026-11-05, issue-1).
      errors = failed.map { |message, ids| "#{message}: #{ids.sort.map { |id| "##{id}" }.join(', ')}" }
      render json: { errors: errors }, status: :unprocessable_entity
    else
      head :ok
    end
  end

  private

  def no_store
    response.headers['Cache-Control'] = 'no-store'
  end

  # The body path takes no format (the API formats belong to the API).
  def refuse_format
    head :not_found if params[:format].present?
  end

  # The ids as the core menu sends them (ids[]=1&ids[]=2) or a comma string,
  # deduplicated; nil unless every element is a String of canonical digits
  # within the id column (a Hash, nested Arrays, blanks, signs, separators
  # and huge numbers included).
  def requested_ids
    raw = params[:ids]
    list =
      case raw
      when Array then raw
      when String then raw.split(',', -1)
      end
    return nil if list.blank? || !list.all? { |id| canonical_id?(id) }

    list.map(&:to_i).uniq
  end

  def requested_parent_id
    raw = params[:parent_id]
    canonical_id?(raw) ? raw.to_i : nil
  end

  def canonical_id?(value)
    value.is_a?(String) && value.length <= 10 &&
      value.match?(RedmineDependingCustomFields::DependencyRules::CANONICAL_ID) && value.to_i <= MAX_ID
  end

  def extract_custom_field_values
    permitted = params.permit(:fieldId, :value, issue: { custom_field_values: {} })
    raw_hash = permitted.dig(:issue, :custom_field_values)

    # Only core's '__none__' marker clears a field; 'none' is an ordinary
    # value (full review of 2026-11-05, context-menu-1).
    values = {}
    (raw_hash || {}).each do |fid, val|
      if val.is_a?(Array)
        if val.delete('__none__')
          values[fid.to_s] = ''
        else
          cleaned = val.reject(&:blank?)
          values[fid.to_s] = cleaned if cleaned.any?
        end
      else
        next if val.blank?
        values[fid.to_s] = val == '__none__' ? '' : val
      end
    end

    if values.blank? && permitted[:fieldId].present?
      fid = permitted[:fieldId].to_s
      val = permitted[:value]
      return {} if val.to_s.blank?
      values[fid] = val == '__none__' ? '' : val
    end

    values
  end

  def find_issues
    ids_param = params[:ids] || params[:issue_ids] || params[:issueIds]
    ids =
      case ids_param
      when Array
        ids_param
      else
        ids_param.to_s.split(',')
      end
    ids = ids.map(&:to_i).reject(&:zero?)
    @issues = Issue.where(id: ids)
  end

  def check_edit_permission
    deny_access unless issues_all? do |issue|
      visible = !issue.respond_to?(:visible?) || issue.visible?
      editable = !issue.respond_to?(:editable?) || issue.editable?(User.current)
      visible && editable
    end
  end

  def issues_all?
    result = true
    @issues.find_each do |issue|
      unless yield(issue)
        result = false
        break
      end
    end
    result
  end
end
