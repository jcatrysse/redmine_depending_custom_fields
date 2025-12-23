# frozen_string_literal: true

# Field format that builds on Redmine's user custom field but adds
# filtering options. Administrators can restrict the selectable users by
# group membership, status and whether administrators should appear.

module RedmineDependingCustomFields
  class ExtendedUserFormat < Redmine::FieldFormat::UserFormat
    add 'extended_user'
    self.form_partial = 'custom_fields/formats/extended_user'
    field_attributes :group_ids, :exclude_admins, :show_active, :show_registered, :show_locked, :only_project_members

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
      BOOLEAN.cast(value) ? true : false
    end

    def possible_values_options(custom_field, object = nil)
      users = filtered_users(custom_field, project_from(object))
      show_active     = boolean(custom_field.show_active)
      show_registered = boolean(custom_field.show_registered)
      show_locked     = boolean(custom_field.show_locked)

      statuses = []
      statuses << User::STATUS_ACTIVE if show_active
      statuses << User::STATUS_REGISTERED if show_registered
      statuses << User::STATUS_LOCKED if show_locked

      visible_users = statuses.any? ? users.where(status: statuses).to_a : []
      users_by_status = visible_users.group_by(&:status)

      options = []
      if show_active && users_by_status[User::STATUS_ACTIVE].present?
        options << [::I18n.t(:status_active), '__group_active__', {disabled: true, class: 'option-group', style: 'font-weight:bold;'}]
        options += users_by_status[User::STATUS_ACTIVE].sort_by(&:name).map { |u| [u.name, u.id.to_s] }
      end
      if show_registered && users_by_status[User::STATUS_REGISTERED].present?
        options << [::I18n.t(:status_registered), '__group_registered__', {disabled: true, class: 'option-group', style: 'font-weight:bold;'}]
        options += users_by_status[User::STATUS_REGISTERED].sort_by(&:name).map { |u| [u.name, u.id.to_s] }
      end
      if show_locked && users_by_status[User::STATUS_LOCKED].present?
        options << [::I18n.t(:status_locked), '__group_locked__', {disabled: true, class: 'option-group', style: 'font-weight:bold;'}]
        options += users_by_status[User::STATUS_LOCKED].sort_by(&:name).map { |u| [u.name, u.id.to_s] }
      end
      options = [["<< #{::I18n.t(:label_me)} >>", User.current.id]] + options if visible_users.include?(User.current)
      options
    end

    def query_filter_values(custom_field, query)
      users = filtered_users(custom_field, query&.project)
      show_active     = boolean(custom_field.show_active)
      show_registered = boolean(custom_field.show_registered)
      show_locked     = boolean(custom_field.show_locked)

      statuses = []
      statuses << User::STATUS_ACTIVE if show_active
      statuses << User::STATUS_REGISTERED if show_registered
      statuses << User::STATUS_LOCKED if show_locked

      visible_users = statuses.any? ? users.where(status: statuses).sorted.to_a : []
      users_by_status = visible_users.group_by(&:status)

      options = []
      if show_active && users_by_status[User::STATUS_ACTIVE].present?
        options += users_by_status[User::STATUS_ACTIVE].map { |u| [u.name, u.id.to_s, ::I18n.t('status_active')] }
      end
      if show_registered && users_by_status[User::STATUS_REGISTERED].present?
        options += users_by_status[User::STATUS_REGISTERED].map { |u| [u.name, u.id.to_s, ::I18n.t('status_registered')] }
      end
      if show_locked && users_by_status[User::STATUS_LOCKED].present?
        options += users_by_status[User::STATUS_LOCKED].map { |u| [u.name, u.id.to_s, ::I18n.t('status_locked')] }
      end

      options.reject! { |opt| opt[1].blank? }
      options.unshift ["<< #{::I18n.t(:label_me)} >>", User.current.id.to_s] if visible_users.include?(User.current)
      options
    end

    def before_custom_field_save(custom_field)
      super
      custom_field.group_ids     = Array(custom_field.group_ids).reject(&:blank?).map(&:to_s)
      custom_field.exclude_admins = boolean(custom_field.exclude_admins)
      custom_field.show_active     = boolean(custom_field.show_active)
      custom_field.show_registered = boolean(custom_field.show_registered)
      custom_field.show_locked     = boolean(custom_field.show_locked)
      custom_field.only_project_members = boolean(custom_field.only_project_members)
    end

    private

    def filtered_users(custom_field, project = nil)
      users = User.all
      group_ids = Array(custom_field.group_ids).reject(&:blank?).map(&:to_i)
      users = users.joins(:groups).where(groups: { id: group_ids }).distinct if group_ids.any?
      users = users.where(admin: false) if boolean(custom_field.exclude_admins)
      if boolean(custom_field.only_project_members) && project
        users = users.joins(:members).where(members: { project_id: project.id }).distinct
      end
      users
    end

    def project_from(object)
      target = object.is_a?(Array) ? object.first : object
      target&.respond_to?(:project) ? target.project : nil
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
