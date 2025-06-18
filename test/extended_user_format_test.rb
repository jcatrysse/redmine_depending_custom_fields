require_relative 'test_helper'

class ExtendedUserFormatTest < ActiveSupport::TestCase
  def setup
    @plugin_settings = Setting.plugin_redmine_depending_custom_fields
  end

  def teardown
    Setting.plugin_redmine_depending_custom_fields = @plugin_settings
  end

  def test_format_registered_when_enabled
    Setting.plugin_redmine_depending_custom_fields = {'enabled_formats' => [RedmineDependingCustomFields::FIELD_FORMAT_USER]}
    RedmineDependingCustomFields.register_formats
    assert_includes Redmine::FieldFormat.available_formats, RedmineDependingCustomFields::FIELD_FORMAT_USER
  end

  def test_format_not_registered_when_disabled
    Setting.plugin_redmine_depending_custom_fields = {'enabled_formats' => []}
    RedmineDependingCustomFields.register_formats
    assert_not_includes Redmine::FieldFormat.available_formats, RedmineDependingCustomFields::FIELD_FORMAT_USER
  end
end
