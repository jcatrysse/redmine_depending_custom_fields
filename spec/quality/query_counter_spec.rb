# frozen_string_literal: true

require_relative '../rails_helper'

# The counting helpers are the basis of every later performance assertion, so
# they must count what they claim to count.
RSpec.describe DcfQueryCounter do
  fixtures :users

  it 'counts SQL statements, ignoring schema and cache queries' do
    expect(dcf_count_queries { User.where(id: 1).to_a }).to eq(1)
    expect(dcf_count_queries { nil }).to eq(0)
  end

  it 'counts YAML loads of a serialized store column' do
    field = dcf_list_field(values: %w[A B])
    loads = dcf_count_yaml_loads { CustomField.find(field.id).format_store }
    expect(loads).to be >= 1
  end

  it 'reports the difference between two blocks' do
    overhead = dcf_plugin_overhead(with: -> { 2.times { User.where(id: 1).to_a } }, without: -> { User.where(id: 1).to_a })
    expect(overhead).to eq(1)
  end
end
