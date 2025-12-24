# Simple helpers for cleaning up dependency hashes coming from forms or the
# API. Values and keys are converted to strings and blank entries are removed.
require 'json'

module RedmineDependingCustomFields
  module Sanitizer
    RULE_OPERATORS = %w[
      equals
      not_equals
      contains
      starts_with
      ends_with
      regex
      lt
      lte
      gt
      gte
      between
      present
      blank
    ].freeze

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

    def self.sanitize_dependency_rules(rules)
      parsed, _error = parse_dependency_rules(rules)
      parsed.each_with_object([]) do |rule, sanitized|
        next unless rule.is_a?(Hash)

        operator = rule['operator'] || rule[:operator]
        operator = operator.to_s.strip
        next unless RULE_OPERATORS.include?(operator)

        child_values = Array(rule['child_values'] || rule[:child_values]).map(&:to_s).reject(&:blank?)
        next if child_values.empty?

        value = rule['value'] || rule[:value]
        value_to = rule['value_to'] || rule[:value_to]

        sanitized_rule = {
          'operator' => operator,
          'value' => value.to_s,
          'child_values' => child_values
        }
        sanitized_rule['value_to'] = value_to.to_s if value_to.present?
        sanitized << sanitized_rule
      end
    end

    def self.parse_dependency_rules(rules)
      parsed = normalize_rule_input(rules)
      return [[], 'invalid'] unless parsed.is_a?(Array)

      [parsed, nil]
    end

    ISO_DATE_PATTERN = /\A\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})?)?\z/.freeze

    def self.invalid_date_rules?(rules)
      Array(rules).any? do |rule|
        next false unless rule.is_a?(Hash)

        operator = rule['operator'] || rule[:operator]
        next false unless %w[equals not_equals lt lte gt gte between].include?(operator.to_s)

        values = [rule['value'] || rule[:value], rule['value_to'] || rule[:value_to]].compact
        values.any? { |val| val.is_a?(String) && !valid_iso_date?(val) }
      end
    end

    def self.invalid_rule_schema?(rules)
      Array(rules).any? do |rule|
        return true unless rule.respond_to?(:to_h)

        rule = rule.to_h
        operator = rule['operator'] || rule[:operator]
        child_values = rule['child_values'] || rule[:child_values]
        return true if operator.to_s.strip.empty?
        return true unless child_values.is_a?(Array) && child_values.any?

        next false if %w[present blank].include?(operator.to_s)

        value = rule['value'] || rule[:value]
        return true if value.to_s.strip.empty?

        if operator.to_s == 'between'
          value_to = rule['value_to'] || rule[:value_to]
          return true if value_to.to_s.strip.empty?
        end

        false
      end
    end

    def self.rule_schema_errors(rules)
      Array(rules).each_with_index.with_object([]) do |(rule, index), errors|
        unless rule.respond_to?(:to_h)
          errors << { index: index, code: 'invalid_rule', message: 'Rule must be an object' }
          next
        end

        rule = rule.to_h
        operator = rule['operator'] || rule[:operator]
        child_values = rule['child_values'] || rule[:child_values]
        operator = operator.to_s
        if operator.strip.empty?
          errors << { index: index, code: 'missing_operator', message: 'Operator is required' }
        end
        unless child_values.is_a?(Array) && child_values.any?
          errors << { index: index, code: 'missing_child_values', message: 'Child values are required' }
        end

        next if operator.strip.empty?
        next if %w[present blank].include?(operator)

        value = rule['value'] || rule[:value]
        if value.to_s.strip.empty?
          errors << { index: index, code: 'missing_value', message: 'Value is required' }
        end

        if operator == 'between'
          value_to = rule['value_to'] || rule[:value_to]
          if value_to.to_s.strip.empty?
            errors << { index: index, code: 'missing_value_to', message: 'Value to is required' }
          end
        end
      end
    end

    def self.valid_iso_date?(value)
      return true if value.respond_to?(:to_date) && !value.is_a?(String)
      return false unless value.is_a?(String) && value.match?(ISO_DATE_PATTERN)

      DateTime.iso8601(value)
      true
    rescue ArgumentError
      false
    end
    private_class_method :valid_iso_date?

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

    def self.normalize_rule_input(rules)
      return rules if rules.is_a?(Array)
      return [] if rules.nil?

      if rules.is_a?(String)
        begin
          return JSON.parse(rules)
        rescue JSON::ParserError
          return nil
        end
      end

      []
    end
    private_class_method :normalize_rule_input
  end
end
