# frozen_string_literal: true

require_relative '../rails_helper'

# WP-04 characterization of FieldRelevance.children_of before WP-05 delegates
# it to DependencyRules.children_of. Today the query has no ORDER BY, so only
# the result set is pinned; WP-05 must return the same set.
RSpec.describe 'FieldRelevance.children_of (characterization)' do
  def children_ids(field)
    RedmineDependingCustomFields::FieldRelevance.children_of(field).map(&:id).sort
  end

  it 'returns the depending children of both families that name the field' do
    list_parent = dcf_list_field
    enum_parent = dcf_enum_field
    list_child = dcf_list_field(format: 'depending_list', parent: list_parent)
    second_child = dcf_list_field(format: 'depending_list', parent: list_parent)
    enum_child = dcf_enum_field(format: 'depending_enumeration', parent: enum_parent)
    dcf_list_field(format: 'depending_list', parent: dcf_list_field)

    expect(children_ids(list_parent)).to eq([list_child.id, second_child.id].sort)
    expect(children_ids(enum_parent)).to eq([enum_child.id])
  end

  it 'returns depending children of a depending parent (chains)' do
    root = dcf_list_field
    middle = dcf_list_field(format: 'depending_list', parent: root)
    leaf = dcf_list_field(format: 'depending_list', parent: middle)

    expect(children_ids(root)).to eq([middle.id])
    expect(children_ids(middle)).to eq([leaf.id])
    expect(children_ids(leaf)).to eq([])
  end

  it 'includes project custom field children of a project custom field parent' do
    parent = dcf_list_field(type: ProjectCustomField)
    child = dcf_list_field(format: 'depending_list', parent: parent, type: ProjectCustomField)

    expect(children_ids(parent)).to eq([child.id])
  end

  it 'ignores plain list fields' do
    parent = dcf_list_field
    expect(children_ids(parent)).to eq([])
  end
end
