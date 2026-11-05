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

  # The format classes register themselves (add in their class bodies);
  # this registers the same instances again, for a reload. Core's
  # FieldFormat.add takes no block (5.1 to 7.0), so label, order and
  # edit_as come from the classes (full review of 2026-11-05,
  # storage-api-boot-6: the blocks never ran).
  def self.register_formats
    Redmine::FieldFormat.add FIELD_FORMAT_EXTENDED_USER, ExtendedUserFormat
    Redmine::FieldFormat.add FIELD_FORMAT_DEPENDING_LIST, DependingListFormat
    Redmine::FieldFormat.add FIELD_FORMAT_DEPENDING_ENUMERATION, DependingEnumerationFormat
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
