# frozen_string_literal: true

require_relative '../rails_helper'

# WP-12 (limits design 6.1 and 6.2, quality S5): the audit value cap.
RSpec.describe 'RedmineDependingCustomFields::AuditPayload' do
  let(:payload) { RedmineDependingCustomFields::AuditPayload }
  let(:cap) { 16_384 }

  def json(value)
    ActiveSupport::JSON.encode(value)
  end

  # Encodes +value+, checks the bound and the encoding, returns the parsed JSON.
  def capped(value, max_bytes: cap)
    out = payload.encode(value, max_bytes: max_bytes)
    expect(out).to be_a(String)
    expect(out.bytesize).to be <= max_bytes
    expect(out).to be_valid_encoding
    JSON.parse(out)
  end

  def s1_mapping
    parents = DcfLargeList.names(27, prefix: 'P')
    DcfLargeList.partition(parents, DcfLargeList.names(5570, tricky_every: 97))
  end

  def nested(depth, kind)
    (1..depth).inject('leaf') { |acc, i| kind == :hash ? { "k#{i}" => acc } : [acc] }
  end

  it 'has the limits of the design' do
    expect([payload::MAX_BYTES, payload::MAX_IDS, payload::MAX_ERROR_CHARS, payload::TOP_KEYS, payload::TOP_STRING])
      .to eq([16_384, 1_000, 4_000, 50, 200])
    expect(payload::LEVELS).to eq([
                                    { array: 20, keys: 50, string: 500, depth: 5 },
                                    { array: 10, keys: 20, string: 200, depth: 4 },
                                    { array: 5, keys: 10, string: 80, depth: 3 },
                                    { array: 1, keys: 5, string: 40, depth: 2 }
                                  ])
  end

  describe '.encode under the cap' do
    it 'keeps nil' do
      expect(payload.encode(nil)).to be_nil
    end

    it 'returns ActiveSupport::JSON output byte for byte' do
      values = [
        { added: 'C', position: nil }, { from: 'A' }, { to: 'A2' }, { removed: 'B' },
        { order: %w[B A], truncated: false }, { default_value: '<b>&</b>' },
        { renamed: [%w[X Y]], activated: [], deactivated: ['Z'], reordered: true },
        { value_dependencies: { 'A' => %w[a1 a2] }, default_value_dependencies: { 'A' => 'a1' } },
        { 'payload_sha256' => 'user', 'payload_truncated' => false },
        { 'u' => "  \u{1F600} é" }, 5, true, 'plain', [1, [2, [3]]]
      ]
      values.each { |value| expect(payload.encode(value)).to eq(json(value)) }
    end

    it 'returns a value of exactly 16,384 bytes unchanged and marks one byte more' do
      at_cap = { 'a' => 'x' * (cap - 8) }
      expect(json(at_cap).bytesize).to eq(cap)
      expect(payload.encode(at_cap)).to eq(json(at_cap))

      over = { 'a' => 'x' * (cap - 7) }
      expect(capped(over)['payload_truncated']).to be(true)
    end
  end

  describe '.encode above the cap' do
    it 'shrinks an S1-like mapping and keeps the top-level scalars and the markers' do
      value = { 'v' => 2, 'links' => 5562, 'mapping_sha256' => 'f' * 64, 'truncated' => false,
                'value_dependencies' => s1_mapping }
      full = json(value)
      expect(full.bytesize).to be > cap

      parsed = capped(value)
      expect(parsed['payload_truncated']).to be(true)
      expect(parsed['payload_bytes']).to eq(full.bytesize)
      expect(parsed['payload_sha256']).to eq(Digest::SHA256.hexdigest(full))
      expect(parsed.values_at('v', 'links', 'mapping_sha256', 'truncated')).to eq([2, 5562, 'f' * 64, false])
      expect(parsed['value_dependencies']).to be_a(Hash)
    end

    it 'shrinks the S1 project mapping save (82 KB) to the cap' do
      mapping = s1_mapping
      after = { value_dependencies: mapping, default_value_dependencies: DcfLargeList.first_child_defaults(mapping) }
      parsed = capped(after)
      expect(parsed['payload_bytes']).to eq(json(after).bytesize)
      expect(parsed['payload_bytes']).to be > 65_535
    end

    it 'marks cut arrays, hashes and strings' do
      value = { 'list' => Array.new(100) { |i| "v#{i}" }, 'map' => (1..100).index_by { |i| "k#{i}" },
                'nested' => { 'text' => 'y' * 20_000 } }
      parsed = capped(value)
      expect(parsed['list'].last).to match(/\A\(\+\d+ more\)\z/)
      expect(parsed['map']['(more)']).to be_a(Integer)
      expect(parsed['nested']['text']).to end_with('...')
    end

    it 'counts the omitted top-level keys' do
      parsed = capped((1..60).index_by { |i| "k#{i}" }.merge('big' => ['x' * 400] * 100))
      expect(parsed['(more)']).to eq(11)
      expect(parsed.keys.size).to eq(50 + 1 + 3)
    end

    # A user key named (more) is never kept in a shrunk Hash, so the marker
    # count is the exact number of omitted keys.
    it 'counts a user key named (more) as omitted' do
      map = { '(more)' => %w[u1 u2] }.merge((1..80).to_h { |i| ["parent #{i}", Array.new(20) { |j| "child #{i}-#{j}" }] })
      expect(json(map).bytesize).to be > cap
      shrunk = capped({ 'value_dependencies' => map })['value_dependencies']
      expect(shrunk['(more)']).to eq(map.size - (shrunk.size - 1))

      top = { '(more)' => 'user' }.merge((1..60).index_by { |i| "k#{i}" }).merge('big' => 'x' * 20_000)
      parsed = capped(top)
      expect(parsed['(more)']).to eq(top.size - (parsed.keys.size - 4))
    end

    it 'turns values below the kept depth into counts' do
      deep = { 'a' => { 'b' => { 'c' => { 'd' => { 'e' => { 'f' => %w[x y] } } } } }, 'pad' => ['z' * 400] * 50 }
      out = payload.encode(deep)
      expect(out.bytesize).to be <= cap
      expect(out).to match(/\(\d+ (keys|items)\)/)
    end

    it 'is deterministic' do
      value = { 'list' => Array.new(5_000) { |i| "v#{i}" }, 'o' => Object.new, 'b' => 'a' * 20_000 }
      other = { 'list' => Array.new(5_000) { |i| "v#{i}" }, 'o' => Object.new, 'b' => 'a' * 20_000 }
      expect(payload.encode(value)).to eq(payload.encode(value.deep_dup))
      expect(payload.encode(value)).to eq(payload.encode(other))
    end

    it 'encodes other objects through as_json' do
      time = Time.utc(2026, 1, 1)
      parsed = capped({ 't' => time, 'b' => 'a' * 20_000 })
      expect(parsed['t']).to eq(time.as_json)
    end

    it 'keeps the own keys of a shrunk project delta' do
      delta = { 'v' => 2, 'mapping_sha256' => 'e' * 64, 'truncated' => true, 'added' => 7,
                'sample' => Array.new(500) { |i| ["parent #{i}", "child #{i}"] } }
      parsed = capped(delta, max_bytes: 4_000)
      expect(parsed.values_at('mapping_sha256', 'truncated', 'added')).to eq(['e' * 64, true, 7])
      expect(parsed['payload_truncated']).to be(true)
    end

    it 'wraps a value that already holds a marker key under value' do
      [{ 'payload_sha256' => 'user', 'big' => 'a' * 20_000 }, { payload_truncated: false, big: 'a' * 20_000 }].each do |v|
        parsed = capped(v)
        expect(parsed.keys).to eq(%w[payload_truncated payload_bytes payload_sha256 value])
        expect(parsed['payload_truncated']).to be(true)
      end
      expect(capped({ 'payload_sha256' => 'user', 'big' => 'a' * 20_000 })['value']['payload_sha256']).to eq('user')
    end

    it 'wraps a value that is not a Hash under value' do
      parsed = capped(['a' * 100] * 500)
      expect(parsed.keys).to eq(%w[payload_truncated payload_bytes payload_sha256 value])
      expect(parsed['value']).to be_a(Array)
      expect(capped('x' * 20_000)['value']).to end_with('...')
    end

    it 'falls back to the markers alone' do
      parsed = capped({ 'a' => 'x' * 10_000 }, max_bytes: payload::MIN_BYTES)
      expect(parsed.keys).to contain_exactly('payload_truncated', 'payload_bytes', 'payload_sha256')
    end

    it 'refuses a cap the markers cannot meet' do
      expect { payload.encode('a' * 1_000, max_bytes: 100) }.to raise_error(ArgumentError)
    end

    it 'stays under the cap for adversarial input' do
      huge = "\u{1F600}<&>\"\\\u0001" * 30_000
      inputs = [
        huge, { 'a' => huge }, { huge => 1 }, nested(50, :hash), nested(50, :array),
        (1..100_000).index_by { |i| "key-#{i}" }, Array.new(10_000) { |i| Array.new(50) { |j| "#{i}-#{j}" } },
        { 'payload_sha256' => 'user', 'list' => Array.new(10_000) { |i| [i] } },
        '<' * 20_000, (1..60).to_h { |i| ["#{'<' * 300}#{i}", '<' * 300] }, { 's' => "\u{1F600}" * 10_000 },
        { 'n' => 10**20_000 }, 'é' * 20_000
      ]
      inputs.each do |value|
        parsed = capped(value)
        expect(parsed['payload_truncated']).to be(true) if json(value).bytesize > cap
      end
    end

    it 'never raises for values JSON cannot encode and marks them as truncated' do
      inputs = [
        { 'a' => (+"caf\xC3").force_encoding('UTF-8') }, (+"\xFF\xFE").force_encoding('BINARY'),
        nested(150, :array), nested(150, :hash), nested(20_000, :array), nested(20_000, :hash)
      ]
      inputs.each { |value| expect(capped(value)['payload_truncated']).to be(true) }
    end
  end

  describe '.encode_ids' do
    it 'keeps the first 1,000 ids as a JSON Array' do
      expect(JSON.parse(payload.encode_ids((1..5_000).to_a))).to eq((1..1_000).to_a)
      expect(payload.encode_ids([3, 1])).to eq('[3,1]')
      expect(payload.encode_ids([])).to eq('[]')
      expect(payload.encode_ids(nil)).to be_nil
    end

    it 'keeps only Integer ids, so the column stays bounded' do
      expect(payload.encode_ids(['x' * 100] * 2_000)).to eq('[]')
      expect(payload.encode_ids(['7', 8, nil])).to eq('[7,8]')
      expect(payload.encode_ids([2**63, 2**63 - 1, '1' * 19, '1' * 18])).to eq("[#{2**63 - 1},#{'1' * 18}]")
    end
  end

  describe '.error_message' do
    it 'cuts at 4,000 characters plus an ellipsis' do
      expect(payload.error_message('x' * 9_000).length).to eq(4_003)
      expect(payload.error_message('x' * 4_000)).to eq('x' * 4_000)
      expect(payload.error_message(nil)).to be_nil
      cut = payload.error_message('é' * 5_000)
      expect([cut.length, cut.bytesize]).to eq([4_003, 8_003])
      expect(payload.error_message(cut)).to eq(cut)
    end

    it 'scrubs invalid bytes' do
      expect(payload.error_message((+"\xFF").force_encoding('BINARY'))).to be_valid_encoding
      expect(payload.error_message((+"caf\xC3").force_encoding('UTF-8'))).to be_valid_encoding
    end
  end

  describe 'AuditRecorder' do
    fixtures :users

    let(:project) { dcf_create_project }
    let(:field) { dcf_list_field }
    let(:recorder) { RedmineDependingCustomFields::AuditRecorder.new(project: project, field: field, user: dcf_admin) }
    let(:events) { RedmineDependingCustomFields::ConfigAuditEvent }

    it 'stores small values byte-identical and large ones capped' do
      recorder.record_success!(action: 'add_value', before: { from: 'A' }, after: { 'big' => 'z' * 40_000 },
                               affected_child_field_ids: (1..1_500).to_a)
      row = events.order(:id).last
      expect(row.before_value).to eq(json({ from: 'A' }))
      expect(row.after_value.bytesize).to be <= cap
      expect(JSON.parse(row.after_value)['payload_truncated']).to be(true)
      expect(row.affected_child_field_ids_list).to eq((1..1_000).to_a)
    end

    it 'caps a large before value as well' do
      recorder.record_success!(action: 'rename_value', before: { 'big' => 'y' * 40_000 }, after: { to: 'B' })
      row = events.order(:id).last
      expect(row.before_value.bytesize).to be <= cap
      expect(JSON.parse(row.before_value)['payload_truncated']).to be(true)
      expect(row.after_value).to eq(json({ to: 'B' }))
    end

    it 'stores nil values as NULL' do
      recorder.record_success!(action: 'remove_value', before: { removed: 'A' }, after: nil)
      expect(events.order(:id).last.after_value).to be_nil
    end

    it 'writes the failure row for a message with invalid bytes' do
      expect do
        recorder.record_failure!(action: 'save_failed', status: 'save_failed',
                                 error_message: (+"bad \xFF").force_encoding('BINARY'))
      end.to change(events, :count).by(1)
      expect(events.order(:id).last.error_message).to be_valid_encoding
    end

    it 'caps a long failure message and keeps the summary at 1,000 characters' do
      recorder.record_failure!(action: 'save_failed', status: 'save_failed', error_message: 'm' * 9_000,
                               summary: 's' * 2_000)
      row = events.order(:id).last
      expect(row.error_message.length).to eq(4_003)
      expect(row.changes_summary.length).to eq(1_000)
    end
  end
end
