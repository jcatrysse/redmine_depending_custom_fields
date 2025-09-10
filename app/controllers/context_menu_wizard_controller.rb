class ContextMenuWizardController < ApplicationController
  include ContextMenuWizardHelper
  before_action :require_login
  before_action :find_issues, only: %i[options save]
  before_action :check_edit_permission, only: :save

  def options
    mapping = Rails.cache.fetch('depending_custom_fields/mapping') do
      RedmineDependingCustomFields::MappingBuilder.build
    end

    if params[:parent_id].present? && params[:parent_value]
      render json: child_options(mapping)
    else
      render json: parent_options(mapping)
    end
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

    errors = []
    @issues.find_each do |issue|
      issue.custom_field_values = values
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

  def parent_options(mapping)
    parent_ids    = mapping.values.map { |i| i[:parent_id].to_i }.uniq
    fields_by_id  = CustomField.where(id: parent_ids).index_by(&:id)

    parent_ids.map do |pid|
      cf = fields_by_id[pid]
      next unless cf

      next unless issues_all? do |issue|
        begin
          issue.available_custom_fields.include?(cf) &&
            RedmineDependingCustomFields::CustomFieldVisibility.visible_to_user?(cf, issue.project, User.current)
        rescue NoMethodError
          true
        end
      end

      allowed = intersect_allowed_values(cf, @issues) || []

      { id: cf.id, name: cf.name, values: allowed }
    end.compact
  end

  def child_options(mapping)
    pid     = params[:parent_id].to_s
    pval    = params[:parent_value].to_s
    childs  = mapping.select { |_, info| info[:parent_id].to_s == pid }
    ids     = childs.keys.map(&:to_i)
    fields  = CustomField.where(id: ids).index_by(&:id)

    childs.map do |cid, info|
      cf = fields[cid.to_i]
      next unless cf

      next unless issues_all? do |issue|
        begin
          issue.available_custom_fields.include?(cf) &&
            RedmineDependingCustomFields::CustomFieldVisibility.visible_to_user?(cf, issue.project, User.current)
        rescue NoMethodError
          true
        end
      end

      allowed_by_parent = Array(info[:map][pval]).map(&:to_s)
      allowed = cf.possible_values_options(@issues).map do |o|
        o.is_a?(Array) ? o[1].to_s : o.to_s
      end
      allowed &= allowed_by_parent if allowed_by_parent.any?

      { id: cf.id, name: cf.name, values: allowed || [] }
    end.compact
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
