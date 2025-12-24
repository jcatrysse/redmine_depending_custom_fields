# frozen_string_literal: true

require_relative 'parent_value_options'

module RedmineDependingCustomFields
  class ParentReference
    ENUMERATED_FORMATS = %w[
      list
      enumeration
      depending_list
      depending_enumeration
    ].freeze

    attr_reader :type, :custom_field, :key

    def self.from_custom_field(custom_field)
      return nil unless custom_field

      if custom_field.parent_field_type.to_s == 'core_field' ||
         (custom_field.parent_field_key.present? && custom_field.parent_custom_field_id.blank?)
        key = custom_field.parent_field_key.to_s
        return nil if key.blank?

        return new(type: 'core_field', key: key)
      end

      parent_id = custom_field.parent_custom_field_id
      return nil if parent_id.blank?

      parent = CustomField.find_by(id: parent_id)
      return nil unless parent

      if custom_field.respond_to?(:type) && parent.respond_to?(:type)
        return nil unless parent.type == custom_field.type
      end

      if custom_field.respond_to?(:field_format) && parent.respond_to?(:field_format)
        expected_formats = case custom_field.field_format.to_s
                           when RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_ENUMERATION
                             [
                               'list',
                               'enumeration',
                               RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST,
                               RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_ENUMERATION
                             ]
                           when RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST
                             ['list', RedmineDependingCustomFields::FIELD_FORMAT_DEPENDING_LIST]
                           end
        return nil if expected_formats && !expected_formats.include?(parent.field_format.to_s)
      end

      new(type: 'custom_field', custom_field: parent)
    end

    def initialize(type:, custom_field: nil, key: nil)
      @type = type
      @custom_field = custom_field
      @key = key
    end

    def enumerated?
      if custom_field
        return false unless custom_field.respond_to?(:field_format)

        ENUMERATED_FORMATS.include?(custom_field.field_format)
      else
        ParentValueOptions.enumerated_core_field?(key)
      end
    end

    def format
      return custom_field.field_format.to_s if custom_field&.respond_to?(:field_format)

      ParentValueOptions.core_field_format(key)
    end

    def label
      if custom_field
        return custom_field.name if custom_field.respond_to?(:name)

        custom_field.to_s
      else
        info = ParentValueOptions::CORE_FIELDS[key.to_s]
        return key.to_s.humanize unless info

        I18n.t(info[:label], default: key.to_s.humanize)
      end
    end

    def options
      return [] unless enumerated?

      if custom_field
        return [] unless custom_field.respond_to?(:possible_values_options)

        custom_field.possible_values_options.reject do |pv|
          (pv.is_a?(Array) ? pv[1] : pv).to_s.blank?
        end
      else
        ParentValueOptions.core_field_values(key)
      end
    end
  end
end
