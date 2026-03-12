# frozen_string_literal: true

module RedmineDependingCustomFields
  module DependingRulesSupport
    private

    def sanitize_and_validate_dependency_rules(custom_field, parent_reference)
      parsed_rules, error = RedmineDependingCustomFields::Sanitizer.parse_dependency_rules(custom_field.dependency_rules)
      custom_field.errors.add(:dependency_rules, ::I18n.t(:text_dependency_rules_invalid_json)) if error

      if parent_reference&.format == 'date' &&
         RedmineDependingCustomFields::Sanitizer.invalid_date_rules?(parsed_rules)
        custom_field.errors.add(:dependency_rules, ::I18n.t(:text_dependency_rules_invalid_date))
      end

      RedmineDependingCustomFields::Sanitizer.rule_schema_errors(parsed_rules).each do |schema_error|
        custom_field.errors.add(
          :dependency_rules,
          ::I18n.t(:text_dependency_rules_invalid_rule_index, index: schema_error[:index] + 1)
        )
      end

      custom_field.dependency_rules = RedmineDependingCustomFields::Sanitizer.sanitize_dependency_rules(parsed_rules)
    end
  end
end
