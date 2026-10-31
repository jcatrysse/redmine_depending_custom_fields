# frozen_string_literal: true

module RedmineDependingCustomFields
  # Search and sort key of a value label (project design 2.7): the same tables
  # and steps as fold() of the editor model (WP-23), asserted on
  # test/js/fixtures/shared/collation_cases.json. NFKD,
  # strip COMBINING, downcase, SPECIAL (the final sigma included, as Ruby
  # downcase never makes it), then each run of [[:space:]] becomes one space
  # and one leading or trailing space goes (neither \s nor strip, which also
  # removes NUL). Stateless: frozen tables only.
  module ValueCollation
    COMBINING = /[\u0300-\u036F\u1AB0-\u1AFF\u1DC0-\u1DFF\u20D0-\u20FF\uFE20-\uFE2F]/.freeze
    SPECIAL = { "\u00DF" => 'ss', "\u00E6" => 'ae', "\u0153" => 'oe', "\u00F8" => 'o', "\u0111" => 'd',
                "\u0142" => 'l', "\u0131" => 'i', "\u00FE" => 'th', "\u03C2" => "\u03C3" }.freeze
    SPECIAL_RE = Regexp.union(SPECIAL.keys).freeze
    SPACE_RUN = /[[:space:]]+/.freeze
    EDGE_SPACE = /\A | \z/.freeze

    module_function

    # Valid UTF-8 text of any value: other encodings are converted, invalid
    # bytes replaced (U+FFFD), so the key never raises.
    def text(value)
      str = value.nil? ? +'' : value.to_s
      if str.encoding != Encoding::UTF_8
        str = if [Encoding::BINARY, Encoding::US_ASCII].include?(str.encoding)
                str.dup.force_encoding(Encoding::UTF_8)
              else
                str.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
              end
      end
      str.valid_encoding? ? str : str.scrub
    end

    def key(label)
      str = text(label)
      # NFKD, COMBINING and SPECIAL change nothing in ASCII.
      unless str.ascii_only?
        str = str.unicode_normalize(:nfkd).gsub(COMBINING, '')
      end
      str = str.downcase
      str = str.gsub(SPECIAL_RE, SPECIAL) unless str.ascii_only?
      str.gsub(SPACE_RUN, ' ').gsub(EDGE_SPACE, '')
    end

    # The folded query split on its single spaces; [] (unfiltered) when the
    # key is empty, so a white space or mark-only query filters nothing.
    def tokens(query)
      return [] if query.nil?

      folded = key(query)
      folded.empty? ? [] : folded.split
    end

    # Every token is a substring of the folded label (AND); no Regexp is
    # built from the query.
    def match?(folded, tokens)
      tokens.all? { |token| folded.include?(token) }
    end

    # Stable sort by key: ties keep their order, also for desc. The label of
    # an item comes from the block (the item itself without one).
    def sort(items, desc: false)
      keyed = items.each_with_index.map { |item, index| [key(block_given? ? yield(item) : item), index, item] }
      keyed.sort! do |a, b|
        order = desc ? b[0] <=> a[0] : a[0] <=> b[0]
        order.zero? ? a[1] <=> b[1] : order
      end
      keyed.map(&:last)
    end
  end
end
