# frozen_string_literal: true

require_relative '../rails_helper'
require 'benchmark'

# WP-28 (project design 5, UD-21): the read-only query object of the values
# page, built from the real DependencyRules.value_options tuples.
RSpec.describe 'RedmineDependingCustomFields::ValuesPage' do
  let(:page_class) { RedmineDependingCustomFields::ValuesPage }
  let(:collation) { RedmineDependingCustomFields::ValueCollation }

  def values(count, prefix = 'Value')
    (1..count).map { |i| format('%<prefix>s %<i>04d', prefix: prefix, i: i) }
  end

  def list(count, prefix = 'Value')
    dcf_list_field(values: values(count, prefix))
  end

  def enum_with(count, name: 'N')
    field = dcf_enum_field(names: [])
    CustomFieldEnumeration.insert_all(
      (1..count).map { |i| { custom_field_id: field.id, name: "#{name}#{i}", position: i, active: true } }
    )
    CustomField.find(field.id)
  end

  def build(field, **options)
    page_class.new(field, **options)
  end

  it 'has the thresholds of UD-21 and gap 11' do
    expect([page_class::UNPAGINATED_MAX, page_class::MAX_PER_PAGE, page_class::FILTER_MIN]).to eq([500, 500, 25])
    expect(page_class::Row.members).to eq([:key, :label, :active, :index])
  end

  describe 'rows' do
    it 'are the value_options tuples of a list with their index, duplicates once' do
      field = dcf_list_field(values: %w[B A C])
      field.update_column(:possible_values, %w[B A C A])
      field = CustomField.find(field.id)
      expect(field.possible_values).to eq(%w[B A C A])
      page = build(field)
      expect(page.rows.map { |r| [r.key, r.label, r.active, r.index] })
        .to eq([['B', 'B', true, 0], ['A', 'A', true, 1], ['C', 'C', true, 2]])
      expect(page.rows.map(&:to_a))
        .to eq(RedmineDependingCustomFields::DependencyRules.value_options(field).each_with_index.map { |o, i| o + [i] })
    end

    it 'key enumerations by id String, inactive included, by position then id' do
      field = dcf_enum_field(names: %w[X Y Z])
      x, y, z = field.enumerations.order(:position).to_a
      y.update!(active: false)
      z.update_column(:position, x.position)
      page = build(CustomField.find(field.id))
      expect(page.rows.map { |r| [r.key, r.label, r.active] })
        .to eq([[x.id.to_s, 'X', true], [z.id.to_s, 'Z', true], [y.id.to_s, 'Y', false]])
      expect(page.total).to eq(3)
    end
  end

  describe 'thresholds' do
    it 'shows the search box above 25 values or when q is present' do
      expect(build(list(25)).show_filter?).to be(false)
      expect(build(list(26)).show_filter?).to be(true)
      expect(build(list(3), q: 'x').show_filter?).to be(true)
      expect(build(list(3), q: "\u00A0 ").show_filter?).to be(false)
    end

    it 'paginates above 500 values only' do
      expect(build(list(500)).paginated?).to be(false)
      expect(build(list(501)).paginated?).to be(true)
    end

    it 'is sortable only unfiltered, unpaginated and with more than one value' do
      expect(build(list(500)).sortable?).to be(true)
      expect(build(list(501)).sortable?).to be(false)
      expect(build(list(1)).sortable?).to be(false)
      expect(build(list(30), q: '0001').sortable?).to be(false)
      expect(build(list(30), q: "\u0301").sortable?).to be(true)
    end

    it 'uses the page batch scope when filtered or paginated' do
      expect(build(list(30)).batch_scope).to be_nil
      expect(build(list(30), q: 'value').batch_scope).to eq('page')
      expect(build(list(501)).batch_scope).to eq('page')
    end
  end

  describe 'search' do
    let(:field) do
      dcf_list_field(values: ["\u0141\u00F3d\u017A", "Krak\u00F3w", "S\u00E3o  Paulo", "\u039F\u0394\u039F\u03A3\u03A4\u03A1\u03A9\u039C\u0391",
                              "\u0141\u00F3d\u017A Krak\u00F3w", 'a.*b', 'axb'])
    end

    def labels(page)
      page.rows.map(&:label)
    end

    it 'matches tokens case- and accent-insensitively with AND' do
      expect(labels(build(field, q: 'lodz'))).to eq(["\u0141\u00F3d\u017A", "\u0141\u00F3d\u017A Krak\u00F3w"])
      expect(labels(build(field, q: 'LODZ krak'))).to eq(["\u0141\u00F3d\u017A Krak\u00F3w"])
      expect(labels(build(field, q: 'paulo sao'))).to eq(["S\u00E3o  Paulo"])
      expect(labels(build(field, q: "\u039F\u0394\u039F\u03A3"))).to eq(["\u039F\u0394\u039F\u03A3\u03A4\u03A1\u03A9\u039C\u0391"])
      page = build(field, q: 'lodz')
      expect([page.filtered?, page.filtered_count, page.total, page.tokens]).to eq([true, 2, 7, ['lodz']])
    end

    it 'keeps regular expression metacharacters literal' do
      expect(labels(build(field, q: '.*'))).to eq(['a.*b'])
      expect(labels(build(field, q: '.*['))).to eq([])
    end

    it 'treats a q whose key is empty as unfiltered' do
      ["\u0301", "  \u3000", ''].each do |query|
        page = build(field, q: query)
        expect([page.filtered?, page.tokens, page.rows.size, page.empty_match?]).to eq([false, [], 7, false])
      end
    end

    it 'reports an empty match only when filtered' do
      page = build(field, q: 'zzz', page: '5')
      expect([page.empty_match?, page.filtered_count, page.rows, page.page]).to eq([true, 0, [], 1])
      expect(build(field).empty_match?).to be(false)
    end

    it 'searches enumeration names, inactive included, never the ids' do
      enum = dcf_enum_field(names: %w[Alpha Beta])
      beta = enum.enumerations.find_by(name: 'Beta')
      beta.update!(active: false)
      enum = CustomField.find(enum.id)
      expect(build(enum, q: 'beta').rows.map(&:key)).to eq([beta.id.to_s])
      expect(build(enum, q: beta.id.to_s).rows).to eq([])
    end

    it 'uses only a String q, cut to 255 characters' do
      [%w[a b], { 'x' => 'y' }, ActionController::Parameters.new('x' => 'y'), 12].each do |query|
        page = build(field, q: query)
        expect([page.query, page.filtered?, page.rows.size]).to eq([nil, false, 7])
      end
      long = build(field, q: 'a' * 100_000)
      expect(long.query.length).to eq(255)
    end

    it 'folds each row at most once and q once, and nothing when unfiltered' do
      calls = 0
      allow(collation).to receive(:key).and_wrap_original do |original, *args|
        calls += 1
        original.call(*args)
      end
      build(field)
      expect(calls).to eq(0)
      build(field, q: 'lodz')
      expect(calls).to eq(7 + 1)
      calls = 0
      build(field, q: "\u0301")
      expect(calls).to eq(1)
    end
  end

  describe 'pagination' do
    let(:field) { list(520) }

    it 'shows 25 rows by default and the rows of page 2' do
      page = build(field, page: '2')
      expect(page.rows.map(&:label)).to eq(values(520)[25, 25])
      expect(page.rows.first.index).to eq(25)
      expect([page.page, page.per_page, page.paginator.page, page.paginator.per_page]).to eq([2, 25, 2, 25])
      expect(page.paginator).to be_a(Redmine::Pagination::Paginator)
      expect(page.paginator.item_count).to eq(520)
    end

    it 'clamps the page into 1..last_page' do
      {
        nil => 1, 0 => 1, '0' => 1, '-3' => 1, 'abc' => 1, '1e3' => 1, '2.7' => 2, '  3' => 3,
        '999' => 21, 999 => 21, '99999999999999999999999' => 21, ['2'] => 1, { 'x' => '2' } => 1
      }.each do |raw, expected|
        page = build(field, page: raw)
        expect(page.page).to eq(expected), "page #{raw.inspect}"
        expect(page.paginator.page).to eq(expected)
      end
      expect(build(field, page: '999').rows.map(&:label)).to eq(values(520)[500, 20])
    end

    it 'caps per_page at 500 with a floor of 1 and tolerates junk' do
      expect(build(field, per_page: 1000).rows.size).to eq(500)
      expect(build(field, per_page: 0).per_page).to eq(1)
      expect(build(field, per_page: -25).per_page).to eq(1)
      expect(build(field, per_page: '7').per_page).to eq(7)
      expect(build(field, per_page: nil).per_page).to eq(25)
      expect(build(field, per_page: 'x').per_page).to eq(25)
    end

    it 'shows every matching row when not paginated, whatever per_page' do
      page = build(list(300), per_page: 25, page: '3')
      expect([page.rows.size, page.page, page.paginated?]).to eq([300, 1, false])
    end

    it 'paginates the filtered rows of a large list' do
      page = build(field, q: '05', page: '2', per_page: 10)
      matching = values(520).select { |v| v.include?('05') }
      expect(page.filtered_count).to eq(matching.size)
      expect(page.rows.map(&:label)).to eq(matching[10, 10])
    end
  end

  describe '#default_options' do
    it 'lists every list value whatever the page or the filter' do
      field = list(520)
      expect(build(field, page: '2', q: '0001').default_options).to eq(values(520).map { |v| [v, v] })
    end

    it 'lists active enumerations only, as [name, id] in position order' do
      field = dcf_enum_field(names: %w[X Y Z])
      x, y, z = field.enumerations.order(:position).to_a
      y.update!(active: false)
      expect(build(CustomField.find(field.id)).default_options).to eq([['X', x.id.to_s], ['Z', z.id.to_s]])
    end
  end

  describe '#list_state' do
    it 'is empty unfiltered on page 1 and holds q and page otherwise' do
      field = list(1_200)
      expect(build(field).list_state).to eq({})
      expect(build(field, q: "\u0301", page: '1').list_state).to eq({})
      expect(build(field, q: 'value', page: '3').list_state).to eq(q: 'value', page: 3)
      expect(build(field, page: '999').list_state).to eq(page: 48)
    end
  end

  describe '.page_for_index' do
    it 'gives the 1-based page of an index above 500 values, else 1' do
      expect(page_class.page_for_index(0, 501, 25)).to eq(1)
      expect(page_class.page_for_index(500, 501, 25)).to eq(21)
      expect(page_class.page_for_index(25, 600, 25)).to eq(2)
      expect(page_class.page_for_index(510, 520, 25)).to eq(21)
      expect(page_class.page_for_index(10, 400, 25)).to eq(1)
      expect(page_class.page_for_index(500, 1_200, 1_000)).to eq(2)
      expect(page_class.page_for_index(nil, 600, 25)).to eq(1)
      expect(page_class.page_for_index(-1, 600, 25)).to eq(1)
      expect(page_class.page_for_index(30, 600, 0)).to eq(31)
      expect(page_class.page_for_index(30, 600, nil)).to eq(2)
    end
  end

  describe '.state_for' do
    it 'keeps q only when it filters and page only above 1' do
      expect(page_class.state_for(nil, nil)).to eq({})
      expect(page_class.state_for("\u0301", '1')).to eq({})
      expect(page_class.state_for('lodz', '3')).to eq(q: 'lodz', page: 3)
      expect(page_class.state_for(%w[a], ['3'])).to eq({})
      expect(page_class.state_for('a' * 300, '2')[:q].length).to eq(255)
    end
  end

  # G6: the timer covers only the pure computation (fold, match, slice); the
  # 25,000 records are loaded before it and the load time is printed apart.
  it 'searches 25,000 enumerations in under 1 s', :perf do
    field = enum_with(25_000, name: "\u0141\u00F3d\u017A ")
    tuples = nil
    load_time = Benchmark.realtime { tuples = RedmineDependingCustomFields::DependencyRules.value_options(field) }
    allow(RedmineDependingCustomFields::DependencyRules).to receive(:value_options).and_return(tuples)
    times = ['lodz', 'nomatch'].map do |query|
      Benchmark.realtime { page_class.new(field, q: query, per_page: 25).rows }
    end
    puts "DCF PERF values page load 25,000 enumerations: #{format('%.3f', load_time)} s (not timed)"
    puts "DCF PERF values page search 25,000 enumerations: #{times.map { |t| format('%.3f', t) }.join(' s, ')} s"
    expect(tuples.size).to eq(25_000)
    expect(times).to all(be < 1.0)
  end
end
