# frozen_string_literal: true

require 'json'
require 'digest'
require 'strscan'

module RedmineDependingCustomFields
  # The one parser of the dependency editor payload, for the admin virtual
  # attribute (WP-22) and DependencyMappingService (WP-27); editor design 2.
  # Stateless: module functions only, nothing memoized and nothing logged.
  # Callers log and audit only "dependencies_json rejected: <code> (<bytes> bytes)".
  module DependencyPayload
    VERSION = 1
    MAX_BYTES = 4 * 1024 * 1024
    # Top object, value_dependencies object, array.
    MAX_NESTING = 3
    MAX_INTEGER_BITS = 63
    MAX_IMPORT_ROWS = 10_000_000
    TOP_LEVEL_KEYS = %w[version source import base value_dependencies default_value_dependencies].freeze
    IMPORT_KEYS = %w[mode rows].freeze
    SOURCES = %w[editor import].freeze
    IMPORT_MODES = %w[merge replace].freeze

    # Only JSON white space counts as nothing posted.
    NOT_BLANK = /[^ \t\r\n]/.freeze
    # Blank keys and values, as String#blank? (Sanitizer). Fixed to UTF-8, so
    # ASCII-only and other Strings do not recompile it in turn.
    BLANK = /\A[[:space:]]*\z/u.freeze
    BASE_FORMAT = /\A[0-9a-f]{64}\z/.freeze
    # Pre-scan (SP-01): a StringScanner loop whose patterns match at the
    # scanner position, string content possessively, so it stays linear
    # without the regex match cache of Ruby 3.2 (Ruby 2.7 to 3.1). The gate
    # also opens on an invalid escape, which json 2.6 and 2.7 accept.
    SCAN_GATE = %r{[0-9]{20}|/|\\[^"\\/bfnrtu]}.freeze
    SCAN_PLAIN = %r{[^"0-9/]+}.freeze
    SCAN_STRING_REST = /(?:[^"\\]++|\\["\\\/bfnrtu])*+"/.freeze
    SCAN_DIGITS = /[0-9]+/.freeze
    SCAN_LONG_DIGITS = /[0-9]{20}/.freeze
    QUOTE = 34
    SLASH = 47

    Result = Struct.new(:value_dependencies, :default_value_dependencies, :source, :import, :base,
                        :error, :bytes, keyword_init: true) do
      def ok?
        error.nil?
      end
    end

    # Raised by parse! only. The message holds the code and the size, never content.
    class Invalid < StandardError
      attr_reader :reason, :bytes

      def initialize(reason, bytes)
        @reason = reason
        @bytes = bytes
        super("dependencies_json rejected: #{reason} (#{bytes} bytes)")
      end
    end

    module_function

    # nil when nothing was posted (nil or a blank String), otherwise a Result
    # that is ok? or carries an error code. Never raises, for any object: the
    # case calls no method of raw (a BasicObject has no nil? or is_a?).
    def parse(raw)
      case raw
      when nil then nil
      when String then parse_string(raw)
      else failure(:not_a_string, 0)
      end
    end

    # Project entry point: nothing posted is an error too. Goes through parse.
    def parse!(raw)
      result = parse(raw)
      raise(Invalid.new(:blank, raw.is_a?(String) ? raw.bytesize : 0), cause: nil) if result.nil?
      raise(Invalid.new(result.error, result.bytes), cause: nil) unless result.ok?

      result
    end

    # SHA-256 of the mapping in canonical form: keys and values as Strings,
    # blanks and empty lists dropped, values unique and sorted, keys sorted.
    # nil and anything but a Hash count as {}. Never raises.
    def digest(value_dependencies, default_value_dependencies)
      canonical = [canonical(value_dependencies), canonical(default_value_dependencies)]
      Digest::SHA256.hexdigest(::JSON.generate(canonical))
    end

    # digest of the mapping as stored (unsaved changes ignored; {} for a new record).
    def stored_digest(custom_field)
      store = custom_field.attribute_in_database('format_store')
      store = {} unless store.is_a?(Hash)
      digest(store['value_dependencies'], store['default_value_dependencies'])
    end

    # parse for a String: encoding, blank, size, pre-scan, JSON.parse, schema.
    def parse_string(raw)
      raw = raw.dup.force_encoding(Encoding::UTF_8) unless raw.encoding == Encoding::UTF_8
      bytes = raw.bytesize
      return failure(:invalid_json, bytes) unless raw.valid_encoding?
      return nil unless raw.match?(NOT_BLANK)
      return failure(:too_large, bytes) if bytes > MAX_BYTES

      error = prescan(raw)
      return failure(error, bytes) if error

      begin
        data = ::JSON.parse(raw, max_nesting: MAX_NESTING, create_additions: false, allow_duplicate_key: true)
      rescue ::JSON::ParserError, EncodingError
        return failure(:invalid_json, bytes)
      end
      return failure(:invalid_json, bytes) unless decoded?(data, 1)

      build(data, bytes)
    end

    def failure(code, bytes)
      Result.new(error: code, bytes: bytes)
    end

    # Outside strings, a run of 20 or more digits gives :number_too_long and a
    # slash (a comment, which some json versions accept) :invalid_json. A
    # string that is unterminated or holds an invalid escape is invalid JSON:
    # :number_too_long when its tail holds such a run, else :invalid_json.
    def prescan(raw)
      return nil unless raw.match?(SCAN_GATE)

      scanner = StringScanner.new(raw)
      loop do
        scanner.skip(SCAN_PLAIN)
        case raw.getbyte(scanner.pos)
        when nil
          return nil
        when QUOTE
          scanner.pos += 1
          next if scanner.skip(SCAN_STRING_REST)

          return scanner.exist?(SCAN_LONG_DIGITS) ? :number_too_long : :invalid_json
        when SLASH
          return :invalid_json
        else
          return :number_too_long if scanner.match?(SCAN_LONG_DIGITS)

          scanner.skip(SCAN_DIGITS)
        end
      end
    end

    # json lets empty containers one level below max_nesting through (2.21)
    # and decodes a lone surrogate escape to invalid UTF-8.
    def decoded?(value, depth)
      case value
      when Hash
        depth <= MAX_NESTING && value.all? { |key, item| key.valid_encoding? && decoded?(item, depth + 1) }
      when Array
        depth <= MAX_NESTING && value.all? { |item| decoded?(item, depth + 1) }
      when String
        value.valid_encoding?
      else
        true
      end
    end

    # Schema checks in the order of editor design 2.2 step 7.
    def build(data, bytes)
      return failure(:not_an_object, bytes) unless data.is_a?(Hash)
      return failure(:unknown_key, bytes) unless data.keys.all? { |key| TOP_LEVEL_KEYS.include?(key) }
      return failure(:unsupported_version, bytes) if data.key?('version') && !version?(data['version'])

      source = data.fetch('source', 'editor')
      return failure(:invalid_source, bytes) unless SOURCES.include?(source)

      import = data.key?('import') ? import_meta(data['import'], source) : nil
      return failure(:invalid_import, bytes) if data.key?('import') && import.nil?

      base = data['base']
      return failure(:invalid_base, bytes) if data.key?('base') && !base?(base)

      links = normalize_links(data.fetch('value_dependencies', {}))
      return failure(:invalid_links, bytes) unless links

      defaults = normalize_defaults(data.fetch('default_value_dependencies', {}))
      return failure(:invalid_defaults, bytes) unless defaults

      Result.new(value_dependencies: links, default_value_dependencies: defaults, source: source,
                 import: import, base: base, bytes: bytes)
    end

    def version?(value)
      value.is_a?(Integer) && value == VERSION
    end

    def base?(value)
      value.is_a?(String) && value.match?(BASE_FORMAT)
    end

    # A new {'mode', 'rows'} Hash, or nil when invalid. Only with source import.
    def import_meta(value, source)
      return nil unless source == 'import' && value.is_a?(Hash) && value.keys.sort == IMPORT_KEYS
      return nil unless IMPORT_MODES.include?(value['mode'])

      rows = value['rows']
      return nil unless rows.is_a?(Integer) && rows >= 0 && rows <= MAX_IMPORT_ROWS

      { 'mode' => value['mode'], 'rows' => rows }
    end

    # Hash<String, Array<String>> in submitted order, or nil when invalid.
    def normalize_links(value)
      return nil unless value.is_a?(Hash)

      value.each_with_object({}) do |(key, items), out|
        list = items.is_a?(Array) ? strings(items) : nil
        return nil unless list

        out[key] = list unless list.empty? || blank?(key)
      end
    end

    # Hash<String, String|Array<String>> in the submitted shape, or nil when invalid.
    def normalize_defaults(value)
      return nil unless value.is_a?(Hash)

      value.each_with_object({}) do |(key, item), out|
        kept = item.is_a?(Array) ? strings(item) : scalar(item)
        return nil unless kept

        out[key] = kept unless blank?(key) || (kept.is_a?(String) ? blank?(kept) : kept.empty?)
      end
    end

    # Unique non-blank Strings in order, or nil when an item is not accepted.
    def strings(items)
      list = items.map { |item| scalar(item) }
      return nil if list.include?(nil)

      list.uniq.reject { |item| blank?(item) }
    end

    # A String, or a positive Integer of at most 63 bits (checked before
    # to_s, SP-01) as its decimal String; nil for anything else.
    def scalar(value)
      return value if value.is_a?(String)
      return value.to_s if value.is_a?(Integer) && value.positive? && value.bit_length <= MAX_INTEGER_BITS

      nil
    end

    def blank?(string)
      string.match?(BLANK)
    end

    # [[key, [values]]] sorted; a single value counts as a list of one, keys
    # that give the same String are merged.
    def canonical(mapping)
      return [] unless mapping.is_a?(Hash)

      merged = {}
      mapping.each do |key, value|
        name = text(key)
        next if name.nil? || blank?(name)

        list = value.is_a?(Array) ? value : [value]
        values = list.filter_map { |item| text(item) }.reject { |item| blank?(item) }
        merged[name] = (merged[name] || []) | values unless values.empty?
      end
      merged.map { |name, values| [name, values.sort] }.sort
    end

    # A valid UTF-8 String for a scalar (invalid bytes replaced), nil otherwise
    # (nil, containers and other objects; never inspect).
    def text(value)
      string = case value
               when String then value
               when Symbol, Numeric, true, false then value.to_s
               end
      return nil if string.nil?

      string = string.dup.force_encoding(Encoding::UTF_8) unless string.encoding == Encoding::UTF_8
      string.valid_encoding? ? string : string.scrub("\uFFFD")
    end

    private_class_method :parse_string, :failure, :prescan, :decoded?, :build, :version?, :base?, :import_meta,
                         :normalize_links, :normalize_defaults, :strings, :scalar, :blank?, :canonical, :text
  end
end
