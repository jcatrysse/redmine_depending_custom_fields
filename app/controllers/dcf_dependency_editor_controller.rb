# frozen_string_literal: true

# The values of a candidate parent field for the dependency editor of the
# admin custom field form (editor design 4.2, AD-7, WP-24): GET
# /dcf_dependency_editor/values?custom_field_id=&type=&kind=. Administrators
# only, through the session: no API key and no format (a .json or .xml
# request is an API request, which ignores the session). require_admin runs
# before any lookup, so other users learn nothing about field ids.
class DcfDependencyEditorController < ApplicationController
  # The field formats each editor kind accepts (DependencyRules families).
  KIND_FORMATS = { 'list' => %w[list depending_list],
                   'enumeration' => %w[enumeration depending_enumeration] }.freeze
  NOT_FOUND = { 'error' => 'not_found' }.freeze

  before_action :require_admin

  def values
    field = requested_field
    return render(json: NOT_FOUND, status: :not_found) unless field

    rules = RedmineDependingCustomFields::DependencyRules
    wire = RedmineDependingCustomFields::DependencyEditorConfig.wire_values(rules.value_options(field))
    render json: { 'id' => field.id, 'name' => field.name, 'kind' => rules.kind(field), 'values' => wire }
  end

  private

  # The field named by custom_field_id when its format is in the family of
  # kind and its STI type equals type; nil otherwise. Only String params are
  # read and the id must be canonical, so no Array or Hash reaches the query.
  def requested_field
    id, kind, type = params.values_at(:custom_field_id, :kind, :type)
    return nil unless [id, kind, type].all?(String)

    formats = KIND_FORMATS[kind]
    return nil unless formats && id.match?(RedmineDependingCustomFields::DependencyRules::CANONICAL_ID)

    field = CustomField.find_by(id: id.to_i)
    field if field && formats.include?(field.field_format) && field.type == type
  end
end
