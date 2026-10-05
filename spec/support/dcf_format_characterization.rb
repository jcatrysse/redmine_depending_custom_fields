# frozen_string_literal: true

# Builders for spec/characterization/depending_formats_spec.rb (WP-04): a
# parent with values A, B, C and a depending child with a1, a2, b1, as a list
# pair or an enumeration pair, plus issues holding legacy combinations.
module DcfFormatCharacterization
  # Option attributes the depending formats add to a value the parent does not allow.
  HIDDEN = { hidden: true, style: 'display:none;' }.freeze

  # The stored value of +name+: the name itself for list fields, the
  # enumeration id (String) for enumeration fields.
  def kit_key(field, name)
    return name if field.field_format.end_with?('list')

    field.enumerations.detect { |e| e.name == name }.id.to_s
  end

  # Parent values A, B, C; A allows a1 and a2, B allows b1, C allows nothing.
  def build_kit(kind, multiple: false, type: IssueCustomField, child_names: %w[a1 a2 b1])
    if kind == :list
      parent = dcf_list_field(values: %w[A B C], type: type)
      child = dcf_list_field(format: 'depending_list', values: child_names, parent: parent,
                             multiple: multiple, type: type)
    else
      parent = dcf_enum_field(names: %w[A B C], type: type)
      child = dcf_enum_field(format: 'depending_enumeration', names: child_names, parent: parent, type: type)
      child.update!(multiple: true) if multiple
    end
    dcf_set_dependencies(
      child,
      value_dependencies: { kit_key(parent, 'A') => [kit_key(child, 'a1'), kit_key(child, 'a2')],
                            kit_key(parent, 'B') => [kit_key(child, 'b1')] },
      default_value_dependencies: { kit_key(parent, 'A') => kit_key(child, 'a2') }
    )
    [parent, child.reload]
  end

  # Two depending fields of +kind+ that name each other as parent (a stored
  # cycle; no validation prevents it today): x1 allows y1, y1 allows x1.
  def build_cycle(kind)
    if kind == :list
      x = dcf_list_field(format: 'depending_list', values: %w[x1 x2])
      y = dcf_list_field(format: 'depending_list', values: %w[y1 y2], parent: x)
    else
      x = dcf_enum_field(format: 'depending_enumeration', names: %w[x1 x2])
      y = dcf_enum_field(format: 'depending_enumeration', names: %w[y1 y2], parent: x)
    end
    x.parent_custom_field_id = y.id
    x.save!
    dcf_set_dependencies(x, value_dependencies: { kit_key(y, 'y1') => [kit_key(x, 'x1')] })
    dcf_set_dependencies(y, value_dependencies: { kit_key(x, 'x1') => [kit_key(y, 'y1')] })
    raise 'stored cycle was not saved' unless CustomField.find(x.id).parent_custom_field_id == y.id

    [x, y]
  end

  # What the core list or enumeration format offers for +field+.
  def core_base(field)
    return field.possible_values if field.field_format.end_with?('list')

    field.enumerations.active.map { |e| [e.name, e.id.to_s] }
  end

  def pair(field, name, *extra)
    [name, kit_key(field, name), *extra]
  end

  def kit_value(field, names)
    keys = Array(names).map { |n| kit_key(field, n) }
    field.multiple? ? keys : keys.first
  end

  # A persisted issue holding +values+ (field => name or names), stored without
  # validation so legacy combinations can be set up. Reloaded, so value_was is
  # what the database holds.
  def kit_issue(project, values)
    tracker, status, priority = dcf_issue_infra(project)
    values.each_key { |f| tracker.custom_fields << f unless tracker.custom_fields.include?(f) }
    issue = Issue.new(project: project, tracker: tracker, subject: 'S', author: dcf_admin,
                      status: status, priority: priority)
    issue.custom_field_values = values.to_h { |f, names| [f.id.to_s, kit_value(f, names)] }
    issue.save!(validate: false)
    Issue.find(issue.id)
  end

  def kit_new_issue(project, values)
    tracker, status, priority = dcf_issue_infra(project)
    values.each_key { |f| tracker.custom_fields << f unless tracker.custom_fields.include?(f) }
    issue = Issue.new(project: project, tracker: tracker, subject: 'S', author: dcf_admin,
                      status: status, priority: priority)
    issue.custom_field_values = values.to_h { |f, names| [f.id.to_s, kit_value(f, names)] }
    issue
  end

  # Core adds custom value errors under the field name (CustomFieldValue#validate_value).
  def errors_for(record, field)
    record.valid?
    record.errors[field.name]
  end
end
