# frozen_string_literal: true

require 'redmine'
require_relative 'redmine_depending_custom_fields/version'
require_relative 'redmine_depending_custom_fields/extended_user_format'

module RedmineDependingCustomFields
  FIELD_FORMAT_USER = 'extended_user'

  def self.register_formats
    formats = Setting.plugin_redmine_depending_custom_fields['enabled_formats'] || []
    if formats.include?(FIELD_FORMAT_USER)
      Redmine::FieldFormat.add(FIELD_FORMAT_USER, RedmineDependingCustomFields::ExtendedUserFormat)
    else
      Redmine::FieldFormat.delete(FIELD_FORMAT_USER)
    end
  end
end
