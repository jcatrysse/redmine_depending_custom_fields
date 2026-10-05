# frozen_string_literal: true

# Deterministic large-list fixture generator for specs (no Faker, no Random).
# Every name is a pure function of its index, so fixtures are identical on every
# Ruby/Redmine version and every run. test/js/support/large_list.js is the
# byte-identical JavaScript twin (spec/quality/dcf_large_list_spec.rb and
# test/js/large_list_parity.test.js pin both).
require 'set'
require 'yaml'

module DcfLargeList
  SYLLABLES = %w[ba be bi bo bu ca ce ci co cu da de di do du fa fe fi fo fu
                 ga ge gi go gu la le li lo lu ma me mi mo mu na ne ni no nu
                 pa pe pi po pu ra re ri ro ru sa se si so su ta te ti to tu].freeze # 60
  ACCENTS = { 'a' => 'ã', 'e' => 'é', 'i' => 'í', 'o' => 'ô', 'u' => 'ú' }.freeze
  PREFIXES = ['', '', '', 'São ', 'Santa ', 'Nova ', 'Porto ', 'Rio '].freeze
  # Values that stress YAML quoting, form param names, CSV import and
  # possible_values= normalization. All survive possible_values= unchanged.
  TRICKY = ['yes', 'no', 'null', '1.0', 'a: b', '# hash', '- dash', "O'Brien", 'say "hi"',
            '[x]', 'a]', 'semi;colon', 'comma, value', 'tab' + "\t" + 'in', 'Ünïcødé ñ'].freeze
  # IBGE distribution of 5,570 municipalities over 27 states (research S1).
  BRAZIL_SIZES = [853, 645, 497, 417, 399, 295, 246, 224, 223, 217, 185, 184, 167, 144, 141, 139,
                  102, 92, 79, 78, 75, 62, 52, 22, 16, 15, 1].freeze

  module_function

  # Bijective base-60 syllable encoding of +index+ (at least +min_syllables+).
  def stem(index, min_syllables = 4)
    parts = []
    n = index
    loop do
      parts << SYLLABLES[n % SYLLABLES.size]
      n /= SYLLABLES.size
      break if n.zero? && parts.size >= min_syllables
    end
    parts.join
  end

  # Deterministic display name, average about 12 characters, about one in
  # three names carries one accented (2-byte) character.
  def name(index, prefix: '')
    s = stem(index)
    if (index % 3).zero?
      pos = s.index(/[aeiou]/)
      s = s.dup
      s[pos] = ACCENTS.fetch(s[pos]) if pos
    end
    "#{prefix}#{PREFIXES[(index / 3) % PREFIXES.size]}#{s.capitalize}"
  end

  # +count+ unique names. tricky_every: n inserts one TRICKY value every n
  # names (suffixed to stay unique).
  def names(count, prefix: '', offset: 0, tricky_every: nil)
    seen = Set.new
    Array.new(count) do |k|
      i = offset + k
      value = if tricky_every && (k % tricky_every).zero?
                "#{TRICKY[(k / tricky_every) % TRICKY.size]} #{i}"
              else
                name(i, prefix: prefix)
              end
      raise ArgumentError, "duplicate fixture name #{value.inspect}" unless seen.add?(value)

      value
    end
  end

  # Deterministic part sizes summing to +total+ (harmonic weights, every part >= 1).
  def sizes(total, parts)
    return BRAZIL_SIZES.dup if total == 5570 && parts == 27
    raise ArgumentError, 'total must be >= parts' if total < parts

    weights = Array.new(parts) { |k| 1.0 / (k + 1) }
    # Naive left fold on purpose: Array#sum uses Kahan-Babuska summation and the
    # JavaScript twin does not, so sum(0.0) would break cross-language parity.
    sum = weights.inject(0.0) { |acc, w| acc + w } # rubocop:disable Performance/Sum
    out = weights.map { |w| [1, ((total - parts) * w / sum).floor + 1].max }
    out[0] += total - out.sum
    out
  end

  # Each child linked to exactly one parent (the research S1/S3 shape).
  def partition(parent_keys, child_keys, part_sizes = nil)
    part_sizes ||= sizes(child_keys.size, parent_keys.size)
    mapping = {}
    offset = 0
    parent_keys.each_with_index do |pk, k|
      mapping[pk.to_s] = child_keys[offset, part_sizes[k]].map(&:to_s)
      offset += part_sizes[k]
    end
    mapping
  end

  # Worst case: every child under every parent.
  def full(parent_keys, child_keys)
    keys = child_keys.map(&:to_s)
    parent_keys.to_h { |pk| [pk.to_s, keys.dup] }
  end

  def first_child_defaults(mapping)
    mapping.each_with_object({}) { |(pk, list), h| h[pk] = list.first if list.any? }
  end

  # Bytes Psych emits for one Array element ("- value\n", quoting included).
  # Array dumps are additive: dump(list) == 4 + sum(element_bytes).
  def element_bytes(value)
    Psych.dump([value]).bytesize - 4
  end

  def yaml_list_bytes(values)
    return 0 if values.empty?

    4 + values.sum { |v| element_bytes(v) }
  end

  # Values whose YAML (possible_values column) is exactly +target+ bytes.
  def values_of_yaml_bytes(target, prefix: 'V')
    values = []
    total = 4
    i = 0
    loop do
      v = name(i, prefix: prefix)
      b = element_bytes(v)
      break if total + b > target - 8

      values << v
      total += b
      i += 1
    end
    pad = target - total - element_bytes("#{prefix}Z")
    raise ArgumentError, 'target too small' if pad.negative?

    last = "#{prefix}Z#{'z' * pad}"
    last = "#{prefix}Z#{'z' * (pad - (element_bytes(last) - element_bytes("#{prefix}Z") - pad))}" if yaml_list_bytes(values + [last]) != target
    values << last
    raise "byte target missed: #{yaml_list_bytes(values)} != #{target}" unless yaml_list_bytes(values) == target

    values
  end
end
