# frozen_string_literal: true

module RedmineDependingCustomFields
  class ParentValueOptions
    CORE_FIELDS = {
      'project_id' => {
        label: :label_project,
        klass: -> { Project.visible(User.current).order(:name) },
        enumerated: true,
        format: 'list'
      },
      'tracker_id' => {
        label: :label_tracker,
        klass: -> { Tracker.sorted },
        enumerated: true,
        format: 'list'
      },
      'status_id' => {
        label: :field_status,
        klass: -> { IssueStatus.sorted },
        enumerated: true,
        format: 'list'
      },
      'priority_id' => {
        label: :field_priority,
        klass: -> { IssuePriority.active },
        enumerated: true,
        format: 'list'
      },
      'assigned_to_id' => {
        label: :field_assigned_to,
        klass: -> { Principal.active.order(:lastname, :firstname) },
        enumerated: true,
        format: 'list'
      },
      'author_id' => {
        label: :field_author,
        klass: -> { User.active.order(:lastname, :firstname) },
        enumerated: true,
        format: 'list'
      },
      'category_id' => {
        label: :field_category,
        klass: -> { IssueCategory.order(:name) },
        enumerated: true,
        format: 'list'
      },
      'fixed_version_id' => {
        label: :label_version,
        klass: -> { Version.visible(User.current).order(:name) },
        enumerated: true,
        format: 'list'
      },
      'subject' => {
        label: :field_subject,
        enumerated: false,
        format: 'string'
      },
      'start_date' => {
        label: :field_start_date,
        enumerated: false,
        format: 'date'
      },
      'due_date' => {
        label: :field_due_date,
        enumerated: false,
        format: 'date'
      },
      'done_ratio' => {
        label: :field_done_ratio,
        enumerated: false,
        format: 'int'
      }
    }.freeze

    def self.core_field_options
      CORE_FIELDS.map do |key, info|
        [I18n.t(info[:label], default: key.humanize), key]
      end
    end

    def self.enumerated_core_field?(key)
      info = CORE_FIELDS[key.to_s]
      info && info[:enumerated]
    end

    def self.core_field_values(key)
      info = CORE_FIELDS[key.to_s]
      return [] unless info && info[:enumerated]

      Array(info[:klass].call).map do |record|
        [record.respond_to?(:name) ? record.name : record.to_s, record.id.to_s]
      end
    end

    def self.core_field_format(key)
      info = CORE_FIELDS[key.to_s]
      info ? info[:format] : 'string'
    end
  end
end
