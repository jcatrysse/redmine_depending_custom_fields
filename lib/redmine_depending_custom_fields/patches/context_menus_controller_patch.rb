# Patch that removes depending custom fields from the default issue context menu
# and cleans up grouped user options. It delegates to MappingBuilder to know
# which fields to hide.

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

      def filter_depending_custom_fields
        mapping = Rails.cache.fetch('depending_custom_fields/mapping') { MappingBuilder.build }
        ids = (mapping.keys + mapping.values.map { |v| v[:parent_id] }).map(&:to_i).uniq

        if instance_variable_defined?(:@custom_fields) && @custom_fields
          @custom_fields = @custom_fields.reject { |cf| ids.include?(cf.id) }
        end

        if instance_variable_defined?(:@options_by_custom_field) &&
           @options_by_custom_field.respond_to?(:reject!)
          @options_by_custom_field.reject! { |field, _| ids.include?(field.id) }
        end
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
