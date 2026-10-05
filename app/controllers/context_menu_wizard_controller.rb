# Saves the values chosen in the context menu wizard. The former 'options'
# action is removed (SD-14): no client used it and it had no visibility check.
class ContextMenuWizardController < ApplicationController
  before_action :require_login
  before_action :find_issues, only: :save
  before_action :check_edit_permission, only: :save

  def save
    values = extract_custom_field_values
    return head :ok if values.blank?

    unless issues_all? do |issue|
      !issue.respond_to?(:safe_attribute?) ||
        issue.safe_attribute?("custom_field_values", User.current)
    end
      return deny_access
    end

    errors = []
    @issues.find_each do |issue|
      # Assign through safe_attributes= like core bulk_update does: it keeps
      # only the custom fields the current user may edit on this issue
      # (visible for the user's roles and not read-only by workflow).
      issue.safe_attributes = { 'custom_field_values' => values }
      issue.save
      errors.concat(issue.errors.full_messages) if issue.errors.any?
    end

    if errors.any?
      render json: { errors: errors }, status: :unprocessable_entity
    else
      head :ok
    end
  end

  private

  def extract_custom_field_values
    permitted = params.permit(:fieldId, :value, issue: { custom_field_values: {} })
    raw_hash = permitted.dig(:issue, :custom_field_values)

    values = {}
    (raw_hash || {}).each do |fid, val|
      if val.is_a?(Array)
        if val.delete('__none__') || val.delete('none')
          values[fid.to_s] = ''
        else
          cleaned = val.reject(&:blank?)
          values[fid.to_s] = cleaned if cleaned.any?
        end
      else
        next if val.blank?
        values[fid.to_s] = (val == '__none__' || val == 'none') ? '' : val
      end
    end

    if values.blank? && permitted[:fieldId].present?
      fid = permitted[:fieldId].to_s
      val = permitted[:value]
      return {} if val.to_s.blank?
      values[fid] = (val == '__none__' || val == 'none') ? '' : val
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
