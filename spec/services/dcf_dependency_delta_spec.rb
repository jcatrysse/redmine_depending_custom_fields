# frozen_string_literal: true

require_relative '../rails_helper'

# WP-27 (project design 4, limits design 6.3, T-DEP-9): the compact audit
# delta v2 of update_dependencies: counts, samples bounded by entries and
# encoded bytes, labels cut by encoded bytes, the mapping digest and the
# client-reported source and import (SP-12).
RSpec.describe 'RedmineDependingCustomFields::DependencyDelta' do
  let(:delta_class) { RedmineDependingCustomFields::DependencyDelta }
  let(:payload) { RedmineDependingCustomFields::DependencyPayload }
  let(:parents) { { 'A' => 'Alpha', 'B' => 'Beta', 'Foo [x]' => 'Foo [x]' } }
  let(:children) { { 'c1' => 'One', 'c2' => 'Two', 'c3' => 'Three' } }

  def delta(new_vd: {}, new_dd: {}, old_vd: {}, old_dd: {}, parent_labels: parents, child_labels: children,
            source: 'editor', import: nil)
    delta_class.new(old_vd: old_vd, old_dd: old_dd, new_vd: new_vd, new_dd: new_dd, parent_labels: parent_labels,
                    child_labels: child_labels, source: source, import: import)
  end

  def encode(value)
    ActiveSupport::JSON.encode(value)
  end

  # The label of the first added pair's parent for +label+.
  def cut(label)
    delta(new_vd: { 'K' => ['c1'] }, parent_labels: { 'K' => label }).after['sample']['added'].first.first
  end

  def encoded_content(text)
    encode(text).bytesize - 2
  end

  it 'has the v2 keys before and after, the import only for source import' do
    d = delta(new_vd: { 'A' => ['c1'] }, new_dd: { 'A' => 'c1' })
    expect(d.before.keys).to eq(%w[v links defaults mapping_sha256])
    expect(d.after.keys).to eq(%w[v source links defaults mapping_sha256 added removed orphans_removed
                                  defaults_changed parents_changed sample truncated])
    expect(d.after['sample'].keys).to eq(%w[added removed defaults])
    expect([d.before['v'], d.after['v'], d.after['source']]).to eq([2, 2, 'editor'])
    expect(d.after['truncated']).to be(false)

    imported = delta(new_vd: { 'A' => ['c1'] }, source: 'import', import: { 'mode' => 'replace', 'rows' => 5_000 })
    expect(imported.after['import']).to eq('mode' => 'replace', 'rows' => 5_000)
    expect(imported.after.keys.last).to eq('import')
    expect(delta(source: 'editor', import: { 'mode' => 'merge', 'rows' => 1 }).after).not_to have_key('import')
    expect(delta(source: 'form').after['source']).to eq('form')
    expect(d.after.keys & %w[payload_truncated payload_bytes payload_sha256 base]).to eq([])
  end

  it 'counts links, defaults, added, removed, orphans, changed defaults and parents (edge case 9)' do
    d = delta(old_vd: { 'A' => %w[c1 zz], 'Gone' => %w[c1], 'Foo [x]' => %w[c3] },
              old_dd: { 'A' => 'c1' },
              new_vd: { 'A' => %w[c1 c2], 'Foo [x]' => %w[c3], 'B' => %w[c1] },
              new_dd: { 'A' => ['c1'], 'B' => 'c1' })

    expect(d.before.slice('links', 'defaults')).to eq('links' => 4, 'defaults' => 1)
    expect(d.after.slice('links', 'defaults', 'added', 'removed', 'orphans_removed', 'defaults_changed',
                         'parents_changed'))
      .to eq('links' => 4, 'defaults' => 2, 'added' => 2, 'removed' => 2, 'orphans_removed' => 2,
             'defaults_changed' => 1, 'parents_changed' => 3)
    expect(d.after['sample']).to eq('added' => [%w[Alpha Two], %w[Beta One]],
                                    'removed' => [%w[Alpha zz], %w[Gone One]],
                                    'defaults' => [['Beta', ['One']]])
  end

  it 'accepts old stored values of other types without raising' do
    d = delta(old_vd: { 'A' => ['c1', 2, nil, ''], 3 => 'c2', '' => ['c1'] }, old_dd: { 'A' => 1, 'B' => nil },
              new_vd: { 'A' => ['c1'] })

    expect(d.before['links']).to eq(3)
    expect(d.before['defaults']).to eq(1)
    expect(d.after['removed']).to eq(2)
    expect(d.before['mapping_sha256']).to eq(payload.digest({ 'A' => %w[c1 2], '3' => ['c2'] }, { 'A' => '1' }))
  end

  it 'digests the mapping as DependencyPayload.digest, independent of order and of the default shape' do
    one = delta(new_vd: { 'A' => %w[c1 c2], 'B' => %w[c3] }, new_dd: { 'A' => 'c1' })
    two = delta(new_vd: { 'B' => %w[c3], 'A' => %w[c2 c1] }, new_dd: { 'A' => ['c1'] })

    expect(one.after['mapping_sha256']).to match(/\A[0-9a-f]{64}\z/)
    expect(one.after['mapping_sha256']).to eq(two.after['mapping_sha256'])
    expect(one.after['mapping_sha256']).to eq(payload.digest({ 'A' => %w[c1 c2], 'B' => %w[c3] }, { 'A' => 'c1' }))
    expect(delta.before['mapping_sha256']).to eq(payload.digest({}, {}))
    expect(one.after['mapping_sha256']).not_to eq(payload.digest({}, {}))
  end

  it 'counts a String default equal to a list of one as unchanged' do
    d = delta(old_vd: { 'A' => ['c1'] }, old_dd: { 'A' => 'c1' }, new_vd: { 'A' => ['c1'] }, new_dd: { 'A' => ['c1'] })

    expect(d.after.slice('added', 'removed', 'defaults_changed', 'parents_changed'))
      .to eq('added' => 0, 'removed' => 0, 'defaults_changed' => 0, 'parents_changed' => 0)
    expect(d.after['sample']).to eq('added' => [], 'removed' => [], 'defaults' => [])
  end

  it 'writes the summary with counts and the enumerated source only' do
    d = delta(old_vd: { 'Gone' => ['c1'] }, new_vd: { 'A' => %w[c1 c2] }, new_dd: { 'A' => 'c1' })
    expect(d.summary).to eq('Updated dependency mapping (editor): +2/-1 links, 1 orphaned removed, ' \
                            '1 default(s) changed, 2 parent value(s)')
    expect(delta(source: 'form').summary)
      .to eq('Updated dependency mapping (form): +0/-0 links, 0 orphaned removed, 0 default(s) changed, 0 parent value(s)')
    replace = delta(new_vd: { 'A' => ['c1'] }, source: 'import', import: { 'mode' => 'replace', 'rows' => 5_000 })
    expect(replace.summary).to start_with('Updated dependency mapping (import, replace, 5000 rows): +1/-0 links')
    expect(delta(source: 'import').summary).to start_with('Updated dependency mapping (import): ')
    expect(d.summary).not_to include('Alpha')
  end

  it 'orders samples by the value order of the labels, unknown keys after them, whatever the submitted order' do
    one = delta(new_vd: { 'Zed' => ['c1'], 'B' => %w[c3 c1], 'A' => %w[zz c2] })
    two = delta(new_vd: { 'A' => %w[c2 zz], 'B' => %w[c1 c3], 'Zed' => ['c1'] })

    expected = [%w[Alpha Two], %w[Alpha zz], %w[Beta One], %w[Beta Three], %w[Zed One]]
    expect(one.after['sample']['added']).to eq(expected)
    expect(two.after).to eq(one.after)
  end

  it 'keeps at most 20 entries per sample list and marks the delta truncated (4,200 links)' do
    big_parents = (1..42).to_h { |i| ["P#{i}", "P#{i}"] }
    big_children = (1..100).to_h { |i| ["C#{i}", "C#{i}"] }
    mapping = big_parents.keys.to_h { |pk| [pk, big_children.keys] }
    d = delta(new_vd: mapping, new_dd: mapping.transform_values(&:first), parent_labels: big_parents,
              child_labels: big_children)

    expect(d.after['added']).to eq(4_200)
    expect(d.after['sample']['added'].size).to eq(20)
    expect(d.after['sample']['added'].first).to eq(%w[P1 C1])
    expect(d.after['sample']['defaults'].size).to eq(20)
    expect(d.after['truncated']).to be(true)
  end

  it 'keeps each sample list at most 4,000 encoded bytes' do
    long = (1..30).to_h { |i| ["P#{i}", "#{'<' * 100}#{i}"] }
    kids = (1..5).to_h { |i| ["C#{i}", "#{'&' * 100}#{i}"] }
    mapping = long.keys.to_h { |pk| [pk, kids.keys] }
    d = delta(new_vd: mapping, new_dd: mapping, parent_labels: long, child_labels: kids, old_vd: {})

    defaults = d.after['sample']['defaults']
    expect(encode(defaults).bytesize).to be <= 4_000
    expect(defaults.size).to be < 20
    expect(defaults.size).to be > 5
    expect(defaults.first.last.size).to eq(3)
    expect(encode(d.after['sample']['added']).bytesize).to be <= 4_000
    expect(d.after['truncated']).to be(true)
  end

  it 'lists at most 3 child labels of the new defaults per defaults entry' do
    d = delta(new_vd: { 'A' => %w[c1 c2 c3 c4 c5] }, new_dd: { 'A' => %w[c3 c1 c2 c4 c5] },
              child_labels: children.merge('c4' => 'Four', 'c5' => 'Five'))

    expect(d.after['sample']['defaults']).to eq([['Alpha', %w[One Two Three]]])
    expect(d.after['truncated']).to be(false)
  end

  it 'cuts labels to 80 encoded bytes by characters, with ... inside the budget' do
    emoji = "\u{1f600}"
    table = {
      'a' * 80 => 'a' * 80,
      'a' * 81 => "#{'a' * 77}...",
      '<' * 400 => "#{'<' * 12}...",
      emoji * 40 => "#{emoji * 19}...",
      "é" * 100 => "#{"é" * 38}...",
      "#{'a' * 79}é" => "#{'a' * 77}..."
    }
    table.each do |label, expected|
      expect(cut(label)).to eq(expected), label[0, 10]
    end
    ["\u0001" * 30, " " * 30, "x " * 30, '"' * 50, '\\' * 50].each do |label|
      out = cut(label)
      expect(out).to be_valid_encoding
      expect(encoded_content(out)).to be <= 80
      expect(out).to end_with('...') unless encoded_content(label) <= 80
      expect(label).to start_with(out.delete_suffix('...'))
      longer = label[0, out.delete_suffix('...').length + 1]
      expect(encoded_content(longer) + 3).to be > 80 if out.end_with?('...')
    end
  end

  it 'scrubs invalid UTF-8 and cuts a 1,000,000-character label quickly' do
    expect(cut("ab\xFFcd".b)).to be_valid_encoding
    expect(cut("\xFF".b * 200)).to be_valid_encoding
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    out = cut('<' * 1_000_000)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    expect(out).to eq("#{'<' * 12}...")
    puts format('DCF PERF dependency delta 1,000,000-character label: %.1f ms', elapsed * 1000)
    expect(elapsed).to be < 0.5
  end

  # T-DEP-9, limits design V19: every sample list at its byte maximum stays
  # under 12,100 bytes and is stored byte-identical by AuditPayload. Added
  # and removed hold 20 pairs of labels cut to exactly 80 encoded bytes
  # (escaped and multibyte characters included); defaults hold 20 entries
  # that fill the 4,000-byte budget (one comma counted per entry).
  it 'keeps the worst case at most 12,100 bytes, never shrunk by AuditPayload (T-DEP-9)' do
    # '<' encodes to 6 bytes: P19 and P20 are 79 bytes uncut, the others cut to 80
    big_parents = (1..100).to_h do |i|
      ["P#{i}", [19, 20].include?(i) ? "#{'<' * 12}#{i}".ljust(19, 'b') : "#{'<' * 12}#{i}#{'a' * 200}"]
    end
    new_kids = (1..200).to_h { |i| ["C#{i}", "#{'&' * 12}#{i}#{'a' * 200}"] }
    old_kids = (1..200).to_h { |i| ["D#{i}", "#{" " * 6}#{"é" * 10}#{i}#{'x' * 200}"] }
    # 104 bytes of default labels (3 shown): an entry is 199 bytes, 198 for P19 and P20
    default_kids = { 'F1' => 'f' * 35, 'F2' => 'g' * 35, 'F3' => 'h' * 34, 'F4' => 'i' * 80 }
    new_vd = big_parents.keys.to_h { |pk| [pk, new_kids.keys] }
    old_vd = big_parents.keys.to_h { |pk| [pk, old_kids.keys] }
    new_dd = big_parents.keys.to_h { |pk| [pk, default_kids.keys] }
    d = delta(old_vd: old_vd, new_vd: new_vd, new_dd: new_dd, parent_labels: big_parents,
              child_labels: new_kids.merge(old_kids).merge(default_kids), source: 'import',
              import: { 'mode' => 'replace', 'rows' => 10_000_000 })

    after = d.after
    json = encode(after)
    puts "DCF PERF dependency delta worst case: #{json.bytesize} bytes"
    expect(after.slice('added', 'removed', 'defaults_changed')).to eq('added' => 20_000, 'removed' => 20_000,
                                                                     'defaults_changed' => 100)
    label = delta_class::LABEL_MAX_BYTES
    %w[added removed].each do |name|
      expect(after['sample'][name].flatten.map { |text| encoded_content(text) }.uniq).to eq([label])
    end
    expect(after['sample'].values.map(&:size)).to eq([20, 20, 20])
    pair_max = 2 + (delta_class::CAP * ((2 * (label + 2)) + 3)) + (delta_class::CAP - 1)
    expect(after['sample'].values.map { |list| encode(list).bytesize })
      .to eq([pair_max, pair_max, delta_class::LIST_MAX_BYTES - 1])
    expect(after['truncated']).to be(true)
    expect(json.bytesize).to be <= 12_100
    expect(RedmineDependingCustomFields::AuditPayload.encode(after)).to eq(json)
    expect(JSON.parse(RedmineDependingCustomFields::AuditPayload.encode(after))).not_to have_key('payload_truncated')
    expect(encode(d.before).bytesize).to be < 200
  end

  it 'runs no query and keeps no class-level state' do
    d = nil
    queries = dcf_count_queries do
      d = delta(old_vd: { 'A' => ['c1'] }, new_vd: { 'B' => %w[c2] }, new_dd: { 'B' => 'c2' })
      [d.before, d.after, d.summary]
    end
    expect(queries).to eq(0)
    expect(delta_class.instance_variables).to eq([])
    expect(delta_class.class_variables).to eq([])
    expect(d.after).to eq(d.after)
  end
end
