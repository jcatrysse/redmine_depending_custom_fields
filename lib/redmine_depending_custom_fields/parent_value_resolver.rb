# frozen_string_literal: true

module RedmineDependingCustomFields
  class ParentValueResolver
    def self.values(customized, parent_reference)
      return [] unless customized && parent_reference

      if parent_reference.type == 'core_field'
        core_values(customized, parent_reference.key)
      else
        custom_field_values(customized, parent_reference.custom_field)
      end
    end

    def self.custom_field_values(customized, parent_field)
      return [] unless parent_field

      Array(customized.custom_field_value(parent_field)).map(&:to_s)
    end
    private_class_method :custom_field_values

    def self.core_values(customized, key)
      return [] if key.blank?

      value = case key.to_s
              when 'project_id'
                customized.respond_to?(:project_id) ? customized.project_id : nil
              when 'tracker_id'
                customized.respond_to?(:tracker_id) ? customized.tracker_id : nil
              when 'status_id'
                customized.respond_to?(:status_id) ? customized.status_id : nil
              when 'priority_id'
                customized.respond_to?(:priority_id) ? customized.priority_id : nil
              when 'assigned_to_id'
                customized.respond_to?(:assigned_to_id) ? customized.assigned_to_id : nil
              when 'author_id'
                customized.respond_to?(:author_id) ? customized.author_id : nil
              when 'category_id'
                customized.respond_to?(:category_id) ? customized.category_id : nil
              when 'fixed_version_id'
                customized.respond_to?(:fixed_version_id) ? customized.fixed_version_id : nil
              when 'subject'
                customized.respond_to?(:subject) ? customized.subject : nil
              when 'start_date'
                customized.respond_to?(:start_date) ? customized.start_date : nil
              when 'due_date'
                customized.respond_to?(:due_date) ? customized.due_date : nil
              when 'done_ratio'
                customized.respond_to?(:done_ratio) ? customized.done_ratio : nil
              else
                nil
              end

      value.present? ? [value.to_s] : []
    end
    private_class_method :core_values
  end
end
