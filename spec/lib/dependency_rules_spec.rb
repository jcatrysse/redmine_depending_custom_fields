# frozen_string_literal: true

require_relative '../rails_helper'

# WP-05: DependencyRules, the central rules module (server design section 3).
# Nothing but FieldRelevance.children_of calls it yet.
RSpec.describe RedmineDependingCustomFields::DependencyRules do
  def dump(hash)
    CustomField.type_for_attribute('format_store').serialize(hash)
  end

  def point(field, parent_id)
    CustomField.where(id: field.id).update_all(['format_store = ?', dump('parent_custom_field_id' => parent_id)])
  end

  def unsaved(format, type: IssueCustomField, parent: nil)
    cf = type.new(name: "U-#{SecureRandom.hex(3)}", field_format: format)
    cf.parent_custom_field_id = parent unless parent.nil?
    cf
  end

  def sanitizer
    RedmineDependingCustomFields::Sanitizer
  end

  # The SQL of the statements with an ORDER BY clause that the block runs.
  def order_clauses(&block)
    statements = []
    callback = ->(*, payload) { statements << payload[:sql] if payload[:sql].to_s.include?('ORDER BY') }
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &block)
    statements
  end

  describe 'module contract' do
    it 'defines the format constants exactly, frozen, with the families as PARENT_FORMATS values' do
      expect(described_class::DEPENDING_FORMATS).to eq(%w[depending_list depending_enumeration])
      expect(described_class::LIST_FAMILY).to eq(%w[list depending_list])
      expect(described_class::ENUM_FAMILY).to eq(%w[enumeration depending_enumeration])
      expect(described_class::ALL_PARENT_FORMATS).to eq(%w[list depending_list enumeration depending_enumeration])
      expect(described_class::PARENT_FORMATS['depending_list']).to equal(described_class::LIST_FAMILY)
      expect(described_class::PARENT_FORMATS['depending_enumeration']).to equal(described_class::ENUM_FAMILY)
      [:DEPENDING_FORMATS, :LIST_FAMILY, :ENUM_FAMILY, :ALL_PARENT_FORMATS, :PARENT_FORMATS, :CANONICAL_ID].each do |name|
        expect(described_class.const_get(name)).to be_frozen, name.to_s
      end
    end

    it 'matches canonical enumeration ids only' do
      expect(described_class::CANONICAL_ID.match?('12')).to be(true)
      expect(%w[012 0 -1 1.0 12a].map { |s| described_class::CANONICAL_ID.match?(s) }).to eq([false] * 5)
    end

    # WP-09 adds dependency_check, no_options?, baseline_source and
    # child_baseline; editable_by? is withdrawn (UD-07). WP-10: was
    # "effective_parent_id, parent_errors and parent_changed? are not
    # defined"; WP-10 adds them.
    it 'uses format literals, keeps no state and defines no withdrawn function' do
      source = File.read(File.expand_path('../../lib/redmine_depending_custom_fields/dependency_rules.rb', __dir__))
      expect(source).not_to include('FIELD_FORMAT')
      expect(source).not_to match(/@[a-z_]+ *(\|\|)?=|@@|Rails\.cache|CurrentAttributes|instance_variable_set/)
      expect(described_class.respond_to?(:editable_by?)).to be(false)
      added = [:dependency_check, :no_options?, :baseline_source, :child_baseline,
               :effective_parent_id, :parent_errors, :parent_changed?]
      expect(added.map { |name| described_class.respond_to?(name) }).to eq([true] * 7)
      expect(described_class.respond_to?(:memo)).to be(false)
      expect(described_class.instance_variables).to eq([])
    end
  end

  describe 'ParentState' do
    # WP-09: values and baseline compare as sets of non-blank Strings, so a
    # repeated value (was: changed) and a blank (nil, '' or none) count once.
    it 'is positional and counts an unavailable parent as changed (UD-05)' do
      state = described_class::ParentState
      parent = CustomField.new

      expect(state.members).to eq([:parent, :available, :values, :baseline])
      expect(state.new(nil, false, [], []).changed?).to be(true)
      expect(state.new(parent, false, %w[a], %w[a]).changed?).to be(true)
      expect(state.new(parent, true, %w[b a], %w[a b]).changed?).to be(false)
      expect(state.new(parent, true, %w[a], %w[b]).changed?).to be(true)
      expect(state.new(parent, true, %w[a a], %w[a]).changed?).to be(false)
      expect(state.new(parent, true, %w[a b], %w[a]).changed?).to be(true)
    end

    it 'treats nil, an empty String and no value as the same blank parent' do
      state = described_class::ParentState
      [[[''], []], [[], [nil]], [[''], nil], [nil, ['']], [['', 'a'], ['a', nil]]].each do |values, baseline|
        expect(state.new(nil, true, values, baseline).changed?).to be(false), [values, baseline].inspect
      end
      expect(state.new(nil, true, [''], ['a']).changed?).to be(true)
    end
  end

  describe 'Problem' do
    it 'takes keywords only and leaves child_key nil' do
      problem = described_class::Problem.new(type: :unknown_parent_key, parent_key: 'x')

      expect(problem.child_key).to be_nil
      expect { described_class::Problem.new('a') }.to raise_error(ArgumentError)
    end
  end

  describe '.depending?, .kind and .parent_formats_for' do
    it 'classifies formats' do
      table = {
        'depending_list' => [true, 'list', %w[list depending_list]],
        'depending_enumeration' => [true, 'enumeration', %w[enumeration depending_enumeration]],
        'list' => [false, 'list', []],
        'enumeration' => [false, 'enumeration', []],
        'string' => [false, nil, []],
        nil => [false, nil, []]
      }
      table.each do |format, (depending, kind, families)|
        cf = IssueCustomField.new(field_format: format)
        expect([described_class.depending?(cf), described_class.kind(cf), described_class.parent_formats_for(cf)])
          .to eq([depending, kind, families]), format.inspect
      end
      expect(described_class.kind(IssueCustomField.new(field_format: 'depending_list'))).to be_a(String)
    end
  end

  describe '.normalize_id and .normalize_values' do
    it 'mirrors to_i and never raises' do
      table = { 12 => 12, '12' => 12, ' 12' => 12, '12abc' => 12, '' => nil, nil => nil, 0 => nil, '0' => nil,
                '-3' => nil, -3 => nil, 'abc' => nil, true => nil, false => nil, [12] => nil, { a: 1 } => nil }
      table.each do |raw, expected|
        expect(described_class.normalize_id(raw)).to eq(expected), raw.inspect
      end
    end

    it 'keeps order, duplicates and inner spaces, drops blanks' do
      expect(described_class.normalize_values(nil)).to eq([])
      expect(described_class.normalize_values('a')).to eq(['a'])
      expect(described_class.normalize_values(['a', '', nil, ' ', 1])).to eq(%w[a 1])
      expect(described_class.normalize_values(%w[b a b])).to eq(%w[b a b])
      expect(described_class.normalize_values([' x '])).to eq([' x '])
    end
  end

  describe '.parent_id' do
    it 'reads the in-memory pointer of depending fields only' do
      list = unsaved('list', parent: 12)

      expect(described_class.parent_id(unsaved('depending_list', parent: '12'))).to eq(12)
      expect(described_class.parent_id(unsaved('depending_list', parent: ''))).to be_nil
      expect(list.parent_custom_field_id).to eq(12)
      expect(described_class.parent_id(list)).to be_nil
    end

    it 'sees an unsaved change' do
      child = dcf_list_field(format: 'depending_list', parent: dcf_list_field)
      child.parent_custom_field_id = '15'
      expect(dcf_count_queries { expect(described_class.parent_id(child)).to eq(15) }).to eq(0)
    end
  end

  describe '.resolve_parent_for_save' do
    let(:parent) { dcf_list_field }

    it 'finds the parent once per raw value and record' do
      child = CustomField.find(dcf_list_field(format: 'depending_list', parent: parent).id)
      result = nil
      first = dcf_count_queries { result = described_class.resolve_parent_for_save(child) }
      second = dcf_count_queries { described_class.resolve_parent_for_save(child) }

      expect(result).to eq(parent)
      expect(first).to be > 0
      expect(second).to eq(0)
    end

    it 'issues today\'s exact lookup and shares the entry between 5 and "5"' do
      cf = unsaved('depending_enumeration', parent: '5')
      expect(CustomField).to receive(:find_by)
        .with(id: 5, type: 'IssueCustomField', field_format: %w[enumeration depending_enumeration]).once.and_return(nil)

      expect(described_class.resolve_parent_for_save(cf)).to be_nil
      cf.parent_custom_field_id = 5
      expect(described_class.resolve_parent_for_save(cf)).to be_nil
    end

    it 'returns nil without a query or a memo entry for blank values and other formats' do
      blank = unsaved('depending_list', parent: '  ')
      list = unsaved('list', parent: parent.id)
      results = nil
      queries = dcf_count_queries do
        results = [blank, unsaved('depending_list'), list].map { |cf| described_class.resolve_parent_for_save(cf) }
      end

      expect(results).to eq([nil, nil, nil])
      expect(queries).to eq(0)
      expect(blank.instance_variable_get(:@dcf_memo)).to be_nil
    end

    it 'returns nil for wrong type, wrong family and dangling ids, memoized' do
      project_list = dcf_list_field(type: ProjectCustomField)
      enum = dcf_enum_field
      [project_list.id, enum.id, 999_999_999, 'abc'].each do |raw|
        cf = unsaved('depending_list', parent: raw)
        expect(described_class.resolve_parent_for_save(cf)).to be_nil
        expect(dcf_count_queries { described_class.resolve_parent_for_save(cf) }).to eq(0), raw.inspect
      end
    end

    it 'looks again after the in-memory pointer changes and keeps one entry per raw value' do
      other = dcf_list_field
      child = CustomField.find(dcf_list_field(format: 'depending_list', parent: parent).id)

      expect(described_class.resolve_parent_for_save(child)).to eq(parent)
      child.parent_custom_field_id = other.id
      expect(dcf_count_queries { expect(described_class.resolve_parent_for_save(child)).to eq(other) }).to be > 0
      child.parent_custom_field_id = parent.id.to_s
      expect(dcf_count_queries { expect(described_class.resolve_parent_for_save(child)).to eq(parent) }).to eq(0)
    end

    it 'resolves a self-parent to the field itself' do
      child = dcf_list_field(format: 'depending_list', parent: parent)
      child.parent_custom_field_id = child.id
      expect(described_class.resolve_parent_for_save(child)).to eq(child)
    end
  end

  describe '.find_parent' do
    it 'looks the id up on every call' do
      field = dcf_list_field
      once = dcf_count_queries { described_class.find_parent(field.id) }
      twice = dcf_count_queries { 2.times { described_class.find_parent(field.id) } }

      expect(described_class.find_parent(field.id)).to eq(field)
      expect(twice).to eq(2 * once)
    end
  end

  describe '.parent_of' do
    let(:parent) { dcf_list_field }

    it 'returns the parent record and queries once per pointer' do
      child = CustomField.find(dcf_list_field(format: 'depending_list', parent: parent).id)
      result = nil
      first = dcf_count_queries { result = described_class.parent_of(child) }

      expect(result).to eq(parent)
      expect(first).to eq(dcf_count_queries { described_class.find_parent(parent.id) })
      expect(dcf_count_queries { described_class.parent_of(child) }).to eq(0)
    end

    it 'returns nil without a query for blank pointers, self and other formats' do
      parent
      self_parent = dcf_list_field(format: 'depending_list')
      self_parent.parent_custom_field_id = self_parent.id
      results = nil
      queries = dcf_count_queries do
        results = [unsaved('depending_list'), unsaved('depending_list', parent: ''), self_parent,
                   unsaved('list', parent: parent.id)].map { |cf| described_class.parent_of(cf) }
      end

      expect(results).to eq([nil, nil, nil, nil])
      expect(queries).to eq(0)
    end

    it 'returns nil for dangling, wrong STI type and wrong family, and memoizes nil' do
      project_list = dcf_list_field(type: ProjectCustomField)
      enum = dcf_enum_field
      list_for_enum = dcf_list_field
      cases = [
        unsaved('depending_list', parent: 999_999_999),
        unsaved('depending_list', parent: project_list.id),
        unsaved('depending_list', parent: enum.id),
        unsaved('depending_enumeration', parent: list_for_enum.id)
      ]
      cases.each do |cf|
        expect(described_class.parent_of(cf)).to be_nil
        expect(dcf_count_queries { described_class.parent_of(cf) }).to eq(0)
      end
    end

    it 'accepts both families and other STI types with a matching parent' do
      enum_parent = dcf_enum_field
      enum_child = unsaved('depending_enumeration', parent: enum_parent.id)
      project_parent = dcf_list_field(type: ProjectCustomField)
      project_child = unsaved('depending_list', type: ProjectCustomField, parent: project_parent.id)
      depending_parent = dcf_list_field(format: 'depending_list', parent: parent)

      expect(described_class.parent_of(enum_child)).to eq(enum_parent)
      expect(described_class.parent_of(project_child)).to eq(project_parent)
      expect(described_class.parent_of(unsaved('depending_list', parent: depending_parent.id))).to eq(depending_parent)
    end

    it 'looks again after the in-memory pointer changes' do
      other = dcf_list_field
      child = CustomField.find(dcf_list_field(format: 'depending_list', parent: parent).id)
      described_class.parent_of(child)
      child.parent_custom_field_id = other.id

      expect(dcf_count_queries { expect(described_class.parent_of(child)).to eq(other) }).to be > 0
    end

    it 'goes through find_parent' do
      stand_in = CustomField.find(parent.id)
      allow(described_class).to receive(:find_parent).with(parent.id).and_return(stand_in)

      expect(described_class.parent_of(unsaved('depending_list', parent: parent.id))).to equal(stand_in)
    end
  end

  describe '.carries?' do
    it 'is strictly true only for an instance of the customized class' do
      expect(described_class.carries?(IssueCustomField.new, Issue.new)).to be(true)
      expect(described_class.carries?(IssueCustomField.new, Project.new)).to be(false)
      expect(described_class.carries?(IssueCustomField.new, nil)).to be(false)
      expect(described_class.carries?(IssueCustomField.new, [Issue.new])).to be(false)
      expect(described_class.carries?(ProjectCustomField.new, Project.new)).to be(true)
      expect(described_class.carries?(UserCustomField.new, User.new)).to be(true)
      expect(described_class.carries?(UserCustomField.new, Group.new)).to be(false)
      expect(described_class.carries?(GroupCustomField.new, Group.new)).to be(true)
      expect(described_class.carries?(CustomField.new, Issue.new)).to be(false)
    end

    it 'is false when customized_class raises' do
      allow(IssueCustomField).to receive(:customized_class).and_raise(NameError)
      expect(described_class.carries?(IssueCustomField.new, Issue.new)).to be(false)
    end
  end

  describe '.lookup_records' do
    def issue_with(fields, project: dcf_create_project)
      tracker, = dcf_issue_infra(project)
      fields.each { |f| tracker.custom_fields << f unless tracker.custom_fields.include?(f) }
      Issue.find(dcf_issue_with_value(project, fields.first, 'A').id)
    end

    def fields_with_children(count)
      parent = dcf_list_field
      [parent] + Array.new(count) { dcf_list_field(format: 'depending_list', parent: parent) }
    end

    it 'costs no query from loaded custom field values, for 1 and for 5 depending fields' do
      [1, 5].each do |count|
        fields = fields_with_children(count)
        issue = issue_with(fields)
        issue.custom_field_values
        result = nil

        expect(dcf_count_queries { result = described_class.lookup_records(issue) }).to eq(0)
        expect(result.keys).to include(*fields.map(&:id))
        issue.custom_field_values.each { |cfv| expect(result[cfv.custom_field.id]).to equal(cfv.custom_field) }
      end
    end

    it 'unites the available fields of an Array of objects without duplicates' do
      project = dcf_create_project
      fields = fields_with_children(2)
      issues = [issue_with(fields, project: project), issue_with(fields, project: project)]
      issues.each(&:available_custom_fields)
      result = nil

      expect(dcf_count_queries { result = described_class.lookup_records(issues) }).to eq(0)
      expect(result.keys).to match_array(issues.flat_map(&:available_custom_fields).map(&:id).uniq)
      expect(result[fields[1].id]).to equal(issues.first.available_custom_fields.find { |f| f.id == fields[1].id })
    end

    it 'gives {} for nil and skips objects without custom fields' do
      expect(described_class.lookup_records(nil)).to eq({})
      expect(described_class.lookup_records([Object.new, nil])).to eq({})
    end
  end

  # WP-10: the effective parent (server design 2.1), the one rule of server
  # validation; client emission (WP-16) and the context menu (WP-15) use it
  # too. Walks follow the stored pointers; the child's own pointer is the
  # in-memory one.
  describe '.effective_parent_id' do
    let(:root) { dcf_list_field(values: %w[A B]) }

    def depending(parent = nil, format: 'depending_list')
      if format == 'depending_list'
        dcf_list_field(format: format, values: %w[a b], parent: parent)
      else
        dcf_enum_field(format: format, names: %w[a b], parent: parent)
      end
    end

    # label => [fresh field, expected effective parent id]
    def pointer_table
      valid = depending(root)
      itself = depending.tap { |f| point(f, f.id) }
      x = depending
      y = depending(x)
      point(x, y.id)
      a = depending
      c = depending(a)
      b = depending(c)
      point(a, b.id)
      enum_root = dcf_enum_field
      {
        'valid' => [valid, root.id],
        'a valid chain of two' => [depending(valid), valid.id],
        'an enumeration parent' => [depending(enum_root, format: 'depending_enumeration'), enum_root.id],
        'dangling' => [depending(root).tap { |f| point(f, CustomField.maximum(:id).to_i + 1_000) }, nil],
        'another type' => [depending(root).tap { |f| point(f, dcf_list_field(type: ProjectCustomField).id) }, nil],
        'another family' => [depending(root).tap { |f| point(f, dcf_enum_field.id) }, nil],
        'itself' => [itself, nil],
        'a member of x <-> y' => [x, nil],
        'the other member of x <-> y' => [y, nil],
        'below x <-> y' => [depending(x), nil],
        'below a self-parent' => [depending(itself), nil],
        'two levels below a self-parent' => [depending(depending(itself)), nil],
        'a member of a -> b -> c -> a' => [b, nil]
      }.transform_values { |(field, id)| [CustomField.find(field.id), id] }
    end

    it 'gives the Integer id of a valid, acyclic parent and nil for every other stored pointer' do
      pointer_table.each do |label, (field, expected)|
        expect(described_class.effective_parent_id(field)).to eq(expected), label
        expect(described_class.effective_parent_id(field)).to be_a(Integer), label if expected
      end
    end

    it 'equals FieldIndex#effective_parent_id_for on a fresh index for every row' do
      pointer_table.each do |label, (field, _expected)|
        oracle = RedmineDependingCustomFields::FieldIndex.load
                   .effective_parent_id_for(field.id, field.type, field.field_format, field.parent_custom_field_id)
        expect(described_class.effective_parent_id(field)).to eq(oracle), label
      end
    end

    it 'implies parent_of, and is nil whenever parent_of is nil' do
      pointer_table.each do |label, (field, _expected)|
        effective = described_class.effective_parent_id(field)
        parent = described_class.parent_of(CustomField.find(field.id))
        expect(parent&.id).to eq(effective), label if effective
        expect(effective).to be_nil, label if parent.nil?
      end
    end

    it 'is nil without a query for a blank, zero, invalid or own pointer and for other formats' do
      root
      [nil, '', '  ', 0, '0', 'abc', -3].each do |raw|
        field = unsaved('depending_list', parent: raw)
        expect(dcf_count_queries { expect(described_class.effective_parent_id(field)).to be_nil }).to eq(0), raw.inspect
      end
      itself = depending
      itself.parent_custom_field_id = itself.id
      expect(dcf_count_queries { expect(described_class.effective_parent_id(itself)).to be_nil }).to eq(0)
      plain = dcf_list_field
      plain.parent_custom_field_id = root.id
      expect(dcf_count_queries { expect(described_class.effective_parent_id(plain)).to be_nil }).to eq(0)
    end

    it 'works for a new record and follows an in-memory pointer change on the same instance' do
      other = dcf_list_field
      field = unsaved('depending_list', parent: root.id.to_s)
      expect(described_class.effective_parent_id(field)).to eq(root.id)
      field.parent_custom_field_id = other.id
      expect(described_class.effective_parent_id(field)).to eq(other.id)
      field.parent_custom_field_id = ''
      expect(described_class.effective_parent_id(field)).to be_nil
    end

    it 'memoizes on the record, nil included, so a repeated call costs no query' do
      valid = CustomField.find(depending(root).id)
      dangling = CustomField.find(depending(root).tap { |f| point(f, CustomField.maximum(:id).to_i + 1_000) }.id)
      [[valid, root.id], [dangling, nil]].each do |field, expected|
        expect(described_class.effective_parent_id(field)).to eq(expected)
        expect(dcf_count_queries { expect(described_class.effective_parent_id(field)).to eq(expected) }).to eq(0)
      end
      expect(described_class.instance_variables).to eq([])
    end

    it 'is nil for an in-memory pointer that closes a cycle with the stored chain' do
      a = CustomField.find(depending.id)
      b = depending(a)
      c = depending(b)
      [b, c].each do |candidate|
        a.parent_custom_field_id = candidate.id
        expect(described_class.effective_parent_id(a)).to be_nil, candidate.id.to_s
      end
      a.parent_custom_field_id = root.id
      expect(described_class.effective_parent_id(a)).to eq(root.id)
    end

    it 'gives nil (unconstrained) when the chain is longer than the walk cap' do
      stub_const('RedmineDependingCustomFields::FieldIndex::WALK_CAP', 3)
      chain = [root]
      4.times { chain << depending(chain.last) }
      expect(described_class.effective_parent_id(CustomField.find(chain[2].id))).to eq(chain[1].id)
      expect(described_class.effective_parent_id(CustomField.find(chain.last.id))).to be_nil
    end

    context 'with the records loaded on an issue' do
      let(:project) { dcf_create_project }

      def issue_with(fields)
        tracker, = dcf_issue_infra(project)
        fields.each { |f| tracker.custom_fields << f unless tracker.custom_fields.include?(f) }
        issue = Issue.find(dcf_issue_with_value(project, fields.first, 'A').id)
        issue.custom_field_values
        issue
      end

      it 'walks a chain of three loaded on the issue without a query and without deserializing a parent store' do
        middle = depending(root)
        child = CustomField.find(depending(middle).id)
        issue = issue_with([root, middle, child])
        lookup = described_class.lookup_records(issue)
        child.parent_custom_field_id
        queries = nil
        loads = dcf_count_yaml_loads do
          queries = dcf_count_queries { expect(described_class.effective_parent_id(child, lookup)).to eq(middle.id) }
        end

        expect([queries, loads]).to eq([0, 0])
      end

      it 'looks an unloaded first hop up through the memoized find_parent, shared with parent_state' do
        child = CustomField.find(depending(root).id)
        issue = issue_with([dcf_list_field, child])
        lookup = described_class.lookup_records(issue)
        one_lookup = dcf_count_queries { described_class.find_parent(root.id) }
        allow(described_class).to receive(:find_parent).and_call_original

        first = dcf_count_queries { expect(described_class.effective_parent_id(child, lookup)).to eq(root.id) }
        expect(first).to eq(one_lookup)
        state = nil
        expect(dcf_count_queries { state = described_class.parent_state(child, issue) }).to eq(0)
        expect([state.parent, state.available]).to eq([root, false])
        expect(described_class).to have_received(:find_parent).once
      end

      # G6 (server design 3.3): the children of a loaded first hop share its
      # stored chain, so a grandparent the issue does not carry costs one raw
      # select for all of them, not one per child.
      it 'shares the stored chain of a loaded parent between its children' do
        middle = depending(root)
        children = Array.new(3) { depending(middle) }
        issue = issue_with([dcf_list_field, middle] + children)
        lookup = described_class.lookup_records(issue)
        per_level = dcf_count_queries { RedmineDependingCustomFields::FieldIndex.new.ensure([root.id]) }

        counts = lookup.values_at(*children.map(&:id)).map do |child|
          dcf_count_queries { expect(described_class.effective_parent_id(child, lookup)).to eq(middle.id) }
        end
        expect(counts).to eq([per_level, 0, 0])
      end

      it 'keeps each child its own verdict on a shared chain: a child the chain passes through gets nil' do
        x = depending(root)
        parent = depending(x)
        sibling = depending(parent)
        issue = issue_with([dcf_list_field, x, parent, sibling])
        lookup = described_class.lookup_records(issue)
        closing = CustomField.find(x.id)
        closing.parent_custom_field_id = parent.id

        expect(described_class.effective_parent_id(lookup[sibling.id], lookup)).to eq(parent.id)
        expect(described_class.effective_parent_id(closing, lookup)).to be_nil
        expect(described_class.effective_parent_id(lookup[parent.id], lookup)).to eq(x.id)
      end

      it 'accepts the available fields of an Array of objects as lookup' do
        middle = depending(root)
        child = CustomField.find(depending(middle).id)
        issues = [issue_with([root, middle, child]), issue_with([root, middle, child])]
        lookup = described_class.lookup_records(issues)

        expect(dcf_count_queries { expect(described_class.effective_parent_id(child, lookup)).to eq(middle.id) }).to eq(0)
      end
    end
  end

  # WP-06 adds parent_state and allowed_for with 0.0.16's semantics; WP-10
  # reads the effective parent (no state without one) and WP-15 gives no
  # state for an object the field does not carry (carries?).
  describe '.parent_state' do
    let(:project) { dcf_create_project }
    let(:parent) { dcf_list_field(values: %w[A B C]) }
    let(:child) { CustomField.find(dcf_list_field(format: 'depending_list', values: %w[a1 b1], parent: parent).id) }

    # A persisted issue holding +values+ (field => value), reloaded. A fresh
    # Project instance each time: a Project memoizes its custom fields.
    def issue_on(values)
      fresh = Project.find(project.id)
      tracker, status, priority = dcf_issue_infra(fresh)
      values.each_key { |f| tracker.custom_fields << f unless tracker.custom_fields.include?(f) }
      issue = Issue.new(project: fresh, tracker: tracker, subject: 'S', author: dcf_admin,
                        status: status, priority: priority)
      issue.custom_field_values = values.to_h { |f, v| [f.id.to_s, v] }
      issue.save!(validate: false)
      Issue.find(issue.id)
    end

    def memo_names(field)
      field.instance_variable_get(:@dcf_memo).to_h.keys.map(&:first)
    end

    it 'reads an available parent from the loaded custom field values, without a query' do
      issue = issue_on(parent => 'A', child => 'a1')
      issue.custom_field_values = { parent.id.to_s => 'B' }
      state = nil

      expect(dcf_count_queries { state = described_class.parent_state(child, issue) }).to eq(0)
      expect(state.parent).to equal(issue.custom_field_values.detect { |v| v.custom_field_id == parent.id }.custom_field)
      expect([state.available, state.values, state.baseline]).to eq([true, ['B'], ['A']])
      expect(memo_names(child)).not_to include(:parent_record)
    end

    it 'keeps blank values, and every value of a multiple parent, as Strings' do
      expect(described_class.parent_state(child, issue_on(parent => '')).values).to eq([''])
      parent.update!(multiple: true)
      state = described_class.parent_state(CustomField.find(child.id), issue_on(parent => %w[A B]))
      expect([state.values, state.baseline]).to eq([%w[A B], %w[A B]])
    end

    it 'gives an unavailable state for an existing parent the object does not carry, looked up once' do
      issue = issue_on(child => 'a1')
      issue.custom_field_values
      allow(described_class).to receive(:find_parent).and_call_original
      state = described_class.parent_state(child, issue)

      expect([state.parent, state.available, state.values, state.baseline]).to eq([parent, false, [], []])
      expect(dcf_count_queries { described_class.parent_state(child, issue) }).to eq(0)
      expect(described_class).to have_received(:find_parent).with(parent.id).once
      # Flipped by WP-15 (carries?): a Project passed for an issue field gave
      # an unavailable state (available false); it gives no state now.
      expect(described_class.parent_state(child, project)).to be_nil
    end

    it 'is nil for a dangling parent, memoized' do
      field = CustomField.find(child.id)
      field.parent_custom_field_id = CustomField.maximum(:id).to_i + 1_000
      issue = issue_on(parent => 'A')
      issue.custom_field_values

      expect(described_class.parent_state(field, issue)).to be_nil
      expect(dcf_count_queries { described_class.parent_state(field, issue) }).to eq(0)
    end

    # Flipped by WP-10 (UD-08, UD-35): was "accepts a parent of any type, of
    # any family and the field itself, unlike parent_of", expecting a state
    # read from the field itself, an unavailable state for the other type and
    # a state read from the enumeration.
    it 'is nil for a parent of another type, of another family or the field itself, like parent_of' do
      point(child, child.id)
      own = CustomField.find(child.id)
      expect(described_class.parent_state(own, issue_on(own => 'a1'))).to be_nil
      expect(described_class.parent_of(own)).to be_nil

      other_type = dcf_list_field(type: ProjectCustomField)
      point(child, other_type.id)
      field = CustomField.find(child.id)
      expect(described_class.parent_state(field, issue_on(parent => 'A'))).to be_nil
      expect(described_class.parent_of(field)).to be_nil

      enum = dcf_enum_field(names: %w[X])
      point(child, enum.id)
      field = CustomField.find(child.id)
      expect(described_class.parent_state(field, issue_on(enum => enum.enumerations.first.id.to_s))).to be_nil
      expect(described_class.parent_of(field)).to be_nil
    end

    # WP-10 (UD-08, UD-35): no state in or below a stored cycle.
    it 'is nil for the members of a stored cycle and for a field whose chain reaches one' do
      x = CustomField.find(dcf_list_field(format: 'depending_list', values: %w[x1]).id)
      y = dcf_list_field(format: 'depending_list', values: %w[y1], parent: x)
      point(x, y.id)
      below = dcf_list_field(format: 'depending_list', values: %w[c1], parent: x)
      itself = dcf_list_field(format: 'depending_list', values: %w[s1])
      point(itself, itself.id)
      below_itself = dcf_list_field(format: 'depending_list', values: %w[d1], parent: itself)
      fields = [x, y, below, itself, below_itself].map { |f| CustomField.find(f.id) }
      issue = issue_on(fields.index_with { |f| f.possible_values.first })

      fields.each do |field|
        expect(described_class.parent_state(field, issue)).to be_nil, field.possible_values.inspect
      end
    end

    it 'is nil without a query, a lookup or a load for no pointer, an invalid pointer, no object or another format' do
      untouchable = Object.new
      def untouchable.custom_field_values
        raise 'custom field values loaded'
      end
      [nil, '', '  ', 0, '0', 'abc', -3].each do |raw|
        field = CustomField.find(child.id)
        field.parent_custom_field_id = raw
        expect(dcf_count_queries { expect(described_class.parent_state(field, untouchable)).to be_nil }).to eq(0), raw.inspect
        expect(memo_names(field)).not_to include(:parent_record)
      end
      expect(dcf_count_queries { expect(described_class.parent_state(child, nil)).to be_nil }).to eq(0)
      plain = dcf_list_field
      plain.parent_custom_field_id = parent.id
      expect(described_class.parent_state(plain, untouchable)).to be_nil
    end

    it 'looks a parent up through find_parent only' do
      stand_in = CustomField.find(parent.id)
      issue = issue_on(child => 'a1')
      issue.custom_field_values
      allow(described_class).to receive(:find_parent).with(parent.id).and_return(stand_in)
      allow(CustomField).to receive(:find_by).and_call_original

      expect(described_class.parent_state(child, issue).parent).to equal(stand_in)
      expect(CustomField).not_to have_received(:find_by)
    end

    # Flipped by WP-15 (carries?): was "asks an object without custom field
    # values like 0.0.16 (NoMethodError)".
    it 'is nil for an object without custom field values (Flipped by WP-15)' do
      expect(described_class.parent_state(child, Object.new)).to be_nil
    end

    # WP-15: the carries? guard runs before the parent pointer is read.
    it 'reads no format_store and runs no query for an object the field does not carry' do
      [project, Object.new].each do |object|
        fresh = CustomField.find(child.id)
        result = :unset
        loads = dcf_count_yaml_loads do
          expect(dcf_count_queries { result = described_class.parent_state(fresh, object) }).to eq(0)
        end
        expect([result, loads]).to eq([nil, 0]), object.class.name
      end
    end
  end

  describe '.allowed_for' do
    rows = JSON.parse(File.read(File.expand_path('../../test/js/fixtures/shared/rules_cases.json', __dir__),
                                encoding: 'UTF-8'))['allowed']

    def field_with(map)
      cf = unsaved('depending_list')
      cf.value_dependencies = map
      cf
    end

    def state(values, available: true)
      described_class::ParentState.new(nil, available, values, [])
    end

    # 0.0.16's inline union (depending_list_format.rb before WP-06).
    def today(map, values)
      mapping = map || {}
      values.flat_map { |v| Array(mapping[v]) }.map(&:to_s)
    end

    it 'equals the shared allowed cases for every mapping a save stores (sanitized)' do
      rows.each do |row|
        result = described_class.allowed_for(field_with(sanitizer.sanitize_dependencies(row['map'])), state(row['parent']))
        expect(result).to eq(Set.new(row['expected'])), row['id']
      end
    end

    it 'equals 0.0.16\'s raw union for every case, sanitized or not, as a Set' do
      rows.each do |row|
        cf = field_with(row['map'])
        result = described_class.allowed_for(cf, state(row['parent']))
        expect(result).to be_a(Set)
        expect(result).to eq(Set.new(today(cf.value_dependencies, row['parent']))), row['id']
      end
    end

    it 'counts a stored blank key and blank links like 0.0.16 (allowed_set does not)' do
      cf = field_with('' => ['a1'], 'A' => [''])
      expect(described_class.allowed_for(cf, state(['']))).to eq(Set['a1'])
      expect(described_class.allowed_for(cf, state(['A']))).to eq(Set[''])
      expect(described_class.allowed_set(cf.value_dependencies, [''])).to be_empty
    end

    it 'is empty for an unavailable parent and for a field without a mapping' do
      expect(described_class.allowed_for(field_with('A' => ['a1']), state([], available: false))).to eq(Set.new)
      expect(described_class.allowed_for(unsaved('depending_list'), state(['A']))).to eq(Set.new)
    end

    it 'reads a saved mapping as is, for a multiple parent' do
      parent = dcf_list_field(values: %w[A B C])
      child = dcf_list_field(format: 'depending_list', values: %w[a1 a2 b1], parent: parent)
      child = dcf_set_dependencies(child, value_dependencies: { 'A' => %w[a1 a2], 'B' => %w[b1 a1] })
      allow(sanitizer).to receive(:sanitize_dependencies).and_call_original

      expect(described_class.allowed_for(child, state(%w[A B]))).to eq(Set.new(today(child.value_dependencies, %w[A B])))
      expect(described_class.allowed_for(child, state(%w[B]))).to eq(Set['b1', 'a1'])
      expect(sanitizer).not_to have_received(:sanitize_dependencies)
    end
  end

  # WP-09: D1 per value (UD-04), copies judged against their source (UD-06),
  # an unavailable parent counts as changed (UD-05). No editable_by? (UD-07).
  describe 'D1: .dependency_check, .baseline_source, .child_baseline and .no_options?' do
    include DcfFormatCharacterization

    let(:project) { dcf_create_project }
    let(:invalid) { I18n.t('activerecord.errors.messages.invalid') }
    let(:kit) { build_kit(:list) }
    let(:parent) { kit.first }
    let(:child) { kit.last }

    def value_of(record, field)
      record.custom_field_values.detect { |v| v.custom_field_id == field.id }
    end

    # A value without a record: child_was is its baseline.
    def detached(map, child, child_was, multiple: false)
      cf = unsaved('depending_list')
      cf.multiple = multiple
      cf.value_dependencies = map
      value = CustomFieldValue.new
      value.custom_field = cf
      value.instance_variable_set(:@value, child)
      value.value_was = child_was
      value
    end

    def state(values, baseline, available: true)
      described_class::ParentState.new(nil, available, values, baseline)
    end

    # Loads the values (as init_journal does), then moves +issue+ to a new
    # tracker carrying the parent and the child: core rebuilds the values.
    def move_to_new_tracker(issue)
      tracker = dcf_tracker
      [parent, child].each { |f| tracker.custom_fields << f }
      project.trackers << tracker
      issue.custom_field_values
      issue.tracker = tracker
      issue
    end

    it 'takes the value and the parent state only, and returns [allowed_empty, errors]' do
      expect(described_class.method(:dependency_check).arity).to eq(2)
      map = { 'A' => %w[a1], 'C' => [] }

      expect(described_class.dependency_check(detached(map, 'a1', nil), state(%w[A], %w[A]))).to eq([false, []])
      expect(described_class.dependency_check(detached(map, 'b1', nil), state(%w[A], %w[A]))).to eq([false, [invalid]])
      expect(described_class.dependency_check(detached(map, '', 'b1'), state(%w[C], %w[A]))).to eq([true, []])
      expect(described_class.dependency_check(detached(map, 'b1', 'b1'), state(%w[C], %w[C]))).to eq([true, []])
      expect(described_class.dependency_check(detached(map, 'b1', 'b1'), state([], [], available: false)))
        .to eq([true, [invalid]])
    end

    it 'gives one message in the locale active at validation time, however many values are bad' do
      value = detached({ 'A' => %w[a1] }, %w[x y z], [], multiple: true)
      { en: 'is invalid', de: 'ist nicht gültig' }.each do |locale, message|
        I18n.with_locale(locale) do
          expect(described_class.dependency_check(value, state(%w[A], %w[A])).last).to eq([message])
        end
      end
    end

    it 'reads only the value, the copy source and the state: no query for a persisted issue or a copy' do
      issue = kit_issue(project, parent => 'A', child => 'b1')
      issue.custom_field_values = { child.id.to_s => 'b1' }
      copy = Issue.new.copy_from(issue)
      [issue, copy].each do |record|
        value = value_of(record, child)
        record_state = described_class.parent_state(value.custom_field, record)
        result = nil
        allow(User).to receive(:current).and_raise('the current user is not read')

        expect(dcf_count_queries { result = described_class.dependency_check(value, record_state) }).to eq(0)
        expect(result).to eq([false, []]), record.new_record?.inspect
      end
    end

    describe '.baseline_source' do
      it 'is the copy source for a new copy only' do
        source = kit_issue(project, parent => 'A', child => 'b1')
        copy = Issue.new.copy_from(source)

        expect(described_class.baseline_source(copy)).to equal(source)
        [source, Issue.new, nil, Object.new, Project.new, Project.copy_from(project)].each do |record|
          expect(described_class.baseline_source(record)).to be_nil, record.class.name
        end
      end

      it 'only reads the object: no copy? call before new_record?, no instance variable written' do
        source = kit_issue(project, parent => 'A', child => 'b1')
        allow(source).to receive(:copy?).and_call_original
        copy = Issue.new.copy_from(source)
        ivars = copy.instance_variables

        expect(described_class.baseline_source(source)).to be_nil
        expect(source).not_to have_received(:copy?)
        expect(described_class.baseline_source(copy)).to equal(source)
        expect(copy.instance_variables).to eq(ivars)
      end
    end

    describe '.child_baseline' do
      it 'is the stored value of a persisted record, as Strings without blanks' do
        multi_parent, multi_child = build_kit(:list, multiple: true)
        issue = kit_issue(project, multi_parent => 'A', multi_child => %w[b1 a1])
        issue.custom_field_values = { multi_child.id.to_s => %w[a2] }

        expect(described_class.child_baseline(value_of(issue, multi_child))).to match_array(%w[b1 a1])
      end

      it 'is the source value for a copy, and [] when the source does not carry the field' do
        copy = Issue.new.copy_from(kit_issue(project, parent => 'A', child => 'b1'))
        copy.custom_field_values = { child.id.to_s => 'a1' }
        expect(described_class.child_baseline(value_of(copy, child))).to eq(%w[b1])

        other = kit_new_issue(project, parent => 'A', child => 'b1')
        allow(other).to receive(:copy?).and_return(true)
        other.instance_variable_set(:@copied_from, double('source', custom_field_value: nil))
        expect(described_class.child_baseline(value_of(other, child))).to eq([])
      end

      it 'is [] for a new record that is not a copy, whatever value_was holds' do
        issue = kit_new_issue(project, parent => 'A', child => 'b1')
        value = value_of(issue, child)
        value.value_was = 'b1'
        expect(described_class.child_baseline(value)).to eq([])
      end

      it 'is value_was for a value without a record' do
        expect(described_class.child_baseline(detached({}, 'a1', ['b1', '', nil, 'a1']))).to eq(%w[b1 a1])
        expect(described_class.child_baseline(detached({}, 'a1', nil))).to eq([])
      end

      it 'is [] without a saved row, also when a tracker change fills in the field default as value_was' do
        child.update_column(:default_value, 'b1')
        issue = move_to_new_tracker(kit_issue(project, parent => 'A'))
        value = value_of(issue, child)

        expect([value.value, value.value_was]).to eq(%w[b1 b1])
        expect(described_class.child_baseline(value)).to eq([])
        expect(described_class.dependency_check(value, described_class.parent_state(child, issue)))
          .to eq([false, [invalid]])
      end
    end

    describe '.parent_state baseline' do
      it 'is the normalized stored value of a persisted record' do
        issue = kit_issue(project, parent => 'A', child => 'a1')
        issue.custom_field_values = { parent.id.to_s => 'B' }
        expect(described_class.parent_state(child, issue).baseline).to eq(%w[A])

        blank = kit_issue(project, child => 'b1')
        blank.custom_field_values = { parent.id.to_s => '' }
        blank_state = described_class.parent_state(child, blank)
        expect([blank_state.values, blank_state.baseline, blank_state.changed?]).to eq([[''], [], false])
      end

      # Core gives a field without a saved row its default on a tracker or
      # project change (Issue#set_custom_field_default?) and value_was copies
      # it; nothing is stored, so the baseline stays [] and the parent counts
      # as changed, as for a copy whose source does not carry it.
      it 'is [] without a saved row, also when a tracker change fills in the parent default, without a query' do
        parent.update!(default_value: 'A')
        issue = move_to_new_tracker(kit_issue(project, child => 'b1'))
        moved = nil

        expect(value_of(issue, parent).value_was).to eq('A')
        expect(dcf_count_queries { moved = described_class.parent_state(child, issue) }).to eq(0)
        expect([moved.values, moved.baseline, moved.changed?]).to eq([%w[A], [], true])
        expect(described_class.dependency_check(value_of(issue, child), moved)).to eq([false, [invalid]])
      end

      it 'is the source value for a copy (not value_was, which holds the default)' do
        parent.update!(default_value: 'B')
        copy = Issue.new.copy_from(kit_issue(project, parent => 'A', child => 'b1'))
        copy_state = described_class.parent_state(child, copy)

        expect(value_of(copy, parent).value_was).to eq('B')
        expect([copy_state.values, copy_state.baseline, copy_state.changed?]).to eq([%w[A], %w[A], false])
        copy.custom_field_values = { parent.id.to_s => 'B' }
        expect(described_class.parent_state(child, copy).changed?).to be(true)
      end

      it 'gives the arrays WP-16 emits: the child and parent baselines dependency_check compares' do
        issue = kit_issue(project, parent => 'A', child => 'b1')
        issue.custom_field_values = { child.id.to_s => 'b1' }
        [issue, Issue.new.copy_from(Issue.find(issue.id))].each do |record|
          value = value_of(record, child)
          record_state = described_class.parent_state(child, record)

          expect([described_class.child_baseline(value), record_state.baseline]).to eq([%w[b1], %w[A]])
          expect(described_class.dependency_check(value, record_state)).to eq([false, []])
          record.custom_field_values = { parent.id.to_s => 'C' }
          expect(described_class.dependency_check(value, described_class.parent_state(child, record)))
            .to eq([true, [invalid]])
        end
      end
    end

    describe '.no_options?' do
      it 'is true when the parent value allows nothing, as dependency_check reports' do
        { 'A' => false, 'C' => true, '' => true }.each do |parent_value, expected|
          issue = kit_new_issue(project, parent => parent_value.empty? ? [] : parent_value, child => [])
          record_state = described_class.parent_state(child, issue)

          expect(described_class.no_options?(child, issue)).to be(expected), parent_value.inspect
          expect(described_class.dependency_check(value_of(issue, child), record_state).first).to be(expected)
        end
      end

      it 'is true for an unavailable parent and false without a parent state' do
        issue = kit_issue(project, child => 'a1')
        expect(described_class.no_options?(child, issue)).to be(true)
        expect(described_class.no_options?(child, nil)).to be(false)
        dangling = CustomField.find(child.id)
        dangling.parent_custom_field_id = CustomField.maximum(:id).to_i + 1_000
        expect(described_class.no_options?(dangling, issue)).to be(false)
        plain = dcf_list_field
        expect(described_class.no_options?(plain, issue)).to be(false)
      end

      it 'is false for a parent deleted after the values were loaded, looked up once per field record' do
        issue = kit_new_issue(project, parent => 'C', child => [])
        field = CustomField.find(child.id)
        expect(described_class.no_options?(field, issue)).to be(true)
        CustomField.where(id: parent.id).delete_all
        fresh = CustomField.find(child.id)
        allow(described_class).to receive(:find_parent).and_call_original

        expect(described_class.no_options?(fresh, issue)).to be(false)
        expect(dcf_count_queries { described_class.no_options?(fresh, issue) }).to eq(0)
        expect(described_class).to have_received(:find_parent).once
      end

      # semantics-r2-1: without an effective parent, parent_state is nil
      # (UD-08, UD-35) but no_options? keeps the 0.0.16 read (the raw pointer:
      # any existing field, of any type and family, the field itself
      # included, its value read from the object) until WP-18 retires the
      # legacy script, which disables such a field while that parent allows
      # nothing and posts ''.
      context 'without an effective parent (0.0.16 read kept until WP-18)' do
        include DcfStoredCycle

        it 'reads the stored parent of a cycle member, a self-parent and a field below a cycle from the object' do
          world = dcf_stored_cycles(:list)
          x, self_parent, below = [world.x, world.self_parent, world.child].map { |f| CustomField.find(f.id) }
          { 'y1' => false, 'y2' => true, '' => true }.each do |y_value, expected|
            issue = kit_new_issue(project, world.y => y_value.empty? ? [] : y_value, x => [])
            expect(described_class.parent_state(x, issue)).to be_nil
            expect(described_class.no_options?(x, issue)).to be(expected), y_value.inspect
          end
          { 's1' => false, 's2' => true }.each do |own, expected|
            issue = kit_new_issue(project, self_parent => own)
            expect(described_class.parent_state(self_parent, issue)).to be_nil
            expect(described_class.no_options?(self_parent, issue)).to be(expected), own
          end
          { 'x1' => false, 'x2' => true }.each do |x_value, expected|
            issue = kit_new_issue(project, world.x => x_value, below => [])
            expect(described_class.parent_state(below, issue)).to be_nil
            expect(described_class.no_options?(below, issue)).to be(expected), x_value
          end
        end

        it 'reads a parent of another type or family: unavailable or unmapped allows nothing, a mapped value allows' do
          other_type = dcf_list_field(values: %w[A B C], type: ProjectCustomField)
          field = dcf_store_parent(child, other_type)
          issue = kit_new_issue(project, parent => 'A', field => [])
          expect(described_class.parent_state(field, issue)).to be_nil
          expect(described_class.no_options?(field, issue)).to be(true)

          enum = dcf_enum_field(names: %w[A])
          enum_key = kit_key(enum, 'A')
          field = dcf_store_parent(child, enum)
          # A fresh Project instance: a Project memoizes its custom fields.
          issue = kit_new_issue(Project.find(project.id), enum => 'A', field => [])
          expect(issue.custom_field_values.map(&:custom_field_id)).to include(enum.id)
          expect(described_class.parent_state(field, issue)).to be_nil
          expect(described_class.no_options?(field, issue)).to be(true)
          store = field.format_store.to_hash.merge('value_dependencies' => { enum_key => %w[a1] })
          CustomField.where(id: field.id).update_all(['format_store = ?', dump(store)])
          expect(described_class.no_options?(CustomField.find(field.id), issue)).to be(false)
        end
      end
    end
  end

  describe 'shared rules cases (test/js/fixtures/shared/rules_cases.json)' do
    cases = JSON.parse(File.read(File.expand_path('../../test/js/fixtures/shared/rules_cases.json', __dir__),
                                 encoding: 'UTF-8'))

    it 'follows the case table schema' do
      sections = {
        'allowed' => { required: %w[id map parent expected], optional: %w[note] },
        'defaults' => { required: %w[id map defaults parent expected_multiple expected_single], optional: %w[note] },
        'd1' => { required: %w[id parent_was parent child_was child map multiple valid],
                  optional: %w[note parent_available] }
      }
      mandatory = {
        'allowed' => %w[allowed-single-parent allowed-union-first-seen-order allowed-parent-order-reversed
                        allowed-unknown-parent-value allowed-no-parent-values allowed-blank-parent-value-ignored
                        allowed-duplicate-parent-values allowed-empty-map allowed-integer-child-ids
                        allowed-blank-and-null-children-dropped allowed-scalar-map-value
                        allowed-duplicate-children-deduped allowed-tricky-strings allowed-unicode-exact
                        allowed-unicode-no-normalization allowed-numeric-like-keys allowed-surrounding-spaces-kept],
        'defaults' => %w[defaults-single-value defaults-array-order-kept defaults-filtered-by-allowed
                         defaults-none-configured defaults-only-unlinked defaults-multi-parent-merge
                         defaults-linked-under-other-parent defaults-integer-ids defaults-no-parent-values
                         defaults-blank-and-null-dropped defaults-key-without-links defaults-tricky-strings
                         defaults-duplicates-deduped defaults-blank-parent-value-ignored],
        'd1' => %w[d1-multi-add-allowed d1-multi-add-disallowed d1-multi-remove-legacy d1-multi-reorder
                   d1-keep-legacy-parent-changed d1-single-legacy-to-allowed d1-single-legacy-to-other-disallowed
                   d1-parent-unavailable-untouched]
      }
      # Only these rows carry a blank key, so dropping blank parent values is observable.
      blank_key_rows = %w[allowed-blank-parent-value-ignored defaults-blank-parent-value-ignored]
      child_literal = lambda do |v|
        v.nil? || (v.is_a?(String) && (v.empty? || !v.strip.empty?)) || (v.is_a?(Integer) && v.between?(1, 2_147_483_647))
      end
      value_map = lambda do |m, blank_key|
        m.is_a?(Hash) && m.all? do |k, v|
          k.is_a?(String) && (blank_key ? k.empty? || !k.strip.empty? : !k.strip.empty?) &&
            (v.is_a?(Array) ? v.all?(&child_literal) : child_literal.call(v))
        end
      end
      expected_list = ->(list) { list.is_a?(Array) && list.all? { |v| v.is_a?(String) && !v.strip.empty? } }

      expect(cases.keys).to eq(%w[version description allowed defaults d1])
      expect(cases['version']).to eq(1)
      expect(cases['description']).to be_a(String)
      expect(cases['description']).to match(/\A[\x20-\x7e]+\z/)
      ids = []
      sections.each do |section, keys|
        rows = cases[section]
        expect(rows).not_to be_empty
        rows.each do |row|
          label = "#{section} row #{row['id'].inspect}"
          expect(keys[:required] - row.keys).to eq([]), label
          expect(row.keys - keys[:required] - keys[:optional]).to eq([]), label
          expect(row['id']).to match(/\A#{section}-[a-z0-9]+(?:-[a-z0-9]+)*\z/), label
          blank_key = blank_key_rows.include?(row['id'])
          expect(value_map.call(row['map'], blank_key)).to be(true), label
          expect(row['map'].key?('')).to eq(blank_key), label
          expect(row['parent'].is_a?(Array) && row['parent'].all? { |v| v.is_a?(String) && (v.empty? || !v.strip.empty?) })
            .to be(true), label
          ids << row['id']
        end
        expect(mandatory[section] - rows.map { |r| r['id'] }).to eq([]), section
      end
      expect(ids.uniq.size).to eq(ids.size)
      expect(blank_key_rows - ids).to eq([])
      cases['allowed'].each { |row| expect(expected_list.call(row['expected'])).to be(true), row['id'] }
      cases['defaults'].each do |row|
        blank_key = blank_key_rows.include?(row['id'])
        expect(value_map.call(row['defaults'], blank_key)).to be(true), row['id']
        expect(row['defaults'].key?('')).to eq(blank_key), row['id']
        expect(expected_list.call(row['expected_multiple'])).to be(true), row['id']
        expect(row['expected_single']).to eq(row['expected_multiple'].first), row['id']
        allowed = described_class.allowed_set(row['map'], row['parent'])
        expect(row['expected_multiple'].all? { |v| allowed.include?(v) }).to be(true), row['id']
      end
      strings = ->(list) { list.is_a?(Array) && list.all?(String) }
      cases['d1'].each do |row|
        label = row['id']
        expect(%w[parent_was child_was child].all? { |key| strings.call(row[key]) }).to be(true), label
        expect([row['multiple'], row['valid']].all? { |v| [true, false].include?(v) }).to be(true), label
        expect(row['child_was'].size <= 1 && row['child'].size <= 1).to be(true), label unless row['multiple']
        next unless row.key?('parent_available')

        expect(row['parent_available']).to be(false), label
        expect([row['parent'], row['parent_was']]).to eq([[], []]), label
      end
    end

    # A stub as in the client: an unsaved field holding the map, a value
    # without a record (so child_was is the stored baseline) and the parent
    # state of the row.
    cases['d1'].each do |row|
      it row['id'] do
        cf = unsaved('depending_list')
        cf.multiple = row['multiple']
        cf.value_dependencies = row['map']
        value = CustomFieldValue.new
        value.custom_field = cf
        value.instance_variable_set(:@value, row['multiple'] ? row['child'] : row['child'].first)
        value.value_was = row['multiple'] ? row['child_was'] : row['child_was'].first
        available = row.fetch('parent_available', true)
        state = described_class::ParentState.new(nil, available, row['parent'], row['parent_was'])

        expect(described_class.dependency_check(value, state).last)
          .to eq(row['valid'] ? [] : [I18n.t('activerecord.errors.messages.invalid')])
      end
    end

    cases['allowed'].each do |row|
      it row['id'] do
        expect(described_class.allowed_values(row['map'], row['parent'])).to eq(row['expected'])
        expect(described_class.allowed_set(row['map'], row['parent'])).to eq(Set.new(row['expected']))
        expect(described_class.allowed_values(sanitizer.sanitize_dependencies(row['map']), row['parent']))
          .to eq(row['expected'])
      end
    end

    cases['defaults'].each do |row|
      it row['id'] do
        map = row['map']
        defaults = row['defaults']
        parent = row['parent']

        expect(described_class.default_values(map, defaults, parent, multiple: true)).to eq(row['expected_multiple'])
        expect(described_class.default_values(map, defaults, parent, multiple: false)).to eq(row['expected_single'])
        sanitized = sanitizer.sanitize_default_dependencies(defaults)
        expect(described_class.default_values(sanitizer.sanitize_dependencies(map), sanitized, parent, multiple: true))
          .to eq(row['expected_multiple'])
      end
    end
  end

  describe '.allowed_set, .allowed_values and .default_values' do
    it 'allows nothing for a map that is not a Hash, without raising' do
      [nil, [], ['A'], 'A'].each do |map|
        expect(described_class.allowed_values(map, ['A'])).to eq([])
        expect(described_class.allowed_set(map, ['A'])).to be_a(Set).and be_empty
      end
      expect(described_class.default_values(nil, nil, ['A'], multiple: true)).to eq([])
      expect(described_class.default_values({ 'A' => ['a'] }, nil, ['A'], multiple: false)).to be_nil
    end

    it 'is pure' do
      map = { 'A' => %w[a1 a2], 'B' => %w[a2 b1] }
      expect(dcf_count_queries { described_class.allowed_values(map, %w[B A]) }).to eq(0)
      expect(described_class.allowed_values(map, %w[B A])).to eq(%w[a2 b1 a1])
    end
  end

  describe '.mapping, .defaults and .hide_when_disabled?' do
    it 'returns the sanitized, unpruned store' do
      cf = unsaved('depending_list')
      cf.value_dependencies = { '' => ['x'], 'A' => ['', 1, 'b'], 'orphan' => ['z'] }
      cf.default_value_dependencies = { 'A' => 1, 'B' => ['', 'c'], '' => 'x' }

      expect(described_class.mapping(cf)).to eq('A' => %w[1 b], 'orphan' => ['z'])
      expect(described_class.defaults(cf)).to eq('A' => '1', 'B' => ['c'])
      expect(described_class.mapping(unsaved('depending_list'))).to eq({})
      expect(described_class.defaults(unsaved('depending_list'))).to eq({})
    end

    it 'casts the stored flag like MappingBuilder' do
      parent = dcf_list_field
      child = dcf_list_field(format: 'depending_list', parent: parent)
      table = { true => true, '1' => true, 1 => true, 'true' => true, 'on' => true, 't' => true,
                nil => false, '' => false, '0' => false, false => false, 'false' => false, 'off' => false }
      table.each do |stored, expected|
        store = { 'parent_custom_field_id' => parent.id, 'hide_when_disabled' => stored }
        CustomField.where(id: child.id).update_all(['format_store = ?', dump(store)])
        builder = RedmineDependingCustomFields::MappingBuilder.build[child.id.to_s][:hide_when_disabled] ? true : false

        expect(described_class.hide_when_disabled?(CustomField.find(child.id))).to be(expected), stored.inspect
        expect(builder).to be(expected), stored.inspect
      end
    end
  end

  describe '.value_keys and .value_options' do
    def enum_with_ties
      field = dcf_enum_field(names: %w[First Second Third])
      first, second, third = field.enumerations.sort_by(&:id)
      CustomFieldEnumeration.where(id: first.id).update_all(position: 2)
      CustomFieldEnumeration.where(id: [second.id, third.id]).update_all(position: 1)
      CustomFieldEnumeration.where(id: second.id).update_all(active: false)
      [CustomField.find(field.id), first, second, third]
    end

    it 'deduplicates list values in possible_values order and reads unsaved values' do
      list = dcf_list_field(values: %w[B A B])
      expect(described_class.value_keys(list)).to eq(%w[B A])
      expect(described_class.value_options(list)).to eq([%w[B B], %w[A A]].map { |k, l| [k, l, true] })

      list.possible_values = "X\nY"
      expect(described_class.value_keys(list)).to eq(%w[X Y])
    end

    it 'orders enumerations by position then id, inactive included unless excluded' do
      field, first, second, third = enum_with_ties

      expect(described_class.value_keys(field)).to eq([second, third, first].map { |e| e.id.to_s })
      expect(described_class.value_keys(field, include_inactive: false)).to eq([third, first].map { |e| e.id.to_s })
      expect(described_class.value_options(field))
        .to eq([[second.id.to_s, 'Second', false], [third.id.to_s, 'Third', true], [first.id.to_s, 'First', true]])
    end

    it 'returns tuples of String, String and a strict boolean, matching value_keys' do
      field, = enum_with_ties
      options = described_class.value_options(field)

      expect(options.map { |o| o.map(&:class) }.flatten.uniq - [String, TrueClass, FalseClass]).to eq([])
      expect(options.map(&:last).map { |active| [true, false].include?(active) }.uniq).to eq([true])
      expect(options.map(&:first)).to eq(described_class.value_keys(field))
      expect(options.none?(Hash)).to be(true)
    end

    it 'gives a new enumeration field no keys without a query' do
      field = unsaved('depending_enumeration')
      result = nil
      expect(dcf_count_queries { result = [described_class.value_keys(field), described_class.value_options(field)] }).to eq(0)
      expect(result).to eq([[], []])
    end

    it 'costs the same for 3 and 30 enumerations and nothing when preloaded' do
      small = CustomField.find(dcf_enum_field(names: %w[a b c]).id)
      large_field = dcf_enum_field(names: Array.new(30) { |i| "v#{i}" })
      large = CustomField.find(large_field.id)
      preloaded = CustomField.includes(:enumerations).find(large_field.id)

      expect(dcf_count_queries { described_class.value_options(large) })
        .to eq(dcf_count_queries { described_class.value_options(small) })
      expect(dcf_count_queries { described_class.value_keys(preloaded) }).to eq(0)
    end
  end

  describe '.mapping_problems' do
    let(:parents) { %w[P1 P2] }
    let(:children) { %w[c1 c2 c3] }

    def problems(vd, dd)
      described_class.mapping_problems(vd, dd, parent_keys: parents, child_keys: children).map(&:to_h)
    end

    it 'is empty for a clean mapping and compares keys as Strings' do
      expect(problems({ 'P1' => %w[c1 c2] }, { 'P1' => 'c2' })).to eq([])
      expect(described_class.mapping_problems({ 1 => [2] }, { 1 => 2 }, parent_keys: ['1'], child_keys: ['2'])).to eq([])
    end

    it 'reports one Problem of each type' do
      expect(problems({ 'X' => ['c1'] }, {})).to eq([{ type: :unknown_parent_key, parent_key: 'X', child_key: nil }])
      expect(problems({ 'P1' => ['zz'] }, {})).to eq([{ type: :unknown_child_value, parent_key: 'P1', child_key: 'zz' }])
      expect(problems({ 'P1' => ['c1'] }, { 'P1' => 'zz' })).to eq([{ type: :unknown_default, parent_key: 'P1', child_key: 'zz' }])
      expect(problems({ 'P1' => ['c1'] }, { 'P1' => 'c2' })).to eq([{ type: :default_not_linked, parent_key: 'P1', child_key: 'c2' }])
      expect(problems({}, { 'X' => 'c1' })).to include(type: :unknown_parent_key, parent_key: 'X', child_key: nil)
    end

    it 'reports a key unknown in both mappings once, in vd then dd order' do
      result = problems({ 'X' => ['c1'], 'P1' => ['zz'] }, { 'X' => 'c1', 'P2' => ['c3'] })

      expect(result.map { |p| p[:type] }).to eq([:unknown_parent_key, :unknown_child_value, :default_not_linked])
      expect(result.last).to eq(type: :default_not_linked, parent_key: 'P2', child_key: 'c3')
      expect(result.count { |p| p[:type] == :unknown_parent_key }).to eq(1)
    end

    it 'is empty exactly when DependencyMappingService#validate_mapping! passes' do
      service = RedmineDependingCustomFields::DependencyMappingService.new(project: nil, field: nil, user: nil)
      table = [
        [{ 'P1' => %w[c1 c2] }, { 'P1' => 'c1' }],
        [{ 'X' => ['c1'] }, {}],
        [{}, { 'X' => 'c1' }],
        [{ 'X' => ['c1'] }, { 'X' => 'c1' }],
        [{ 'P1' => ['zz'] }, {}],
        [{ 'P1' => ['c1'] }, { 'P1' => 'zz' }],
        [{ 'P1' => ['c1'] }, { 'P1' => %w[c1 c2] }],
        [{ 'P1' => ['c1'], 'P2' => ['c2'] }, { 'P1' => 'c2' }],
        [{ 'P2' => %w[c3] }, { 'P2' => ['c3'] }]
      ]
      table.each do |vd, dd|
        vd = sanitizer.sanitize_dependencies(vd)
        dd = sanitizer.sanitize_default_dependencies(dd)
        passes = begin
          service.send(:validate_mapping!, vd, dd, parents, children)
          true
        rescue RedmineDependingCustomFields::OperationError
          false
        end
        expect(problems(vd, dd).empty?).to eq(passes), [vd, dd].inspect
      end
    end
  end

  describe '.prune_mapping' do
    def prune(vd, dd, parent_keys: %w[P1 P2], child_keys: %w[c1 c2 c3], multiple: true)
      described_class.prune_mapping(vd, dd, parent_keys: parent_keys, child_keys: child_keys, multiple: multiple)
    end

    it 'drops unknown parent keys unless parent_keys is nil' do
      expect(prune({ 'X' => ['c1'], 'P1' => ['c1'] }, {})).to eq([{ 'P1' => ['c1'] }, {}])
      expect(prune({ 'X' => ['c1'], 'P1' => ['c1'] }, {}, parent_keys: nil)).to eq([{ 'X' => ['c1'], 'P1' => ['c1'] }, {}])
    end

    it 'drops unknown child values and keys left empty, ordering by parent then child order' do
      vd, = prune({ 'P2' => %w[c3 zz c1 c3], 'P1' => %w[c2], 'X' => ['c1'] }, {}, parent_keys: %w[P1 P2])
      expect(vd).to eq('P1' => ['c2'], 'P2' => %w[c1 c3])
      expect(vd.keys).to eq(%w[P1 P2])
      expect(prune({ 'P1' => ['zz'] }, {})).to eq([{}, {}])
    end

    it 'keeps inactive enumeration ids that are in child_keys' do
      field = dcf_enum_field(names: %w[On Off])
      on, off = field.enumerations.sort_by(&:id)
      off.update!(active: false)
      child_keys = described_class.value_keys(CustomField.find(field.id))

      vd, dd = prune({ 'P1' => [off.id, on.id] }, { 'P1' => off.id.to_s }, child_keys: child_keys, multiple: false)
      expect(vd).to eq('P1' => [on.id.to_s, off.id.to_s])
      expect(dd).to eq('P1' => off.id.to_s)
    end

    it 'keeps only linked defaults, in child order, shaped by multiple' do
      vd = { 'P1' => %w[c1 c2], 'P2' => ['c3'] }
      dd = { 'P1' => %w[c2 zz c1], 'P2' => 'c1', 'X' => 'c1' }

      expect(prune(vd, dd, multiple: true)[1]).to eq('P1' => %w[c1 c2])
      expect(prune(vd, dd, multiple: false)[1]).to eq('P1' => 'c1')
    end

    it 'never mutates its inputs and returns Sanitizer fixed points' do
      vd = { 'P1' => %w[c2 c1].freeze, 'P2' => ['', 'c3'].freeze }.freeze
      dd = { 'P1' => %w[c1].freeze }.freeze
      out_vd, out_dd = prune(vd, dd)

      expect(sanitizer.sanitize_dependencies(out_vd)).to eq(out_vd)
      expect(sanitizer.sanitize_default_dependencies(out_dd)).to eq(out_dd)
      expect(vd['P1']).to eq(%w[c2 c1])
    end
  end

  describe '.children_of and FieldRelevance.children_of' do
    def oracle(field)
      CustomField.where(field_format: %w[depending_list depending_enumeration]).to_a
                 .select { |c| c.parent_custom_field_id.to_i == field.id }.map(&:id).sort
    end

    it 'returns the same set as the stored pointer comparison' do
      parent = dcf_list_field
      child = dcf_list_field(format: 'depending_list', parent: parent)
      project_child = dcf_list_field(format: 'depending_list', type: ProjectCustomField)
      point(project_child, parent.id)
      enum_child = dcf_enum_field(format: 'depending_enumeration')
      point(enum_child, parent.id)
      self_parent = dcf_list_field(format: 'depending_list')
      point(self_parent, self_parent.id)
      string_child = dcf_list_field(format: 'depending_list')
      point(string_child, parent.id.to_s)
      stray_list = dcf_list_field
      point(stray_list, parent.id)

      CustomField.all.each do |field|
        expect(described_class.children_of(field).map(&:id).sort).to eq(oracle(field)), field.name
        expect(RedmineDependingCustomFields::FieldRelevance.children_of(field).map(&:id).sort).to eq(oracle(field))
      end
      expect(described_class.children_of(parent).map(&:id))
        .to match_array([child, project_child, enum_child, string_child].map(&:id))
      expect(described_class.children_of(self_parent).map(&:id)).to eq([self_parent.id])
    end

    it 'orders by position, then id' do
      parent = dcf_list_field
      first, second, third = Array.new(3) { dcf_list_field(format: 'depending_list', parent: parent) }
      CustomField.where(id: first.id).update_all(position: 9)
      CustomField.where(id: [second.id, third.id]).update_all(position: 3)

      expect(described_class.children_of(parent).map(&:id)).to eq([second.id, third.id, first.id])
      expect(order_clauses { described_class.children_of(parent) })
        .to contain_exactly(match(/ORDER BY\s+\S*position\S*\s+ASC,\s*\S*\bid\S*\s+ASC/i))
    end

    it 'loads only the children when given an index, and skips the load when there are none' do
      parent = dcf_list_field
      childless = dcf_list_field
      dcf_list_field(format: 'depending_list', parent: parent)
      load_cost = dcf_count_queries { RedmineDependingCustomFields::FieldIndex.load }
      index = RedmineDependingCustomFields::FieldIndex.load

      without = dcf_count_queries { described_class.children_of(parent) }
      with = dcf_count_queries { described_class.children_of(parent, index: index) }
      expect(without).to eq(with + load_cost)
      expect(dcf_count_queries { described_class.children_of(childless) }).to eq(load_cost)
      expect(dcf_count_queries { described_class.children_of(childless, index: index) }).to eq(0)
      expect(dcf_count_yaml_loads { described_class.children_of(parent) }).to eq(0)
    end

    it 'gives a new record no children without a query' do
      expect(dcf_count_queries { expect(described_class.children_of(IssueCustomField.new)).to eq([]) }).to eq(0)
    end

    it 'returns full writable records' do
      parent = dcf_list_field(values: %w[A B])
      child = dcf_list_field(format: 'depending_list', parent: parent, values: %w[x])
      dcf_set_dependencies(child, value_dependencies: { 'A' => ['x'] })
      loaded = described_class.children_of(parent).first

      expect(loaded).to be_a(IssueCustomField)
      expect(loaded.readonly?).to be(false)
      expect(loaded.value_dependencies).to eq('A' => ['x'])
      loaded.value_dependencies = { 'B' => ['x'] }
      expect { loaded.save! }.not_to raise_error
    end

    it 'is what FieldRelevance.children_of delegates to' do
      parent = dcf_list_field
      allow(described_class).to receive(:children_of).and_call_original
      RedmineDependingCustomFields::FieldRelevance.children_of(parent)

      expect(described_class).to have_received(:children_of).with(parent)
    end
  end

  describe 'topology helpers' do
    def chain
      root = dcf_list_field
      field_a = dcf_list_field(format: 'depending_list', parent: root)
      field_b = dcf_list_field(format: 'depending_list', parent: field_a)
      field_c = dcf_list_field(format: 'depending_list', parent: field_b)
      [root, field_a, field_b, field_c]
    end

    def stored_cycle
      field_x = dcf_list_field(format: 'depending_list')
      field_y = dcf_list_field(format: 'depending_list')
      point(field_x, field_y.id)
      point(field_y, field_x.id)
      [CustomField.find(field_x.id), CustomField.find(field_y.id)]
    end

    it 'lists descendants and terminates on stored cycles' do
      _root, field_a, field_b, field_c = chain
      field_x, field_y = stored_cycle

      expect(described_class.descendant_ids(field_a)).to eq([field_b.id, field_c.id])
      expect(described_class.descendant_ids(field_x)).to eq([field_y.id])
      expect(dcf_count_queries { expect(described_class.descendant_ids(IssueCustomField.new)).to eq([]) }).to eq(0)
    end

    it 'costs the same for 1 and for 25 depending fields' do
      root = dcf_list_field
      field = dcf_list_field(format: 'depending_list', parent: root)
      one = dcf_count_queries { described_class.descendant_ids(field) && described_class.in_cycle?(field) }
      24.times { dcf_list_field(format: 'depending_list', parent: field) }
      many = dcf_count_queries { described_class.descendant_ids(field) && described_class.in_cycle?(field) }

      expect(many).to eq(one)
    end

    it 'names cycle members along the cycle and only flags members' do
      field_x, field_y = stored_cycle
      below = dcf_list_field(format: 'depending_list')
      point(below, field_x.id)
      self_parent = dcf_list_field(format: 'depending_list')
      point(self_parent, self_parent.id)
      _root, field_a, = chain

      expect(described_class.in_cycle?(field_x)).to be(true)
      expect(described_class.cycle_member_ids(field_x)).to eq([field_x.id, field_y.id])
      expect(described_class.cycle_member_ids(field_y)).to eq([field_y.id, field_x.id])
      expect(described_class.in_cycle?(below)).to be(false)
      expect(described_class.cycle_member_ids(below)).to eq([])
      expect(described_class.in_cycle?(field_a)).to be(false)
      expect(described_class.cycle_member_ids(self_parent)).to eq([self_parent.id])
      expect(dcf_count_queries { expect(described_class.in_cycle?(IssueCustomField.new)).to be(false) }).to eq(0)
    end

    it 'uses a given index without a query' do
      field_x, = stored_cycle
      index = RedmineDependingCustomFields::FieldIndex.load
      queries = dcf_count_queries do
        described_class.in_cycle?(field_x, index: index)
        described_class.descendant_ids(field_x, index: index)
      end

      expect(queries).to eq(0)
    end

    it 'never fetches the plain root of a chain, and skips non-depending fields' do
      root, field_a, field_b, = chain
      index = RedmineDependingCustomFields::FieldIndex.load
      load_cost = dcf_count_queries { RedmineDependingCustomFields::FieldIndex.load }

      expect(dcf_count_queries { expect(described_class.in_cycle?(field_b, index: index)).to be(false) }).to eq(0)
      expect(dcf_count_queries { expect(described_class.cycle_member_ids(field_a, index: index)).to eq([]) }).to eq(0)
      expect(dcf_count_queries { described_class.in_cycle?(field_b) }).to eq(load_cost)
      expect(dcf_count_queries { expect(described_class.cycle_member_ids(root)).to eq([]) }).to eq(0)
    end

    describe '.parent_candidates' do
      it 'offers fields of the same type and family by position and id, minus self and descendants' do
        root, field_a, field_b, field_c = chain
        other_root = dcf_list_field
        CustomField.where(id: other_root.id).update_all(position: 0)
        dcf_list_field(type: ProjectCustomField)
        dcf_enum_field
        dcf_list_field(format: 'string', values: nil)

        expect(described_class.parent_candidates(CustomField.find(field_b.id)).map(&:id))
          .to eq([other_root.id, root.id, field_a.id])
        expect(described_class.parent_candidates(CustomField.find(field_c.id)).map(&:id))
          .to eq([other_root.id, root.id, field_a.id, field_b.id])
        field = CustomField.find(field_c.id)
        expect(order_clauses { described_class.parent_candidates(field) })
          .to include(match(/ORDER BY\s+\S*position\S*\s+ASC,\s*\S*\bid\S*\s+ASC/i))
      end

      it 'keeps the current parent of a stored cycle member, never the field itself' do
        field_x, field_y = stored_cycle
        self_parent = dcf_list_field(format: 'depending_list')
        point(self_parent, self_parent.id)

        expect(described_class.parent_candidates(field_x).map(&:id)).to include(field_y.id)
        expect(described_class.parent_candidates(field_x).map(&:id)).not_to include(field_x.id)
        expect(described_class.parent_candidates(CustomField.find(self_parent.id)).map(&:id)).not_to include(self_parent.id)
      end

      it 'gives a new record every candidate and never offers a dangling or foreign parent' do
        root, field_a, field_b, field_c = chain
        enum_root = dcf_enum_field
        new_list = unsaved('depending_list', parent: 999_999_999)
        new_enum = unsaved('depending_enumeration')

        expect(described_class.parent_candidates(new_list).map(&:id)).to eq([root, field_a, field_b, field_c].map(&:id))
        expect(described_class.parent_candidates(new_enum).map(&:id)).to eq([enum_root.id])
        expect(described_class.parent_candidates(dcf_list_field)).to eq([])
      end
    end
  end

  describe 'CustomFieldPatch#dcf_memo' do
    it 'is a public instance method of CustomField' do
      expect(CustomField.public_method_defined?(:dcf_memo)).to be(true)
    end

    it 'runs the block once per name and key, nil and false included' do
      field = CustomField.new
      runs = Hash.new(0)
      3.times do
        field.dcf_memo(:a, 1) { runs[:one] += 1 }
        field.dcf_memo(:a, 'k') do
          runs[:nil_result] += 1
          nil
        end
        field.dcf_memo(:a, [1, 2]) do
          runs[:false_result] += 1
          false
        end
      end
      field.dcf_memo(:b, 1) { runs[:other_name] += 1 }
      field.dcf_memo(:a, 2) { runs[:other_key] += 1 }

      expect(runs).to eq(one: 1, nil_result: 1, false_result: 1, other_name: 1, other_key: 1)
      expect(field.dcf_memo(:a, 'k') { :never }).to be_nil
      expect(field.dcf_memo(:a, [1, 2]) { :never }).to be(false)
    end

    it 'is scoped to the record instance' do
      stored = dcf_list_field
      first = CustomField.find(stored.id)
      second = CustomField.find(stored.id)
      first.dcf_memo(:x, 1) { :first }

      expect(second.dcf_memo(:x, 1) { :second }).to eq(:second)
    end

    it 'stores nothing when the block raises' do
      field = CustomField.new
      runs = 0
      failing = lambda do
        runs += 1
        raise ArgumentError
      end
      expect { field.dcf_memo(:x, 1, &failing) }.to raise_error(ArgumentError)
      field.dcf_memo(:x, 1) { runs += 1 }

      expect(runs).to eq(2)
    end

    it 'adds dcf_memo only: no new callback and no other public method' do
      patch = RedmineDependingCustomFields::Patches::CustomFieldPatch
      own = patch.instance_methods(false) + patch.private_instance_methods(false)
      filters = CustomField.__callbacks.values.flat_map(&:to_a).map(&:filter)

      expect(filters.select { |f| f.is_a?(Symbol) && own.include?(f) }).to eq([:dispatch_after_custom_field_save])
      expect(patch.public_instance_methods(false)).to match_array([:validate_custom_value, :dcf_memo])
    end
  end
end
