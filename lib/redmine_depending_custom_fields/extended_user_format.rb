# frozen_string_literal: true

module RedmineDependingCustomFields
  class ExtendedUserFormat < Redmine::FieldFormat::UserFormat
    self.label = :field_format_user
  end
end
