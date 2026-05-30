require_relative '../rails_helper'

RSpec.describe RedmineDependingCustomFields::UsageCalculator do
  let(:project) { dcf_create_project(name: 'A') }
  let(:other)   { dcf_create_project(name: 'B') }

  describe 'CustomValue usage counts (T-USE-1/2)' do
    it 'counts usage in this project and in other projects separately' do
      field = dcf_list_field(values: %w[A B], is_for_all: true)
      dcf_issue_with_value(project, field, 'A')
      dcf_issue_with_value(project, field, 'A')
      dcf_issue_with_value(other, field, 'A')

      expect(described_class.usage_here(field, 'A', project)).to eq(2)
      expect(described_class.usage_other(field, 'A', project)).to eq(1)
      expect(described_class.usage_total(field, 'A')).to eq(3)
    end
  end

  describe 'dependency reference counts on both sides (T-USE-4)' do
    it 'counts own-side child refs and parent-side refs' do
      parent = dcf_list_field(name: 'Parent', values: %w[A B], is_for_all: true)
      child = dcf_list_field(format: 'depending_list', name: 'Child', values: %w[c1 c2],
                             parent: parent, is_for_all: true)
      dcf_set_dependencies(child, value_dependencies: { 'A' => %w[c1], 'B' => %w[c1] })

      # 'c1' appears twice as a child value in the child's own store.
      expect(described_class.own_dep_refs(child, 'c1')).to eq(2)
      # 'A' is used as a parent key in one depending child.
      expect(described_class.parent_key_refs(parent, 'A')).to eq(1)
      expect(described_class.affected_child_fields(parent, 'A').map(&:id)).to eq([child.id])
    end
  end
end
