# frozen_string_literal: true

require_relative '../rails_helper'

# WP-21 (editor design 2, AD-18, SP-01, FM-18): DependencyPayload is the one
# parser of the dependency editor payload, for the admin virtual attribute
# (WP-22, parse) and DependencyMappingService (WP-27, parse!). It has no
# callers yet. Everything is pure except stored_digest, which reads a saved
# field. Timed examples print "DCF PERF" lines into the log.
RSpec.describe 'RedmineDependingCustomFields::DependencyPayload' do
  let(:payload) { RedmineDependingCustomFields::DependencyPayload }
  let(:codes) do
    [:not_a_string, :too_large, :number_too_long, :invalid_json, :not_an_object, :unknown_key, :unsupported_version,
     :invalid_source, :invalid_import, :invalid_base, :invalid_links, :invalid_defaults]
  end
  let(:max_bytes) { 4 * 1024 * 1024 }
  let(:long_digits) { '12345678901234567890' }

  def error_of(raw)
    payload.parse(raw)&.error
  end

  # The result of +raw+, asserting that JSON.parse never ran.
  def without_json_parse(raw)
    expect(JSON).not_to receive(:parse)
    payload.parse(raw)
  end

  def links_of(value_dependencies)
    result = payload.parse(JSON.generate('value_dependencies' => value_dependencies))
    expect(result).to be_ok, result.error.inspect
    result.value_dependencies
  end

  def defaults_of(default_value_dependencies)
    result = payload.parse(JSON.generate('default_value_dependencies' => default_value_dependencies))
    expect(result).to be_ok, result.error.inspect
    result.default_value_dependencies
  end

  def seconds
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  end

  # Best of three timed runs after one warm-up run.
  def fastest(&block)
    yield
    GC.start
    Array.new(3) { seconds(&block) }.min
  end

  def utf8(bytes)
    String.new(bytes, encoding: Encoding::UTF_8)
  end

  def report(text)
    RSpec.configuration.reporter.message("DCF PERF #{text} (Ruby #{RUBY_VERSION}, json #{JSON::VERSION})")
  end

  # Runs the block with Warning[:deprecated] on, so json deprecation warnings
  # (which can quote keys) would reach $stderr.
  def with_deprecation_warnings
    previous = Warning[:deprecated]
    Warning[:deprecated] = true
    yield
  ensure
    Warning[:deprecated] = previous
  end

  describe 'API' do
    it 'defines the constants of editor design 2.2' do
      expect(payload::VERSION).to eq(1)
      expect(payload::MAX_BYTES).to eq(4_194_304)
      expect(payload::MAX_NESTING).to eq(3)
      expect(payload::MAX_INTEGER_BITS).to eq(63)
      expect(payload::MAX_IMPORT_ROWS).to eq(10_000_000)
      expect(payload::TOP_LEVEL_KEYS).to eq(%w[version source import base value_dependencies default_value_dependencies])
      expect(payload::IMPORT_KEYS).to eq(%w[mode rows])
      expect(payload::SOURCES).to eq(%w[editor import])
      expect(payload::IMPORT_MODES).to eq(%w[merge replace])
      %w[TOP_LEVEL_KEYS IMPORT_KEYS SOURCES IMPORT_MODES].each do |name|
        expect(payload.const_get(name)).to be_frozen, name
        expect(payload.const_get(name)).to all(be_frozen)
      end
    end

    it 'has a keyword Result struct with ok? and an Invalid error with reason and bytes' do
      expect(payload::Result.members)
        .to eq([:value_dependencies, :default_value_dependencies, :source, :import, :base, :error, :bytes])
      expect(payload::Result.new(error: :invalid_json, bytes: 1)).not_to be_ok
      expect(payload::Result.new(bytes: 2)).to be_ok
      error = payload::Invalid.new(:invalid_json, 12)
      expect(error).to be_a(StandardError)
      expect([error.reason, error.bytes, error.message]).to eq([:invalid_json, 12, 'dependencies_json rejected: invalid_json (12 bytes)'])
    end

    it 'exposes parse, parse!, digest and stored_digest and hides its helpers' do
      [:parse, :parse!, :digest, :stored_digest].each { |name| expect(payload).to respond_to(name) }
      [:parse_string, :failure, :prescan, :decoded?, :build, :version?, :base?, :import_meta, :normalize_links, :normalize_defaults,
       :strings, :scalar, :blank?, :canonical, :text].each { |name| expect(payload).not_to respond_to(name), name.to_s }
    end

    it 'loads under the eager loader with the constant its file name gives, required by the plugin lib' do
      lib = File.expand_path('../../lib', __dir__)
      expect { Rails.autoloaders.main.eager_load_dir(lib) }.not_to raise_error
      path = File.join(lib, 'redmine_depending_custom_fields', 'dependency_payload.rb')
      expect(Rails.autoloaders.main.cpath_expected_at(path)).to eq('RedmineDependingCustomFields::DependencyPayload')
      expect(File.read(File.join(lib, 'redmine_depending_custom_fields.rb')))
        .to include("require_relative 'redmine_depending_custom_fields/dependency_payload'")
    end

    it 'keeps no state: no module variables, no cache, no logger' do
      raw = '{"value_dependencies":{"a":["b"]}}'
      first = payload.parse(raw)
      payload.parse!(raw)
      payload.digest({ 'a' => ['b'] }, nil)
      payload.stored_digest(IssueCustomField.new)
      second = payload.parse(raw)
      expect(second).to eq(first)
      expect(second).not_to equal(first)
      expect(second.value_dependencies).not_to equal(first.value_dependencies)
      expect(payload.instance_variables).to eq([])
      expect(payload.class_variables).to eq([])
      # Variable writes are scanned in spec/quality/format_singleton_state_spec.rb.
      source = File.read(File.expand_path('../../lib/redmine_depending_custom_fields/dependency_payload.rb', __dir__))
      expect(source).not_to match(/Thread\.current|Rails\.(?:cache|logger)|CurrentAttributes|dcf_memo/)
    end
  end

  describe 'blank and nil (AD-2)' do
    it 'returns nil for nil and for JSON white space only, before the size check' do
      expect(payload.parse(nil)).to be_nil
      ['', ' ', "  \n", "\t", " \r\n\t "].each { |raw| expect(payload.parse(raw)).to be_nil, raw.inspect }
      expect(payload.parse(' ' * (max_bytes + 1))).to be_nil
    end

    it 'treats other white space and NUL as content (invalid_json)' do
      ["\u00a0", "\u0000", "\u3000", "\v", "\f"].each do |raw|
        expect(error_of(raw)).to eq(:invalid_json), raw.inspect
      end
    end

    it "parses '{}' as an ok, empty mapping (a clear for the callers)" do
      result = payload.parse('{}')
      expect(result).to be_ok
      expect(result.to_h).to eq(value_dependencies: {}, default_value_dependencies: {}, source: 'editor',
                                import: nil, base: nil, error: nil, bytes: 2)
    end

    it 'raises Invalid :blank from parse! for nil and blank Strings' do
      [[nil, 0], ['', 0], ['  ', 2], ["  \n", 3], ["\t", 1]].each do |raw, bytes|
        expect { payload.parse!(raw) }.to raise_error(payload::Invalid) { |e|
          expect([e.reason, e.bytes, e.message]).to eq([:blank, bytes, "dependencies_json rejected: blank (#{bytes} bytes)"])
        }
      end
    end

    it 'returns the ok Result from parse! and goes through parse exactly once' do
      expect(payload).to receive(:parse).once.and_call_original
      result = payload.parse!('{"value_dependencies":{"a":["b"]}}')
      expect(result).to be_ok
      expect(result.value_dependencies).to eq('a' => ['b'])
    end

    it 'raises Invalid with the error code and the byte count of a failed parse' do
      expect(payload).to receive(:parse).once.and_call_original
      expect { payload.parse!('{"x":1}') }.to raise_error(payload::Invalid) { |e|
        expect([e.reason, e.bytes, e.message]).to eq([:unknown_key, 7, 'dependencies_json rejected: unknown_key (7 bytes)'])
      }
    end
  end

  describe 'input type' do
    it 'gives not_a_string with 0 bytes for anything but a String, without reading it' do
      upload = ActionDispatch::Http::UploadedFile.new(tempfile: Tempfile.new('dcf'), filename: 'm.json',
                                                     type: 'application/json')
      expect(upload).not_to receive(:read)
      object = Object.new
      expect(object).not_to receive(:to_s)
      expect(object).not_to receive(:inspect)
      [{ 'a' => 1 }, ActionController::Parameters.new('x' => '1'), ['{}'], 1, :x, true, false, upload, object].each do |raw|
        result = payload.parse(raw)
        expect([result.error, result.bytes]).to eq([:not_a_string, 0]), raw.class.name
        expect { payload.parse!(raw) }.to raise_error(payload::Invalid) { |e| expect([e.reason, e.bytes]).to eq([:not_a_string, 0]) }
      end
      # BasicObject has no nil?, is_a? or class.
      basic = BasicObject.new
      expect([payload.parse(basic).error, payload.parse(basic).bytes]).to eq([:not_a_string, 0])
      expect { payload.parse!(basic) }.to raise_error(payload::Invalid) { |e| expect(e.reason).to eq(:not_a_string) }
    end
  end

  describe 'encoding' do
    it 'gives invalid_json for invalid UTF-8 before the blank, size and pre-scan checks, without JSON.parse' do
      expect(JSON).not_to receive(:parse)
      broken = utf8("\xff\xfe")
      expect([payload.parse(broken).error, payload.parse(broken).bytes]).to eq([:invalid_json, 2])
      expect(error_of(utf8("\xff#{long_digits}"))).to eq(:invalid_json)
      expect(error_of(utf8(" \xff "))).to eq(:invalid_json)
      expect(error_of(utf8("#{'x' * (max_bytes + 1)}\xff"))).to eq(:invalid_json)
      expect(error_of(utf8("[\"\xff\"]"))).to eq(:invalid_json)
      expect(error_of("[\"\xff\"]".b)).to eq(:invalid_json)
    end

    it 're-tags a binary String on a copy: frozen input works and keeps its encoding' do
      raw = "{\"value_dependencies\":{\"\u00c4\":[\"\u00f6\"]}}".b.freeze
      result = payload.parse(raw)
      expect(result).to be_ok
      expect(result.value_dependencies).to eq("\u00c4" => ["\u00f6"])
      expect(result.bytes).to eq(raw.bytesize)
      expect(raw.encoding).to eq(Encoding::ASCII_8BIT)
      expect(raw).to be_frozen
      frozen = '{"value_dependencies":{"a":["b"]}}'
      expect(frozen).to be_frozen
      expect(payload.parse(frozen)).to be_ok
      expect(frozen.encoding).to eq(Encoding::UTF_8)
    end

    it 'does not strip a byte order mark or transcode other encodings' do
      expect(error_of(utf8("\xEF\xBB\xBF{}"))).to eq(:invalid_json)
      expect(error_of('{}'.encode(Encoding::UTF_16LE))).to eq(:invalid_json)
    end

    it 'gives invalid_json for a lone surrogate escape (decoded to invalid UTF-8) and keeps paired ones' do
      ['{"value_dependencies":{"\\udc00":["x"]}}', '{"value_dependencies":{"a":["\\udfff"]}}',
       '{"default_value_dependencies":{"a":"\\udc00"}}', '{"default_value_dependencies":{"a":["\\ud800"]}}',
       '{"source":"\\udc00"}', '{"base":"\\udc00"}'].each do |raw|
        expect(error_of(raw)).to eq(:invalid_json), raw
      end
      expect(links_of("\u{1F600}" => ["\u{1F600}"])).to eq("\u{1F600}" => ["\u{1F600}"])
      expect(payload.parse('{"value_dependencies":{"\\ud83d\\ude00":["x"]}}').value_dependencies).to eq("\u{1F600}" => ['x'])
    end
  end

  describe 'size (MAX_BYTES)' do
    # The prefix is 29 bytes and the suffix 4.
    def padded(bytes)
      "{\"value_dependencies\":{\"a\":[\"#{'x' * (bytes - 33)}\"]}}"
    end

    it 'accepts exactly MAX_BYTES and refuses one byte more before the pre-scan and JSON.parse' do
      expect(padded(max_bytes).bytesize).to eq(max_bytes)
      expect(payload.parse(padded(max_bytes))).to be_ok
      result = without_json_parse(padded(max_bytes + 1))
      expect([result.error, result.bytes]).to eq([:too_large, 4_194_305])
    end

    it 'counts bytes, not characters, and wins over invalid JSON and long numbers' do
      expect(JSON).not_to receive(:parse)
      expect(error_of("\u00e9" * 2_097_153)).to eq(:too_large)
      expect(error_of('{' * (max_bytes + 1))).to eq(:too_large)
      expect(error_of("[#{'9' * (max_bytes + 1)}]")).to eq(:too_large)
      expect { payload.parse!('[' * (max_bytes + 1)) }.to raise_error(payload::Invalid) { |e| expect(e.reason).to eq(:too_large) }
    end
  end

  describe 'pre-scan (SP-01)' do
    it 'rejects a 1,000,000-digit integer in under 100 ms without calling JSON.parse' do
      raw = "{\"value_dependencies\":{\"a\":[#{'9' * 1_000_000}]}}"
      expect(without_json_parse(raw).error).to eq(:number_too_long)
      elapsed = fastest { payload.parse(raw) }
      report(format('1,000,000-digit integer rejected in %.3f ms', elapsed * 1000))
      expect(elapsed).to be < 0.1
    end

    it 'rejects 20-digit integers, negatives, fractions and exponents anywhere, without JSON.parse' do
      expect(JSON).not_to receive(:parse)
      [
        "{\"value_dependencies\":{\"a\":[#{long_digits}]}}",
        "{\"value_dependencies\":{\"a\":[-#{long_digits}]}}",
        "{\"value_dependencies\":{\"a\":[1.#{long_digits}]}}",
        "{\"value_dependencies\":{\"a\":[0.#{long_digits}]}}",
        "{\"value_dependencies\":{\"a\":[1e#{long_digits}]}}",
        "{\"value_dependencies\":{\"a\":[1E-#{long_digits}]}}",
        "{\"default_value_dependencies\":{\"a\":#{long_digits}}}",
        "{\"version\":#{long_digits}}",
        "{\"source\":\"import\",\"import\":{\"mode\":\"merge\",\"rows\":#{long_digits}}}",
        "[#{long_digits}]",
        long_digits
      ].each do |raw|
        result = payload.parse(raw)
        expect([result.error, result.bytes]).to eq([:number_too_long, raw.bytesize]), raw
      end
    end

    it 'rejects a long number after 1 MiB of ordinary entries within the 1 s smoke bound' do
      entries = Array.new(30_000) { |i| "\"parent #{i}\":[\"child #{i}\",\"c #{i}\"]" }.join(',')
      raw = "{\"value_dependencies\":{#{entries},\"a\":[#{'9' * 1_000_000}]}}"
      expect(raw.bytesize).to be > 2_000_000
      expect(without_json_parse(raw).error).to eq(:number_too_long)
      elapsed = fastest { payload.parse(raw) }
      report(format('long number after %d bytes of entries rejected in %.1f ms', raw.bytesize - 1_000_000, elapsed * 1000))
      expect(elapsed).to be < 1
    end

    it 'never flags digits inside strings' do
      allow(JSON).to receive(:parse).and_call_original
      key = "a,#{long_digits}123"
      expect(links_of(key => ["x\"#{long_digits}", '+32 470 12 34 56 78 90 12 34', 'BE71096123456769123456789012'],
                      long_digits => [long_digits]))
        .to eq(key => ["x\"#{long_digits}", '+32 470 12 34 56 78 90 12 34', 'BE71096123456769123456789012'],
               long_digits => [long_digits])
      expect(payload.parse(JSON.generate('base' => '1' * 64)).base).to eq('1' * 64)
      expect(JSON).to have_received(:parse).exactly(2).times
    end

    it 'ends a string exactly where JSON does (escaped backslash, escaped quote)' do
      expect(JSON).not_to receive(:parse)
      ["[\"x\\\\\",#{long_digits}]", "[\"\\\"\",#{long_digits}]", "[\"a\\\\\\\"\",#{long_digits}]"].each do |raw|
        expect(payload.parse(raw).error).to eq(:number_too_long), raw
      end
    end

    it 'flags a long digit run in the tail of an unterminated string (fail closed)' do
      expect(JSON).not_to receive(:parse)
      ["{\"a\":[\"x#{long_digits}", "[\"abc, #{long_digits}]", "\\\"#{'\\"' * 1000}#{long_digits}"].each do |raw|
        expect(payload.parse(raw).error).to eq(:number_too_long), raw[0, 40]
      end
      expect(payload.parse('{"a":["x/y').error).to eq(:invalid_json)
    end

    it 'lets 19 digits through to JSON.parse and the integer rule' do
      allow(JSON).to receive(:parse).and_call_original
      expect(error_of('{"value_dependencies":{"a":[9999999999999999999]}}')).to eq(:invalid_links)
      expect(links_of('a' => [9_223_372_036_854_775_807])).to eq('a' => ['9223372036854775807'])
      expect(JSON).to have_received(:parse).twice
    end

    it 'rejects a slash outside strings (a JSON comment) without JSON.parse, on every json version' do
      expect(JSON).not_to receive(:parse)
      digits = '9' * 1_000_000
      ["{\"value_dependencies\":{\"a\":[/*\"*/#{digits}/*\"*/]}}",
       "{\"value_dependencies\":{\"a\":[//\"\n#{digits}]}}",
       '{"a":/*x*/["b"]}', "{\"a\":[\"b\"]//\n}", '/'].each do |raw|
        result = payload.parse(raw)
        expect(result.error).to eq(:invalid_json), raw[0, 40]
      end
      elapsed = fastest { payload.parse("{\"value_dependencies\":{\"a\":[/*\"*/#{digits}/*\"*/]}}") }
      expect(elapsed).to be < 0.1
    end

    it 'accepts slashes inside strings' do
      expect(links_of('a/b' => ['a/b', 'http://x/y', '/'])).to eq('a/b' => ['a/b', 'http://x/y', '/'])
      expect(payload.parse('{"value_dependencies":{"a":["\\/"]}}').value_dependencies).to eq('a' => ['/'])
    end

    # json 2.6 and 2.7 decode an invalid escape to the bare character, 2.21
    # rejects it.
    it 'rejects invalid escapes without JSON.parse, on every json version' do
      expect(JSON).not_to receive(:parse)
      ['{"value_dependencies":{"a":["\\x"]}}', '{"value_dependencies":{"a":["\\\'"]}}', '{"value_dependencies":{"a":["\\a"]}}',
       '{"value_dependencies":{"a":["\\U0041"]}}', '{"value_dependencies":{"a":["b\\0"]}}', '{"value_dependencies":{"\\x":["a"]}}',
       '{"source":"\\ "}', "{\"value_dependencies\":{\"a\":[\"\\\n\"]}}", "[\"\\\u00e9\"]"].each do |raw|
        expect(error_of(raw)).to eq(:invalid_json), raw
      end
      # As for an unterminated string: a 20-digit run after it is number_too_long.
      expect(error_of("{\"value_dependencies\":{\"a\":[\"\\x\",#{long_digits}]}}")).to eq(:number_too_long)
    end

    it 'decodes every valid escape, also when an escaped backslash precedes a letter' do
      allow(JSON).to receive(:parse).and_call_original
      raw = '{"value_dependencies":{"a\\\\x":["\\"\\\\\\/\\b\\f\\n\\r\\t\\u00e9\\\\\'"]}}'
      expect(payload.parse(raw).value_dependencies).to eq("a\\x" => ["\"\\/\b\f\n\r\t\u00e9\\'"])
      expect(JSON).to have_received(:parse).once
    end

    it 'stays linear on escape-heavy unterminated strings' do
      expect(JSON).not_to receive(:parse)
      small = '\\"' * 200_000 + long_digits
      tail = "{\"a\":[\"#{'x\\"' * 200_000}#{long_digits}"
      # A quadratic scan takes seconds here on Ruby 2.7 to 3.1.
      [small, tail].each do |raw|
        expect(payload.parse(raw).error).to eq(:number_too_long)
        expect(fastest { payload.parse(raw) }).to be < 0.5
      end
      big = "\"#{'\\"' * ((max_bytes - 30) / 2)}#{long_digits}"
      expect(big.bytesize).to be <= max_bytes
      elapsed = fastest { expect(payload.parse(big).error).to eq(:number_too_long) }
      report(format('4 MiB unterminated escaped-quote string scanned in %.1f ms', elapsed * 1000))
      # The 4 MiB budget; a quadratic scan would take hours.
      expect(elapsed).to be < 2.5
    end

    # Ruby 3.2 added a regex match cache that hides backtracking blowups; a
    # back reference turns it off, as on Ruby 2.7 to 3.1.
    it 'stays linear with the regex match cache turned off' do
      names = payload.constants.select { |name| payload.const_get(name).is_a?(Regexp) }
      expect(names).to include(:SCAN_GATE, :SCAN_STRING_REST, :BLANK)
      names.each do |name|
        original = payload.const_get(name)
        uncached = Regexp.new("#{original.source}|()\\1(?!)", original.options)
        expect(Regexp.linear_time?(uncached)).to be(false) if Regexp.respond_to?(:linear_time?)
        stub_const("RedmineDependingCustomFields::DependencyPayload::#{name}", uncached)
      end
      {
        "\"#{'\\"' * 32_000}#{long_digits}" => :number_too_long,
        "{\"a\":[\"#{'x\\"' * 32_000}#{long_digits}" => :number_too_long,
        "#{"\"\\\n" * 20_000}#{long_digits}" => :number_too_long,
        "[#{"\"#{'a' * 20}\"," * 3_000}#{long_digits}]" => :number_too_long,
        JSON.generate('value_dependencies' => { 'a/b' => ["#{' ' * 100_000}x", ' ' * 100_000] }) => nil
      }.each do |raw, code|
        result = nil
        elapsed = seconds { result = payload.parse(raw) }
        expect(result.error).to eq(code)
        expect(elapsed).to be < 0.1
      end
    end
  end

  describe 'JSON decoding' do
    it 'decodes with JSON.parse, max_nesting 3, no additions and duplicate keys allowed' do
      raw = '{"value_dependencies":{"a":["b"]}}'
      allow(JSON).to receive(:parse).and_call_original
      expect(payload.parse(raw)).to be_ok
      expect(JSON).to have_received(:parse).once
        .with(raw, hash_including(max_nesting: 3, create_additions: false, allow_duplicate_key: true))
    end

    it 'gives invalid_json for malformed documents, NaN, Infinity and trailing commas' do
      ['{"value_dependencies"', '{"x":NaN}', '{"value_dependencies":{"a":[NaN]}}', '[Infinity]', '[-Infinity]',
       '{"value_dependencies":{"a":["b",]}}', '{"value_dependencies":{"a":["b"],}}', "{'a':1}", '{"a":1}}',
       "{\"value_dependencies\":{\"a\":[\"b\u0001\"]}}", '{"value_dependencies":{"a":["\\x"]}}',
       '{"value_dependencies":{"a":["\\\'"]}}', 'nul', ']'].each do |raw|
        expect(error_of(raw)).to eq(:invalid_json), raw
      end
    end

    it 'gives invalid_json for nesting deeper than 3, before the schema checks, on every json version' do
      ['{"value_dependencies":{"a":[["x"]]}}', '{"value_dependencies":{"a":[{"k":1}]}}',
       '{"default_value_dependencies":{"a":[["x"]]}}', '{"value_dependencies":{"a":[[]]}}',
       '{"value_dependencies":{"a":[{}]}}', '{"default_value_dependencies":{"a":[{}]}}',
       '{"meta":{"a":{"b":["x"]}}}', '{"meta":{"a":{"b":{}}}}', '[[[[]]]]', '[[[["x"]]]]'].each do |raw|
        expect(error_of(raw)).to eq(:invalid_json), raw
      end
    end

    it 'never keeps a parser message (they quote the input)' do
      raw = '{"value_dependencies":{"SECRET_MARKER":["a"]'
      expect { payload.parse!(raw) }.to raise_error(payload::Invalid) { |e|
        expect([e.reason, e.bytes, e.cause]).to eq([:invalid_json, raw.bytesize, nil])
        expect(e.full_message).not_to include('SECRET_MARKER')
      }
      expect(payload.parse(raw).inspect).not_to include('SECRET_MARKER')
    end

    it 'raises Invalid without a cause also inside a rescue clause of the caller' do
      raise ArgumentError, 'SECRET_MARKER'
    rescue ArgumentError
      expect { payload.parse!('[') }.to raise_error(payload::Invalid) { |e| expect(e.cause).to be_nil }
      expect { payload.parse!(' ') }.to raise_error(payload::Invalid) { |e| expect(e.cause).to be_nil }
    end

    it 'keeps json_class and date-like values as plain data' do
      previous = ActiveSupport.parse_json_times
      ActiveSupport.parse_json_times = true
      result = payload.parse('{"value_dependencies":{"json_class":["JSON::GenericObject"],"2024-01-01":["2024-01-01T10:00:00Z"]}}')
      expect(result.value_dependencies).to eq('json_class' => ['JSON::GenericObject'], '2024-01-01' => ['2024-01-01T10:00:00Z'])
    ensure
      ActiveSupport.parse_json_times = previous
    end

    it 'takes the last of duplicate keys silently (no warning that would quote the key)' do
      with_deprecation_warnings do
        raw = '{"value_dependencies":{"SECRET_MARKER":["a"],"SECRET_MARKER":["b"]},"source":"x","source":"import"}'
        result = nil
        expect { result = payload.parse(raw) }.not_to output.to_stderr
        expect(result.value_dependencies).to eq('SECRET_MARKER' => ['b'])
        expect(result.source).to eq('import')
      end
    end
  end

  describe 'schema' do
    it 'gives not_an_object for anything but a JSON object' do
      ['null', '1', 'true', '"x"', '[]', '[{}]'].each { |raw| expect(error_of(raw)).to eq(:not_an_object), raw }
    end

    it 'gives unknown_key for any top-level key outside the six, meta and json_class included' do
      ['{"meta":{"source":"import"}}', '{"json_class":"Foo"}', '{"Value_dependencies":{}}', '{" version":1}',
       '{"__proto__":{}}', '{"value_dependencies":{},"x":null}'].each do |raw|
        expect(error_of(raw)).to eq(:unknown_key), raw
      end
    end

    it 'checks in the order of editor design 2.2 step 7 (the first failure wins)' do
      {
        '{"meta":1,"version":2}' => :unknown_key,
        '{"meta":1,"source":"x"}' => :unknown_key,
        '{"version":2,"source":"x"}' => :unsupported_version,
        '{"source":"x","import":{"mode":"merge","rows":1}}' => :invalid_source,
        '{"source":"x","base":"zz"}' => :invalid_source,
        '{"source":"import","import":{"mode":"x","rows":1},"base":"zz"}' => :invalid_import,
        '{"import":null,"value_dependencies":{"a":"x"}}' => :invalid_import,
        '{"base":"zz","value_dependencies":{"a":"x"}}' => :invalid_base,
        '{"value_dependencies":{"a":"x"},"default_value_dependencies":{"a":null}}' => :invalid_links,
        '{"default_value_dependencies":{"a":null}}' => :invalid_defaults
      }.each { |raw, code| expect(error_of(raw)).to eq(code), raw }
    end

    it 'accepts only the Integer 1 as version' do
      expect(payload.parse('{"version":1}')).to be_ok
      ['1.0', '"1"', 'null', 'true', '0', '2', '-1', '[1]'].each do |version|
        expect(error_of("{\"version\":#{version}}")).to eq(:unsupported_version), version
      end
    end

    it 'defaults source to editor and accepts only editor or import' do
      expect(payload.parse('{}').source).to eq('editor')
      expect(payload.parse('{"source":"editor"}').source).to eq('editor')
      expect(payload.parse('{"source":"import"}').source).to eq('import')
      ['"Editor"', '"EDITOR"', 'null', '""', '"form"', '["import"]', '1', 'true'].each do |source|
        expect(error_of("{\"source\":#{source}}")).to eq(:invalid_source), source
      end
    end

    it 'accepts import only with source import and exactly mode and rows' do
      result = payload.parse('{"version":1,"source":"import","import":{"mode":"replace","rows":5000}}')
      expect(result).to be_ok
      expect(result.import).to eq('mode' => 'replace', 'rows' => 5000)
      expect(payload.parse('{"source":"import","import":{"rows":0,"mode":"merge"}}').import).to eq('mode' => 'merge', 'rows' => 0)
      expect(payload.parse('{"source":"import","import":{"mode":"merge","rows":10000000}}').import['rows']).to eq(10_000_000)
      only_source = payload.parse('{"source":"import"}')
      expect([only_source.ok?, only_source.import]).to eq([true, nil])
      expect(payload.parse('{}').import).to be_nil
    end

    it 'gives invalid_import for import without source import and for any other shape' do
      ok = '"mode":"merge","rows":1'
      [
        "{\"source\":\"editor\",\"import\":{#{ok}}}", "{\"import\":{#{ok}}}", '{"import":null}',
        '{"source":"import","import":null}', '{"source":"import","import":{"mode":"x","rows":1}}',
        '{"source":"import","import":{"mode":"MERGE","rows":1}}', '{"source":"import","import":{"mode":"merge","rows":-1}}',
        '{"source":"import","import":{"mode":"merge","rows":10000001}}', '{"source":"import","import":{"mode":"merge","rows":1.0}}',
        '{"source":"import","import":{"mode":"merge","rows":"5"}}', '{"source":"import","import":{"mode":"merge","rows":true}}',
        '{"source":"import","import":{"mode":"merge"}}', '{"source":"import","import":{"rows":1}}',
        "{\"source\":\"import\",\"import\":{#{ok},\"x\":1}}", '{"source":"import","import":{}}',
        '{"source":"import","import":["merge",1]}', '{"source":"import","import":"merge"}',
        '{"source":"import","import":{"mode":null,"rows":1}}'
      ].each { |raw| expect(error_of(raw)).to eq(:invalid_import), raw }
    end

    it 'accepts a base of 64 lowercase hex characters only, and returns it unchanged' do
      digest = payload.digest({ 'a' => ['b'] }, {})
      [digest, 'a' * 64, '0' * 64].each do |base|
        result = payload.parse(JSON.generate('base' => base))
        expect([result.ok?, result.base]).to eq([true, base])
      end
      expect(payload.parse('{}').base).to be_nil
      ['A' * 64, 'a' * 63, 'a' * 65, "#{'a' * 64}\n", "\n#{'a' * 64}", "#{'a' * 63}g", 'zz', '', nil, ['a' * 64], 123,
       { 'a' => 'b' }].each do |base|
        expect(error_of(JSON.generate('base' => base))).to eq(:invalid_base), base.inspect
      end
    end

    it 'does not compare base with the stored mapping (a stale base parses)' do
      stale = payload.digest({ 'old' => ['x'] }, {})
      expect(payload.parse(JSON.generate('base' => stale, 'value_dependencies' => { 'new' => ['y'] })).base).to eq(stale)
    end
  end

  describe 'value_dependencies' do
    it 'round-trips brackets and prototype-like keys byte for byte and in order' do
      keys = ['Foo [x]', 'a]', '[', ']', '[]', 'a[b][c]', '__proto__', 'constructor', 'prototype', 'toString',
              'hasOwnProperty', 'json_class', '&amp;', '<script>alert(1)</script>', "\u00e9\u00e8", "\u{1F600}", '11',
              "a\nb", "a\u2028b", "tab\there", '"quoted"', 'back\\slash']
      mapping = keys.each_with_index.to_h { |key, i| [key, ["v#{i}]", "[w#{i}"]] }
      result = links_of(mapping)
      expect(result).to eq(mapping)
      expect(result.keys).to eq(keys)
      expect(result.keys).to all(be_a(String))
      expect(links_of('Foo [x]' => ['a]', '[b'])).to eq('Foo [x]' => ['a]', '[b'])
      expect(links_of('__proto__' => ['a'], 'constructor' => ['b']).keys).to eq(%w[__proto__ constructor])
    end

    it 'stringifies integers, drops blanks and keeps the first of duplicates' do
      expect(links_of('11' => [21])).to eq('11' => ['21'])
      expect(links_of('a' => ['b', 'a', 'b', 1, '1', '', ' ', "\u00a0"])).to eq('a' => %w[b a 1])
      expect(links_of('a' => ['x', 'x', 1, '1', ''])).to eq('a' => %w[x 1])
      expect(links_of('' => ['x'], ' ' => ['x'], "\t" => ['y'], 'b' => [], 'c' => ['', ' '])).to eq({})
      expect(links_of('a ' => [' x ', 'y'])).to eq('a ' => [' x ', 'y'])
    end

    it 'treats a missing key as {} and rejects anything but an object of arrays' do
      expect(payload.parse('{"default_value_dependencies":{}}').value_dependencies).to eq({})
      ['{"value_dependencies":null}', '{"value_dependencies":[]}', '{"value_dependencies":["a"]}',
       '{"value_dependencies":"a"}', '{"value_dependencies":{"a":"x"}}', '{"value_dependencies":{"a":null}}',
       '{"value_dependencies":{"a":{"b":"c"}}}', '{"value_dependencies":{"a":1}}', '{"value_dependencies":{"":"x"}}'].each do |raw|
        expect(error_of(raw)).to eq(:invalid_links), raw
      end
    end

    it 'accepts integers only when positive with at most 63 bits, checked before to_s' do
      expect(links_of('a' => [1, 9_223_372_036_854_775_807])).to eq('a' => %w[1 9223372036854775807])
      %w[9223372036854775808 9999999999999999999 0 -1 -0 -9223372036854775807 1.5 1.0 1e2 1e400 -1e400 true false null
         "x",1.5].each do |value|
        expect(error_of("{\"value_dependencies\":{\"a\":[#{value}]}}")).to eq(:invalid_links), value
        expect(error_of("{\"value_dependencies\":{\"\":[#{value}]}}")).to eq(:invalid_links), value
      end
    end

    it 'still bounds integers when the pre-scan is bypassed (defense in depth)' do
      allow(payload).to receive(:prescan).and_return(nil)
      raw = "{\"value_dependencies\":{\"a\":[#{'9' * 1_000_000}]}}"
      result = nil
      # JSON.parse alone takes about 0.3 s; Integer#to_s would add 5 s.
      elapsed = fastest { result = payload.parse(raw) }
      expect(result.error).to eq(:invalid_links)
      expect(elapsed).to be < 3
    end
  end

  describe 'default_value_dependencies' do
    it 'keeps the submitted shape: a String stays a String, an Array an Array of Strings' do
      expect(defaults_of('A' => 'x', 'B' => 2, 'C' => ['y', 3, 'y', '3'], 'D' => ['z']))
        .to eq('A' => 'x', 'B' => '2', 'C' => %w[y 3], 'D' => ['z'])
    end

    it 'drops blank keys and values and empty lists, and keeps hostile keys in order' do
      expect(defaults_of('A' => '', 'B' => [], 'C' => ' ', 'D' => ['', ' '], '' => 'x', ' ' => ['x'])).to eq({})
      expect(defaults_of('__proto__' => 'a', 'Foo [x]' => ['a]'], 'constructor' => 1))
        .to eq('__proto__' => 'a', 'Foo [x]' => ['a]'], 'constructor' => '1')
      expect(defaults_of('__proto__' => 'a').keys).to eq(['__proto__'])
    end

    it 'does not cross-check defaults against links (pruning is DependencyRules.prune_mapping)' do
      result = payload.parse('{"value_dependencies":{"a":["x"]},"default_value_dependencies":{"p":"y","a":"z"}}')
      expect(result.default_value_dependencies).to eq('p' => 'y', 'a' => 'z')
    end

    it 'gives invalid_defaults for null, objects, floats, booleans and bad integers' do
      expect(payload.parse('{"value_dependencies":{}}').default_value_dependencies).to eq({})
      %w[null {"x":1} {} [true] [null] true false 1.5 [1.5] 0 -1 [0] 9223372036854775808 1e400].each do |value|
        expect(error_of("{\"default_value_dependencies\":{\"a\":#{value}}}")).to eq(:invalid_defaults), value
      end
      ['{"default_value_dependencies":null}', '{"default_value_dependencies":[]}', '{"default_value_dependencies":"a"}']
        .each { |raw| expect(error_of(raw)).to eq(:invalid_defaults), raw }
    end
  end

  describe 'Result' do
    it 'carries only the error and the byte count on failure' do
      result = payload.parse('{"value_dependencies":{"SECRET_MARKER":[1.5]}}')
      expect(result).not_to be_ok
      expect(result.to_h.compact).to eq(error: :invalid_links, bytes: result.bytes)
      expect(result.inspect).not_to include('SECRET_MARKER')
      expect([payload.parse('{"x":1}').bytes, payload.parse('[').bytes]).to eq([7, 1])
    end

    it 'returns plain, mutable Hashes with String keys on success' do
      result = payload.parse('{"value_dependencies":{"a":["b"]},"default_value_dependencies":{"a":"b"},' \
                             '"source":"import","import":{"mode":"merge","rows":1}}')
      [result.value_dependencies, result.default_value_dependencies, result.import].each do |hash|
        expect(hash.class).to eq(Hash)
        expect(hash).not_to be_frozen
        expect(hash.keys).to all(be_a(String))
      end
      result.default_value_dependencies['a'] = ['b']
      expect(result.bytes).to eq(result.to_h[:bytes])
    end
  end

  describe 'never raises' do
    def random_value(rng, depth)
      case depth.positive? ? rng.rand(8) : rng.rand(5)
      when 0 then ['x', '', ' ', 'a]', "\u00e9", '\\', '"', '/'].sample(random: rng)
      when 1 then [1, 0, -1, 2**63, 2**63 - 1, 1.5].sample(random: rng)
      when 2 then [true, false, nil].sample(random: rng)
      when 3 then 'k' * rng.rand(3)
      when 4 then rng.rand(10**25)
      when 5, 6 then Array.new(rng.rand(3)) { random_value(rng, depth - 1) }
      else Array.new(rng.rand(3)) { [random_key(rng), random_value(rng, depth - 1)] }.to_h
      end
    end

    def random_key(rng)
      (payload::TOP_LEVEL_KEYS + %w[mode rows meta a]).sample(random: rng)
    end

    it 'returns nil or a Result with a known code for fuzzed input, and parse! raises only Invalid' do
      rng = Random.new(21)
      valid = JSON.generate('version' => 1, 'source' => 'import', 'import' => { 'mode' => 'merge', 'rows' => 3 },
                            'base' => 'a' * 64, 'value_dependencies' => { 'Foo [x]' => ['a]', 7], '__proto__' => ["\u00e9"] },
                            'default_value_dependencies' => { 'Foo [x]' => 'a]' })
      inserts = ['"', '\\', '/', '[', '{', ']', '}', ',', ':', '1' * 25, '-', 'e', '.', "\xff".b, 'null', '\\u', '\\udc00']
      inputs = Array.new(5_000) do
        case rng.rand(4)
        when 0 then valid[0, rng.rand(valid.size)]
        when 1
          bytes = valid.b
          bytes.setbyte(rng.rand(bytes.bytesize), rng.rand(256))
          bytes.force_encoding(Encoding::UTF_8)
        when 2 then valid.b.insert(rng.rand(valid.bytesize), inserts.sample(random: rng).b).force_encoding(Encoding::UTF_8)
        else JSON.generate(Array.new(rng.rand(4)) { [random_key(rng), random_value(rng, rng.rand(5))] }.to_h)
        end
      end
      outcomes = Hash.new(0)
      inputs.each do |raw|
        result = payload.parse(raw)
        expect(result).to be_nil.or(be_a(payload::Result))
        expect(codes).to include(result.error) if result && !result.ok?
        outcomes[result.nil? ? :nil : result.error || :ok] += 1
        begin
          payload.parse!(raw)
        rescue payload::Invalid => e
          expect(codes + [:blank]).to include(e.reason)
        end
      end
      expect(outcomes.keys).to include(:ok, :invalid_json, :unknown_key)
    end
  end

  describe 'no content in logs, warnings or messages (SP-06, SP-09)' do
    it 'writes nothing to the log or to stderr and keeps payload content out of every error' do
      io = StringIO.new
      allow(Rails).to receive(:logger).and_return(Logger.new(io))
      marker = 'SECRET_MARKER'
      raws = [
        "{\"#{marker}\":1", "{\"meta\":\"#{marker}\"}", "{\"value_dependencies\":{\"a\":[/*#{marker}*/\"b\"]}}",
        "{\"value_dependencies\":{\"#{marker}\":[\"a\"],\"#{marker}\":[\"b\"]},\"meta\":1}",
        utf8("\xEF\xBB\xBF{\"#{marker}\":1}"),
        "{\"value_dependencies\":{\"#{marker}\\udc00\":[\"x\"]}}", "{\"value_dependencies\":{\"#{marker}\":[1.5]}}",
        "{\"value_dependencies\":{\"#{marker}\":[\"#{'x' * max_bytes}\"]}}", "[\"#{marker}\",#{long_digits}]",
        "{\"source\":\"#{marker}\"}", "{\"base\":\"#{marker}\"}"
      ]
      with_deprecation_warnings do
        raws.each do |raw|
          expect do
            result = payload.parse(raw)
            expect(result).not_to be_ok
            expect(result.inspect).not_to include(marker)
            expect { payload.parse!(raw) }.to raise_error(payload::Invalid) { |e|
              expect(e.cause).to be_nil
              expect(e.full_message).not_to include(marker)
              expect(e.message).to eq("dependencies_json rejected: #{e.reason} (#{raw.bytesize} bytes)")
            }
          end.not_to output.to_stderr
        end
      end
      expect(io.string).to eq('')
    end
  end

  describe '.digest' do
    let(:empty) { payload.digest({}, {}) }

    it 'is 64 lowercase hex characters and accepted as base' do
      digest = payload.digest({ 'a' => ['b'] }, { 'a' => 'b' })
      expect(digest).to match(/\A[0-9a-f]{64}\z/)
      expect(payload.parse(JSON.generate('base' => digest))).to be_ok
    end

    it 'ignores key and value order, blanks, empty lists and duplicates; nil equals {}' do
      expect(payload.digest({ 'a' => %w[y x], 'b' => ['1'] }, nil)).to eq(payload.digest({ 'b' => [1], 'a' => %w[x y] }, {}))
      expect(payload.digest({ 'a' => %w[y x] }, { 'p' => %w[b a] })).to eq(payload.digest({ 'a' => %w[x y] }, { 'p' => %w[a b] }))
      expect(payload.digest(nil, nil)).to eq(empty)
      expect(payload.digest({ 'a' => [] }, { 'b' => '' })).to eq(empty)
      expect(payload.digest({ '' => ['a'], ' ' => ['b'], 'c' => ['', ' ', nil] }, {})).to eq(empty)
      expect(payload.digest({ 'a' => %w[x x] }, {})).to eq(payload.digest({ 'a' => ['x'] }, {}))
    end

    it 'equals for HashWithIndifferentAccess, Symbol keys, Integer values and String or Array defaults' do
      plain = payload.digest({ 'a' => ['1'], '2' => ['x'] }, { 'a' => ['1'] })
      expect(payload.digest(ActiveSupport::HashWithIndifferentAccess.new('a' => ['1'], '2' => ['x']),
                            ActiveSupport::HashWithIndifferentAccess.new('a' => '1'))).to eq(plain)
      expect(payload.digest({ :a => [1], 2 => [:x] }, { a: 1 })).to eq(plain)
      expect(payload.digest(nil, { 'A' => 'x' })).to eq(payload.digest({}, { 'A' => ['x'] }))
    end

    it 'distinguishes links from defaults and keeps keys and values apart' do
      expect(payload.digest({ 'A' => ['x'] }, {})).not_to eq(payload.digest({}, { 'A' => ['x'] }))
      expect(payload.digest({ 'a,b' => ['c'] }, {})).not_to eq(payload.digest({ 'a' => ['b,c'] }, {}))
      expect(payload.digest({ 'a' => ['b', 'c'] }, {})).not_to eq(payload.digest({ 'a' => ['b,c'] }, {}))
      expect(payload.digest({ 'a' => ['x'] }, {})).not_to eq(empty)
    end

    it 'is pinned to one canonical JSON form (the same on every Ruby and json version)' do
      vd = { 'Foo [x]' => ['a]', '<&>', 'a]'], "\u00e9" => ["\u{1F600}", "line\u2028sep"], "ctl\u0001" => [42],
             'b/c' => ['"q"', '\\'] }
      dd = { 'Foo [x]' => 'a]', "\u00e9" => ["\u{1F600}"], 'k' => 7 }
      canonical = "[[[\"Foo [x]\",[\"<&>\",\"a]\"]],[\"b/c\",[\"\\\"q\\\"\",\"\\\\\"]],[\"ctl\\u0001\",[\"42\"]]," \
                  "[\"\u00e9\",[\"line\u2028sep\",\"\u{1F600}\"]]],[[\"Foo [x]\",[\"a]\"]],[\"k\",[\"7\"]],[\"\u00e9\",[\"\u{1F600}\"]]]]"
      expect(payload.digest(vd, dd)).to eq(Digest::SHA256.hexdigest(canonical))
      expect(payload.digest(vd, dd)).to eq('1b930b235e69a9b358305e80452750b0a8831c6add8bc54db217bfe3fcd1d4de')
      expect(empty).to eq('643d5437104296e21d906ecb15b2c96ad278f20cfc4af53b12bb6069bd853726')
    end

    it 'never raises or warns on odd stored shapes' do
      with_deprecation_warnings do
        expect do
          ['garbage', ['a'], 1, { 'a' => [{ 'k' => 'v' }] }, { "\xFF".b => ['x'] }, { 'A' => ["\xff".b] },
           { 'a' => [nil, ['b']] }, { 'a' => Object.new }, { nil => ['x'] }, { 'a' => (1..(10**9)) }].each do |odd|
            expect(payload.digest(odd, odd)).to match(/\A[0-9a-f]{64}\z/)
          end
        end.not_to output.to_stderr
      end
      expect(payload.digest('garbage', ['a'])).to eq(empty)
      expect(payload.digest({ 'a' => [{ 'k' => 'v' }, ['b']] }, {})).to eq(empty)
      expect(payload.digest({ "\u00e9".b => ["\u00e9".b] }, {})).to eq(payload.digest({ "\u00e9" => ["\u00e9"] }, {}))
    end
  end

  describe '.stored_digest' do
    let(:parent) { dcf_list_field(values: %w[A B]) }
    let(:field) do
      child = dcf_list_field(format: 'depending_list', values: %w[a1 a2 b1], parent: parent)
      dcf_set_dependencies(child, value_dependencies: { 'A' => %w[a1 a2], 'B' => %w[b1] },
                                  default_value_dependencies: { 'A' => 'a1' })
    end

    it 'is digest of the stored mapping without a query and without touching the record' do
      field
      expected = payload.digest({ 'A' => %w[a1 a2], 'B' => %w[b1] }, { 'A' => 'a1' })
      digest = nil
      expect(dcf_count_queries { digest = payload.stored_digest(field) }).to eq(0)
      expect(digest).to eq(expected)
      expect(field).not_to be_changed
      expect(payload.stored_digest(CustomField.find(field.id))).to eq(expected)
    end

    it 'ignores unsaved changes and follows a save' do
      before = payload.stored_digest(field)
      field.value_dependencies = { 'A' => %w[a1] }
      field.default_value_dependencies = {}
      expect(payload.stored_digest(field)).to eq(before)
      field.save!
      expect(payload.stored_digest(field)).to eq(payload.digest({ 'A' => %w[a1] }, {}))
    end

    it 'covers only the mapping: other format_store keys do not change it' do
      before = payload.stored_digest(field)
      field.update!(url_pattern: 'http://example.test/%value%')
      expect(payload.stored_digest(field.reload)).to eq(before)
    end

    it 'gives digest({}, {}) for a new record and tolerates a corrupt store' do
      expect(payload.stored_digest(IssueCustomField.new(value_dependencies: { 'A' => ['a1'] }))).to eq(payload.digest({}, {}))
      field.update_column(:format_store, { 'value_dependencies' => 'garbage', 'default_value_dependencies' => [1] })
      expect(payload.stored_digest(CustomField.find(field.id))).to eq(payload.digest({}, {}))
    end
  end

  describe 'performance budget' do
    it 'parses the worst-case 4 MiB payload with 100,000 keys in under 2.5 s' do
      mapping = {}
      (1..100_000).each { |i| mapping["parent #{i} \"q\"/\u00e9"] = ["c#{i}", i] }
      mapping['k'] = ["x#{'1' * 25}"]
      raw = JSON.generate('version' => 1, 'source' => 'editor', 'value_dependencies' => mapping)
      expect(raw.bytesize).to be_between(4_000_000, max_bytes)
      result = nil
      elapsed = fastest { result = payload.parse(raw) }
      expect(result).to be_ok
      expect(result.value_dependencies.size).to eq(100_001)
      expect(result.value_dependencies["parent 7 \"q\"/\u00e9"]).to eq(%w[c7 7])
      digest_elapsed = fastest { payload.digest(result.value_dependencies, result.default_value_dependencies) }
      report(format('100,000-key payload of %d bytes parsed in %.1f ms, digest in %.1f ms',
                    raw.bytesize, elapsed * 1000, digest_elapsed * 1000))
      expect(elapsed).to be < 2.5
      expect(digest_elapsed).to be < 2.5
    end

    # The slash opens the pre-scan gate, so the scan steps through every
    # token in Ruby: the slowest accepted 4 MiB shape found.
    it 'parses 4 MiB of one-digit integers under a key with a slash in under 2.5 s' do
      prefix = '{"value_dependencies":{"a/b":['
      count = (max_bytes - prefix.bytesize - 2) / 2
      raw = "#{prefix}#{Array.new(count, '1').join(',')}]}}"
      expect(raw.bytesize).to be_between(max_bytes - 1, max_bytes)
      result = nil
      elapsed = fastest { result = payload.parse(raw) }
      expect(result).to be_ok
      expect(result.value_dependencies).to eq('a/b' => ['1'])
      scan_elapsed = fastest { expect(payload.send(:prescan, raw)).to be_nil }
      report(format('%d one-digit integers under a key with a slash (%d bytes) parsed in %.1f ms, pre-scan %.1f ms',
                    count, raw.bytesize, elapsed * 1000, scan_elapsed * 1000))
      expect(elapsed).to be < 2.5
    end
  end
end
