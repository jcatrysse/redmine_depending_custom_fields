# frozen_string_literal: true

require 'redmine'
require_relative 'redmine_depending_custom_fields/extended_user_format'
require_relative 'redmine_depending_custom_fields/depending_list_format'
require_relative 'redmine_depending_custom_fields/depending_enumeration_format'
require_relative 'redmine_depending_custom_fields/hooks/view_layouts_base_html_head_hook'
require_relative 'redmine_depending_custom_fields/custom_field_visibility'
require_relative 'redmine_depending_custom_fields/field_index'
require_relative 'redmine_depending_custom_fields/dependency_rules'
require_relative 'redmine_depending_custom_fields/storage_limits'
require_relative 'redmine_depending_custom_fields/dependency_payload'
require_relative 'redmine_depending_custom_fields/dependency_editor_config'

module RedmineDependingCustomFields
  FIELD_FORMAT_EXTENDED_USER = 'extended_user'
  FIELD_FORMAT_DEPENDING_LIST = 'depending_list'
  FIELD_FORMAT_DEPENDING_ENUMERATION = 'depending_enumeration'
  # The posted dependency mapping (up to 4 MiB) stays out of the request log.
  # Anchored: value_dependencies and the other keys stay readable.
  LOG_FILTER = /\Adependencies_json\z/.freeze

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

  # Appends in place, because env_config keeps a reference to this Array, and
  # once, because plugin init runs again on every reload.
  def self.filter_request_log
    filters = Rails.application.config.filter_parameters
    filters << LOG_FILTER unless filters.include?(LOG_FILTER)
    filters
  end
end

RedmineDependingCustomFields.filter_request_log
