# frozen_string_literal: true

require_relative '../rails_helper'

# WP-11 (limits design 10.1 and 10.2): the generator's S1 scenario and the
# exact 65,535-byte boundary against the MySQL TEXT limit, stubbed so the
# examples run on every adapter. Nothing above the limit is ever written.
RSpec.describe 'StorageLimits at scale', :large do
  fixtures :users

  let(:limits) { RedmineDependingCustomFields::StorageLimits }

  before { allow(limits).to receive(:column_limit).and_return(65_535) }

  it 'refuses the S1 field (27 x 5,570) with one error per column and writes nothing' do
    parent_values = DcfLargeList.names(27, prefix: 'P')
    child_values = DcfLargeList.names(5570, tricky_every: 97)
    parent = dcf_list_field(values: parent_values)
    mapping = DcfLargeList.partition(parent_values, child_values)
    child = IssueCustomField.new(name: "S1-#{SecureRandom.hex(3)}", field_format: 'depending_list',
                                 possible_values: child_values, is_for_all: true)
    child.parent_custom_field_id = parent.id.to_s
    child.value_dependencies = mapping
    child.default_value_dependencies = DcfLargeList.first_child_defaults(mapping)
    expect(child.possible_values).to eq(child_values)

    expect(child.valid?).to be(false)
    expect(child.errors.details.keys).to eq([:possible_values, :value_dependencies])
    details = child.errors.details.values.map(&:first)
    expect(details.pluck(:error)).to eq([:dcf_storage_too_large, :dcf_storage_too_large])
    expect(details.pluck(:column)).to eq(%w[possible_values format_store])
    expect(details.pluck(:max_bytes)).to eq([65_535, 65_535])
    expect(details.pluck(:bytes))
      .to eq([limits.preview_bytes(child, 'possible_values'), limits.preview_bytes(child, 'format_store')])
    expect(details.pluck(:bytes)).to all(be > 65_535)

    expect { expect(child.save).to be(false) }.not_to change(CustomField, :count)
    expect(child).to be_new_record
  end

  it 'saves a list of exactly 65,535 bytes and refuses 65,536 bytes' do
    fits = IssueCustomField.new(name: "Fits-#{SecureRandom.hex(3)}", field_format: 'list', is_for_all: true,
                                possible_values: DcfLargeList.values_of_yaml_bytes(65_535))
    expect(limits.preview_bytes(fits, 'possible_values')).to eq(65_535)
    expect(fits.save).to be(true), fits.errors.full_messages.inspect
    raw = CustomField.connection.select_value(CustomField.where(id: fits.id).select(:possible_values).to_sql)
    expect(raw.bytesize).to eq(65_535)

    over = IssueCustomField.new(name: "Over-#{SecureRandom.hex(3)}", field_format: 'list', is_for_all: true,
                                possible_values: DcfLargeList.values_of_yaml_bytes(65_536))
    expect(over.save).to be(false)
    expect(over.errors.details[:possible_values])
      .to eq([{ error: :dcf_storage_too_large, size: limits.delimited(65_536), limit: limits.delimited(65_535),
                bytes: 65_536, max_bytes: 65_535, column: 'possible_values' }])
  end
end
