# frozen_string_literal: true

# Field format that builds on Redmine's user custom field but adds
# filtering options. Administrators can restrict the selectable users by
# group membership, status and whether administrators should appear.

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
      BOOLEAN.cast(value) ? true : false
    end

    def possible_values_options(custom_field, object = nil)
      users = filtered_users(custom_field)
      show_active     = show_active?(custom_field)
      show_registered = boolean(custom_field.show_registered)
      show_locked     = boolean(custom_field.show_locked)
      statuses = statuses(custom_field)

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
      users = filtered_users(custom_field)
      show_active     = show_active?(custom_field)
      show_registered = boolean(custom_field.show_registered)
      show_locked     = boolean(custom_field.show_locked)
      statuses = statuses(custom_field)

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

    # The ids core's RecordList#validate_custom_value would accept, checked
    # with one query on the submitted ids instead of building every option
    # (full review of 2026-11-05, storage-api-boot-3): a user the field
    # offers (statuses, groups, administrators, visibility), or a stored
    # value of an existing user (value_was, as core). Anything else, a group
    # marker included, is 'is not included in the list'.
    def validate_custom_value(custom_value)
      values = Array.wrap(custom_value.value).map(&:to_s).reject(&:empty?)
      return [] if values.empty?

      cf = custom_value.custom_field
      ids = values.grep(/\A\d+\z/).map(&:to_i)
      allowed = statuses(cf).any? && ids.any? ? filtered_users(cf).where(status: statuses(cf), id: ids).pluck(:id) : []
      allowed = allowed.map(&:to_s)
      stored = Array.wrap(custom_value.value_was).map(&:to_s) & (values - allowed)
      allowed += User.where(id: stored.map(&:to_i)).pluck(:id).map(&:to_s) if stored.any?
      (values - allowed).empty? ? [] : [::I18n.t('activerecord.errors.messages.inclusion')]
    end

    # A missing show_active counts as true, as the admin form shows it
    # (full review of 2026-11-05, storage-api-boot-5: a field created
    # through the API without it listed nobody).
    def before_custom_field_save(custom_field)
      super
      custom_field.group_ids     = Array(custom_field.group_ids).reject(&:blank?).map(&:to_s)
      custom_field.exclude_admins = boolean(custom_field.exclude_admins)
      custom_field.show_active     = show_active?(custom_field)
      custom_field.show_registered = boolean(custom_field.show_registered)
      custom_field.show_locked     = boolean(custom_field.show_locked)
    end

    private

    def show_active?(custom_field)
      custom_field.show_active.nil? ? true : boolean(custom_field.show_active)
    end

    def statuses(custom_field)
      statuses = []
      statuses << User::STATUS_ACTIVE if show_active?(custom_field)
      statuses << User::STATUS_REGISTERED if boolean(custom_field.show_registered)
      statuses << User::STATUS_LOCKED if boolean(custom_field.show_locked)
      statuses
    end

    # Full review of 2026-11-05 (storage-api-boot-4): a viewer who is not an
    # administrator gets only the users core lets that viewer see (role
    # setting 'Users visibility', Principal.visible); its status rule is left
    # to the field, so locked and registered users stay as the field says.
    def filtered_users(custom_field, viewer = User.current)
      users = User.all
      group_ids = Array(custom_field.group_ids).reject(&:blank?).map(&:to_i)
      users = users.joins(:groups).where(groups: { id: group_ids }).distinct if group_ids.any?
      users = users.where(admin: false) if boolean(custom_field.exclude_admins)
      unless viewer.nil? || viewer.admin?
        users = users.where(id: Principal.visible(viewer).unscope(where: :status).select(:id))
      end
      users
    end
  end
end
