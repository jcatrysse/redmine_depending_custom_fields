# frozen_string_literal: true

require 'redmine'
require_relative 'redmine_depending_custom_fields/extended_user_format'
require_relative 'redmine_depending_custom_fields/depending_list_format'
require_relative 'redmine_depending_custom_fields/depending_enumeration_format'
require_relative 'redmine_depending_custom_fields/parent_reference'
require_relative 'redmine_depending_custom_fields/parent_value_options'
require_relative 'redmine_depending_custom_fields/parent_value_resolver'
require_relative 'redmine_depending_custom_fields/dependency_evaluator'
require_relative 'redmine_depending_custom_fields/hooks/view_layouts_base_html_head_hook'
require_relative 'redmine_depending_custom_fields/custom_field_visibility'

module RedmineDependingCustomFields
  FIELD_FORMAT_EXTENDED_USER = 'extended_user'
  FIELD_FORMAT_DEPENDING_LIST = 'depending_list'
  FIELD_FORMAT_DEPENDING_ENUMERATION = 'depending_enumeration'

  def self.register_formats
    Redmine::FieldFormat.add FIELD_FORMAT_EXTENDED_USER, ExtendedUserFormat do |format|
      format.label = :label_extended_user
      format.order = 8
      format.edit_as = 'user'
    end

    Redmine::FieldFormat.add FIELD_FORMAT_DEPENDING_LIST, DependingListFormat do |format|
      format.label = :label_depending_list
      format.order = 9
      format.edit_as = 'list'
    end

    Redmine::FieldFormat.add FIELD_FORMAT_DEPENDING_ENUMERATION, DependingEnumerationFormat do |format|
      format.label = :label_depending_enumeration
      format.order = 10
      format.edit_as = 'enumeration'
    end
  end

end
