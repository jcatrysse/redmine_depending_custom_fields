require_relative '../rails_helper'

RSpec.describe RedmineDependingCustomFields::DependencyMappingService do
  let(:project) { dcf_create_project }
  let(:user) { dcf_admin }

  def build_pair
    parent = dcf_list_field(name: 'Parent', values: %w[A B], is_for_all: false, projects: [project])
    child = dcf_list_field(format: 'depending_list', name: 'Child', values: %w[c1 c2],
                           parent: parent, is_for_all: false, projects: [project])
    [parent, child]
  end

  def call(field, params)
    described_class.new(project: project, field: field, user: user, params: params).call
  end

  it 'saves a valid mapping and default (T-DEP-1)' do
    _parent, child = build_pair
    call(child, value_dependencies: { 'A' => ['c1'] }, default_value_dependencies: { 'A' => 'c1' })
    expect(child.reload.value_dependencies).to eq('A' => ['c1'])
    expect(child.default_value_dependencies).to eq('A' => 'c1')
  end

  it 'rejects an unknown child value (T-DEP-2)' do
    _parent, child = build_pair
    expect { call(child, value_dependencies: { 'A' => ['nope'] }) }
      .to raise_error(RedmineDependingCustomFields::OperationError) { |e| expect(e.key).to eq(:error_invalid_dependency) }
  end

  it 'rejects an unknown parent key (T-DEP-3)' do
    _parent, child = build_pair
    expect { call(child, value_dependencies: { 'ZZ' => ['c1'] }) }
      .to raise_error(RedmineDependingCustomFields::OperationError) { |e| expect(e.key).to eq(:error_invalid_dependency) }
  end

  it 'rejects a default that is not an allowed child (T-DEP-5)' do
    _parent, child = build_pair
    expect do
      call(child, value_dependencies: { 'A' => ['c1'] }, default_value_dependencies: { 'A' => 'c2' })
    end.to raise_error(RedmineDependingCustomFields::OperationError) { |e| expect(e.key).to eq(:error_invalid_dependency) }
  end

  it 'stores multiple per-parent defaults for a multiple child field (T-DEP-6)' do
    parent = dcf_list_field(name: 'Parent', values: %w[A B], is_for_all: false, projects: [project])
    child = dcf_list_field(format: 'depending_list', name: 'Child', values: %w[c1 c2],
                           parent: parent, is_for_all: false, projects: [project], multiple: true)
    call(child,
         value_dependencies: { 'A' => %w[c1 c2] },
         default_value_dependencies: { 'A' => %w[c1 c2] })
    expect(child.reload.default_value_dependencies).to eq('A' => %w[c1 c2])
  end

  it 'rejects a multiple default that is not an allowed child (T-DEP-6)' do
    parent = dcf_list_field(name: 'Parent', values: %w[A B], is_for_all: false, projects: [project])
    child = dcf_list_field(format: 'depending_list', name: 'Child', values: %w[c1 c2],
                           parent: parent, is_for_all: false, projects: [project], multiple: true)
    expect do
      call(child,
           value_dependencies: { 'A' => %w[c1] },
           default_value_dependencies: { 'A' => %w[c1 c2] })
    end.to raise_error(RedmineDependingCustomFields::OperationError) { |e| expect(e.key).to eq(:error_invalid_dependency) }
  end

  it 'rejects a standard list (no parent / not a depending format) (T-REL-9)' do
    field = dcf_list_field(format: 'list', is_for_all: false, projects: [project])
    expect { call(field, value_dependencies: {}) }
      .to raise_error(RedmineDependingCustomFields::OperationError) { |e| expect(e.key).to eq(:error_format_unsupported) }
  end
end
