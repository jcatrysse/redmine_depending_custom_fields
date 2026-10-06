# frozen_string_literal: true

require_relative '../rails_helper'

# WP-05: FieldIndex, the single topology helper (server design section 4).
# Stored pointers that save! would normalize (String ids, dangling, cross-type,
# self-parents, cycles) are written as raw YAML with SQL.
RSpec.describe RedmineDependingCustomFields::FieldIndex do
  def dump(hash)
    CustomField.type_for_attribute('format_store').serialize(hash)
  end

  def write_raw(field, raw)
    CustomField.where(id: field.id).update_all(['format_store = ?', raw])
  end

  def point(field, parent_id)
    write_raw(field, dump('parent_custom_field_id' => parent_id))
  end

  def stored_raw(field)
    CustomField.connection.select_value(CustomField.where(id: field.id).select(:format_store).to_sql)
  end

  # id => parent id (nil for a root); rows of depending IssueCustomFields.
  def synthetic(pointers, roots: {})
    rows = pointers.each_with_object({}) do |(id, pid), h|
      h[id] = described_class::Row.new(id, 'IssueCustomField', 'depending_list', pid)
    end
    roots.each { |id, format| rows[id] = described_class::Row.new(id, 'IssueCustomField', format, nil) }
    rows
  end

  def chain_rows(length)
    pointers = { 1 => nil }
    (2..length).each { |id| pointers[id] = id - 1 }
    synthetic(pointers)
  end

  def accessor_oracle(raw)
    store = CustomField.type_for_attribute('format_store').deserialize(raw)
    value = store.is_a?(Hash) ? store['parent_custom_field_id'] : nil
    id = value.to_i
    id.positive? ? id : nil
  end

  describe 'constants and names' do
    it 'defines the anchored regex exactly and frozen' do
      expect(described_class::PARENT_RE.source)
        .to eq(%q{^parent_custom_field_id: *(?:'(\d*)'|"(\d*)"|(\d*)) *$})
      expect(described_class::PARENT_RE).to be_frozen
      expect(described_class::PARENT_RE.options).to eq(0)
    end

    it 'has a positional Row struct with the four members' do
      row = described_class::Row.new(1, 'IssueCustomField', 'depending_list', 2)
      expect(described_class::Row.members).to eq([:id, :type, :field_format, :parent_id])
      expect(row.to_a).to eq([1, 'IssueCustomField', 'depending_list', 2])
    end

    it 'does not create the superseded limits and Graph names' do
      expect(described_class).not_to respond_to(:build)
      expect(described_class.public_instance_methods(false)).not_to include(:child_ids, :children, :type_of, :include?)
      expect(described_class.constants).not_to include(:PARENT_LINE, :MAX_CHAIN)
      expect(defined?(RedmineDependingCustomFields::DependencyRules::Graph)).to be_nil
    end

    it 'keeps no class-level state' do
      described_class.load.descendant_ids(1)
      expect(described_class.instance_variables).to eq([])
      expect(described_class.class_variables).to eq([])
    end
  end

  describe '.parent_id_from_raw' do
    regex_hits = [
      ['an Integer id', { 'parent_custom_field_id' => 12 }, 12],
      ['a String id', { 'parent_custom_field_id' => '12' }, 12],
      ['a quoted id with a leading zero', { 'parent_custom_field_id' => '012' }, 12],
      ['a blank id', { 'parent_custom_field_id' => '' }, nil],
      ['a nil id', { 'parent_custom_field_id' => nil }, nil],
      ['a zero id', { 'parent_custom_field_id' => '0' }, nil],
      ['the key after other keys', { 'url_pattern' => 'x', 'parent_custom_field_id' => 7, 'value_dependencies' => { 'a' => ['b'] } }, 7],
      ['a nested key followed by the top-level key',
       { 'value_dependencies' => { "a\nparent_custom_field_id: 9" => ['x'] }, 'parent_custom_field_id' => 3 }, 3],
      ['a mapping key named like the pointer', { 'value_dependencies' => { 'parent_custom_field_id: 9' => ['x'] }, 'parent_custom_field_id' => 4 }, 4],
      ['an array element block scalar', { 'value_dependencies' => { 'a' => ["\nparent_custom_field_id: 9"] }, 'parent_custom_field_id' => 5 }, 5],
      ['a block scalar url_pattern', { 'url_pattern' => "x\nparent_custom_field_id: 9", 'parent_custom_field_id' => 6 }, 6],
      ['a long folded scalar', { 'url_pattern' => "#{'word ' * 30}parent_custom_field_id: 9 #{'word ' * 30}", 'parent_custom_field_id' => 2 }, 2],
      ['a double-quoted id', "---\nparent_custom_field_id: \"12\"\n", 12],
      ['a blank id with a trailing space', "---\nparent_custom_field_id: \n", nil],
      ['the legacy HashWithIndifferentAccess header', "--- !ruby/hash:ActiveSupport::HashWithIndifferentAccess\nparent_custom_field_id: 7\n", 7],
      ['the key on line 3', "---\nx: 1\nparent_custom_field_id: 7\ny: 2\n", 7]
    ]

    regex_hits.each do |label, input, expected|
      it "reads #{label} with the regex, without deserializing" do
        raw = input.is_a?(Hash) ? dump(input) : input
        type = CustomField.type_for_attribute('format_store')
        allow(type).to receive(:deserialize).and_call_original
        result = :unset
        loads = dcf_count_yaml_loads { result = described_class.parent_id_from_raw(raw) }

        expect(result).to eq(expected)
        expect(loads).to eq(0)
        expect(type).not_to have_received(:deserialize)
        expect(result).to eq(accessor_oracle(raw))
      end
    end

    it 'gives nil for nil, empty and key-less values without deserializing' do
      key_less = dump('value_dependencies' => { 'a' => ['b'] })
      results = nil
      loads = dcf_count_yaml_loads do
        results = [nil, '', "--- {}\n", key_less].map { |raw| described_class.parent_id_from_raw(raw) }
      end
      expect(results).to eq([nil, nil, nil, nil])
      expect(loads).to eq(0)
    end

    decoys = [
      ['a nested key block scalar', { 'value_dependencies' => { "a\nparent_custom_field_id: 9" => ['x'] } }],
      ['a mapping key named like the pointer', { 'value_dependencies' => { 'parent_custom_field_id: 9' => ['x'] } }],
      ['an array element block scalar', { 'value_dependencies' => { 'a' => ["\nparent_custom_field_id: 9"] } }],
      ['a block scalar url_pattern', { 'url_pattern' => "x\nparent_custom_field_id: 9" }],
      ['a long folded scalar', { 'url_pattern' => "#{'word ' * 30}parent_custom_field_id: 9 #{'word ' * 30}" }]
    ]

    decoys.each do |label, hash|
      it "never takes the id embedded in #{label}" do
        raw = dump(hash)
        expect(raw).to include('parent_custom_field_id: 9')
        expect(described_class.parent_id_from_raw(raw)).to be_nil
      end
    end

    fallbacks = [
      ['a symbol key', "---\n:parent_custom_field_id: 12\n", 12],
      ['flow style', "--- {parent_custom_field_id: 5}\n", 5],
      ['an indented root', "---\n  parent_custom_field_id: 6\n", 6],
      ['CRLF line ends', "---\r\nparent_custom_field_id: 12\r\n", 12],
      ['digits followed by letters', "---\nparent_custom_field_id: 12abc\n", 12],
      ['a plus sign', "---\nparent_custom_field_id: +12\n", 12],
      ['a negative id', "---\nparent_custom_field_id: -5\n", nil],
      ['a tilde', "---\nparent_custom_field_id: ~\n", nil],
      ['null', "---\nparent_custom_field_id: null\n", nil],
      ['a float', "---\nparent_custom_field_id: 12.0\n", 12],
      ['a quoted id with a trailing space', "---\nparent_custom_field_id: '12 '\n", 12]
    ]

    fallbacks.each do |label, raw, expected|
      it "deserializes #{label} and returns the accessor value" do
        result = :unset
        loads = dcf_count_yaml_loads { result = described_class.parent_id_from_raw(raw) }

        expect(result).to eq(expected)
        expect(result).to eq(accessor_oracle(raw))
        expect(loads).to be > 0
      end
    end

    it 'reads YAML without the --- header like the accessor of the running Rails' do
      field = dcf_list_field(format: 'depending_list')
      ['parent_custom_field_id: 7', "parent_custom_field_id: 7\n", ":parent_custom_field_id: 7\n"].each do |raw|
        expect(described_class.parent_id_from_raw(raw)).to eq(accessor_oracle(raw)), raw.inspect
        write_raw(field, raw)
        accessor = CustomField.find(field.id).parent_custom_field_id.to_i
        expect(described_class.parent_id_from_raw(stored_raw(field))).to eq(accessor.positive? ? accessor : nil), raw.inspect
      end
    end

    it 'gives nil for a disallowed class and for broken YAML, without raising' do
      expect(described_class.parent_id_from_raw("---\nparent_custom_field_id: !ruby/object:Object {}\n")).to be_nil
      expect(described_class.parent_id_from_raw("---\nparent_custom_field_id: [1\n")).to be_nil
    end

    it 'reads an intact top-level line of a String with invalid UTF-8' do
      raw = (+"---\nparent_custom_field_id: 7\nvalue_dependencies:\n  '\xC3").force_encoding('UTF-8')
      expect(raw.valid_encoding?).to be(false)
      expect { described_class.parent_id_from_raw(raw) }.not_to raise_error
      expect(described_class.parent_id_from_raw(raw)).to eq(7)
    end

    it 'reads the key of a Hash left by an in-memory assignment and ignores other objects' do
      expect(described_class.parent_id_from_raw('parent_custom_field_id' => '8')).to eq(8)
      expect(described_class.parent_id_from_raw(parent_custom_field_id: 9)).to eq(9)
      expect(described_class.parent_id_from_raw(ActiveSupport::HashWithIndifferentAccess.new(parent_custom_field_id: 4))).to eq(4)
      expect(described_class.parent_id_from_raw(12)).to be_nil
      expect(described_class.parent_id_from_raw(['parent_custom_field_id: 3'])).to be_nil
    end
  end

  describe '.load' do
    it 'reads one row per depending field with Integer ids and the stored pointer' do
      parent = dcf_list_field
      child = dcf_list_field(format: 'depending_list', parent: parent)
      enum_parent = dcf_enum_field
      enum_child = dcf_enum_field(format: 'depending_enumeration', parent: enum_parent, type: IssueCustomField)
      index = described_class.load

      expect(index.row(child.id).id).to be_a(Integer)
      expect(index.row(child.id).to_a).to eq([child.id, 'IssueCustomField', 'depending_list', parent.id])
      expect(index.row(enum_child.id).to_a).to eq([enum_child.id, 'IssueCustomField', 'depending_enumeration', enum_parent.id])
    end

    it 'gives a non-depending row no parent even when its store carries the key' do
      other = dcf_list_field
      list = dcf_list_field
      list.parent_custom_field_id = other.id
      list.save!
      expect(stored_raw(list)).to include("parent_custom_field_id: #{other.id}")

      index = described_class.load
      expect(index.children_ids(other.id)).to eq([])
      expect(index.row(list.id).to_a).to eq([list.id, 'IssueCustomField', 'list', nil])
    end

    it 'issues the same number of queries for 1 and for 25 depending fields' do
      parent = dcf_list_field
      dcf_list_field(format: 'depending_list', parent: parent)
      one = dcf_count_queries { described_class.load }
      24.times { dcf_list_field(format: 'depending_list', parent: parent) }
      many = dcf_count_queries { described_class.load }

      expect(many).to eq(one)
    end

    it 'runs a single named raw SELECT on custom_fields' do
      dcf_list_field(format: 'depending_list', parent: dcf_list_field)
      statements = []
      callback = lambda do |*, payload|
        statements << payload unless payload[:name].to_s.match?(/\A(?:SCHEMA|CACHE|TRANSACTION)\z/)
      end
      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { described_class.load }

      expect(statements.map { |s| s[:name] }).to eq([described_class::QUERY_NAME])
      expect(statements.first[:sql]).to match(/\ASELECT .*FROM\W+custom_fields\W/i)
    end

    it 'neither deserializes format_store nor instantiates records' do
      parent = dcf_list_field(values: %w[A B])
      3.times do
        child = dcf_list_field(format: 'depending_list', parent: parent, values: %w[x y])
        dcf_set_dependencies(child, value_dependencies: { 'A' => ['x'] }, default_value_dependencies: { 'A' => 'x' })
      end
      instantiated = 0
      callback = ->(*, payload) { instantiated += payload[:record_count].to_i }
      loads = nil
      ActiveSupport::Notifications.subscribed(callback, 'instantiation.active_record') do
        loads = dcf_count_yaml_loads { described_class.load }
      end

      expect(loads).to eq(0)
      expect(instantiated).to eq(0)
    end

    it 'reflects database changes made between two loads' do
      first_parent = dcf_list_field
      second_parent = dcf_list_field
      child = dcf_list_field(format: 'depending_list', parent: first_parent)
      before = described_class.load
      point(child, second_parent.id)
      after = described_class.load

      expect(before.parent_id(child.id)).to eq(first_parent.id)
      expect(after.parent_id(child.id)).to eq(second_parent.id)
    end
  end

  describe '.new with records:' do
    let(:parent) { dcf_list_field }
    let(:child) { dcf_list_field(format: 'depending_list', parent: parent) }

    it 'reads the stored pointer of a loaded record without a query or a deserialization' do
      record = CustomField.find(child.id)
      index = described_class.new(records: { record.id => record })
      pid = nil
      queries = nil
      loads = dcf_count_yaml_loads { queries = dcf_count_queries { pid = index.parent_id(record.id) } }

      expect(pid).to eq(parent.id)
      expect(queries).to eq(0)
      expect(loads).to eq(0)
      expect(record.instance_variable_get(:@attributes)['format_store'].has_been_read?).to be_falsey
    end

    it 'reads nothing at construction' do
      record = CustomField.find(child.id)
      allow(record).to receive(:read_attribute_before_type_cast).and_call_original
      queries = dcf_count_queries { described_class.new(records: { record.id => record }) }

      expect(queries).to eq(0)
      expect(record).not_to have_received(:read_attribute_before_type_cast)
    end

    it 'shows the stored pointer, not an unsaved in-memory change' do
      other = dcf_list_field
      record = CustomField.find(child.id)
      record.parent_custom_field_id = other.id

      expect(described_class.new(records: { record.id => record }).parent_id(record.id)).to eq(parent.id)
    end

    it 'writes nothing onto the records' do
      record = CustomField.find(child.id)
      before = record.instance_variables
      index = described_class.new(records: { record.id => record })
      index.ensure([record.id])
      index.effective_parent_id_for(record.id, record.type, record.field_format, index.parent_id(record.id))

      expect(record.instance_variables).to eq(before)
    end

    it 'is valid without arguments and copies a frozen rows: Hash' do
      rows = synthetic({}, roots: { 1 => 'list' }).freeze
      index = described_class.new(rows: rows)
      index.ensure([999_999_999])

      expect(described_class.new.row(nil)).to be_nil
      expect(rows.keys).to eq([1])
      expect(index.exists?(999_999_999)).to be(false)
    end
  end

  describe '#ensure' do
    let!(:fields) { Array.new(3) { dcf_list_field } }

    it 'fetches unknown ids in one batched query' do
      one = dcf_count_queries { described_class.new.ensure([fields[0].id]) }
      four = dcf_count_queries { described_class.new.ensure(fields.map(&:id) + [999_999_999]) }

      expect(four).to eq(one)
    end

    it 'skips known ids, including ids remembered as missing' do
      index = described_class.new
      index.ensure([fields[0].id, 999_999_999])
      queries = dcf_count_queries do
        index.ensure([fields[0].id, 999_999_999])
        index.row(fields[0].id)
        index.exists?(999_999_999)
      end

      expect(queries).to eq(0)
      expect(index.exists?(999_999_999)).to be(false)
      expect(index.row(999_999_999)).to be_nil
    end

    it 'takes loaded records first and queries only the rest' do
      record = CustomField.find(fields[0].id)
      only_records = described_class.new(records: { record.id => record })
      mixed = described_class.new(records: { record.id => record })

      expect(dcf_count_queries { only_records.ensure([record.id]) }).to eq(0)
      expect(dcf_count_queries { mixed.ensure([record.id, fields[1].id]) })
        .to eq(dcf_count_queries { described_class.new.ensure([fields[1].id]) })
    end

    it 'drops blank ids and accepts a Set, a single value and numeric Strings' do
      index = described_class.new

      expect(dcf_count_queries { index.ensure([nil, '', 0, -1, 'abc']) }).to eq(0)
      expect(index.ensure([])).to be(index)
      index.ensure(Set[fields[0].id.to_s])
      index.ensure(fields[1].id)
      expect(dcf_count_queries { index.row(fields[0].id) && index.row(fields[1].id) }).to eq(0)
    end

    it 'fetches fields of any type and format' do
      project_enum = dcf_enum_field(type: ProjectCustomField)
      index = described_class.new.ensure([project_enum.id])

      expect(index.row(project_enum.id).to_a).to eq([project_enum.id, 'ProjectCustomField', 'enumeration', nil])
    end
  end

  describe '#row, #parent_id and #exists?' do
    it 'treats String and Integer ids alike' do
      field = dcf_list_field
      index = described_class.new

      expect(index.row(field.id.to_s)).to equal(index.row(field.id))
      expect(index.exists?(field.id.to_s)).to be(true)
    end

    it 'answers blank ids without a query' do
      index = described_class.new
      results = nil
      queries = dcf_count_queries do
        results = [index.row(nil), index.row(''), index.row(0), index.row('abc'), index.parent_id(nil), index.exists?(nil)]
      end

      expect(results).to eq([nil, nil, nil, nil, nil, false])
      expect(queries).to eq(0)
    end

    it 'queries a dangling id once' do
      index = described_class.new
      first = dcf_count_queries { index.row(999_999_999) }
      second = dcf_count_queries { index.row(999_999_999) }

      expect(first).to eq(dcf_count_queries { described_class.new.ensure([999_999_999]) })
      expect(second).to eq(0)
    end
  end

  describe '#children_ids' do
    it 'matches the stored pointer comparison for every stored shape' do
      parent = dcf_list_field
      integer_child = dcf_list_field(format: 'depending_list', parent: parent)
      grandchild = dcf_list_field(format: 'depending_list', parent: integer_child)
      string_child = dcf_list_field(format: 'depending_list')
      write_raw(string_child, dump('parent_custom_field_id' => parent.id.to_s))
      letters_child = dcf_list_field(format: 'depending_list')
      write_raw(letters_child, "---\nparent_custom_field_id: #{parent.id}abc\n")
      symbol_child = dcf_list_field(format: 'depending_list')
      write_raw(symbol_child, "---\n:parent_custom_field_id: #{parent.id}\n")
      project_child = dcf_list_field(format: 'depending_list', type: ProjectCustomField)
      point(project_child, parent.id)
      enum_child = dcf_enum_field(format: 'depending_enumeration')
      point(enum_child, parent.id)
      self_parent = dcf_list_field(format: 'depending_list')
      point(self_parent, self_parent.id)
      decoy = dcf_list_field(format: 'depending_list')
      write_raw(decoy, dump('value_dependencies' => { "a\nparent_custom_field_id: #{parent.id}" => ['x'] }))
      blank_child = dcf_list_field(format: 'depending_list')
      point(blank_child, '')
      null_child = dcf_list_field(format: 'depending_list')
      write_raw(null_child, nil)
      dangling = dcf_list_field(format: 'depending_list')
      point(dangling, 999_999_999)
      stray_list = dcf_list_field
      point(stray_list, parent.id)
      headerless_child = dcf_list_field(format: 'depending_list')
      write_raw(headerless_child, "parent_custom_field_id: #{parent.id}\n")

      expect(stored_raw(string_child)).to eq("---\nparent_custom_field_id: '#{parent.id}'\n")
      expect(stored_raw(symbol_child)).to start_with("---\n:parent_custom_field_id:")
      expect(stored_raw(null_child)).to be_nil
      expect(stored_raw(self_parent)).to eq("---\nparent_custom_field_id: #{self_parent.id}\n")

      depending = CustomField.where(field_format: %w[depending_list depending_enumeration]).to_a
      index = described_class.load
      CustomField.all.each do |field|
        oracle = depending.select { |c| c.parent_custom_field_id.to_i == field.id }.map(&:id).sort
        expect(index.children_ids(field.id)).to eq(oracle), "children of #{field.name}"
      end
      # The accessor reads a headerless row as {} on Rails 6.1 and as the id on 7.x.
      headerless = accessor_oracle(stored_raw(headerless_child)) == parent.id ? [headerless_child.id] : []
      expect(index.children_ids(parent.id))
        .to eq(([integer_child, string_child, letters_child, symbol_child, project_child, enum_child].map(&:id) + headerless).sort)
      expect(index.children_ids(self_parent.id)).to eq([self_parent.id])
      expect(index.children_ids(integer_child.id)).to eq([grandchild.id])
      expect(index.children_ids(null_child.id) + index.children_ids(blank_child.id) + index.children_ids(decoy.id)).to eq([])
      expect(index.children_ids(dangling.id)).to eq([])
    end

    it 'returns [] for nil, zero, negative and blank ids' do
      dcf_list_field(format: 'depending_list')
      index = described_class.load

      expect([nil, 0, -1, ''].map { |id| index.children_ids(id) }).to eq([[], [], [], []])
    end

    it 'costs no query on a loaded index and accepts String ids' do
      parent = dcf_list_field
      child = dcf_list_field(format: 'depending_list', parent: parent)
      index = described_class.load
      result = nil

      expect(dcf_count_queries { result = index.children_ids(parent.id.to_s) }).to eq(0)
      expect(result).to eq([child.id])
    end

    it 'lists only the known rows on an index not built by load' do
      index = described_class.new(rows: synthetic({ 2 => 1, 3 => 1, 4 => 2 }))

      expect(index.children_ids(1)).to eq([2, 3])
      expect(described_class.new.children_ids(1)).to eq([])
    end

    it 'lists the rows that #ensure adds after an earlier call' do
      parent = dcf_list_field
      child = CustomField.find(dcf_list_field(format: 'depending_list', parent: parent).id)
      sibling = dcf_list_field(format: 'depending_list', parent: parent)
      index = described_class.new(records: { child.id => child })

      expect(index.children_ids(parent.id)).to eq([])
      index.ensure([child.id])
      expect(index.children_ids(parent.id)).to eq([child.id])
      index.ensure([sibling.id])
      expect(index.children_ids(parent.id)).to eq([child.id, sibling.id].sort)
    end
  end

  describe '#descendant_ids' do
    it 'walks a chain breadth first without the start' do
      index = described_class.new(rows: synthetic({ 2 => 1, 3 => 2 }, roots: { 1 => 'list' }))
      expect(index.descendant_ids(1)).to eq([2, 3])
    end

    it 'orders by level, then by ascending id within a level, whatever the parent order' do
      index = described_class.new(rows: synthetic({ 5 => 1, 3 => 1, 4 => 3, 2 => 5 }, roots: { 1 => 'list' }))
      expect(index.descendant_ids(1)).to eq([3, 5, 2, 4])
    end

    it 'terminates on A<->B, a cycle with a tail and a self-parent' do
      expect(described_class.new(rows: synthetic({ 1 => 2, 2 => 1 })).descendant_ids(1)).to eq([2])
      expect(described_class.new(rows: synthetic({ 1 => 2, 2 => 1, 3 => 1 })).descendant_ids(1)).to eq([2, 3])
      expect(described_class.new(rows: synthetic({ 1 => 1, 2 => 1 })).descendant_ids(1)).to eq([2])
    end

    it 'stops at 1,000 ids on a long chain and a wide star, without a query' do
      chain = described_class.new(rows: chain_rows(1_500))
      star = described_class.new(rows: synthetic((2..1_501).to_h { |id| [id, 1] }, roots: { 1 => 'list' }))
      results = nil
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      queries = dcf_count_queries { results = [chain.descendant_ids(1), star.descendant_ids(1)] }
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      expect(queries).to eq(0)
      expect(results.map(&:size)).to eq([1_000, 1_000])
      expect(results.map { |ids| ids.uniq.size }).to eq([1_000, 1_000])
      expect(results[0].first(3)).to eq([2, 3, 4])
      expect(elapsed).to be < 2.0
    end

    it 'contains every field whose ancestors include the start' do
      rows = synthetic({ 2 => 1, 3 => 2, 4 => 5, 5 => 4, 6 => 4, 7 => 7, 8 => 7, 9 => 3 }, roots: { 1 => 'list' })
      index = described_class.new(rows: rows)
      rows.each_key do |x|
        index.ancestor_ids(x).each do |ancestor|
          expect(index.descendant_ids(ancestor)).to include(x) unless ancestor == x
        end
      end
    end
  end

  describe '#ancestor_ids' do
    it 'lists the chain nearest first, ending with the plain root' do
      root = dcf_list_field
      middle = dcf_list_field(format: 'depending_list', parent: root)
      leaf = dcf_list_field(format: 'depending_list', parent: middle)

      expect(described_class.load.ancestor_ids(leaf.id)).to eq([middle.id, root.id])
      expect(described_class.new.ancestor_ids(leaf.id)).to eq([middle.id, root.id])
    end

    it 'walks known rows without a query' do
      index = described_class.new(rows: synthetic({ 11 => 10, 12 => 11 }, roots: { 10 => 'list' }))
      result = nil

      expect(dcf_count_queries { result = index.ancestor_ids(12) }).to eq(0)
      expect(result).to eq([11, 10])
    end

    it 'terminates on stored cycles, listing the revisited field once' do
      expect(described_class.new(rows: synthetic({ 1 => 2, 2 => 1 })).ancestor_ids(1)).to eq([2, 1])
      expect(described_class.new(rows: synthetic({ 1 => 1 })).ancestor_ids(1)).to eq([1])
      expect(described_class.new(rows: synthetic({ 1 => 2, 2 => 3, 3 => 1 })).ancestor_ids(1)).to eq([2, 3, 1])
      expect(described_class.new(rows: synthetic({ 4 => 1, 1 => 2, 2 => 1 })).ancestor_ids(4)).to eq([1, 2])
    end

    it 'stops before a dangling id and remembers it as missing' do
      child = dcf_list_field(format: 'depending_list')
      point(child, 999_999_999)
      index = described_class.load

      expect(index.ancestor_ids(child.id)).to eq([])
      expect(dcf_count_queries { index.ancestor_ids(child.id) }).to eq(0)
    end

    it 'finds the field being saved above a candidate that closes a cycle' do
      root = dcf_list_field
      field_a = dcf_list_field(format: 'depending_list', parent: root)
      field_b = dcf_list_field(format: 'depending_list', parent: field_a)

      expect(described_class.load.ancestor_ids(field_b.id)).to include(field_a.id)
    end

    it 'stops at 1,000 ids on a longer chain' do
      result = described_class.new(rows: chain_rows(1_500)).ancestor_ids(1_500)

      expect(result.size).to eq(1_000)
      expect(result.uniq.size).to eq(1_000)
      expect(result.first).to eq(1_499)
    end
  end

  describe '#effective_parent_id_for' do
    let(:root) { dcf_list_field }
    let(:middle) { dcf_list_field(format: 'depending_list', parent: root) }
    let(:leaf) { dcf_list_field(format: 'depending_list', parent: middle) }

    def effective(index, child, pid)
      index.effective_parent_id_for(child&.id, 'IssueCustomField', 'depending_list', pid)
    end

    it 'takes exactly four arguments' do
      expect(described_class.instance_method(:effective_parent_id_for).arity).to eq(4)
    end

    it 'returns the pointer of a valid acyclic chain' do
      index = described_class.load

      expect(effective(index, leaf, middle.id)).to eq(middle.id)
      expect(effective(index, middle, root.id)).to eq(root.id)
      expect(effective(index, leaf, middle.id.to_s)).to eq(middle.id)
    end

    it 'returns nil for blank, self, dangling, wrong type, wrong family and non-depending children' do
      project_list = dcf_list_field(type: ProjectCustomField)
      enum = dcf_enum_field
      index = described_class.load

      expect([nil, '', 0].map { |pid| effective(index, leaf, pid) }).to eq([nil, nil, nil])
      expect(effective(index, leaf, leaf.id)).to be_nil
      expect(effective(index, leaf, 999_999_999)).to be_nil
      expect(effective(index, leaf, project_list.id)).to be_nil
      expect(effective(index, leaf, enum.id)).to be_nil
      expect(index.effective_parent_id_for(leaf.id, 'IssueCustomField', 'list', middle.id)).to be_nil
      expect(index.effective_parent_id_for(leaf.id, 'IssueCustomField', 'depending_enumeration', middle.id)).to be_nil
    end

    it 'returns nil for both members of A<->B and for a child below the cycle' do
      field_a = dcf_list_field(format: 'depending_list')
      field_b = dcf_list_field(format: 'depending_list')
      below = dcf_list_field(format: 'depending_list')
      point(field_a, field_b.id)
      point(field_b, field_a.id)
      point(below, field_a.id)
      index = described_class.load

      expect(effective(index, field_a, field_b.id)).to be_nil
      expect(effective(index, field_b, field_a.id)).to be_nil
      expect(effective(index, below, field_a.id)).to be_nil
    end

    it 'treats a self-parent ancestor as a cycle' do
      self_parent = dcf_list_field(format: 'depending_list')
      point(self_parent, self_parent.id)
      child = dcf_list_field(format: 'depending_list')
      point(child, self_parent.id)
      index = described_class.load

      expect(effective(index, child, self_parent.id)).to be_nil
    end

    it 'uses the given pointer, never the child row, so new records work' do
      other = dcf_list_field
      back = dcf_list_field(format: 'depending_list')
      point(back, leaf.id)
      index = described_class.load

      expect(effective(index, nil, middle.id)).to eq(middle.id)
      expect(effective(index, leaf, other.id)).to eq(other.id)
      expect(effective(index, leaf, back.id)).to be_nil
    end

    it 'costs no query once the chain is known, from records or from rows' do
      ids = [root.id, middle.id, leaf.id]
      records = CustomField.where(id: ids).index_by(&:id)
      index = described_class.new(records: records)
      result = nil

      expect(dcf_count_queries { result = effective(index, leaf, middle.id) }).to eq(0)
      expect(result).to eq(middle.id)
      expect(dcf_count_queries { effective(index, leaf, middle.id) }).to eq(0)
    end

    it 'fetches each unknown chain level once' do
      leaf
      index = described_class.new
      first = dcf_count_queries { effective(index, leaf, middle.id) }
      second = dcf_count_queries { effective(index, leaf, middle.id) }
      per_level = dcf_count_queries { described_class.new.ensure([root.id]) }

      expect(first).to eq(2 * per_level)
      expect(second).to eq(0)
    end

    it 'accepts a chain of exactly 1,000 fields and rejects 1,001' do
      expect(described_class.new(rows: chain_rows(1_000))
        .effective_parent_id_for(nil, 'IssueCustomField', 'depending_list', 1_000)).to eq(1_000)
      expect(described_class.new(rows: chain_rows(1_001))
        .effective_parent_id_for(nil, 'IssueCustomField', 'depending_list', 1_001)).to be_nil
    end

    it 'returns nil when the chain exceeds 1,000 hops and the pointer below it' do
      long = described_class.new(rows: chain_rows(1_500))
      short = described_class.new(rows: chain_rows(900))
      queries = dcf_count_queries do
        expect(long.effective_parent_id_for(nil, 'IssueCustomField', 'depending_list', 1_500)).to be_nil
        expect(short.effective_parent_id_for(nil, 'IssueCustomField', 'depending_list', 900)).to eq(900)
      end

      expect(queries).to eq(0)
    end
  end

  describe '#cycle_from' do
    it 'lists the cycle members in walk order from the first member met' do
      expect(described_class.new(rows: synthetic({ 1 => 2, 2 => 1 })).cycle_from(1)).to eq([1, 2])
      expect(described_class.new(rows: synthetic({ 1 => 2, 2 => 1 })).cycle_from(2)).to eq([2, 1])
      expect(described_class.new(rows: synthetic({ 1 => 2, 2 => 3, 3 => 1 })).cycle_from(1)).to eq([1, 2, 3])
      expect(described_class.new(rows: synthetic({ 1 => 2, 2 => 3, 3 => 1 })).cycle_from(2)).to eq([2, 3, 1])
      expect(described_class.new(rows: synthetic({ 1 => 2, 2 => 1, 3 => 1 })).cycle_from(3)).to eq([1, 2])
      expect(described_class.new(rows: synthetic({ 1 => 1 })).cycle_from(1)).to eq([1])
    end

    it 'returns [] for chains, roots, nil and unknown ids' do
      index = described_class.new(rows: synthetic({ 2 => 1, 3 => 2 }, roots: { 1 => 'list' }))

      expect([index.cycle_from(3), index.cycle_from(1), index.cycle_from(nil)]).to eq([[], [], []])
      expect(described_class.load.cycle_from(999_999_999)).to eq([])
    end

    it 'returns [] after 1,000 hops on a longer ring' do
      pointers = (1..1_500).to_h { |id| [id, id == 1_500 ? 1 : id + 1] }
      expect(described_class.new(rows: synthetic(pointers)).cycle_from(1)).to eq([])
    end

    it 'lists a ring of exactly 1,000 fields and gives [] for 1,001' do
      ring = ->(size) { synthetic((1..size).to_h { |id| [id, id == size ? 1 : id + 1] }) }

      expect(described_class.new(rows: ring.call(1_000)).cycle_from(1)).to eq((1..1_000).to_a)
      expect(described_class.new(rows: ring.call(1_001)).cycle_from(1)).to eq([])
    end

    it 'agrees with effective_parent_id_for for every valid stored pointer' do
      rows = synthetic({ 2 => 1, 3 => 2, 4 => 5, 5 => 4, 6 => 4, 7 => 7, 8 => 7, 9 => 3, 10 => 6 }, roots: { 1 => 'list' })
      index = described_class.new(rows: rows)
      checked = 0
      rows.each_value do |row|
        next unless row.parent_id && row.parent_id != row.id

        effective = index.effective_parent_id_for(row.id, row.type, row.field_format, row.parent_id)
        expect(effective.nil?).to eq(index.cycle_from(row.id).any?), "row #{row.id}"
        checked += 1
      end
      expect(checked).to eq(8)
    end

    it 'follows raw pointers through other types and validates only the first hop' do
      field_a = dcf_list_field(format: 'depending_list')
      field_b = dcf_list_field(format: 'depending_list', type: ProjectCustomField)
      child = dcf_list_field(format: 'depending_list')
      point(field_a, field_b.id)
      point(field_b, field_a.id)
      point(child, field_a.id)
      index = described_class.load

      expect(index.effective_parent_id_for(child.id, 'IssueCustomField', 'depending_list', field_a.id)).to be_nil
      expect(index.cycle_from(child.id)).to eq([field_a.id, field_b.id])
      expect(index.ancestor_ids(child.id)).to eq([field_a.id, field_b.id])
    end

    it 'never fetches on a FieldIndex.load index, with the same results as a scoped index' do
      root = dcf_list_field
      middle = dcf_list_field(format: 'depending_list', parent: root)
      leaf = dcf_list_field(format: 'depending_list', parent: middle)
      index = described_class.load
      results = nil
      queries = dcf_count_queries do
        results = [index.cycle_from(leaf.id), index.cycle_from(root.id), index.cycle_from(999_999_999),
                   index.effective_parent_id_for(leaf.id, 'IssueCustomField', 'depending_list', middle.id)]
      end
      scoped = described_class.load(CustomField.where(id: leaf.id))
      scoped_results = [scoped.cycle_from(leaf.id), scoped.cycle_from(root.id), scoped.cycle_from(999_999_999),
                        scoped.effective_parent_id_for(leaf.id, 'IssueCustomField', 'depending_list', middle.id)]

      expect(queries).to eq(0)
      expect(results).to eq([[], [], [], middle.id])
      expect(scoped_results).to eq(results)
      expect(dcf_count_queries { described_class.load(CustomField.where(id: leaf.id)).cycle_from(leaf.id) }).to be > 1
    end

    it 'finds stored cycles in the database' do
      field_a = dcf_list_field(format: 'depending_list')
      field_b = dcf_list_field(format: 'depending_list')
      below = dcf_list_field(format: 'depending_list')
      point(field_a, field_b.id)
      point(field_b, field_a.id)
      point(below, field_a.id)
      index = described_class.load

      expect(index.cycle_from(field_a.id)).to eq([field_a.id, field_b.id])
      expect(index.cycle_from(below.id)).to eq([field_a.id, field_b.id])
    end
  end
end
