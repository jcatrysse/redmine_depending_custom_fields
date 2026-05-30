module RedmineDependingCustomFields
  # Computes how a value is used: CustomValue counts (this project / other
  # projects) and dependency reference counts on BOTH sides — own-side (this
  # field as child) and parent-side (this field's value used as a parent key in
  # depending children). See Feasibility §5 and Functional §8.
  module UsageCalculator
    # Past this many CustomValue rows we stop counting and report "too large"
    # rather than running an unbounded scan (Functional §7 / UI §4).
    USAGE_CAP = 50_000

    module_function

    # value_key is the stored CustomValue.value: the option string for list
    # families, the enumeration id (string) for enum families.
    def usage_total(field, value_key)
      CustomValue.where(custom_field_id: field.id, value: value_key.to_s).limit(USAGE_CAP + 1).count
    end

    def usage_here(field, value_key, project)
      base = CustomValue.where(custom_field_id: field.id, value: value_key.to_s)
      scope_to_project(field, base, project).limit(USAGE_CAP + 1).count
    end

    def usage_other(field, value_key, project)
      [usage_total(field, value_key) - usage_here(field, value_key, project), 0].max
    end

    def capped?(count)
      count > USAGE_CAP
    end

    def scope_to_project(field, base, project)
      if field.is_a?(ProjectCustomField)
        base.where(customized_type: 'Project', customized_id: project.id)
      else
        base.where(customized_type: 'Issue',
                   customized_id: Issue.where(project_id: project.id).select(:id))
      end
    end

    # Own-side: how many times this child field's own value appears as an
    # allowed child value in its own mapping. Only depending formats have one.
    def own_dep_refs(field, child_value)
      return 0 unless FieldRelevance.depending_format?(field)

      cv = child_value.to_s
      count = 0
      (field.value_dependencies || {}).each_value do |vals|
        count += Array(vals).map(&:to_s).count(cv)
      end
      (field.default_value_dependencies || {}).each_value do |v|
        count += Array(v).map(&:to_s).count(cv)
      end
      count
    end

    # Parent-side: how many depending children reference this value as a parent
    # key in value_dependencies and/or default_value_dependencies.
    def parent_key_refs(field, parent_value)
      pv = parent_value.to_s
      FieldRelevance.children_of(field).sum do |child|
        refs = 0
        refs += 1 if (child.value_dependencies || {}).key?(pv)
        refs += 1 if (child.default_value_dependencies || {}).key?(pv)
        refs
      end
    end

    def affected_child_fields(field, parent_value)
      pv = parent_value.to_s
      FieldRelevance.children_of(field).select do |child|
        (child.value_dependencies || {}).key?(pv) ||
          (child.default_value_dependencies || {}).key?(pv)
      end
    end
  end
end
