# frozen_string_literal: true

require_relative '../rails_helper'
require 'ripper'
require 'timeout'

# WP-15: wizard roots and levels from the selection graph (server design 7.5)
# with real records. A field is offered only when every selected issue lets
# the user edit it (available, visible for the user's roles, not read-only by
# workflow), like core editable_custom_fields; below a field that is not
# offered nothing is offered (fail closed). Rewritten from the 0.0.16 spec,
# which stubbed Rails.cache and CustomField.where.
RSpec.describe RedmineDependingCustomFields::ParentDetector do
  include DcfStoredCycle

  fixtures :users

  let(:project) { dcf_create_project }
  let(:role) { dcf_create_role(permissions: [:view_issues, :edit_issues]) }
  let(:other_role) { dcf_create_role(permissions: [:view_issues, :edit_issues]) }
  let(:user) { member_of(project) }
  let(:tracker) { dcf_tracker }
  let(:other_status) { dcf_issue_status }

  before { allow(User).to receive(:current).and_return(user) }

  def member_of(target, member_role = role)
    member = dcf_create_user("pd-#{SecureRandom.hex(3)}")
    dcf_add_member(member, target, member_role)
    member
  end

  def priority
    IssuePriority.first || IssuePriority.create!(name: 'Normal')
  end

  def enable(*fields, on: tracker, target: project)
    target.trackers << on unless target.trackers.include?(on)
    fields.each { |field| on.custom_fields << field unless on.custom_fields.include?(field) }
  end

  # A persisted issue, reloaded so it carries no memoized state.
  def issue(status: nil, on: tracker, target: project)
    target.trackers << on unless target.trackers.include?(on)
    record = Issue.new(project: target, tracker: on, subject: 'S', author: dcf_admin,
                       status: status || on.default_status, priority: priority)
    record.save!(validate: false)
    Issue.find(record.id)
  end

  def depending(parent, name: nil)
    dcf_list_field(format: 'depending_list', values: %w[v1 v2], parent: parent, name: name)
  end

  # A list root with one depending child, both enabled on the tracker.
  def root_with_child(position: :keep)
    root = dcf_list_field
    child = depending(root)
    CustomField.where(id: root.id).update_all(position: position) unless position == :keep
    enable(root, child)
    root
  end

  def read_only(field, status, rule_role: role)
    WorkflowPermission.create!(tracker_id: tracker.id, old_status_id: status.id, role_id: rule_role.id,
                               field_name: field.id.to_s, rule: 'readonly')
  end

  def ids(fields)
    fields.map(&:id)
  end

  def level_ids(levels)
    levels.map { |level| ids(level) }
  end

  def graph_for(issues)
    RedmineDependingCustomFields::SelectionGraph.new(issues)
  end

  describe '.for_issues' do
    it 'returns no root for no issues' do
      expect(described_class.for_issues([])).to eq([])
      expect(described_class.for_issues(nil)).to eq([])
      expect(described_class.for_issues([nil])).to eq([])
    end

    it 'keeps its positional signature and orders the roots by position (nil as 0) and id' do
      late = root_with_child(position: 5)
      first = root_with_child(position: nil)
      tie_a = root_with_child(position: 2)
      tie_b = root_with_child(position: 2)

      expect(ids(described_class.for_issues([issue, issue]))).to eq([first.id, tie_a.id, tie_b.id, late.id])
    end

    it 'excludes a root that is not available on every selected issue' do
      root = dcf_list_field
      child = depending(root)
      enable(root, child)
      other = dcf_tracker
      enable(child, on: other)
      on_both = [issue, issue(on: other)]

      expect(described_class.for_issues(on_both)).to eq([])
      expect(ids(described_class.for_issues([on_both.first]))).to eq([root.id])
    end

    it 'excludes a root outside the selection (no field in the graph)' do
      enable(depending(dcf_list_field))

      expect(described_class.for_issues([issue])).to eq([])
    end

    it 'includes a depending root whose own parent was deleted' do
      root = dcf_store_parent(dcf_list_field(format: 'depending_list', values: %w[r1]), CustomField.maximum(:id).to_i + 1_000)
      enable(root, depending(root))

      expect(ids(described_class.for_issues([issue]))).to eq([root.id])
    end

    it 'excludes a root hidden for the user roles (core visible_by?) and offers it to an administrator' do
      root = root_with_child
      root.update!(visible: false, role_ids: [other_role.id])
      issues = [issue]

      expect(described_class.for_issues(issues)).to eq([])
      expect(ids(described_class.for_issues(issues, user: dcf_admin))).to eq([root.id])
    end

    it 'excludes a root that is read-only by workflow on any selected issue, whatever the order' do
      root = root_with_child
      first = issue
      second = issue(status: other_status)
      read_only(root, other_status)

      expect(described_class.for_issues([first, second])).to eq([])
      expect(described_class.for_issues([second, first])).to eq([])
      expect(ids(described_class.for_issues([first]))).to eq([root.id])
    end

    it 'offers exactly the roots core lets the user edit on every selected issue' do
      plain = root_with_child
      workflow = root_with_child
      hidden = root_with_child
      hidden.update!(visible: false, role_ids: [other_role.id])
      status_only = root_with_child
      Role.non_member.update!(permissions: [:view_issues, :edit_issues])
      [tracker.default_status, other_status].each do |status|
        Role.all.select(&:consider_workflow?).each { |workflow_role| read_only(workflow, status, rule_role: workflow_role) }
      end
      read_only(status_only, other_status)
      stranger = dcf_create_user("stranger-#{SecureRandom.hex(3)}")
      roots = [plain, workflow, hidden, status_only]
      issue_ids = [issue.id, issue(status: other_status).id]

      offered = [user, dcf_admin, stranger].map do |someone|
        allow(User).to receive(:current).and_return(someone)
        ids(described_class.for_issues(Issue.where(id: issue_ids).to_a, user: someone))
      end
      expected = [user, dcf_admin, stranger].map do |someone|
        fresh = Issue.where(id: issue_ids).to_a
        ids(roots.select { |root| fresh.all? { |i| i.editable_custom_fields(someone).include?(root) } })
      end

      expect(offered).to eq(expected)
      expect(offered).to eq([[plain.id], [plain.id, hidden.id, status_only.id], [plain.id, status_only.id]])
    end

    it 'applies the workflow rules of the given user, not those of User.current' do
      root = root_with_child
      read_only(root, other_status)
      other = member_of(project, other_role)
      issue_ids = [issue(status: other_status).id, issue(status: other_status).id]
      oracle = lambda do |someone|
        Issue.where(id: issue_ids).to_a.all? { |i| i.editable_custom_fields(someone).include?(root) }
      end
      expect([oracle.call(other), oracle.call(user)]).to eq([true, false])

      allow(User).to receive(:current).and_return(user)
      expect(ids(described_class.for_issues(Issue.where(id: issue_ids).to_a, user: other))).to eq([root.id])
      allow(User).to receive(:current).and_return(other)
      expect(described_class.for_issues(Issue.where(id: issue_ids).to_a, user: user)).to eq([])
    end

    it 'fails closed when visible_by? raises: the field is hidden and only its id and the error class are logged' do
      root = root_with_child
      issues = [issue, issue]
      graph = graph_for(issues)
      field = graph.field(root.id)
      allow(field).to receive(:visible_by?).and_raise(ActiveRecord::StatementInvalid, 'SELECT secret_value')
      allow(Rails.logger).to receive(:warn)
      message = "[DCF] wizard visibility check failed for custom field ##{root.id}: ActiveRecord::StatementInvalid"

      expect(described_class.for_issues(issues, graph: graph)).to eq([])
      expect(Rails.logger).to have_received(:warn).with(message).once
      expect(described_class.wizard_levels(field, issues, graph: graph)).to eq([])
      expect(Rails.logger).to have_received(:warn).with(message).twice
      expect(Rails.logger).not_to have_received(:warn).with(/secret_value/)
    end

    it 'checks visibility once per field, project and tracker, whatever the number of issues or statuses' do
      root = root_with_child
      issues = [issue, issue(status: other_status), issue]
      graph = graph_for(issues)
      expect(graph.field(root.id)).to receive(:visible_by?).once.and_call_original

      expect(ids(described_class.for_issues(issues, graph: graph))).to eq([root.id])
    end

    it 'checks visibility once per project for issues of two projects' do
      root = root_with_child
      second_project = dcf_create_project
      dcf_add_member(user, second_project, role)
      issues = [issue, issue(target: second_project), issue, issue(target: second_project)]
      graph = graph_for(issues)
      expect(graph.field(root.id)).to receive(:visible_by?).twice.and_call_original

      expect(ids(described_class.for_issues(issues, graph: graph))).to eq([root.id])
    end

    it 'adds the same queries for 1 and 10 issues once core loaded their editable fields' do
      root_with_child
      read_only(dcf_list_field, other_status)
      counts = [1, 10].map do |n|
        issues = Array.new(n) { issue }
        issues.each(&:editable_custom_fields)
        dcf_count_queries do
          graph = graph_for(issues)
          described_class.for_issues(issues, graph: graph).each do |found|
            described_class.wizard_levels(found, issues, graph: graph)
          end
        end
      end

      expect(counts.uniq.size).to eq(1)
    end

    # WP-18: MappingBuilder is deleted (UD-14); its not_to receive line is gone.
    it 'uses no cache and no CustomField query' do
      root = root_with_child
      issues = [issue]
      issues.each(&:editable_custom_fields)
      expect(Rails.cache).not_to receive(:fetch)
      expect(CustomField).not_to receive(:where)

      expect(ids(described_class.for_issues(issues))).to eq([root.id])
    end
  end

  describe '.wizard_levels' do
    let(:parent) { dcf_list_field }
    let(:child) { depending(parent) }
    let(:grandchild) { depending(child) }

    before { enable(parent, child, grandchild) }

    def levels_for(issues)
      graph = graph_for(issues)
      level_ids(described_class.wizard_levels(graph.field(parent.id), issues, graph: graph))
    end

    it 'walks the chain level by level' do
      expect(levels_for([issue, issue(status: other_status)])).to eq([[parent.id], [child.id], [grandchild.id]])
    end

    it 'offers nothing below a child that is read-only on one selected issue (fail closed)' do
      read_only(child, other_status)

      expect(levels_for([issue, issue(status: other_status)])).to eq([[parent.id]])
      expect(levels_for([issue])).to eq([[parent.id], [child.id], [grandchild.id]])
    end

    it 'stops below a grandchild that is read-only on one selected issue' do
      read_only(grandchild, other_status)

      expect(levels_for([issue(status: other_status), issue])).to eq([[parent.id], [child.id]])
    end

    it 'offers nothing below a child hidden for the user roles' do
      child.update!(visible: false, role_ids: [other_role.id])

      expect(levels_for([issue])).to eq([[parent.id]])
    end

    it 'is empty for a root the user cannot edit on every issue' do
      read_only(parent, other_status)

      expect(levels_for([issue, issue(status: other_status)])).to eq([])
    end

    it 'terminates on an injected cycle and lists each field once' do
      first = dcf_list_field
      second = dcf_list_field
      enable(first, second)
      issues = [issue]
      graph = double('graph')
      allow(graph).to receive(:children_of) { |id| id == first.id ? [second, first] : [first, second] }

      levels = Timeout.timeout(2) { described_class.wizard_levels(first, issues, graph: graph) }
      expect(level_ids(levels)).to eq([[first.id], [second.id]])

      allow(graph).to receive(:children_of).and_return([first])
      expect(level_ids(Timeout.timeout(2) { described_class.wizard_levels(first, issues, graph: graph) }))
        .to eq([[first.id]])
    end
  end

  describe 'state' do
    # Same detection as spec/quality/format_singleton_state_spec.rb: names of
    # assigned instance, class and global variables.
    def state_writes(path)
      found = []
      walk = lambda do |node|
        next unless node.is_a?(Array)

        if node[0] == :var_field && node[1].is_a?(Array) && [:@ivar, :@cvar, :@gvar].include?(node[1][0])
          found << node[1][1]
        end
        node.each { |child_node| walk.call(child_node) }
      end
      walk.call(Ripper.sexp(File.read(path)))
      found
    end

    it 'keeps no state in ParentDetector or in the context menu hook (process-wide singleton)' do
      root = File.expand_path('../..', __dir__)
      %w[app/models/redmine_depending_custom_fields/parent_detector.rb
         lib/redmine_depending_custom_fields/hooks/context_menu_hook.rb].each do |path|
        expect(state_writes(File.join(root, path))).to eq([]), path
      end
      root_with_child
      described_class.for_issues([issue])
      expect(described_class.instance_variables).to eq([])
    end
  end
end
