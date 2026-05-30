module RedmineDependingCustomFields
  # Operation B — rename a possible value. List family rewrites possible_values,
  # default_value, CustomValue rows, own dependency entries (depending_list
  # only) and cascades the parent key into depending children. Enum family only
  # renames the CustomFieldEnumeration name (id-stable, no rewrite/cascade).
  # See Operations Spec §B.
  class RenameValueService < BaseService
    def audit_action
      'rename_value'
    end

    private

    def perform!
      list_family? ? rename_list! : rename_enum!
    end

    def rename_list!
      old = @params[:old_value].to_s
      nv = normalize(@params[:new_value])
      raise OperationError.new(:error_value_blank) if nv.blank?
      raise OperationError.new(:error_field_not_found, http_status: :not_found) unless possible_values.include?(old)
      raise OperationError.new(:error_value_duplicate) if nv != old && possible_values.include?(nv)

      usage_here  = UsageCalculator.usage_here(field, old, project)
      usage_other = UsageCalculator.usage_other(field, old, project)
      own_refs    = UsageCalculator.own_dep_refs(field, old)
      parent_refs = UsageCalculator.parent_key_refs(field, old)
      affected    = UsageCalculator.affected_child_fields(field, old)

      if !confirmed? && (usage_other.positive? || shared_or_global? || own_refs.positive? || parent_refs.positive?)
        raise ConfirmationRequired.new(build_impact(old, usage_here, usage_other, own_refs, parent_refs, affected))
      end

      field.possible_values = possible_values.map { |x| x == old ? nv : x }
      field.default_value = nv if field.default_value.to_s == old
      rows = CustomValue.where(custom_field_id: field.id, value: old).update_all(value: nv)
      rewrite_own_list_deps!(old, nv) if depending?
      field.save!

      touched = cascade_parent_key!(old, nv, :rename)

      Outcome.new(before: { from: old }, after: { to: nv },
                  summary: "Renamed '#{old}' to '#{nv}'",
                  affected_projects_count: affected_projects_count,
                  affected_values_count: rows,
                  affected_child_field_ids: touched)
    end

    def rename_enum!
      enum = field.enumerations.find_by(id: @params[:enumeration_id])
      raise OperationError.new(:error_field_not_found, http_status: :not_found) unless enum

      nv = normalize(@params[:new_value])
      raise OperationError.new(:error_value_blank) if nv.blank?

      dup = field.enumerations.where(active: true).where.not(id: enum.id).pluck(:name)
      raise OperationError.new(:error_value_duplicate) if dup.include?(nv)

      old = enum.name
      # Id-stable: renaming the name does not touch CustomValue, own deps, or
      # parent keys, so no confirmation/cascade is needed (UI Spec §4).
      enum.update!(name: nv)

      Outcome.new(before: { from: old }, after: { to: nv },
                  summary: "Renamed enumeration '#{old}' to '#{nv}'",
                  affected_projects_count: affected_projects_count,
                  affected_values_count: 0)
    end
  end
end
