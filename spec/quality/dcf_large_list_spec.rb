# frozen_string_literal: true

require_relative '../rails_helper'
require 'digest'
require 'json'

# The large-list generator must produce the same data on every Ruby and in
# JavaScript (test/js/large_list_parity.test.js pins the same hashes).
RSpec.describe DcfLargeList do
  def sha16(text)
    Digest::SHA256.hexdigest(text)[0, 16]
  end

  it 'pins names(5570, tricky_every: 97)' do
    expect(sha16(described_class.names(5570, tricky_every: 97).join("\n"))).to eq('233acf899217e962')
  end

  it 'pins the 27 x 5,570 partition' do
    parents = described_class.names(27, prefix: 'P')
    children = described_class.names(5570, tricky_every: 97)
    expect(sha16(JSON.generate(described_class.partition(parents, children)))).to eq('466b240daca61be9')
  end

  it 'pins sizes() for small and large shapes' do
    expect(sha16(described_class.sizes(25_000, 5000).join(','))).to eq('63b3c3c03829ed24')
    expect(sha16(described_class.sizes(1000, 7).join(','))).to eq('3cf77e9fea249ba6')
    expect(described_class.sizes(5570, 27).sum).to eq(5570)
  end

  it 'reproduces the MySQL TEXT overflow with 5,570 names' do
    expect(described_class.yaml_list_bytes(described_class.names(5570))).to be > 65_535
  end

  [1000, 65_535, 65_536].each do |target|
    it "builds a value list whose YAML is exactly #{target} bytes" do
      values = described_class.values_of_yaml_bytes(target)
      expect(Psych.dump(values).bytesize).to eq(target)
    end
  end

  it 'gives every tricky value a unique name' do
    values = described_class.names(2000, tricky_every: 7)
    expect(values.uniq.size).to eq(2000)
    expect(values).to include(a_string_starting_with('[x] '), a_string_starting_with('semi;colon '))
  end
end

RSpec.describe 'DcfConfigHelpers fixture records' do
  fixtures :users

  it 'assigns ids from the fixed range of the base class, in order' do
    first = dcf_fixture_record(IssueCustomField, { name: "F-#{SecureRandom.hex(3)}", field_format: 'string' })
    second = dcf_fixture_record(IssueCustomField, { name: "G-#{SecureRandom.hex(3)}", field_format: 'string' })

    expect([first.id, second.id]).to eq([9_100_001, 9_100_002])
  end

  it 'builds a tracker with its own default status' do
    tracker = dcf_tracker
    expect(tracker.default_status).to be_a(IssueStatus)
    expect(tracker).to be_persisted
  end
end
