# frozen_string_literal: true

require 'set'

module RedmineDependingCustomFields
  # Wizard roots and levels of the issue context menu (server design 7.5,
  # WP-15). A field is offered only when the user may edit it on every
  # selected issue: available, visible for the user's roles (core
  # visible_by?) and not read-only by workflow, which equals core
  # editable_custom_fields(user). Below a field that is not offered nothing
  # is offered (fail closed). Any error hides the field (SP-10).
  #
  # Class methods only: memos are local Hashes of one call. Availability and
  # visibility are kept per [field, project, tracker] (SP-08), the read-only
  # names per [project, tracker, status], since workflow rules depend on the
  # status.
  class ParentDetector
    PARENT_FORMATS = DependencyRules::ALL_PARENT_FORMATS

    def self.for_issues(issues, graph: nil, user: User.current)
      issues = Array(issues).compact
      return [] if issues.empty?

      graph ||= SelectionGraph.new(issues)
      memo = {}
      graph.root_parent_ids.filter_map { |id| graph.field(id) }
           .select { |cf| PARENT_FORMATS.include?(cf.field_format) && usable_on_all?(cf, issues, user, memo) }
           .sort_by { |cf| [cf.position || 0, cf.id] }
    end

    # Level by level from +root+; the next level comes from the kept fields
    # only. The visited Set ends the walk on any stored data.
    def self.wizard_levels(root, issues, graph:, user: User.current)
      issues = Array(issues).compact
      levels = []
      visited = Set.new
      memo = {}
      current = [root]
      until current.empty?
        level = current.select { |cf| visited.add?(cf.id) && usable_on_all?(cf, issues, user, memo) }
        break if level.empty?

        levels << level
        current = level.flat_map { |cf| graph.children_of(cf.id) }
      end
      levels
    end

    def self.usable_on_all?(cf, issues, user, memo = {})
      issues.all? do |issue|
        key = [cf.id, issue.project_id, issue.tracker_id]
        visible = memo.key?(key) ? memo[key] : (memo[key] = usable_on?(cf, issue, user))
        visible && editable_on?(cf, issue, user, memo)
      end
    end

    def self.usable_on?(cf, issue, user)
      issue.available_custom_fields.include?(cf) && cf.visible_by?(issue.project, user)
    rescue StandardError => e
      log_failure(cf, e)
      false
    end

    # Not read-only by workflow on +issue+. nil names (a failed lookup) hide
    # every field.
    def self.editable_on?(cf, issue, user, memo)
      key = [:read_only, issue.project_id, issue.tracker_id, issue.status_id]
      unless memo.key?(key)
        memo[key] = begin
          read_only_names(issue, user)
        rescue StandardError => e
          log_failure(cf, e)
          nil
        end
      end
      !memo[key].nil? && !memo[key].include?(cf.id.to_s)
    end

    # Without a user argument core reuses the rules it memoized on the issue
    # for the current user (the context menu already loaded them).
    def self.read_only_names(issue, user)
      user == User.current ? issue.read_only_attribute_names : issue.read_only_attribute_names(user)
    end

    def self.log_failure(cf, error)
      Rails.logger.warn("[DCF] wizard visibility check failed for custom field ##{cf.id}: #{error.class}")
    end

    private_class_method :editable_on?, :read_only_names, :log_failure
  end
end
