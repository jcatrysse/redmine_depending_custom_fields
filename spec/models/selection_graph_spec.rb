# frozen_string_literal: true

require_relative '../rails_helper'

# WP-15: the per-request topology of the issue context menu (server design
# 7.2). Candidates are the union of the selected objects' available custom
# fields; children are the depending candidates with an effective parent.
RSpec.describe RedmineDependingCustomFields::SelectionGraph do
  include DcfStoredCycle

  fixtures :users

  let(:project) { dcf_create_project }

  def priority
    IssuePriority.first || IssuePriority.create!(name: 'Normal')
  end

  # A new tracker of the project with +fields+ enabled.
  def tracker_with(*fields)
    tracker = dcf_tracker
    project.trackers << tracker unless project.trackers.include?(tracker)
    fields.each { |field| tracker.custom_fields << field }
    tracker
  end

  # A persisted issue of +tracker+, reloaded: nothing of it is loaded yet.
  def issue_on(tracker)
    issue = Issue.new(project: project, tracker: tracker, subject: 'S', author: dcf_admin,
                      status: tracker.default_status, priority: priority)
    issue.save!(validate: false)
    Issue.find(issue.id)
  end

  def issues_with(*fields)
    [issue_on(tracker_with(*fields))]
  end

  def depending(parent, type: IssueCustomField)
    dcf_list_field(format: 'depending_list', values: %w[v1 v2], parent: parent, type: type)
  end

  def missing_id
    CustomField.maximum(:id).to_i + 1_000
  end

  # Raw selects of the topology helper (FieldIndex::QUERY_NAME) in the block.
  def field_index_queries(&block)
    count = 0
    callback = lambda do |*, payload|
      count += 1 if payload[:name] == RedmineDependingCustomFields::FieldIndex::QUERY_NAME
    end
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &block)
    count
  end

  describe '.new' do
    it 'accepts nil, nil entries and any collection, without a query' do
      issues = issues_with(dcf_list_field)

      expect(described_class.new(nil).candidate_fields).to eq([])
      expect(described_class.new([issues.first, nil]).candidate_fields.map(&:id))
        .to eq(issues.first.available_custom_fields.map(&:id))
      expect(dcf_count_queries { described_class.new(issues) }).to eq(0)
    end
  end

  describe '#candidate_fields' do
    it 'is the union of the available custom fields of the selection, each id once, first instance kept' do
      shared = dcf_list_field
      only_a = dcf_list_field
      only_b = dcf_list_field
      on_a = issue_on(tracker_with(shared, only_a))
      on_b = issue_on(tracker_with(shared, only_b))
      graph = described_class.new([on_a, on_b])

      expect(graph.candidate_fields.map(&:id)).to contain_exactly(shared.id, only_a.id, only_b.id)
      expect(graph.field(shared.id)).to equal(on_a.available_custom_fields.detect { |f| f.id == shared.id })
    end

    it 'costs no query once the available custom fields are loaded' do
      issues = Array.new(3) { issue_on(tracker_with(dcf_list_field, dcf_list_field)) }
      issues.each(&:available_custom_fields)

      expect(dcf_count_queries { described_class.new(issues).candidate_fields }).to eq(0)
    end
  end

  describe 'children and hidden fields' do
    it 'hides a chain parent -> child -> grandchild and keeps the parent as the only root' do
      parent = dcf_list_field
      child = depending(parent)
      grandchild = depending(child)
      graph = described_class.new(issues_with(parent, child, grandchild))

      expect(graph.children.map(&:id)).to contain_exactly(child.id, grandchild.id)
      expect(graph.child_ids).to eq(Set[child.id, grandchild.id])
      expect(graph.parent_ids).to eq(Set[parent.id, child.id])
      expect(graph.hidden_field_ids).to eq(Set[parent.id, child.id, grandchild.id])
      expect(graph.root_parent_ids).to eq(Set[parent.id])
    end

    it 'hides an enumeration parent and its depending_enumeration child' do
      parent = dcf_enum_field
      child = dcf_enum_field(format: 'depending_enumeration', parent: parent)
      graph = described_class.new(issues_with(parent, child))

      expect(graph.hidden_field_ids).to eq(Set[parent.id, child.id])
      expect(graph.root_parent_ids).to eq(Set[parent.id])
    end

    it 'gives no child for a deleted parent, a parent of another type or family, or the field itself' do
      dangling = dcf_store_parent(dcf_list_field(format: 'depending_list', values: %w[d1]), missing_id)
      other_type = dcf_store_parent(dcf_list_field(format: 'depending_list', values: %w[t1]),
                                    dcf_list_field(type: ProjectCustomField))
      enum = dcf_enum_field
      other_family = dcf_store_parent(dcf_list_field(format: 'depending_list', values: %w[f1]), enum)
      itself = dcf_list_field(format: 'depending_list', values: %w[s1])
      itself = dcf_store_parent(itself, itself)
      graph = described_class.new(issues_with(dangling, other_type, enum, other_family, itself))

      expect(graph.children).to eq([])
      expect(graph.hidden_field_ids).to be_empty
      expect(graph.root_parent_ids).to be_empty
    end

    [:list, :enumeration].each do |kind|
      it "gives no child in or below a stored cycle (#{kind})" do
        world = dcf_stored_cycles(kind)
        graph = described_class.new(issues_with(world.root, *world.depending))

        expect(graph.children).to eq([])
        expect(graph.hidden_field_ids).to be_empty
      end
    end

    it 'hides a child whose parent is outside the selection; the parent is a root without a field' do
      parent = dcf_list_field
      child = depending(parent)
      graph = described_class.new(issues_with(child))

      expect(graph.child_ids).to eq(Set[child.id])
      expect(graph.hidden_field_ids).to eq(Set[parent.id, child.id])
      expect(graph.root_parent_ids).to eq(Set[parent.id])
      expect(graph.field(parent.id)).to be_nil
    end

    it 'agrees with DependencyRules.effective_parent_id for every candidate' do
      world = dcf_stored_cycles(:list)
      parent = dcf_list_field
      child = depending(parent)
      outside = depending(depending(dcf_list_field))
      issues = issues_with(world.root, *world.depending, parent, child, outside)
      graph = described_class.new(issues)
      lookup = RedmineDependingCustomFields::DependencyRules.lookup_records(issues)

      graph.candidate_fields.each do |field|
        fresh = CustomField.find(field.id)
        expected = !RedmineDependingCustomFields::DependencyRules.effective_parent_id(fresh, lookup).nil?
        expect(graph.child_ids.include?(field.id)).to eq(expected), field.name
      end
    end
  end

  describe 'cost' do
    it 'runs no query when every parent is among the candidates' do
      parent = dcf_list_field
      child = depending(parent)
      grandchild = depending(child)
      issues = issues_with(parent, child, grandchild)
      issues.each(&:available_custom_fields)
      graph = described_class.new(issues)

      expect(dcf_count_queries do
        graph.hidden_field_ids
        graph.root_parent_ids
        graph.children_of(parent.id)
      end).to eq(0)
    end

    # Raw selects and all statements of building +issues+' children (G6 R16:
    # compared only as invariance or differential).
    def children_cost(issues)
      issues.each(&:available_custom_fields)
      total = nil
      raw = field_index_queries { total = dcf_count_queries { described_class.new(issues).children } }
      [raw, total]
    end

    def cost_difference(more, less)
      children_cost(more).zip(children_cost(less)).map { |a, b| a - b }
    end

    it 'loads parents outside the selection in one batched raw select, for 1 or 5 children' do
      differences = [1, 5].map do |n|
        parents = Array.new(n) { dcf_list_field }
        children = parents.map { |parent| depending(parent) }
        cost_difference(issues_with(*children), issues_with(*parents, *children))
      end

      expect(differences.uniq.size).to eq(1)
      expect(differences.first).to eq([1, 1])
    end

    it 'loads ancestors outside the selection one level per query, for 1 or 5 children' do
      expect(RedmineDependingCustomFields::FieldIndex).not_to receive(:load)
      differences = [1, 5].map do |n|
        below_outside_parents = Array.new(n) { depending(depending(dcf_list_field)) }
        below_plain_parents = Array.new(n) { depending(dcf_list_field) }
        cost_difference(issues_with(*below_outside_parents), issues_with(*below_plain_parents))
      end

      expect(differences.uniq.size).to eq(1)
      expect(differences.first).to eq([1, 1])
    end

    it 'deserializes no format_store while the graph is built and read' do
      parent = dcf_list_field
      child = depending(parent)
      outside = depending(depending(dcf_list_field))
      issues = issues_with(parent, child, outside)

      loads = dcf_count_yaml_loads do
        graph = described_class.new(issues)
        graph.hidden_field_ids
        graph.root_parent_ids
        graph.children_of(parent.id)
      end
      expect(loads).to eq(0)
    end
  end

  describe '#children_of and #field' do
    it 'orders the children of a parent by position (nil as 0) and id' do
      parent = dcf_list_field
      first, second, third = Array.new(3) { depending(parent) }
      CustomField.where(id: [first.id, second.id]).update_all(position: 7)
      CustomField.where(id: third.id).update_all(position: nil)
      graph = described_class.new(issues_with(parent, first, second, third))

      expect(graph.children_of(parent.id).map(&:id)).to eq([third.id, first.id, second.id])
      expect(graph.children_of(first.id)).to eq([])
    end

    it 'returns nil for ids outside the selection' do
      graph = described_class.new(issues_with(dcf_list_field))

      expect(graph.field(missing_id)).to be_nil
      expect(graph.field(nil)).to be_nil
    end
  end

  describe '#built_for?' do
    it 'compares the ids of the selection, ignoring order and nil entries' do
      tracker = tracker_with(dcf_list_field)
      a, b, c = Array.new(3) { issue_on(tracker) }
      graph = described_class.new([a, b])

      expect(graph.built_for?([b, a])).to be(true)
      expect(graph.built_for?([a, nil, b])).to be(true)
      expect(graph.built_for?([Issue.find(a.id), Issue.find(b.id)])).to be(true)
      expect(graph.built_for?([a])).to be(false)
      expect(graph.built_for?([a, b, c])).to be(false)
      expect(graph.built_for?([a, c])).to be(false)
      expect(graph.built_for?([])).to be(false)
      expect(graph.built_for?(nil)).to be(false)
      expect(described_class.new([nil]).built_for?([])).to be(true)
    end
  end

  describe 'other customized objects (SD-03)' do
    it 'works on any objects that answer available_custom_fields and keeps no class-level state' do
      parent = dcf_list_field(type: TimeEntryCustomField)
      child = depending(parent, type: TimeEntryCustomField)
      entry = Struct.new(:available_custom_fields).new(CustomField.where(id: [parent.id, child.id]).to_a)
      graph = described_class.new([entry])

      expect(graph.hidden_field_ids).to eq(Set[parent.id, child.id])
      expect(graph.root_parent_ids).to eq(Set[parent.id])
      expect(described_class.instance_variables).to eq([])
    end
  end
end
