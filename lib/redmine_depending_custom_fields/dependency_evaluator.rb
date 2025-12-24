# frozen_string_literal: true

require_relative 'parent_reference'
require_relative 'parent_value_resolver'
require_relative 'sanitizer'
require 'date'

module RedmineDependingCustomFields
  class DependencyEvaluator
    Result = Struct.new(:allowed, :has_rules, :has_mapping, :applicable, keyword_init: true)

    NUMERIC_FORMATS = %w[int float].freeze
    DATE_FORMATS = %w[date].freeze

    def self.evaluate(custom_field, customized)
      parent_reference = ParentReference.from_custom_field(custom_field)
      return Result.new(allowed: [], has_rules: false, has_mapping: false, applicable: false) unless parent_reference

      applicable = applicable?(customized, parent_reference)
      return Result.new(allowed: [], has_rules: false, has_mapping: false, applicable: false) unless applicable

      parent_values = ParentValueResolver.values(customized, parent_reference)

      rules = Sanitizer.sanitize_dependency_rules(custom_field.dependency_rules)
      if rules.any?
        allowed = allowed_from_rules(parent_values, rules, parent_reference.format)
        return Result.new(allowed: allowed, has_rules: true, has_mapping: true, applicable: true)
      end

      mapping = if custom_field.respond_to?(:value_dependencies)
                  Sanitizer.sanitize_dependencies(custom_field.value_dependencies)
                else
                  {}
                end
      allowed = allowed_from_mapping(parent_values, mapping)
      Result.new(allowed: allowed, has_rules: false, has_mapping: mapping.present?, applicable: true)
    end

    def self.allowed_from_mapping(parent_values, mapping)
      return [] if parent_values.blank?

      parent_values.flat_map { |v| Array(mapping[v.to_s]) }
                   .map(&:to_s)
                   .uniq
    end
    private_class_method :allowed_from_mapping

    def self.allowed_from_rules(parent_values, rules, parent_format)
      return [] if rules.blank?

      type = value_type(parent_format)
      rules.each_with_object([]) do |rule, allowed|
        next unless rule_matches?(rule, parent_values, type)

        rule['child_values'].each do |value|
          allowed << value unless allowed.include?(value)
        end
      end
    end
    private_class_method :allowed_from_rules

    def self.value_type(format)
      return :number if NUMERIC_FORMATS.include?(format.to_s)
      return :date if DATE_FORMATS.include?(format.to_s)

      :string
    end
    private_class_method :value_type

    def self.rule_matches?(rule, parent_values, type)
      operator = rule['operator'].to_s
      values = Array(parent_values).map(&:to_s)

      return values.any?(&:present?) if operator == 'present'
      return values.all?(&:blank?) if operator == 'blank'

      normalized_values = values.map { |value| normalize_value(value, type) }.compact
      return false if normalized_values.empty?

      value = normalize_value(rule['value'], type)
      value_to = normalize_value(rule['value_to'], type)
      return false if %w[equals not_equals contains starts_with ends_with regex lt lte gt gte].include?(operator) && value.nil?
      return false if operator == 'between' && (value.nil? || value_to.nil?)

      case operator
      when 'equals'
        normalized_values.any? { |v| v == value }
      when 'not_equals'
        normalized_values.any? { |v| v != value }
      when 'contains'
        normalized_values.any? { |v| v.to_s.include?(value.to_s) }
      when 'starts_with'
        normalized_values.any? { |v| v.to_s.start_with?(value.to_s) }
      when 'ends_with'
        normalized_values.any? { |v| v.to_s.end_with?(value.to_s) }
      when 'regex'
        begin
          pattern = Regexp.new(rule['value'].to_s)
          normalized_values.any? { |v| v.to_s.match?(pattern) }
        rescue RegexpError
          false
        end
      when 'lt'
        normalized_values.any? { |v| comparable?(v, value) && v < value }
      when 'lte'
        normalized_values.any? { |v| comparable?(v, value) && v <= value }
      when 'gt'
        normalized_values.any? { |v| comparable?(v, value) && v > value }
      when 'gte'
        normalized_values.any? { |v| comparable?(v, value) && v >= value }
      when 'between'
        return false unless comparable?(value, value_to)
        min, max = value <= value_to ? [value, value_to] : [value_to, value]
        normalized_values.any? { |v| comparable?(v, min) && v >= min && v <= max }
      else
        false
      end
    end
    private_class_method :rule_matches?

    def self.normalize_value(value, type)
      return nil if value.nil?

      case type
      when :number
        begin
          Float(value)
        rescue ArgumentError, TypeError
          nil
        end
      when :date
        return value.to_date if value.respond_to?(:to_date) && !value.is_a?(String)
        string_value = value.to_s
        return nil unless string_value.match?(RedmineDependingCustomFields::Sanitizer::ISO_DATE_PATTERN)

        begin
          DateTime.iso8601(string_value).to_date
        rescue ArgumentError
          nil
        end
      else
        value.to_s
      end
    end
    private_class_method :normalize_value

    def self.comparable?(left, right)
      !left.nil? && !right.nil?
    end
    private_class_method :comparable?

    def self.applicable?(customized, parent_reference)
      return false unless customized

      if parent_reference.type == 'core_field'
        customized.respond_to?(parent_reference.key)
      else
        customized.respond_to?(:custom_field_value)
      end
    end
    private_class_method :applicable?
  end
end
