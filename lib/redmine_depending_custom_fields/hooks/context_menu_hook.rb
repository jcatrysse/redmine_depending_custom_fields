# View hook that injects a mini wizard for depending custom fields into the
# issue context menu. Only shown when the current user is allowed to edit all
# selected issues.

module RedmineDependingCustomFields
  module Hooks
    class ContextMenuHook < Redmine::Hook::ViewListener
      def view_issues_context_menu_end(ctx = {})
        issues  = Array(ctx[:issues])
        user    = ctx[:controller].try(:current_user) || User.current

        return if issues.any? {|issue| !user.allowed_to?(:edit_issues, issue.project)}

        parents = ParentMenuBuilder.build(issues)
        mapping = Rails.cache.fetch('depending_custom_fields/mapping') do
          MappingBuilder.build
        end
        parent_ids   = parents.map { |p| p[:id].to_i }
        field_ids    = (parent_ids + mapping.keys.map(&:to_i) +
                        mapping.values.map { |v| v[:parent_id].to_i }).uniq
        fields_by_id = CustomField.where(id: field_ids).index_by(&:id)

        view_context = ctx[:controller].view_context
        view_context.extend(CustomFieldsHelper)
        view_context.extend(ContextMenuWizardHelper)

        view_context.render(
          partial: 'depending_custom_fields/context_menu_wizard',
          collection: parents,
          as: :parent,
          locals: { issues: issues, mapping: mapping, fields_by_id: fields_by_id }
        )
      end
    end
  end
end
