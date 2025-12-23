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

      new(type: 'custom_field', custom_field: parent)
    end

    def initialize(type:, custom_field: nil, key: nil)
      @type = type
      @custom_field = custom_field
      @key = key
    end

    def enumerated?
      if custom_field
        ENUMERATED_FORMATS.include?(custom_field.field_format)
      else
        ParentValueOptions.enumerated_core_field?(key)
      end
    end

    def format
      return custom_field.field_format.to_s if custom_field

      ParentValueOptions.core_field_format(key)
    end

    def label
      if custom_field
        custom_field.name
      else
        info = ParentValueOptions::CORE_FIELDS[key.to_s]
        return key.to_s.humanize unless info

        I18n.t(info[:label], default: key.to_s.humanize)
      end
    end

    def options
      return [] unless enumerated?

      if custom_field
        custom_field.possible_values_options.reject do |pv|
          (pv.is_a?(Array) ? pv[1] : pv).to_s.blank?
        end
      else
        ParentValueOptions.core_field_values(key)
      end
    end
  end
end
