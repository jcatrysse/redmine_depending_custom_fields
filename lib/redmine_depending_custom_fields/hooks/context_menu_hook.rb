# View hook that injects a mini wizard for depending custom fields into the
# issue context menu. Only shown when the current user may edit the attributes
# of all selected issues, and only for fields the user may edit on all of them.
# The listener is a process-wide singleton: it keeps nothing between calls.

module RedmineDependingCustomFields
  module Hooks
    class ContextMenuHook < Redmine::Hook::ViewListener
      def view_issues_context_menu_end(ctx = {})
        issues  = Array(ctx[:issues])
        user    = ctx[:controller].try(:current_user) || User.current

        # Core's edit gate of the menu (@can[:edit]): the attributes of every
        # issue, tracker permissions included (full review of 2026-11-05,
        # context-menu-3); false on a closed project.
        return if issues.any? { |issue| !issue.attributes_editable?(user) }

        render_wizard(ctx[:controller], issues, user)
      rescue StandardError => e
        Rails.logger.warn("[DCF] context menu wizard failed: #{e.class}")
        nil
      end

      private

      def render_wizard(controller, issues, user)
        graph = selection_graph(controller, issues)
        parents = ParentDetector.for_issues(issues, graph: graph, user: user)
        return nil if parents.empty?

        view_context = controller.view_context
        view_context.extend(CustomFieldsHelper)
        view_context.extend(ContextMenuWizardHelper)

        view_context.render(
          partial: 'depending_custom_fields/context_menu_wizard',
          collection: parents,
          as: :parent_field,
          locals: { issues: issues, graph: graph, user: user }
        )
      end

      # The graph of the patched controller when it was built for the same
      # issues, otherwise a new one.
      def selection_graph(controller, issues)
        if controller.respond_to?(:dcf_selection_graph, true)
          graph = controller.send(:dcf_selection_graph)
          return graph if graph&.built_for?(issues)
        end
        SelectionGraph.new(issues)
      end
    end
  end
end
