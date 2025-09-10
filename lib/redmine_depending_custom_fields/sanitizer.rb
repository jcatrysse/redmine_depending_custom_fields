# Simple helpers for cleaning up dependency hashes coming from forms or the
# API. Values and keys are converted to strings and blank entries are removed.
module RedmineDependingCustomFields
  module Sanitizer
    def self.sanitize_dependencies(hash)
      return {} unless hash.is_a?(Hash)
      hash.each_with_object({}) do |(k, v), h|
        key = k.to_s
        next if key.blank?
        values = Array(v).map(&:to_s).reject(&:blank?)
        h[key] = values if values.any?
      end
    end

    def self.sanitize_default_dependencies(hash)
      return {} unless hash.is_a?(Hash)
      hash.each_with_object({}) do |(k, v), h|
        key = k.to_s
        next if key.blank?

        values = Array(v).map(&:to_s).reject(&:blank?)
        next if values.empty?

        h[key] = v.is_a?(Array) ? values : values.first
      end
    end

    # Mirrors ApplicationController#replace_none_values_with_blank
    # Converts 'none' and '__none__' markers into blank strings so that
    # assigning the resulting hash clears the corresponding attributes.
    def self.replace_none_values_with_blank(params)
      attributes = (params || {})
      attributes.each_key { |k| attributes[k] = '' if attributes[k] == 'none' }
      if (custom = attributes[:custom_field_values])
        custom.each_key do |k|
          if custom[k].is_a?(Array)
            custom[k] << '' if custom[k].delete('__none__')
          else
            custom[k] = '' if custom[k] == '__none__'
          end
        end
      end
      attributes
    end
  end
end
