module RedmineDependingCustomFields
  # Operation A — add a possible value (list family) or enumeration (enum
  # family). See Operations Spec §A.
  class AddValueService < BaseService
    def audit_action
      'add_value'
    end

    private

    def perform!
      v = normalize(@params[:value])
      raise OperationError.new(:error_value_blank) if v.blank?

      list_family? ? add_list_value!(v) : add_enum_value!(v)
    end

    def add_list_value!(v)
      raise OperationError.new(:error_value_duplicate) if possible_values.include?(v)

      values = possible_values.dup
      pos = @params[:position].presence && @params[:position].to_i
      if pos
        pos = pos.clamp(0, values.length)
        values.insert(pos, v)
      else
        values << v
      end
      field.possible_values = values
      field.save!

      Outcome.new(after: { added: v, position: pos }, summary: "Added value '#{v}'",
                  affected_values_count: 0)
    end

    def add_enum_value!(v)
      active_names = field.enumerations.where(active: true).pluck(:name)
      raise OperationError.new(:error_value_duplicate) if active_names.include?(v)

      next_pos = (field.enumerations.maximum(:position) || 0) + 1
      CustomFieldEnumeration.create!(custom_field_id: field.id, name: v, position: next_pos, active: true)

      Outcome.new(after: { added: v }, summary: "Added enumeration '#{v}'",
                  affected_values_count: 0)
    end
  end
end
