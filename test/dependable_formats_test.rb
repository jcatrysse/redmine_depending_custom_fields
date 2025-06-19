require_relative 'test_helper'

class DependableFormatsTest < ActiveSupport::TestCase
  def setup
    @plugin_settings = Setting.plugin_redmine_depending_custom_fields
  end

  def teardown
    Setting.plugin_redmine_depending_custom_fields = @plugin_settings
  end

  def test_list_format_registered_when_enabled
    Setting.plugin_redmine_depending_custom_fields = {'enabled_formats' => [RedmineDependingCustomFields::FIELD_FORMAT_DEPENDABLE_LIST]}
    RedmineDependingCustomFields.register_formats
    assert_includes Redmine::FieldFormat.available_formats, RedmineDependingCustomFields::FIELD_FORMAT_DEPENDABLE_LIST
  end

  def test_list_format_not_registered_when_disabled
    Setting.plugin_redmine_depending_custom_fields = {'enabled_formats' => []}
    RedmineDependingCustomFields.register_formats
    assert_not_includes Redmine::FieldFormat.available_formats, RedmineDependingCustomFields::FIELD_FORMAT_DEPENDABLE_LIST
  end

  def test_enumeration_format_registered_when_enabled
    Setting.plugin_redmine_depending_custom_fields = {'enabled_formats' => [RedmineDependingCustomFields::FIELD_FORMAT_DEPENDABLE_ENUMERATION]}
    RedmineDependingCustomFields.register_formats
    assert_includes Redmine::FieldFormat.available_formats, RedmineDependingCustomFields::FIELD_FORMAT_DEPENDABLE_ENUMERATION
  end

  def test_enumeration_format_not_registered_when_disabled
    Setting.plugin_redmine_depending_custom_fields = {'enabled_formats' => []}
    RedmineDependingCustomFields.register_formats
    assert_not_includes Redmine::FieldFormat.available_formats, RedmineDependingCustomFields::FIELD_FORMAT_DEPENDABLE_ENUMERATION
  end
end
