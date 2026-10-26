# frozen_string_literal: true

require_relative '../rails_helper'

# MemCacheStore (and namespaced Memory/File stores) do not support
# delete_matched. The depending formats called it in after_save, inside the
# save transaction, so every depending field save rolled back with an error.
# WP-18 (server design 7.1): no depending save calls any Rails.cache method
# any more (after_custom_field_save and the CustomFieldPatch dispatch are
# deleted).
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

  # WP-18: a store that records every public call made from plugin code
  # (core's own cache use, if any, is not counted, so the example does not
  # depend on core internals).
  describe 'with a store that records every call' do
    let(:plugin_root) { File.expand_path('../..', __dir__) }
    let(:calls) { [] }
    let(:recording_class) do
      log = calls
      root = plugin_root
      stub_const('DcfRecordingStore', Class.new(ActiveSupport::Cache::NullStore) do
        [:fetch, :read, :write, :delete, :delete_matched, :exist?, :fetch_multi, :read_multi, :write_multi,
         :delete_multi, :increment, :decrement, :clear, :cleanup].each do |name|
          define_method(name) do |*args, &block|
            paths = caller_locations.map(&:path)
            from_plugin = paths.any? { |path| path.start_with?(root) && !path.include?('/spec/') }
            log << [name, args.first.to_s] if from_plugin
            super(*args, &block)
          end
        end
      end)
    end

    before { allow(Rails).to receive(:cache).and_return(recording_class.new) }

    it 'calls no cache method while depending fields of both formats are created and updated' do
      parent = dcf_list_field(values: %w[A B])
      child = dcf_list_field(format: 'depending_list', values: %w[a1 b1], parent: parent)
      child = dcf_set_dependencies(child, value_dependencies: { 'A' => %w[a1] })
      child.update!(name: "#{child.name} renamed", hide_when_disabled: '1')
      enum_parent = dcf_enum_field(names: %w[X Y])
      enum_child = dcf_enum_field(format: 'depending_enumeration', names: %w[x1], parent: enum_parent)
      enum_child = dcf_set_dependencies(enum_child, value_dependencies: {
                                          enum_parent.enumerations.first.id.to_s => [enum_child.enumerations.first.id.to_s]
                                        })
      enum_child.update!(name: "#{enum_child.name} renamed")
      issue = dcf_real_issue(dcf_create_project, parent => 'A', child => 'a1')
      issue.reload.custom_field_values = { child.id.to_s => '' }
      issue.save!

      expect(calls).to eq([])
    end

    it 'calls no cache method during a project-level service save' do
      project = dcf_create_project
      parent = dcf_list_field(values: %w[A B])
      child = dcf_list_field(format: 'depending_list', values: %w[a1], parent: parent)

      RedmineDependingCustomFields::AddValueService
        .new(project: project, field: child, user: dcf_admin, params: { value: 'a2' }).call

      expect(child.reload.possible_values).to include('a2')
      expect(calls).to eq([])
    end

    it 'records a call made from plugin code and none from a spec (self check)' do
      Rails.cache.read('dcf/from-spec')
      lib_file = File.join(plugin_root, 'lib', 'redmine_depending_custom_fields.rb')
      RubyVM::InstructionSequence.compile('Rails.cache.read("dcf/self-check")', lib_file).eval

      expect(calls).to eq([[:read, 'dcf/self-check']])
    end
  end
end
