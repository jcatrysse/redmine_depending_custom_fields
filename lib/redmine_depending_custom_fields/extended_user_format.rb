# frozen_string_literal: true

module RedmineDependingCustomFields
  class ExtendedUserFormat < Redmine::FieldFormat::UserFormat
    add 'extended_user'
    self.form_partial = 'custom_fields/formats/extended_user'
    field_attributes :group_ids, :exclude_admins, :show_active, :show_registered, :show_locked

    # Use User as target class so the field supports sorting and grouping
    def target_class
      User
    end

    def label
      :label_extended_user
    end

    def edit_as
      'user'
    end

    BOOLEAN = ActiveModel::Type::Boolean.new
    private_constant :BOOLEAN

    def boolean(value)
      BOOLEAN.cast(value)
    end

    def possible_values_options(custom_field, object = nil)
      users = filtered_users(custom_field)
      show_active     = boolean(custom_field.show_active)
      show_registered = boolean(custom_field.show_registered)
      show_locked     = boolean(custom_field.show_locked)

      active_users     = show_active ? users.where(status: User::STATUS_ACTIVE) : User.none
      registered_users = show_registered ? users.where(status: User::STATUS_REGISTERED) : User.none
      inactive_users   = show_locked ? users.where(status: User::STATUS_LOCKED) : User.none

      visible_users = active_users.to_a + registered_users.to_a + inactive_users.to_a

      options = []
      if active_users.any?
        options << [::I18n.t(:status_active), '', {disabled: true, class: 'option-group', style: 'font-weight:bold;'}]
        options += active_users.sorted.map { |u| [u.name, u.id.to_s] }
      end
      if registered_users.any?
        options << [::I18n.t(:status_registered), '', {disabled: true, class: 'option-group', style: 'font-weight:bold;'}]
        options += registered_users.sorted.map { |u| [u.name, u.id.to_s] }
      end
      if inactive_users.any?
        options << [::I18n.t(:status_locked), '', {disabled: true, class: 'option-group', style: 'font-weight:bold;'}]
        options += inactive_users.sorted.map { |u| [u.name, u.id.to_s] }
      end
      options = [["<< #{::I18n.t(:label_me)} >>", User.current.id]] + options if visible_users.include?(User.current)
      options
    end

    def query_filter_values(custom_field, query)
      users = filtered_users(custom_field)
      show_active     = boolean(custom_field.show_active)
      show_registered = boolean(custom_field.show_registered)
      show_locked     = boolean(custom_field.show_locked)

      options = []
      options += users.where(status: User::STATUS_ACTIVE).sorted.map { |u| [u.name, u.id.to_s, ::I18n.t('status_active')] } if show_active
      options += users.where(status: User::STATUS_REGISTERED).sorted.map { |u| [u.name, u.id.to_s, ::I18n.t('status_registered')] } if show_registered
      options += users.where(status: User::STATUS_LOCKED).sorted.map { |u| [u.name, u.id.to_s, ::I18n.t('status_locked')] } if show_locked

      visible_users = []
      visible_users += users.where(status: User::STATUS_ACTIVE).to_a if show_active
      visible_users += users.where(status: User::STATUS_REGISTERED).to_a if show_registered
      visible_users += users.where(status: User::STATUS_LOCKED).to_a if show_locked
      if visible_users.include?(User.current)
        options.unshift ["<< #{::I18n.t(:label_me)} >>", User.current.id.to_s]
      end
      options
    end

    def before_custom_field_save(custom_field)
      super
      custom_field.group_ids     = Array(custom_field.group_ids).reject(&:blank?).map(&:to_s)
      custom_field.exclude_admins = boolean(custom_field.exclude_admins)
      custom_field.show_active     = boolean(custom_field.show_active)
      custom_field.show_registered = boolean(custom_field.show_registered)
      custom_field.show_locked     = boolean(custom_field.show_locked)
    end

    private

    def filtered_users(custom_field)
      users = User.all
      group_ids = Array(custom_field.group_ids).reject(&:blank?).map(&:to_i)
      users = users.joins(:groups).where(groups: { id: group_ids }).distinct if group_ids.any?
      users = users.where(admin: false) if boolean(custom_field.exclude_admins)
      users
    end

    def cast_single_value(custom_field, value, customized = nil)
      User.find_by_id(value.to_i)
    end

    def validate_single_value(custom_field, value, customized)
      u = cast_single_value(custom_field, value, customized)
      u ? [] : [::I18n.t('activerecord.errors.messages.invalid')]
    end

    def value_to_s(custom_field, value, customized = nil)
      user = cast_single_value(custom_field, value, customized)
      user.nil? ? '' : user.name
    end
  end
end
