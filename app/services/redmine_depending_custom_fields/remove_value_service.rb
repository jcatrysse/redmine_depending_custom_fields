module RedmineDependingCustomFields
  # Operation C — remove a possible value. List family removes from
  # possible_values (CustomValue rows are left orphaned, never deleted). Enum
  # family deactivates when in use, hard-destroys when unused. Both prune the
  # value as a parent key from depending children. See Operations Spec §C.
  class RemoveValueService < BaseService
    def audit_action
      'remove_value'
    end

    private

    def perform!
      list_family? ? remove_list! : remove_enum!
    end

    def remove_list!
      value = @params[:value].to_s
      raise OperationError.new(:error_field_not_found, http_status: :not_found) unless possible_values.include?(value)

      impact = gather_impact(value)
      guard_removal!(impact, value)

      field.possible_values = possible_values.reject { |x| x == value }
      field.default_value = nil if field.default_value.to_s == value
      prune_own_deps!(value) if depending?
      field.save!

      touched = cascade_parent_key!(value, nil, :remove)

      Outcome.new(before: { removed: value }, after: nil,
                  summary: "Removed value '#{value}'",
                  affected_projects_count: affected_projects_count,
                  affected_values_count: impact[:total],
                  affected_child_field_ids: touched)
    end

    def remove_enum!
      enum = field.enumerations.find_by(id: @params[:enumeration_id])
      raise OperationError.new(:error_field_not_found, http_status: :not_found) unless enum

      value_key = enum.id.to_s
      impact = gather_impact(value_key)
      guard_removal!(impact, value_key)

      if impact[:total].positive?
        enum.update!(active: false) # deactivate so historical ids still resolve
        after = { deactivated: enum.name }
      else
        enum.destroy!
        after = { destroyed: enum.name }
      end
      if depending?
        prune_own_deps!(value_key)
        field.save!
      end

      touched = cascade_parent_key!(value_key, nil, :remove)

      Outcome.new(before: { removed: enum.name }, after: after,
                  summary: "Removed enumeration '#{enum.name}'",
                  affected_projects_count: affected_projects_count,
                  affected_values_count: impact[:total],
                  affected_child_field_ids: touched)
    end

    def gather_impact(value_key)
      usage_here  = UsageCalculator.usage_here(field, value_key, project)
      usage_other = UsageCalculator.usage_other(field, value_key, project)
      {
        usage_here:  usage_here,
        usage_other: usage_other,
        total:       usage_here + usage_other,
        own_refs:    UsageCalculator.own_dep_refs(field, value_key),
        parent_refs: UsageCalculator.parent_key_refs(field, value_key),
        affected:    UsageCalculator.affected_child_fields(field, value_key)
      }
    end

    def guard_removal!(impact, value_key)
      raise OperationError.new(:error_value_in_use) if block_removal_when_used? && impact[:total].positive?

      needs_confirm = impact[:total].positive? || impact[:own_refs].positive? ||
                      impact[:parent_refs].positive? || shared_or_global?
      return if confirmed? || !needs_confirm

      raise ConfirmationRequired.new(
        build_impact(value_key, impact[:usage_here], impact[:usage_other],
                     impact[:own_refs], impact[:parent_refs], impact[:affected])
      )
    end
  end
end
