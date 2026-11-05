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
  end
end
