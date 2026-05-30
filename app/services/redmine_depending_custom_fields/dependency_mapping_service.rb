module RedmineDependingCustomFields
  # Operations F + G — value dependency mapping and default value dependencies,
  # saved together in one transaction. Only depending formats with a parent are
  # eligible. Builds via the existing Sanitizer (key typing reused, not
  # reinvented) and validates parent/child existence. See Operations Spec §F/§G.
  class DependencyMappingService < BaseService
    def audit_action
      'update_dependencies'
    end

    private

    def dependency_op?
      true
    end

    def perform!
      parent = CustomField.find_by(id: field.parent_custom_field_id)
      raise OperationError.new(:error_invalid_dependency) unless parent
      raise OperationError.new(:error_field_not_found, http_status: :not_found) unless FieldRelevance.relevant?(parent, project)

      vd = Sanitizer.sanitize_dependencies(@params[:value_dependencies])
      dd = Sanitizer.sanitize_default_dependencies(@params[:default_value_dependencies])

      parent_keys  = value_keys_of(parent)
      child_values = value_keys_of(field)

      validate_mapping!(vd, dd, parent_keys, child_values)

      field.value_dependencies = vd
      field.default_value_dependencies = dd
      field.save!

      Outcome.new(after: { value_dependencies: vd, default_value_dependencies: dd },
                  summary: 'Updated dependency mapping',
                  affected_projects_count: affected_projects_count)
    end

    def validate_mapping!(vd, dd, parent_keys, child_values)
      vd.each do |pkey, arr|
        raise OperationError.new(:error_invalid_dependency) unless parent_keys.include?(pkey.to_s)

        Array(arr).each do |cv|
          raise OperationError.new(:error_invalid_dependency) unless child_values.include?(cv.to_s)
        end
      end

      dd.each do |pkey, val|
        raise OperationError.new(:error_invalid_dependency) unless parent_keys.include?(pkey.to_s)

        allowed = Array(vd[pkey.to_s]).map(&:to_s)
        Array(val).each do |cv|
          raise OperationError.new(:error_invalid_dependency) unless child_values.include?(cv.to_s)
          raise OperationError.new(:error_invalid_dependency) unless allowed.include?(cv.to_s)
        end
      end
    end
  end
end
