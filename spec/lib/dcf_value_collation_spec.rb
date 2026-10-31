# frozen_string_literal: true

require_relative '../rails_helper'
require 'json'

# WP-28 (project design 2.7, WP-23 open input): ValueCollation gives the keys
# of the editor model's fold() (assets/javascripts/dcf_dependency_editor_model.js)
# on the shared fixture and on the white space and sigma cases of
# test/js/collation_parity.test.js.
RSpec.describe 'RedmineDependingCustomFields::ValueCollation' do
  let(:collation) { RedmineDependingCustomFields::ValueCollation }

  fixture = File.expand_path('../../test/js/fixtures/shared/collation_cases.json', __dir__)
  # The default external encoding is US-ASCII in CI shells.
  cases = JSON.parse(File.read(fixture, encoding: 'UTF-8'))

  # The EXTRA cases of collation_parity.test.js, written with \u escapes.
  extra = [
    ["a\uFEFFb", "a\uFEFFb"],
    ["\uFEFF x \uFEFF", "\uFEFF x \uFEFF"],
    ["a\u2028b", 'a b'],
    ["a\u2029b", 'a b'],
    ["a\u1680b", 'a b'],
    ["a\u0085b", 'a b'],
    ["a\u3000b", 'a b'],
    ["a\u00A0\u202F\u205Fb", 'a b'],
    ["\u0000x", "\u0000x"],
    ["x\u0000", "x\u0000"],
    ["a\u200Bb", "a\u200Bb"],
    ["\t\n\v\f\r x \u3000", 'x'],
    ["\u039F\u0394\u039F\u03A3", "\u03BF\u03B4\u03BF\u03C3"],
    ["\u03BF\u03B4\u03BF\u03C2", "\u03BF\u03B4\u03BF\u03C3"],
    ["A\u03A3 B", "a\u03C3 b"],
    ["\u1E9E", 'ss']
  ]

  it 'reads exactly 20 [input, expected] String pairs from the shared fixture' do
    expect(cases.size).to eq(20)
    expect(cases).to all(satisfy { |pair| pair.size == 2 && pair.all?(String) })
    expect(cases.map(&:first).uniq.size).to eq(20)
  end

  cases.each do |input, expected|
    it "folds #{input.inspect} to #{expected.inspect} like fold()" do
      expect(collation.key(input)).to eq(expected)
    end
  end

  extra.each do |input, expected|
    it "folds #{input.inspect} to #{expected.inspect} (white space and sigma rule)" do
      expect(collation.key(input)).to eq(expected)
    end
  end

  it 'mirrors all 16 white space and sigma cases of collation_parity.test.js' do
    source = File.read(File.expand_path('../../test/js/collation_parity.test.js', __dir__), encoding: 'UTF-8')
    block = source[/const EXTRA = \[(.*?)\n\];/m, 1]
    expect(block.scan(/^\s+\['/).size).to eq(extra.size)
  end

  it 'maps every SPECIAL letter and the final sigma after downcase' do
    pairs = { "\u00DF" => 'ss', "\u00C6" => 'ae', "\u0152" => 'oe', "\u00D8" => 'o', "\u0110" => 'd',
              "\u0141" => 'l', "\u0131" => 'i', "\u00DE" => 'th', "\u03C2" => "\u03C3" }
    pairs.each { |letter, folded| expect(collation.key(letter)).to eq(folded) }
    expect(collation::SPECIAL.keys.size).to eq(9)
  end

  it 'strips only the five COMBINING ranges, not every nonspacing mark' do
    expect(collation.key("e\u0301\u1AB0\u1DC0\u20D0\uFE20")).to eq('e')
    # U+0591 (a Hebrew accent) is \p{Mn} but outside the ranges: kept.
    expect(collation.key("a\u0591")).to eq("a\u0591")
  end

  it 'never raises on nil, numbers, invalid UTF-8 or binary input' do
    expect(collation.key(nil)).to eq('')
    expect(collation.key(12)).to eq('12')
    expect(collation.key("\xFF".b)).to eq("\uFFFD")
    expect(collation.key((+"Ab\xFFc").force_encoding('UTF-8'))).to eq("ab\uFFFDc")
    expect(collation.key((+"caf\xE9").force_encoding('ISO-8859-1'))).to eq('cafe')
    expect(collation.key("\xFF".b).encoding).to eq(Encoding::UTF_8)
  end

  describe '.tokens' do
    it 'is empty for a query whose key is empty (unfiltered)' do
      ['', ' ', "\u00A0\t", "\u0301", "\u0301\u0302 \u3000", nil].each do |query|
        expect(collation.tokens(query)).to eq([])
      end
    end

    it 'splits the folded query on single spaces' do
      expect(collation.tokens("  \u0141\u00F3d\u017A  Krak\u00F3w ")).to eq(%w[lodz krakow])
      expect(collation.tokens("a\u0000b c")).to eq(["a\u0000b", 'c'])
    end
  end

  describe '.match?' do
    it 'is an AND substring match on the folded key; no tokens match everything' do
      key = collation.key("\u0141\u00F3d\u017A Krak\u00F3w")
      expect(collation.match?(key, collation.tokens('lodz'))).to be(true)
      expect(collation.match?(key, collation.tokens('krak LODZ'))).to be(true)
      expect(collation.match?(key, collation.tokens('lodz warsaw'))).to be(false)
      expect(collation.match?(key, [])).to be(true)
    end

    it 'keeps regular expression metacharacters literal' do
      expect(collation.match?(collation.key('a.*b'), collation.tokens('.*'))).to be(true)
      expect(collation.match?(collation.key('axxb'), collation.tokens('.*'))).to be(false)
      expect(collation.match?(collation.key('x'), collation.tokens('.*['))).to be(false)
    end
  end

  describe '.sort' do
    it 'orders by key and keeps ties in their original order (stable)' do
      items = ['b', 'A', 'a', "\u00E9", 'e', 'B']
      expect(collation.sort(items)).to eq(['A', 'a', 'b', 'B', "\u00E9", 'e'])
    end

    it 'reverses the key order for desc but still keeps tie order' do
      items = ['b', 'A', 'a', "\u00E9", 'e', 'B']
      expect(collation.sort(items, desc: true)).to eq(["\u00E9", 'e', 'b', 'B', 'A', 'a'])
    end

    it 'takes the label from a block and returns a new Array' do
      rows = [[3, 'Zeta'], [1, "\u00C1lpha"], [2, 'alpha']]
      sorted = collation.sort(rows, &:last)
      expect(sorted.map(&:first)).to eq([1, 2, 3])
      expect(rows.map(&:first)).to eq([3, 1, 2])
    end
  end

  it 'keeps no module state (frozen constants only)' do
    expect(collation.instance_variables).to be_empty
    expect(collation.class_variables).to be_empty
    expect(collation.constants.map { |name| collation.const_get(name) }.grep_v(Module))
      .to all(be_frozen)
  end
end
