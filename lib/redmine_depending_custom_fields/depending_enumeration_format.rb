# frozen_string_literal: true

require_relative 'depending_format_methods'

# Field format for enumeration custom fields that depend on the value of
# another custom field. The mapping is a hash where the parent option maps to
# an array of allowed child enumeration ids. Filtering, validation and
# persistence of that mapping are shared with the list format
# (DependingFormatMethods).

module RedmineDependingCustomFields
  class DependingEnumerationFormat < Redmine::FieldFormat::EnumerationFormat
    include DependingFormatMethods

    add 'depending_enumeration'
    self.form_partial = 'custom_fields/formats/depending_enumeration'

    def label
      :label_depending_enumeration
    end

    # Restricted by the parent value of the query's project when that maps a
    # non-empty set, all values otherwise.
    def query_filter_values(custom_field, query = nil)
      raw = super(custom_field, query)
      project = query&.project
      parent = CustomField.find_by(id: custom_field.parent_custom_field_id)
      parent_values = Array(project&.custom_field_value(parent)).map(&:to_s)
      mapping = custom_field.value_dependencies || {}
      allowed = parent_values.flat_map { |pv| Array(mapping[pv]) }.map(&:to_s).uniq

      raw.flat_map do |opt|
        if opt.is_a?(Array) && opt[1].is_a?(Array)
          opt[1].map { |lbl, val| [lbl, val.to_s] if val.present? && (allowed.empty? || allowed.include?(val.to_s)) }.compact
        else
          lbl, val = opt.is_a?(Array) ? opt.take(2) : [opt, opt]
          [[lbl, val.to_s]] if val.present? && (allowed.empty? || allowed.include?(val.to_s))
        end
      end.compact
    end
  end
end
