# frozen_string_literal: true

require 'redmine'
require_relative 'redmine_depending_custom_fields/extended_user_format'
require_relative 'redmine_depending_custom_fields/dependable_list_format'
require_relative 'redmine_depending_custom_fields/hooks/view_layouts_base_html_head_hook'

module RedmineDependingCustomFields
  FIELD_FORMAT_EXTENDED_USER = 'extended_user'
  FIELD_FORMAT_DEPENDABLE_LIST = 'dependable_list'
  FIELD_FORMAT_DEPENDABLE_ENUMERATION = 'dependable_enumeration'

  def self.register_formats
    formats = Setting.plugin_redmine_depending_custom_fields['enabled_formats'] || []
    if formats.include?(FIELD_FORMAT_EXTENDED_USER)
      Redmine::FieldFormat.add FIELD_FORMAT_EXTENDED_USER, ExtendedUserFormat do |format|
        format.label = :label_extended_user
        format.order = 8
        format.edit_as = 'user'
      end
    else
      Redmine::FieldFormat.delete FIELD_FORMAT_EXTENDED_USER
    end

    if formats.include?(FIELD_FORMAT_DEPENDABLE_LIST)
      Redmine::FieldFormat.add FIELD_FORMAT_DEPENDABLE_LIST, DependableListFormat do |format|
        format.label = :label_dependable_list
        format.order = 9
        format.edit_as = 'list'
      end
    else
      Redmine::FieldFormat.delete FIELD_FORMAT_DEPENDABLE_LIST
    end

    if formats.include?(FIELD_FORMAT_DEPENDABLE_ENUMERATION)
      Redmine::FieldFormat.add FIELD_FORMAT_DEPENDABLE_ENUMERATION, DependableEnumerationFormat do |format|
        format.label = :label_dependable_enumeration
        format.order = 10
        format.edit_as = 'enumeration'
      end
    else
      Redmine::FieldFormat.delete FIELD_FORMAT_DEPENDABLE_ENUMERATION
    end
  end
end
