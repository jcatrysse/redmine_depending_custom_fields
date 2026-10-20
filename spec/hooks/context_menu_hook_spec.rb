require_relative '../rails_helper'

# WP-15: the hook no longer uses ParentMenuBuilder, MappingBuilder or
# Rails.cache (the old examples stubbed them). It reuses the selection graph
# of the patched controller, asks ParentDetector for the roots and renders
# nothing, without a view context, when there is none.
RSpec.describe RedmineDependingCustomFields::Hooks::ContextMenuHook do
  let(:hook) { described_class.send(:new) }
  let(:view_context) { double('view', extend: nil, render: 'wizard') }
  let(:controller) { double('controller', view_context: view_context, current_user: user) }
  let(:user) { instance_double(User) }
  let(:project1) { instance_double(Project) }
  let(:project2) { instance_double(Project) }
  let(:issue1) { instance_double(Issue, id: 1, project: project1) }
  let(:issue2) { instance_double(Issue, id: 2, project: project2) }
  let(:issues) { [issue1, issue2] }
  let(:graph) { instance_double('RedmineDependingCustomFields::SelectionGraph') }
  let(:root) { instance_double(CustomField, id: 10) }
  let(:graph_class) { RedmineDependingCustomFields::SelectionGraph }
  let(:detector) { RedmineDependingCustomFields::ParentDetector }

  # A controller with the private reader the patch adds.
  def patched_controller(controller_graph)
    klass = Class.new do
      def initialize(graph, view)
        @graph = graph
        @view = view
      end

      def view_context
        @view
      end

      private

      def dcf_selection_graph
        @graph
      end
    end
    klass.new(controller_graph, view_context)
  end

  def allow_edit(on = [project1, project2])
    on.each { |project| allow(user).to receive(:allowed_to?).with(:edit_issues, project).and_return(true) }
  end

  context 'when the user lacks the edit permission on one issue' do
    before do
      allow(user).to receive(:allowed_to?).with(:edit_issues, project1).and_return(true)
      allow(user).to receive(:allowed_to?).with(:edit_issues, project2).and_return(false)
    end

    it 'builds nothing and renders nothing' do
      expect(graph_class).not_to receive(:new)
      expect(detector).not_to receive(:for_issues)
      expect(controller).not_to receive(:view_context)

      expect(hook.view_issues_context_menu_end(issues: issues, controller: controller)).to be_nil
    end
  end

  context 'when the user may edit every issue' do
    before { allow_edit }

    it 'returns nil without a view context when there is no root' do
      allow(graph_class).to receive(:new).with(issues).and_return(graph)
      allow(detector).to receive(:for_issues).and_return([])
      expect(controller).not_to receive(:view_context)

      expect(hook.view_issues_context_menu_end(issues: issues, controller: controller)).to be_nil
    end

    it 'renders the wizard partial for the roots with the issues, the graph and the gate user' do
      allow(graph_class).to receive(:new).with(issues).and_return(graph)
      allow(detector).to receive(:for_issues).with(issues, graph: graph, user: user).and_return([root])
      expect(view_context).to receive(:extend).with(CustomFieldsHelper)
      expect(view_context).to receive(:extend).with(ContextMenuWizardHelper)
      expect(view_context).to receive(:render).with(
        partial: 'depending_custom_fields/context_menu_wizard',
        collection: [root],
        as: :parent_field,
        locals: { issues: issues, graph: graph, user: user }
      ).and_return('wizard')

      expect(hook.view_issues_context_menu_end(issues: issues, controller: controller)).to eq('wizard')
    end

    it 'reuses the graph of the patched controller when it was built for the same issues' do
      allow(User).to receive(:current).and_return(user)
      allow(graph).to receive(:built_for?).with(issues).and_return(true)
      expect(graph_class).not_to receive(:new)
      expect(detector).to receive(:for_issues).with(issues, graph: graph, user: user).and_return([])

      hook.view_issues_context_menu_end(issues: issues, controller: patched_controller(graph))
    end

    it 'builds its own graph when the controller graph belongs to another selection' do
      allow(User).to receive(:current).and_return(user)
      other = instance_double('RedmineDependingCustomFields::SelectionGraph')
      allow(other).to receive(:built_for?).with([issue2]).and_return(false)
      expect(graph_class).to receive(:new).with([issue2]).and_return(graph)
      expect(detector).to receive(:for_issues).with([issue2], graph: graph, user: user).and_return([])

      hook.view_issues_context_menu_end(issues: [issue2], controller: patched_controller(other))
    end

    it 'builds its own graph when a real controller graph was built for other issues' do
      allow(User).to receive(:current).and_return(user)
      other = graph_class.new([issue1])
      expect(graph_class).to receive(:new).with(issues).and_return(graph)
      expect(detector).to receive(:for_issues).with(issues, graph: graph, user: user).and_return([])

      hook.view_issues_context_menu_end(issues: issues, controller: patched_controller(other))
    end

    it 'builds its own graph when the controller has no graph' do
      allow(User).to receive(:current).and_return(user)
      expect(graph_class).to receive(:new).with(issues).and_return(graph)
      allow(detector).to receive(:for_issues).and_return([])

      hook.view_issues_context_menu_end(issues: issues, controller: patched_controller(nil))
    end

    it 'fails closed: renders no wizard and logs only the error class' do
      allow(graph_class).to receive(:new).and_return(graph)
      allow(detector).to receive(:for_issues).and_raise(RuntimeError, 'secret value')
      allow(Rails.logger).to receive(:warn)
      expect(controller).not_to receive(:view_context)

      expect(hook.view_issues_context_menu_end(issues: issues, controller: controller)).to be_nil
      expect(Rails.logger).to have_received(:warn).with('[DCF] context menu wizard failed: RuntimeError').once
    end

    it 'keeps no state on the process-wide listener' do
      allow(graph_class).to receive(:new).and_return(graph)
      allow(detector).to receive(:for_issues).and_return([root])

      before = hook.instance_variables
      hook.view_issues_context_menu_end(issues: issues, controller: controller)
      expect(hook.instance_variables).to eq(before)
    end
  end
end
