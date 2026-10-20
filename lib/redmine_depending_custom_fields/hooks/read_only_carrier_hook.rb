# frozen_string_literal: true

module RedmineDependingCustomFields
  module Hooks
    # UD-37 (WP-16): one hidden carrier per depending child the user sees
    # but cannot edit (ClientData.locked_children), in the form scope of the
    # issue form (inside #all_attributes, so updateIssueFrom re-renders it)
    # and the project form. No id, no name, not a form control, no text;
    # nothing for a child the user cannot see. Built with the view's tag
    # helpers (escaped once). A carrier never breaks the form. The listener
    # is a process-wide singleton: it keeps nothing between calls.
    class ReadOnlyCarrierHook < Redmine::Hook::ViewListener
      def view_issues_form_details_bottom(context = {})
        carriers(context[:hook_caller], context[:issue])
      end

      def view_projects_form(context = {})
        carriers(context[:hook_caller], context[:project])
      end

      private

      def carriers(view, record)
        return '' unless view.respond_to?(:content_tag) && record

        tags = ClientData.locked_children(record).map { |data| view.content_tag(:span, '', hidden: true, data: data) }
        view.safe_join(tags)
      rescue StandardError => e
        Rails.logger.warn("[DCF] read-only carrier skipped: #{e.class}")
        ''
      end
    end
  end
end
