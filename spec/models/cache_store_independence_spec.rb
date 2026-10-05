# frozen_string_literal: true

require_relative '../rails_helper'

# MemCacheStore (and namespaced Memory/File stores) do not support
# delete_matched. The depending formats called it in after_save, inside the
# save transaction, so every depending field save rolled back with an error.
RSpec.describe 'Depending field saves without delete_matched support' do
  fixtures :users

  # Mimics ActiveSupport::Cache::MemCacheStore#delete_matched. Named, because
  # cache instrumentation uses the store class name.
  let(:store_class) do
    stub_const('DcfNoDeleteMatchedStore', Class.new(ActiveSupport::Cache::NullStore) do
      def delete_matched(*)
        raise NotImplementedError, "#{self.class.name} does not support delete_matched"
      end
    end)
  end

  before { allow(Rails).to receive(:cache).and_return(store_class.new) }

  it 'creates and updates a depending list field' do
    parent = dcf_list_field(values: %w[A B])
    child = dcf_list_field(format: 'depending_list', values: %w[a1 b1], parent: parent)
    dcf_set_dependencies(child, value_dependencies: { 'A' => %w[a1], 'B' => %w[b1] })

    expect(child.reload.value_dependencies).to eq('A' => %w[a1], 'B' => %w[b1])
  end

  it 'creates and updates a depending enumeration field' do
    parent = dcf_enum_field(names: %w[X Y])
    child = dcf_enum_field(format: 'depending_enumeration', names: %w[x1 y1], parent: parent)
    parent_key = parent.enumerations.first.id.to_s
    child_key = child.enumerations.first.id.to_s
    dcf_set_dependencies(child, value_dependencies: { parent_key => [child_key] })

    expect(child.reload.value_dependencies).to eq(parent_key => [child_key])
  end

  it 'saves through a project-level service' do
    project = dcf_create_project
    parent = dcf_list_field(values: %w[A B])
    child = dcf_list_field(format: 'depending_list', values: %w[a1], parent: parent)

    RedmineDependingCustomFields::AddValueService
      .new(project: project, field: child, user: dcf_admin, params: { value: 'a2' }).call

    expect(child.reload.possible_values).to include('a2')
  end
end
