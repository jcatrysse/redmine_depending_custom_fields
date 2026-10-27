# frozen_string_literal: true

require_relative '../rails_helper'

# WP-22 (BC-02, quality G7 and S7, AD-5): D6 pruning runs only on the admin
# JSON transport. The plugin API, extended-API style safe_attributes= saves,
# project cascades and admin saves that post no dependencies_json keep the
# stored mapping byte for byte: orphan parent keys and child values,
# bracket-corrupted keys, links to inactive enumerations, keys out of parent
# order and a String default on a multiple field. The rendered matrix form
# still drops some of them (spec/characterization/admin_nested_params_spec.rb)
# until WP-25 replaces it; the untouched admin save here posts no mapping params.
RSpec.describe 'Stored mapping preservation outside the admin JSON transport (BC-02)', type: :request do
  fixtures :users

  let(:payload) { RedmineDependingCustomFields::DependencyPayload }
  let(:rules) { RedmineDependingCustomFields::DependencyRules }
  let(:parent) { dcf_list_field(name: "Parent-#{SecureRandom.hex(3)}", values: %w[A B]) }
  let(:mapping) { { 'B' => %w[b1], 'A' => %w[a1 nope], 'ZZ' => %w[nope], '[x]' => %w[b1], 'a]' => %w[b1] } }
  let(:defaults) { { 'A' => 'a1', 'ZZ' => 'nope' } }
  let(:list_child) do
    field = dcf_list_field(format: 'depending_list', name: "Child-#{SecureRandom.hex(3)}", values: %w[a1 b1],
                           parent: parent, multiple: true)
    field.update!(hide_when_disabled: '1')
    dcf_set_dependencies(field, value_dependencies: mapping, default_value_dependencies: defaults)
  end
  let(:enum_parent) { dcf_enum_field(name: "EnumParent-#{SecureRandom.hex(3)}", names: %w[X Y Z]) }
  let(:enum_child) do
    field = dcf_enum_field(format: 'depending_enumeration', names: %w[x1 y1 z1], parent: enum_parent)
    x, y, z = enum_parent.enumerations.order(:position).map { |e| e.id.to_s }
    x1, y1, z1 = enum_child_ids(field)
    dcf_set_dependencies(field, value_dependencies: { z => [x1], x => [z1, x1], y => [y1], '999999' => [x1] },
                                default_value_dependencies: { x => z1 })
    CustomFieldEnumeration.where(id: [z, z1]).update_all(active: false)
    field
  end

  def enum_child_ids(field)
    field.enumerations.order(:position).map { |e| e.id.to_s }
  end

  def raw_store(field)
    CustomField.connection.select_value(CustomField.where(id: field.id).select(:format_store).to_sql)
  end

  def spy_transport
    [:prune_mapping, :value_keys, :mapping_problems, :value_options].each do |name|
      allow(rules).to receive(name).and_call_original
    end
    allow(payload).to receive(:stored_digest).and_call_original
    allow(payload).to receive(:parse).and_call_original
  end

  def expect_no_transport
    [:prune_mapping, :value_keys, :mapping_problems, :value_options].each do |name|
      expect(rules).not_to have_received(name)
    end
    expect(payload).not_to have_received(:stored_digest)
    expect(payload).not_to have_received(:parse)
  end

  before { allow(User).to receive(:current).and_return(dcf_admin) }

  it 'stores the fixture as given: orphans, corrupted keys, inactive links, key order and a String default' do
    expect(CustomField.find(list_child.id).value_dependencies.keys).to eq(['B', 'A', 'ZZ', '[x]', 'a]'])
    expect(CustomField.find(list_child.id).default_value_dependencies).to eq(defaults)
    expect(CustomField.find(enum_child.id).value_dependencies.size).to eq(4)
  end

  it 'leaves the row byte-identical on a plugin API rename-only PUT' do
    [list_child, enum_child].each do |field|
      raw_before = raw_store(field)
      spy_transport

      put "/depending_custom_fields/#{field.id}.json", params: { custom_field: { name: "#{field.name}-api" } }

      expect(response).to have_http_status(200), response.body
      expect(CustomField.find(field.id).name).to eq("#{field.name}-api")
      expect(raw_store(field)).to eq(raw_before)
    end
    expect_no_transport
  end

  it 'leaves the row byte-identical on an extended-API style safe_attributes= save of other attributes' do
    [list_child, enum_child].each do |field|
      raw_before = raw_store(field)
      spy_transport
      record = CustomField.find(field.id)
      record.safe_attributes = { 'name' => "#{field.name}-ext", 'description' => 'changed' }

      expect(record.save).to be(true), record.errors.full_messages.inspect
      expect(raw_store(field)).to eq(raw_before)
    end
    expect_no_transport
  end

  it 'stores nested mapping params of an extended-API style save sanitize-only, in submitted order (E28)' do
    record = CustomField.find(list_child.id)
    spy_transport
    record.safe_attributes = { 'value_dependencies' => { 'ZZ' => ['nope'], 'B' => ['b1', ''], 'a]' => ['b1'] },
                               'default_value_dependencies' => { 'ZZ' => 'nope' } }

    expect(record.save).to be(true), record.errors.full_messages.inspect
    stored = CustomField.find(list_child.id)
    expect(stored.value_dependencies.to_hash).to eq('ZZ' => %w[nope], 'B' => %w[b1], 'a]' => %w[b1])
    expect(stored.value_dependencies.keys).to eq(['ZZ', 'B', 'a]'])
    expect(stored.default_value_dependencies.to_hash).to eq('ZZ' => 'nope')
    expect_no_transport
  end

  it 'renames only the cascaded key on a project rename and keeps every other key' do
    list_child
    project = dcf_create_project
    spy_transport

    RedmineDependingCustomFields::RenameValueService
      .new(project: project, field: CustomField.find(parent.id), user: dcf_admin,
           params: { old_value: 'A', new_value: 'A2', confirm: '1' }).call

    stored = CustomField.find(list_child.id)
    expect(stored.value_dependencies.to_hash)
      .to eq('B' => %w[b1], 'A2' => %w[a1 nope], 'ZZ' => %w[nope], '[x]' => %w[b1], 'a]' => %w[b1])
    expect(stored.default_value_dependencies.to_hash).to eq('A2' => 'a1', 'ZZ' => 'nope')
    expect(stored.hide_when_disabled).to eq('1')
    expect_no_transport
  end

  it 'leaves the row byte-identical on an admin save that posts no mapping (absent, empty or white space)' do
    [:prune_mapping, :value_keys].each { |name| allow(rules).to receive(name).and_call_original }
    allow(payload).to receive(:stored_digest).and_call_original
    [list_child, enum_child].each do |field|
      raw_before = raw_store(field)
      [{}, { dependencies_json: '' }, { dependencies_json: " \n\t" }].each_with_index do |extra, i|
        put "/custom_fields/#{field.id}", params: { custom_field: { name: "#{field.name}-#{i}" }.merge(extra) }

        expect(response).to redirect_to("/custom_fields/#{field.id}/edit")
        expect(CustomField.find(field.id).name).to eq("#{field.name}-#{i}")
        expect(raw_store(field)).to eq(raw_before)
      end
    end
    [:prune_mapping, :value_keys].each { |name| expect(rules).not_to have_received(name) }
    expect(payload).not_to have_received(:stored_digest)
  end

  it 'keeps the bytes of a JSON-saved mapping through a later API rename-only PUT' do
    put "/custom_fields/#{list_child.id}",
        params: { custom_field: { dependencies_json: JSON.generate('value_dependencies' => { 'B' => %w[b1], 'A' => %w[b1 a1] },
                                                                   'default_value_dependencies' => { 'B' => 'b1' }) } }
    expect(response).to redirect_to("/custom_fields/#{list_child.id}/edit")
    stored = CustomField.find(list_child.id)
    expect(stored.value_dependencies.to_hash).to eq('A' => %w[a1 b1], 'B' => %w[b1])
    expect(stored.default_value_dependencies.to_hash).to eq('B' => %w[b1])
    raw_after_json = raw_store(list_child)
    spy_transport

    put "/depending_custom_fields/#{list_child.id}.json", params: { custom_field: { name: "#{list_child.name}-api" } }

    expect(response).to have_http_status(200), response.body
    expect(raw_store(list_child)).to eq(raw_after_json)
    expect_no_transport
  end

  it 'calls DependencyRules.prune_mapping only from the admin transport' do
    root = File.expand_path('../..', __dir__)
    callers = Dir[File.join(root, '{app,lib}', '**', '*.{rb,erb,rake}')].select do |path|
      File.read(path).include?('prune_mapping')
    end
    expect(callers.map { |path| path.delete_prefix("#{root}/") }).to match_array(
      %w[lib/redmine_depending_custom_fields/dependency_rules.rb
         lib/redmine_depending_custom_fields/patches/custom_field_validation_patch.rb]
    )
  end
end
