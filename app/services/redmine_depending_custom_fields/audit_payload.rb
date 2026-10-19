# frozen_string_literal: true

require 'digest'

module RedmineDependingCustomFields
  # Audit value cap (limits design 6.1). JSON at or under the cap is returned
  # byte-identical to ActiveSupport::JSON.encode. Above it, keys are
  # stringified and nested content is shrunk level by level while top-level
  # scalars are kept; the top-level object gets payload_truncated,
  # payload_bytes and payload_sha256 of the full JSON. These names do not
  # collide with the project delta keys (truncated, mapping_sha256).
  # Never raises for a value: one that JSON cannot encode (invalid bytes,
  # nesting above MAX_NESTING) is scrubbed, cut and marked; its markers then
  # describe that cleaned form. Stateless: module functions only.
  module AuditPayload
    MAX_BYTES = 16_384
    MAX_IDS = 1_000
    MAX_ERROR_CHARS = 4_000
    TOP_KEYS = 50
    TOP_STRING = 200
    LEVELS = [
      { array: 20, keys: 50, string: 500, depth: 5 },
      { array: 10, keys: 20, string: 200, depth: 4 },
      { array: 5, keys: 10, string: 80, depth: 3 },
      { array: 1, keys: 5, string: 40, depth: 2 }
    ].freeze
    MARK_KEYS = %w[payload_truncated payload_bytes payload_sha256].freeze
    MORE_KEY = '(more)'
    # The JSON gem refuses deeper nesting (ActiveSupport 7.2 and later).
    MAX_NESTING = 100
    # Smallest cap the marker object alone always fits.
    MIN_BYTES = 160
    # Ids are stored as Integers of at most 63 bits.
    MAX_ID_BITS = 63

    module_function

    def encode(value, max_bytes: MAX_BYTES)
      return nil if value.nil?
      raise ArgumentError, "max_bytes must be at least #{MIN_BYTES}" if max_bytes < MIN_BYTES

      json = native_json(value)
      return json if json && json.bytesize <= max_bytes

      plain = normalize(value, 0)
      json ||= ActiveSupport::JSON.encode(plain)
      fit(plain, json.bytesize, Digest::SHA256.hexdigest(json), max_bytes)
    end

    # The first MAX_IDS Integer ids (a String of digits counts), as a JSON
    # Array without markers.
    def encode_ids(ids)
      return nil if ids.nil?

      kept = Array(ids).filter_map { |id| integer_id(id) }.first(MAX_IDS)
      ActiveSupport::JSON.encode(kept)
    end

    # Cut by characters; applying it twice gives the same text.
    def error_message(message)
      return nil if message.nil?

      cut(text(message), MAX_ERROR_CHARS)
    end

    # ActiveSupport::JSON output, or nil when JSON cannot encode +value+.
    def native_json(value)
      return nil unless encodable?(value)

      json = ActiveSupport::JSON.encode(value)
      json.valid_encoding? ? json : nil
    rescue StandardError, SystemStackError
      nil
    end

    # False for nesting deeper than MAX_NESTING or a String with invalid or
    # binary bytes. Iterative, so a deep value cannot exhaust the stack.
    def encodable?(value)
      stack = [[value, 0]]
      until stack.empty?
        item, depth = stack.pop
        if item.is_a?(Hash) || item.is_a?(Array)
          return false if depth >= MAX_NESTING

          (item.is_a?(Hash) ? item.to_a.flatten(1) : item).each { |child| stack.push([child, depth + 1]) }
        elsif item.is_a?(String)
          return false unless clean_text?(item)
        end
      end
      true
    end

    def clean_text?(string)
      string.valid_encoding? && (string.encoding != Encoding::BINARY || string.ascii_only?)
    end

    # JSON-ready copy: String keys, scrubbed UTF-8 text, other objects through
    # as_json, containers below MAX_NESTING as counts.
    def normalize(value, depth)
      case value
      when Hash
        return "(#{value.size} keys)" if depth >= MAX_NESTING

        value.each_with_object({}) { |(k, v), h| h[text(k)] = normalize(v, depth + 1) }
      when Array
        return "(#{value.size} items)" if depth >= MAX_NESTING

        value.map { |v| normalize(v, depth + 1) }
      when String, Symbol then text(value)
      when Integer, TrueClass, FalseClass, NilClass then value
      when Float then value.finite? ? value : nil
      else
        depth >= MAX_NESTING ? text(value.class.name) : normalize(json_value(value), depth + 1)
      end
    end

    def json_value(value)
      value.as_json
    rescue StandardError, SystemStackError
      value.class.name
    end

    def text(value)
      s = value.to_s
      unless s.encoding == Encoding::UTF_8
        s = begin
          s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
        rescue EncodingError
          s.dup.force_encoding(Encoding::UTF_8)
        end
      end
      s.valid_encoding? ? s : s.scrub
    end

    # The first level whose JSON fits, else the markers alone.
    def fit(plain, bytes, digest, max_bytes)
      LEVELS.each do |level|
        candidate = ActiveSupport::JSON.encode(mark(shrink_top(plain, level), bytes, digest))
        return candidate if candidate.bytesize <= max_bytes
      end
      ActiveSupport::JSON.encode(markers(bytes, digest))
    end

    # Top level: the first TOP_KEYS entries are kept; scalars survive every
    # level (strings cut at TOP_STRING); nested values shrink with the level.
    def shrink_top(value, level)
      return shrink(value, level, 0) unless value.is_a?(Hash)

      kept = entries(value, TOP_KEYS).each_with_object({}) do |(k, v), h|
        h[cut(k, TOP_STRING)] = v.is_a?(Hash) || v.is_a?(Array) ? shrink(v, level, 1) : top_scalar(v)
      end
      count_more(kept, value)
    end

    # The first +max+ entries without a user key named like the marker, so
    # "(more)" always counts the omitted keys.
    def entries(hash, max)
      hash.reject { |k, _| k == MORE_KEY }.first(max)
    end

    def count_more(kept, value)
      omitted = value.size - kept.size
      kept[MORE_KEY] = omitted if omitted.positive?
      kept
    end

    def top_scalar(value)
      value.is_a?(String) ? cut(value, TOP_STRING) : value
    end

    def shrink(value, level, depth)
      case value
      when Hash
        return "(#{value.size} keys)" if depth >= level[:depth]

        kept = entries(value, level[:keys]).each_with_object({}) do |(k, v), h|
          h[cut(k, level[:string])] = shrink(v, level, depth + 1)
        end
        count_more(kept, value)
      when Array
        return "(#{value.size} items)" if depth >= level[:depth]

        kept = value.first(level[:array]).map { |v| shrink(v, level, depth + 1) }
        kept << "(+#{value.size - level[:array]} more)" if value.size > level[:array]
        kept
      when String then cut(value, level[:string])
      else value
      end
    end

    def cut(string, max)
      string.length > max ? "#{string[0, max]}..." : string
    end

    # A Hash without marker keys gets the markers merged in; anything else is
    # wrapped under 'value'.
    def mark(value, bytes, digest)
      return value.merge(markers(bytes, digest)) if value.is_a?(Hash) && (value.keys & MARK_KEYS).empty?

      markers(bytes, digest).merge('value' => value)
    end

    def markers(bytes, digest)
      { 'payload_truncated' => true, 'payload_bytes' => bytes, 'payload_sha256' => digest }
    end

    def integer_id(id)
      if id.is_a?(Integer)
        id.bit_length <= MAX_ID_BITS ? id : nil
      elsif id.is_a?(String) && id.match?(/\A\d{1,18}\z/)
        id.to_i
      end
    end
  end
end
