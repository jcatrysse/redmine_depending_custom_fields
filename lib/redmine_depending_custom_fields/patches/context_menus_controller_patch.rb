# Patch that removes depending custom fields from the default issue context menu
# and cleans up grouped user options. The fields to hide come from the
# per-request SelectionGraph of the selected issues (WP-15, no cache).

module RedmineDependingCustomFields
  module Patches
    module ContextMenusControllerPatch
      def render(*args, **kwargs, &block)
        if respond_to?(:params) && issue_context_menu_request?
          begin
            filter_depending_custom_fields
            remove_illegal_user_values
          rescue => e
            Rails.logger.warn "[DCF] context menu filtering failed: #{e.class} - #{e.message}"
          end
        end
        super
      end

      private

      # Redmine 5.x/6.x route the issue context menu through
      # ContextMenusController#issues, while Redmine 7.0 uses the namespaced
      # ContextMenus::IssuesController#index. Match both so the filtering runs
      # regardless of the running version.
      def issue_context_menu_request?
        (params[:controller] == 'context_menus' && params[:action] == 'issues') ||
          (params[:controller] == 'context_menus/issues' && params[:action] == 'index')
      end

      # One graph per request, shared with ContextMenuHook.
      def dcf_selection_graph
        @dcf_selection_graph ||= SelectionGraph.new(Array(@issues))
      end

      # Hides the children with an effective parent that are available on the
      # selection, and their parents. Nothing to do (and no graph) without
      # core submenus: no edit permission, a closed project, an error page.
      def filter_depending_custom_fields
        options = instance_variable_defined?(:@options_by_custom_field) ? @options_by_custom_field : nil
        return if options.blank? || !options.respond_to?(:reject!)

        hidden = dcf_selection_graph.hidden_field_ids
        options.reject! { |field, _| hidden.include?(field.id) }
      end

      def remove_illegal_user_values
        return unless instance_variable_defined?(:@options_by_custom_field)

        @options_by_custom_field.each do |cf, values|
          next unless values.respond_to?(:reject!)

          values.reject! do |entry|
            entry.is_a?(Array) && entry[1].to_s.starts_with?('__group_')
          end
        end
      end
    end
  end
end
