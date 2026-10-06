# frozen_string_literal: true

require_relative 'depending_format_methods'

# Field format for list custom fields whose options are filtered based on the
# value of a parent custom field. `value_dependencies` defines the mapping of
# allowed child options per parent value. Filtering, validation and
# persistence of that mapping are shared with the enumeration format
# (DependingFormatMethods).

module RedmineDependingCustomFields
  class DependingListFormat < Redmine::FieldFormat::ListFormat
    include DependingFormatMethods

    add 'depending_list'
    self.form_partial = 'custom_fields/formats/depending_list'

    def label
      :label_depending_list
    end

    # Every non-blank value, never restricted by the parent.
    def query_filter_values(custom_field, query = nil)
      raw = possible_values_options(custom_field, query&.project)
      raw.map do |opt|
        label, value = opt.is_a?(Array) ? opt.take(2) : [opt, opt]
        next if value.blank?

        [label, value.to_s]
      end.compact
    end
  end
end
