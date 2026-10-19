# frozen_string_literal: true

require_relative '../rails_helper'

# WP-11 (BC-02, quality S7, limits design 4.4 and 10.2): the storage check
# measures the sanitize-only normalization; no save path it runs on prunes
# orphan, inactive or bracket-corrupted mapping keys, and an unchanged column
# is never measured, even when it is above the limit.
RSpec.describe 'Storage validation without pruning (BC-02)' do
  fixtures :users

  let(:limits) { RedmineDependingCustomFields::StorageLimits }
  let(:rules) { RedmineDependingCustomFields::DependencyRules }
  let(:parent) { dcf_list_field(name: "Parent-#{SecureRandom.hex(3)}", values: %w[A B]) }
  let(:mapping) { { 'A' => %w[a1 nope], 'ZZ' => %w[nope], '[x]' => %w[b1], 'a]' => %w[b1] } }
  let(:child) do
    field = dcf_list_field(format: 'depending_list', name: "Child-#{SecureRandom.hex(3)}", values: %w[a1 b1],
                           parent: parent)
    dcf_set_dependencies(field, value_dependencies: mapping, default_value_dependencies: { 'ZZ' => 'nope' })
  end

  def raw_store(field)
    CustomField.connection.select_value(CustomField.where(id: field.id).select(:format_store).to_sql)
  end

  def spy_pruning
    [:prune_mapping, :mapping_problems, :value_keys, :value_options].each do |name|
      allow(rules).to receive(name).and_call_original
    end
  end

  def expect_no_pruning
    [:prune_mapping, :mapping_problems, :value_keys, :value_options].each do |name|
      expect(rules).not_to have_received(name)
    end
  end

  describe 'plugin API name-only PUT', type: :request do
    before { allow(User).to receive(:current).and_return(dcf_admin) }

    it 'saves while the stored columns are above a stubbed limit and leaves them byte-identical' do
      raw_before = raw_store(child)
      values_before = CustomField.connection.select_value(CustomField.where(id: child.id).select(:possible_values).to_sql)
      allow(limits).to receive(:column_limit).and_return(1)
      spy_pruning

      put "/depending_custom_fields/#{child.id}.json", params: { custom_field: { name: "#{child.name}-x" } }

      expect(response).to have_http_status(200), response.body
      expect(CustomField.find(child.id).name).to eq("#{child.name}-x")
      expect(raw_store(child)).to eq(raw_before)
      expect(CustomField.connection.select_value(CustomField.where(id: child.id).select(:possible_values).to_sql))
        .to eq(values_before)
      expect(CustomField.find(child.id).value_dependencies.keys).to eq(['A', 'ZZ', '[x]', 'a]'])
      expect_no_pruning
    end
  end

  it 'measures and stores a safe_attributes= save (extended API style) without pruning' do
    field = CustomField.find(child.id)
    field.safe_attributes = { 'value_dependencies' => { 'ZZ' => ['nope'], '[x]' => ['b1'], 'A' => ['a1', 'a1', ''] },
                              'default_value_dependencies' => { 'ZZ' => 'nope' } }
    bytes = limits.preview_bytes(field, 'format_store')
    allow(limits).to receive(:column_limit).and_return(nil)
    allow(limits).to receive(:column_limit).with('format_store').and_return(bytes)
    spy_pruning

    expect(field.save).to be(true), field.errors.full_messages.inspect
    expect(raw_store(field).bytesize).to eq(bytes)
    expect(CustomField.find(child.id).value_dependencies).to eq('ZZ' => ['nope'], '[x]' => ['b1'], 'A' => %w[a1 a1])
    expect(CustomField.find(child.id).default_value_dependencies).to eq('ZZ' => 'nope')
    expect_no_pruning
  end

  it 'keeps unrelated keys of a child through a project rename cascade (child.save!)' do
    project = dcf_create_project
    child
    spy_pruning
    allow(limits).to receive(:column_limit).and_return(65_535)

    RedmineDependingCustomFields::RenameValueService
      .new(project: project, field: CustomField.find(parent.id), user: dcf_admin,
           params: { old_value: 'A', new_value: 'A2', confirm: '1' }).call

    stored = CustomField.find(child.id)
    expect(stored.value_dependencies.keys).to contain_exactly('A2', 'ZZ', '[x]', 'a]')
    expect(stored.value_dependencies['A2']).to eq(%w[a1 nope])
    expect(stored.value_dependencies['ZZ']).to eq(%w[nope])
    expect(stored.default_value_dependencies).to eq('ZZ' => 'nope')
    expect_no_pruning
  end

  it 'refuses a rename cascade that grows a child over a stubbed limit, rolling everything back' do
    project = dcf_create_project
    child
    raw_child = raw_store(child)
    values_before = CustomField.find(parent.id).possible_values
    allow(limits).to receive(:column_limit).and_return(nil)
    allow(limits).to receive(:column_limit).with('format_store').and_return(raw_child.bytesize)

    expect do
      RedmineDependingCustomFields::RenameValueService
        .new(project: project, field: CustomField.find(parent.id), user: dcf_admin,
             params: { old_value: 'A', new_value: "A#{'2' * 20}", confirm: '1' }).call
    end.to raise_error(RedmineDependingCustomFields::OperationError)

    expect(raw_store(child)).to eq(raw_child)
    expect(CustomField.find(parent.id).possible_values).to eq(values_before)
  end
end
