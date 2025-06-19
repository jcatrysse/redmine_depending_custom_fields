require_relative 'test_helper'

class ExtendedUserFormatTest < ActiveSupport::TestCase
  def setup
    @plugin_settings = Setting.plugin_redmine_depending_custom_fields
  end

  def teardown
    Setting.plugin_redmine_depending_custom_fields = @plugin_settings
  end

  def test_format_registered_when_enabled
    Setting.plugin_redmine_depending_custom_fields = {'enabled_formats' => [RedmineDependingCustomFields::FIELD_FORMAT_EXTENDED_USER]}
    RedmineDependingCustomFields.register_formats
    assert_includes Redmine::FieldFormat.available_formats, RedmineDependingCustomFields::FIELD_FORMAT_EXTENDED_USER
  end

  def test_format_not_registered_when_disabled
    Setting.plugin_redmine_depending_custom_fields = {'enabled_formats' => []}
    RedmineDependingCustomFields.register_formats
    assert_not_includes Redmine::FieldFormat.available_formats, RedmineDependingCustomFields::FIELD_FORMAT_EXTENDED_USER
  end


  def test_active_users_returned_when_show_active_enabled
    field = UserCustomField.new(field_format: RedmineDependingCustomFields::FIELD_FORMAT_EXTENDED_USER,
                                show_active: true,
                                show_registered: false,
                                show_locked: false,
                                exclude_admins: false,
                                group_ids: [])
    format = RedmineDependingCustomFields::ExtendedUserFormat.new
    options = format.possible_values_options(field)
    ids = options.select {|o| o.is_a?(Array) && o.size >= 2 && o[1].present?}.map {|o| o[1]}
    assert_includes ids, User.where(status: User::STATUS_ACTIVE).first.id.to_s
  end

  def test_query_filter_values_returns_active_users_when_show_active_enabled
    field = UserCustomField.new(field_format: RedmineDependingCustomFields::FIELD_FORMAT_EXTENDED_USER,
                                show_active: true,
                                show_registered: false,
                                show_locked: false,
                                exclude_admins: false,
                                group_ids: [])
    format = RedmineDependingCustomFields::ExtendedUserFormat.new
    values = format.query_filter_values(field, nil)
    ids = values.map {|v| v[1]}
    assert_includes ids, User.where(status: User::STATUS_ACTIVE).first.id.to_s
  end
end
