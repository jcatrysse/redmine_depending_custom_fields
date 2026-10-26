# frozen_string_literal: true

require_relative '../rails_helper'

# WP-06: DependingFormatMethods, the methods both depending formats share
# (server design section 5), on real fields and issues. Results are those of
# 0.0.16 (spec/characterization/depending_formats_spec.rb pins the main
# rows); this file adds the cases the characterization does not cover. Later
# work packages append to the describe of the method they change.
RSpec.describe RedmineDependingCustomFields::DependingFormatMethods do
  include DcfFormatCharacterization
  include DcfStoredCycle

  fixtures :users

  let(:project) { dcf_create_project }
  let(:invalid) { I18n.t('activerecord.errors.messages.invalid') }
  let(:inclusion) { I18n.t('activerecord.errors.messages.inclusion') }
  let(:hidden) { DcfFormatCharacterization::HIDDEN }

  def rules
    RedmineDependingCustomFields::DependencyRules
  end

  def store_type
    CustomField.type_for_attribute('format_store')
  end

  # The format_store column as the database holds it.
  def raw_store(field)
    CustomField.connection.select_value(CustomField.where(id: field.id).select(:format_store).to_sql)
  end

  # Writes +changes+ into the stored format_store without callbacks, for
  # pointers before_save would not keep (another type or family) and mappings
  # the sanitizer would change. Returns a fresh instance.
  def write_store(field, changes)
    store = CustomField.find(field.id).format_store.to_hash.merge(changes)
    CustomField.where(id: field.id).update_all(['format_store = ?', store_type.serialize(store)])
    CustomField.find(field.id)
  end

  def preview_bytes(field)
    store_type.serialize(field.format.storage_preview(field, field.format_store))
  end

  def other_type_field(kind)
    kind == :list ? dcf_list_field(type: ProjectCustomField) : dcf_enum_field(type: ProjectCustomField)
  end

  def other_family_field(kind, **options)
    kind == :list ? dcf_enum_field(**options) : dcf_list_field(**options)
  end

  def same_family_field(kind, names)
    kind == :list ? dcf_list_field(values: names) : dcf_enum_field(names: names)
  end

  # The DependencyRules functions that prune or check a mapping (BC-02: never
  # used when a field is saved).
  def pruning_helpers
    [:prune_mapping, :mapping_problems, :value_keys, :value_options]
  end

  def value_of(issue, field)
    issue.custom_field_values.detect { |v| v.custom_field_id == field.id }
  end

  describe 'structure' do
    # WP-16: the module adds edit_tag and bulk_edit_tag (the data contract);
    # super still reaches core List for both formats. WP-18 (UD-14):
    # after_custom_field_save is deleted with the cache.
    shared = [:before_custom_field_save, :bulk_edit_tag, :edit_tag, :normalized_store_pairs,
              :possible_values_options, :storage_preview, :validate_custom_field, :validate_custom_value,
              :value_from_keyword]
    formats = {
      RedmineDependingCustomFields::DependingListFormat => {
        core: Redmine::FieldFormat::ListFormat,
        super_owners: { possible_values_options: Redmine::FieldFormat::ListFormat,
                        validate_custom_value: Redmine::FieldFormat::ListFormat,
                        validate_custom_field: Redmine::FieldFormat::ListFormat,
                        before_custom_field_save: Redmine::FieldFormat::Base,
                        edit_tag: Redmine::FieldFormat::List,
                        bulk_edit_tag: Redmine::FieldFormat::List },
        options_owner: Redmine::FieldFormat::ListFormat,
        body: [:label, :query_filter_values],
        label: :label_depending_list
      },
      # WP-08: the class body defines the edit form options (F2 fix), above
      # core RecordList.
      RedmineDependingCustomFields::DependingEnumerationFormat => {
        core: Redmine::FieldFormat::EnumerationFormat,
        super_owners: { possible_values_options: Redmine::FieldFormat::EnumerationFormat,
                        validate_custom_value: Redmine::FieldFormat::RecordList,
                        validate_custom_field: Redmine::FieldFormat::Base,
                        before_custom_field_save: Redmine::FieldFormat::Base,
                        possible_custom_value_options: Redmine::FieldFormat::RecordList,
                        edit_tag: Redmine::FieldFormat::List,
                        bulk_edit_tag: Redmine::FieldFormat::List },
        options_owner: RedmineDependingCustomFields::DependingEnumerationFormat,
        body: [:label, :possible_custom_value_options, :query_filter_values],
        label: :label_depending_enumeration
      }
    }

    formats.each do |klass, spec|
      context klass.name.demodulize do
        it 'includes the module once, between the class and its core format' do
          expect(described_class).to be_a(Module)
          expect(described_class).not_to be_a(Class)
          expect(klass.ancestors.first(3)).to eq([klass, described_class, spec[:core]])
          expect(klass.ancestors.count(described_class)).to eq(1)
        end

        it 'takes the shared methods from the module, public, with super reaching core' do
          shared.each do |name|
            expect(klass.instance_method(name).owner).to eq(described_class), name.to_s
            expect(klass.public_method_defined?(name)).to be(true), name.to_s
          end
          spec[:super_owners].each do |name, owner|
            expect(klass.instance.method(name).super_method.owner).to eq(owner), name.to_s
          end
        end

        it 'keeps only its own methods in the class body, all public' do
          expect(klass.instance_methods(false).sort).to eq(spec[:body])
          expect(klass.private_instance_methods(false)).to eq([])
          expect(klass.instance.public_methods).to include(*spec[:body])
          expect(klass.instance.label).to eq(spec[:label])
          expect(klass.instance.method(:query_filter_values).parameters).to eq([[:req, :custom_field], [:opt, :query]])
        end

        # WP-16: the edit tags moved from core List to the module (they add the
        # data-dcf-* attributes and call super); was owner List for both.
        it 'takes the edit tags from the module, leaves customized_class_names and the list edit form options to core' do
          expect(klass.instance_method(:edit_tag).owner).to eq(described_class)
          expect(klass.instance_method(:bulk_edit_tag).owner).to eq(described_class)
          expect(klass.instance.method(:edit_tag).super_method.owner).to eq(Redmine::FieldFormat::List)
          expect(klass.instance.method(:bulk_edit_tag).super_method.owner).to eq(Redmine::FieldFormat::List)
          expect(klass.instance_method(:possible_custom_value_options).owner).to eq(spec[:options_owner])
          expect(klass.method(:customized_class_names).owner).not_to eq(klass.singleton_class)
        end

        it 'stays registered under its format name' do
          expect(Redmine::FieldFormat.find(klass.format_name)).to equal(klass.instance)
        end
      end
    end

    # WP-16: ten shared methods (edit_tag and bulk_edit_tag added; was eight).
    # Flipped by WP-18: nine (after_custom_field_save deleted; was ten).
    it 'has exactly the nine shared public methods and only dcf_ private helpers' do
      expect(described_class.public_instance_methods(false).sort).to eq(shared)
      expect(described_class.private_instance_methods(false).map(&:to_s)).to all(start_with('dcf_'))
    end

    it 'declares the four store attributes once per including class (self.included)' do
      attributes = %w[parent_custom_field_id value_dependencies default_value_dependencies hide_when_disabled]
      expect(CustomField.stored_attributes[:format_store].map(&:to_s)).to include(*attributes)
      field = IssueCustomField.new
      attributes.each do |name|
        expect(field).to respond_to(name, "#{name}=")
      end
      lib = File.expand_path('../../lib/redmine_depending_custom_fields', __dir__)
      %w[depending_list_format.rb depending_enumeration_format.rb].each do |file|
        expect(File.read(File.join(lib, file))).not_to include('field_attributes'), file
      end
    end

    it 'offers storage_preview on the depending formats only, with two arguments' do
      %w[list enumeration extended_user].each do |name|
        expect(Redmine::FieldFormat.find(name)).not_to respond_to(:storage_preview), name
      end
      %w[depending_list depending_enumeration].each do |name|
        fmt = Redmine::FieldFormat.find(name)
        expect(fmt.method(:storage_preview).arity).to eq(2), name
        expect { fmt.storage_preview(IssueCustomField.new(field_format: name)) }.to raise_error(ArgumentError)
      end
    end

    # WP-09: the dependency rule itself is DependencyRules.dependency_check.
    it 'resolves parents only through DependencyRules, with today\'s rules' do
      source = File.read(File.expand_path('../../lib/redmine_depending_custom_fields/depending_format_methods.rb', __dir__))
      expect(source).not_to match(/CustomField\.(find_by|where)/)
      expect(source).not_to match(/no_options\?|effective_parent_id|parent_of|carries\?|prune_mapping|editable/)
      expect(source).to include('DependencyRules.dependency_check(custom_value, state)')
      expect(source).not_to match(/FIELD_FORMAT/)
    end

    it 'loads under the eager loader with the constant its file name gives' do
      lib = File.expand_path('../../lib', __dir__)
      expect { Rails.autoloaders.main.eager_load_dir(lib) }.not_to raise_error
      path = File.join(lib, 'redmine_depending_custom_fields/depending_format_methods.rb')
      expect(Rails.autoloaders.main.cpath_expected_at(path)).to eq('RedmineDependingCustomFields::DependingFormatMethods')
    end
  end

  describe '#normalized_store_pairs' do
    [:list, :enumeration].each do |kind|
      context "for a depending #{kind}" do
        let(:kit) { build_kit(kind) }
        let(:parent) { kit.first }
        let(:child) { kit.last }

        def pointer_pair(field, raw)
          field.parent_custom_field_id = raw
          field.format.normalized_store_pairs(field).assoc('parent_custom_field_id')
        end

        it 'turns the parent id into what before_save stores' do
          table = {
            parent.id.to_s => parent.id,
            parent.id => parent.id,
            0 => nil,
            'abc' => nil,
            CustomField.maximum(:id).to_i + 1_000 => nil,
            other_type_field(kind).id => nil,
            other_family_field(kind).id => nil,
            child.id => child.id
          }
          table.each do |raw, expected|
            expect(pointer_pair(CustomField.find(child.id), raw)).to eq(['parent_custom_field_id', expected]), raw.inspect
          end
          expect(pointer_pair(CustomField.find(child.id), parent.id.to_s).last).to be_a(Integer)
          [nil, '', '  '].each do |raw|
            expect(pointer_pair(CustomField.find(child.id), raw)).to be_nil, raw.inspect
          end
        end

        it 'returns the pairs in before_save order, sanitized, without changing the record' do
          field = CustomField.find(child.id)
          a1 = kit_key(child, 'a1')
          field.parent_custom_field_id = parent.id.to_s
          field.value_dependencies = { kit_key(parent, 'A') => [a1, '', nil], '' => [a1], 7 => a1 }
          field.default_value_dependencies = { kit_key(parent, 'A') => [a1, ''], 'B' => '' }

          expect(field.format.normalized_store_pairs(field))
            .to eq([['parent_custom_field_id', parent.id],
                    ['value_dependencies', { kit_key(parent, 'A') => [a1], '7' => [a1] }],
                    ['default_value_dependencies', { kit_key(parent, 'A') => [a1] }]])
          expect(field.parent_custom_field_id).to eq(parent.id.to_s)

          loaded = CustomField.find(child.id)
          loaded.format.normalized_store_pairs(loaded)
          expect(loaded.changes_to_save).to eq({})
        end

        it 'keeps orphan keys, unknown children, inactive enumerations and bracket keys (no pruning)' do
          b1 = kit_key(child, 'b1')
          child.enumerations.detect { |e| e.name == 'b1' }.update!(active: false) if kind == :enumeration
          mapping = { kit_key(parent, 'A') => [kit_key(child, 'a1'), 'nope'], 'ZZ' => ['nope'], '[x]' => [b1], 'a]' => [b1] }
          defaults = { 'ZZ' => 'nope', kit_key(parent, 'B') => kit_key(child, 'a1') }
          field = CustomField.find(child.id)
          field.value_dependencies = mapping
          field.default_value_dependencies = defaults
          pruning_helpers.each { |name| allow(rules).to receive(name) }

          pairs = field.format.normalized_store_pairs(field).to_h
          expect(pairs['value_dependencies']).to eq(mapping)
          expect(pairs['default_value_dependencies']).to eq(defaults)
          pruning_helpers.each { |name| expect(rules).not_to have_received(name) }
        end
      end
    end
  end

  describe '#storage_preview' do
    [:list, :enumeration].each do |kind|
      context "for a depending #{kind}" do
        let(:kit) { build_kit(kind) }
        let(:parent) { kit.first }
        let(:child) { kit.last }

        def expect_preview_bytes_stored(field)
          bytes = preview_bytes(field)
          order = field.format.storage_preview(field, field.format_store).keys
          field.save!
          expect(bytes).to eq(raw_store(field))
          expect(order).to eq(CustomField.find(field.id).format_store.keys)
        end

        it 'equals the stored bytes for a parent id given as a String' do
          field = CustomField.find(child.id)
          field.parent_custom_field_id = parent.id.to_s
          expect_preview_bytes_stored(field)
          expect(CustomField.find(child.id).parent_custom_field_id).to eq(parent.id)
        end

        it 'equals the stored bytes for parent ids that resolve to nothing' do
          # Every field of the example exists before the missing id is taken,
          # so none of them can be created with that id.
          child
          others = [other_type_field(kind).id, other_family_field(kind).id]
          missing = CustomField.maximum(:id).to_i + 1_000
          [0, 'abc', missing, *others].each do |raw|
            field = CustomField.find(child.id)
            field.parent_custom_field_id = raw
            expect_preview_bytes_stored(field)
            expect(CustomField.find(child.id).parent_custom_field_id).to be_nil
          end
        end

        it 'equals the stored bytes for a blank parent id, kept as an empty String' do
          field = CustomField.find(child.id)
          field.parent_custom_field_id = ''
          expect_preview_bytes_stored(field)
          expect(CustomField.find(child.id).parent_custom_field_id).to eq('')
        end

        it 'equals the stored bytes with blank keys, blank values and empty rows' do
          a1 = kit_key(child, 'a1')
          field = CustomField.find(child.id)
          field.value_dependencies = { '' => [a1], nil => ['x'], :sym => a1, 7 => a1, 'A' => [a1, '', nil], 'X' => ['', nil] }
          field.default_value_dependencies = { '' => a1, 'B' => '', 'C' => [a1, ''] }
          expect_preview_bytes_stored(field)
        end

        it 'equals the stored bytes for an unchanged record' do
          field = CustomField.find(child.id)
          field.name = "#{field.name} renamed"
          before = raw_store(field)
          expect_preview_bytes_stored(field)
          expect(raw_store(field)).to eq(before)
        end

        it 'equals the stored bytes without pruning orphan, inactive and bracket keys' do
          b1 = kit_key(child, 'b1')
          child.enumerations.detect { |e| e.name == 'b1' }.update!(active: false) if kind == :enumeration
          field = CustomField.find(child.id)
          field.value_dependencies = { 'ZZ' => ['nope'], kit_key(parent, 'B') => [b1], '[x]' => [b1], 'a]' => [b1] }
          field.default_value_dependencies = { 'ZZ' => 'nope' }
          expect_preview_bytes_stored(field)
          expect(CustomField.find(child.id).value_dependencies.keys).to eq(['ZZ', kit_key(parent, 'B'), '[x]', 'a]'])
        end

        it 'equals the stored bytes of a new record, keys appended in save order' do
          format = kind == :list ? 'depending_list' : 'depending_enumeration'
          field = IssueCustomField.new(name: "New-#{SecureRandom.hex(3)}", field_format: format, is_for_all: true)
          field.possible_values = %w[a1 a2] if kind == :list
          field.hide_when_disabled = '1'
          field.value_dependencies = { kit_key(parent, 'A') => ['a1'] }
          field.url_pattern = 'http://example.test/%value%'
          field.parent_custom_field_id = parent.id.to_s
          expect_preview_bytes_stored(field)
          expect(CustomField.find(field.id).format_store.keys)
            .to eq(%w[hide_when_disabled value_dependencies url_pattern parent_custom_field_id default_value_dependencies])
        end

        it 'changes neither the store nor the record' do
          field = CustomField.find(child.id)
          snapshot = field.format_store.deep_dup
          preview = field.format.storage_preview(field, field.format_store)

          expect(field.format_store).to eq(snapshot)
          expect(field.changed?).to be(false)
          expect(preview).to be_an_instance_of(Hash)
          expect(preview).not_to equal(field.format_store)
          expect(preview.keys).to all(be_a(String))

          field.parent_custom_field_id = parent.id.to_s
          field.default_value = kit_key(child, 'a1')
          field.format.storage_preview(field, field.format_store)
          expect(field.parent_custom_field_id).to eq(parent.id.to_s)
          expect(field.default_value).to eq(kit_key(child, 'a1'))
        end

        it 'works on the store it is given, plain Hash or nil, without changing it' do
          field = CustomField.find(child.id)
          store = { 'extra' => 1, 'value_dependencies' => { 'old' => ['x'] } }
          preview = field.format.storage_preview(field, store)

          expect(store).to eq('extra' => 1, 'value_dependencies' => { 'old' => ['x'] })
          expect(preview.keys).to eq(%w[extra value_dependencies parent_custom_field_id default_value_dependencies])
          expect(preview['value_dependencies']).to eq(rules.mapping(field))
          expect(field.format.storage_preview(field, nil)).to eq(field.format.normalized_store_pairs(field).to_h)
        end

        it 'looks the parent up once across preview, validation and save' do
          field = CustomField.find(child.id)
          field.parent_custom_field_id = parent.id.to_s
          allow(CustomField).to receive(:find_by).and_call_original

          field.format.storage_preview(field, field.format_store)
          field.valid?
          field.save!

          expect(CustomField).to have_received(:find_by).with(hash_including(id: parent.id, type: field.type)).once
          expect(dcf_count_queries { field.format.storage_preview(field, field.format_store) }).to eq(0)
          field.parent_custom_field_id = parent.id
          expect(dcf_count_queries { field.format.storage_preview(field, field.format_store) }).to eq(0)
        end

        it 'looks again once for a pointer changed after the preview and stores the new parent' do
          other = same_family_field(kind, %w[X])
          field = CustomField.find(child.id)
          field.parent_custom_field_id = parent.id.to_s
          allow(CustomField).to receive(:find_by).and_call_original

          field.format.storage_preview(field, field.format_store)
          field.parent_custom_field_id = other.id.to_s
          expect_preview_bytes_stored(field)

          expect(CustomField).to have_received(:find_by).with(hash_including(type: field.type)).twice
          expect(CustomField.find(child.id).parent_custom_field_id).to eq(other.id)
        end
      end
    end

    it 'equals the stored bytes for the S1 list mapping (27 x 5,570)', :large do
      parent_values = DcfLargeList.names(27, prefix: 'P')
      child_values = DcfLargeList.names(5570, tricky_every: 97)
      # UD-38 (WP-13): a TEXT column (MySQL/MariaDB) cannot hold S1, so skip before the first write there.
      needed = DcfLargeList.yaml_list_bytes(child_values)
      storage = RedmineDependingCustomFields::StorageLimits
      limit = %w[possible_values format_store].filter_map { |c| storage.column_limit(c) }.min
      if limit && limit < needed
        skip "UD-38: S1 needs #{needed} bytes of possible_values (more in format_store), the column limit is " \
             "#{limit} bytes; run widen_core_columns to cover it"
      end
      parent = dcf_list_field(values: parent_values)
      child = CustomField.find(dcf_list_field(format: 'depending_list', values: child_values, parent: parent).id)
      mapping = DcfLargeList.partition(parent_values, child_values)
      child.value_dependencies = mapping
      child.default_value_dependencies = DcfLargeList.first_child_defaults(mapping)
      child.parent_custom_field_id = parent.id.to_s

      bytes = preview_bytes(child)
      child.save!
      expect(bytes).to eq(raw_store(child))
      expect(CustomField.find(child.id).value_dependencies).to eq(mapping)
    end
  end

  describe '#before_custom_field_save' do
    [:list, :enumeration].each do |kind|
      context "for a depending #{kind}" do
        let(:kit) { build_kit(kind) }
        let(:parent) { kit.first }
        let(:child) { kit.last }

        it 'assigns the normalized pairs' do
          field = CustomField.find(child.id)
          field.parent_custom_field_id = parent.id.to_s
          expect(field.format).to receive(:normalized_store_pairs).with(field).once.and_call_original
          field.format.before_custom_field_save(field)
          expect(field.parent_custom_field_id).to eq(parent.id)
        end

        # WP-10: a save refuses a self-parent (dcf_circular_dependency), so
        # it is saved without validation here (was: save!).
        it 'keeps a stored self-parent (same type and family) and clears the core default value' do
          field = CustomField.find(child.id)
          field.parent_custom_field_id = child.id
          field.default_value = kit_key(child, 'a1')
          field.save!(validate: false)
          expect(CustomField.find(child.id).parent_custom_field_id).to eq(child.id)
          expect(CustomField.find(child.id).default_value).to be_nil
        end

        it 'keeps the core default value when the given parent does not resolve' do
          field = CustomField.find(child.id)
          field.parent_custom_field_id = other_family_field(kind).id
          field.default_value = kit_key(child, 'a1')
          field.save!
          expect(CustomField.find(child.id).parent_custom_field_id).to be_nil
          expect(CustomField.find(child.id).default_value).to eq(kit_key(child, 'a1'))
        end

        it 'stores orphan keys, unknown children, inactive enumerations and bracket keys unchanged' do
          b1 = kit_key(child, 'b1')
          child.enumerations.detect { |e| e.name == 'b1' }.update!(active: false) if kind == :enumeration
          mapping = { kit_key(parent, 'A') => [kit_key(child, 'a1'), 'nope'], 'ZZ' => ['nope'], '[x]' => [b1], 'a]' => [b1] }
          defaults = { 'ZZ' => 'nope', kit_key(parent, 'B') => kit_key(child, 'a1') }
          field = CustomField.find(child.id)
          field.value_dependencies = mapping
          field.default_value_dependencies = defaults
          field.save!
          stored = CustomField.find(child.id)
          expect(stored.value_dependencies.to_hash.to_a).to eq(mapping.to_a)
          expect(stored.default_value_dependencies.to_hash.to_a).to eq(defaults.to_a)
        end
      end
    end
  end

  describe '#possible_values_options' do
    [:list, :enumeration].each do |kind|
      context "for a depending #{kind}" do
        let(:kit) { build_kit(kind) }
        let(:parent) { kit.first }
        let(:child) { kit.last }
        let(:fmt) { child.format }

        def options(*visible)
          %w[a1 a2 b1].map { |name| visible.include?(name) ? pair(child, name) : pair(child, name, hidden) }
        end

        it 'returns the core list for nil and an Array, without a lookup' do
          issues = [kit_issue(project, parent => 'A'), kit_issue(project, parent => 'B')]
          expect(fmt.possible_values_options(child, nil)).to eq(core_base(child))
          expect(fmt.possible_values_options(child, [])).to eq(core_base(child))
          expect(fmt.possible_values_options(child, nil)).to equal(child.possible_values) if kind == :list
          overhead = dcf_count_queries { fmt.possible_values_options(child, issues) } -
                     dcf_count_queries { fmt.possible_values_options(child, nil) }
          expect(overhead).to eq(0)
          expect(fmt.possible_values_options(child, issues)).to eq(core_base(child))
        end

        it 'returns the core list for a blank, zero or non-numeric pointer' do
          issue = kit_issue(project, parent => 'A')
          ['', 'abc', 0].each do |raw|
            field = CustomField.find(child.id)
            field.parent_custom_field_id = raw
            expect(fmt.possible_values_options(field, issue)).to eq(core_base(child)), raw.inspect
          end
        end

        # Flipped by WP-10 (UD-35): was "filters a stored self-parent by the
        # field's own value" (options('a1') under a1, all hidden under a2).
        it 'returns the core list for a stored self-parent' do
          field = write_store(child, 'parent_custom_field_id' => child.id,
                                     'value_dependencies' => { kit_key(child, 'a1') => [kit_key(child, 'a1')] })

          expect(fmt.possible_values_options(field, kit_issue(project, child => 'a1'))).to eq(core_base(child))
          expect(fmt.possible_values_options(field, kit_issue(project, child => 'a2'))).to eq(core_base(child))
        end

        # Flipped by WP-10: was "hides every option for a stored parent of
        # another custom field type" (all hidden).
        it 'returns the core list for a stored parent of another custom field type' do
          field = write_store(child, 'parent_custom_field_id' => other_type_field(kind).id)
          expect(fmt.possible_values_options(field, kit_issue(project, parent => 'A'))).to eq(core_base(child))
        end

        # Flipped by WP-10: was "filters by a stored parent outside the format
        # family" (options('a2')).
        it 'returns the core list for a stored parent outside the format family' do
          other = other_family_field(kind, **(kind == :list ? { names: %w[A B] } : { values: %w[A B] }))
          field = write_store(child, 'parent_custom_field_id' => other.id,
                                     'value_dependencies' => { kit_key(other, 'A') => [kit_key(child, 'a2')] })
          expect(fmt.possible_values_options(field, kit_issue(project, other => 'A'))).to eq(core_base(child))
        end

        # WP-10 (UD-08): no hidden options in or below a stored cycle.
        it 'returns the core list for the members of a stored cycle and the fields below them' do
          world = dcf_stored_cycles(kind)
          issue = kit_issue(project, world.x => 'x1', world.y => 'y2', world.child => 'c2',
                                     world.self_parent => 's2', world.below_self_parent => 'd2')
          [world.x, world.y, world.child, world.self_parent, world.below_self_parent].each do |field|
            expect(field.format.possible_values_options(field, issue)).to eq(core_base(field)), field.name
          end
        end

        it 'reads a pointer stored as a String like an Integer' do
          issue = kit_issue(project, parent => 'A')
          field = write_store(child, 'parent_custom_field_id' => parent.id.to_s)
          expect(field.format_store['parent_custom_field_id']).to eq(parent.id.to_s)
          expect(fmt.possible_values_options(field, issue)).to eq(options('a1', 'a2'))
        end

        it 'hides every option when the parent is not enabled for the tracker' do
          issue = kit_issue(project, parent => 'A', child => 'a1')
          issue.tracker.custom_fields.delete(parent)
          expect(fmt.possible_values_options(child, Issue.find(issue.id))).to eq(options)
        end

        it 'unites the links of every value of a multiple parent' do
          parent.update!(multiple: true)
          expect(fmt.possible_values_options(child, kit_issue(project, parent => %w[A B]))).to eq(options('a1', 'a2', 'b1'))
          expect(fmt.possible_values_options(child, kit_issue(project, parent => %w[C]))).to eq(options)
        end

        it 'applies a stored blank mapping key to a blank parent value, as 0.0.16 does' do
          field = write_store(child, 'value_dependencies' => { '' => [kit_key(child, 'a1')],
                                                               kit_key(parent, 'A') => [kit_key(child, 'a2')] })
          expect(fmt.possible_values_options(field, kit_issue(project, parent => [], child => []))).to eq(options('a1'))
        end

        it 'follows an in-memory pointer change on the same instance' do
          other = same_family_field(kind, %w[X])
          field = dcf_set_dependencies(CustomField.find(child.id), value_dependencies: {
                                         kit_key(parent, 'A') => [kit_key(child, 'a1')],
                                         kit_key(other, 'X') => [kit_key(child, 'b1')]
                                       })
          issue = kit_issue(project, parent => 'A', other => 'X')
          expect(fmt.possible_values_options(field, issue)).to eq(options('a1'))
          field.parent_custom_field_id = other.id
          expect(fmt.possible_values_options(field, issue)).to eq(options('b1'))
        end

        it 'builds a fresh attribute Hash for every hidden option' do
          result = fmt.possible_values_options(child, kit_issue(project, parent => 'C'))
          attributes = result.map(&:last)
          expect(attributes).to all(eq(hidden))
          expect(attributes.map(&:object_id).uniq.size).to eq(3)
          expect(attributes.first.keys).to eq([:hidden, :style])
          expect(attributes).to all(satisfy { |h| !h.frozen? })
        end

        it 'adds no query when the parent is among the loaded custom field values' do
          issue = kit_issue(project, parent => 'A')
          issue.custom_field_values
          overhead = dcf_count_queries { fmt.possible_values_options(child, issue) } -
                     dcf_count_queries { fmt.possible_values_options(child, nil) }
          expect(overhead).to eq(0)
        end

        it 'adds one memoized lookup when the parent is not available on the object' do
          issue = kit_issue(project, parent => 'A', child => 'a1')
          issue.tracker.custom_fields.delete(parent)
          issue = Issue.find(issue.id)
          issue.custom_field_values
          field = CustomField.find(child.id)
          first = dcf_count_queries { fmt.possible_values_options(field, issue) } -
                  dcf_count_queries { fmt.possible_values_options(field, nil) }
          second = dcf_count_queries { fmt.possible_values_options(field, issue) } -
                   dcf_count_queries { fmt.possible_values_options(field, nil) }
          expect([first, second]).to eq([1, 0])
        end

        # Flipped by WP-15 (carries?): was "raises for an object without custom
        # fields when the parent exists, and returns the core list when it does
        # not" (NoMethodError for an existing parent).
        it 'returns the core list for an object without custom fields (Flipped by WP-15)' do
          expect(fmt.possible_values_options(child, Object.new)).to eq(core_base(child))
          field = write_store(child, 'parent_custom_field_id' => CustomField.maximum(:id).to_i + 1_000)
          expect(fmt.possible_values_options(field, Object.new)).to eq(core_base(child))
        end

        # WP-15: "gives the context menu wizard helper today's intersection" is
        # removed with ContextMenuWizardHelper#intersect_allowed_values.
      end
    end
  end

  # WP-08 (F2): the enumeration edit form options. Core RecordList read
  # options.map(&:last) on the hidden 3-tuples, so a stored value the parent
  # does not allow was appended a second time. The list format keeps core
  # ListFormat's method.
  describe '#possible_custom_value_options' do
    let(:kit) { build_kit(:enumeration) }
    let(:parent) { kit.first }
    let(:child) { kit.last }
    let(:fmt) { child.format }
    let(:core) { Redmine::FieldFormat::EnumerationFormat.instance }

    def deactivate(field, name)
      field.enumerations.detect { |e| e.name == name }.update!(active: false)
    end

    # [label, id] pairs only, each id once.
    def expect_plain_pairs(options)
      expect(options).to all(be_an(Array))
      expect(options.map(&:size).uniq).to eq([2])
      expect(options.flatten.grep(Hash)).to eq([])
      expect(options.map(&:last).uniq).to eq(options.map(&:last))
    end

    it 'returns the unfiltered active list as plain pairs, whatever the parent value' do
      values = {
        'stored a1 under A' => value_of(kit_issue(project, parent => 'A', child => 'a1'), child),
        'new issue under A' => value_of(kit_new_issue(project, parent => 'A'), child),
        'stored b1 under B' => value_of(kit_issue(project, parent => 'B', child => 'b1'), child),
        'blank parent' => value_of(kit_issue(project, parent => [], child => []), child),
        'parent without links' => value_of(kit_issue(project, parent => 'C'), child),
        'no object' => CustomFieldValue.new(custom_field: child, value: 'zz')
      }
      allow(rules).to receive(:parent_state).and_call_original
      allow(CustomField).to receive(:find_by).and_call_original
      values.each do |label, value|
        options = fmt.possible_custom_value_options(value)
        expect(options).to eq(core_base(child)), label
        expect(options).to eq(core.possible_custom_value_options(value)), label
        expect_plain_pairs(options)
      end
      expect(rules).not_to have_received(:parent_state)
      expect(CustomField).not_to have_received(:find_by)
    end

    it 'returns the same list for a dangling parent and a stored self-parent' do
      issue = kit_issue(project, parent => 'A', child => 'a1')
      dangling = write_store(child, 'parent_custom_field_id' => CustomField.maximum(:id).to_i + 1_000)
      expect(fmt.possible_custom_value_options(value_of(issue, child).tap { |v| v.custom_field = dangling }))
        .to eq(core_base(child))
      itself = write_store(child, 'parent_custom_field_id' => child.id,
                                  'value_dependencies' => { kit_key(child, 'a1') => [kit_key(child, 'a1')] })
      expect(fmt.possible_custom_value_options(value_of(Issue.find(issue.id), child).tap { |v| v.custom_field = itself }))
        .to eq(core_base(child))
    end

    it 'offers a stored value the parent does not allow once, as a plain pair' do
      options = fmt.possible_custom_value_options(value_of(kit_issue(project, parent => 'A', child => 'b1'), child))
      expect(options).to eq([pair(child, 'a1'), pair(child, 'a2'), pair(child, 'b1')])
      expect_plain_pairs(options)
    end

    it 'offers each stored value of a multiple child once' do
      parent, child = build_kit(:enumeration, multiple: true)
      value = value_of(kit_issue(project, parent => 'A', child => %w[b1 a1]), child)
      expect(value.value_was).to match_array([kit_key(child, 'a1'), kit_key(child, 'b1')])
      expect(child.format.possible_custom_value_options(value))
        .to eq([pair(child, 'a1'), pair(child, 'a2'), pair(child, 'b1')])
    end

    it 'appends a stored inactive id once, after the active list' do
      deactivate(child, 'a2')
      value = value_of(kit_issue(project, parent => 'A', child => 'a2'), child)
      expected = [pair(child, 'a1'), pair(child, 'b1'), pair(child, 'a2')]
      expect(fmt.possible_custom_value_options(value)).to eq(expected)
      a2 = kit_key(child, 'a2')
      [a2, [a2], [a2, '', nil, a2], ['', a2]].each do |stored|
        value.value_was = stored
        expect(fmt.possible_custom_value_options(value)).to eq(expected), stored.inspect
      end
      [nil, '', [nil], [''], []].each do |stored|
        value.value_was = stored
        expect(fmt.possible_custom_value_options(value)).to eq(core_base(child)), stored.inspect
      end
    end

    # a1 moves behind a2, so position order (a2, a1) differs from id order,
    # update order and stored order (all a1, a2).
    it 'appends every stored inactive id of a multiple child once, in position order' do
      parent, child = build_kit(:enumeration, multiple: true)
      child.enumerations.detect { |e| e.name == 'a1' }.update_columns(position: 5)
      deactivate(child, 'a1')
      deactivate(child, 'a2')
      value = value_of(kit_issue(project, parent => 'A', child => %w[a1 b1 a2]), child)
      expect(value.value_was).to eq([kit_key(child, 'a1'), kit_key(child, 'b1'), kit_key(child, 'a2')])
      options = child.format.possible_custom_value_options(value)
      expect(options).to eq([pair(child, 'b1'), pair(child, 'a2'), pair(child, 'a1')])
      expect_plain_pairs(options)
    end

    it 'never offers an inactive id that is not stored, also when the mapping links it (QA-21)' do
      deactivate(child, 'b1')
      b1 = kit_key(child, 'b1')
      expect(CustomField.find(child.id).value_dependencies[kit_key(parent, 'B')]).to eq([b1])
      copy = Issue.new.copy_from(kit_issue(project, parent => 'B', child => 'b1'))
      changed = kit_issue(project, parent => 'B', child => 'a1')
      changed.custom_field_values = { child.id.to_s => b1 }
      values = {
        'posted on a new issue' => value_of(kit_new_issue(project, parent => 'B', child => 'b1'), child),
        'linked only' => value_of(kit_issue(project, parent => 'B'), child),
        'posted over a stored a1' => value_of(changed, child),
        'issue copy' => value_of(copy, child),
        'no object' => CustomFieldValue.new(custom_field: child, value: b1)
      }
      values.each do |label, value|
        expect(fmt.possible_custom_value_options(value)).to eq([pair(child, 'a1'), pair(child, 'a2')]), label
      end
      expect(values['issue copy'].value).to eq(b1)
    end

    # Like core, a stored id is looked up across fields (not scoped to the
    # field's own enumerations); an id with no row or a non-numeric one adds
    # nothing.
    it 'appends a stored id of another field like core, and nothing for an unknown or non-numeric id' do
      other = dcf_enum_field(names: %w[z1])
      z1 = kit_key(other, 'z1')
      issue = kit_issue(project, parent => 'A', child => 'a1')
      CustomValue.where(customized_type: 'Issue', customized_id: issue.id, custom_field_id: child.id)
                 .update_all(value: z1)
      value = value_of(Issue.find(issue.id), child)
      expect(value.value_was).to eq(z1)
      expect(fmt.possible_custom_value_options(value)).to eq(core_base(child) + [['z1', z1]])
      expect(fmt.possible_custom_value_options(value)).to eq(core.possible_custom_value_options(value))
      [(CustomFieldEnumeration.maximum(:id).to_i + 1_000).to_s, 'abc'].each do |stored|
        value.value_was = stored
        expect(fmt.possible_custom_value_options(value)).to eq(core_base(child)), stored
        expect(core.possible_custom_value_options(value)).to eq(core_base(child)), stored
      end
    end

    it 'accepts a stored id of another field assigned unchanged when no parent applies, like core' do
      free = dcf_enum_field(format: 'depending_enumeration', names: %w[f1 f2])
      z1 = kit_key(dcf_enum_field(names: %w[z1]), 'z1')
      issue = kit_issue(project, free => 'f1')
      CustomValue.where(customized_type: 'Issue', customized_id: issue.id, custom_field_id: free.id)
                 .update_all(value: z1)
      stored = Issue.find(issue.id)
      stored.custom_field_values = { free.id.to_s => z1 }
      expect(errors_for(stored, free)).to eq([])
      fresh = kit_new_issue(project, free => [])
      fresh.custom_field_values = { free.id.to_s => z1 }
      expect(errors_for(fresh, free)).to eq([inclusion])
    end

    it 'runs the queries core runs, and looks stored ids up only when some are missing' do
      deactivate(child, 'a2')
      values = [value_of(kit_issue(project, parent => 'A', child => []), child),
                value_of(kit_issue(project, parent => 'A', child => 'b1'), child),
                value_of(kit_issue(project, parent => 'A', child => 'a2'), child)]
      counts = values.map do |value|
        fmt.possible_custom_value_options(value)
        core.possible_custom_value_options(value)
        mine = dcf_count_queries { fmt.possible_custom_value_options(value) }
        expect(mine).to eq(dcf_count_queries { core.possible_custom_value_options(value) })
        mine
      end
      expect(counts).to eq([1, 1, 2])
    end

    it 'keeps no state on a fresh format object' do
      deactivate(child, 'a2')
      fresh = RedmineDependingCustomFields::DependingEnumerationFormat.send(:new)
      fresh.possible_custom_value_options(value_of(kit_issue(project, parent => 'A', child => 'a2'), child))
      expect(fresh.instance_variables).to eq([])
    end

    # Core List#edit_tag renders these options; each stored value must give
    # exactly one control and no option may be hidden by the server.
    describe 'in the edit tags' do
      let(:view) { ActionView::Base.empty }

      def render_tag(field, issue)
        value = value_of(issue, field).tap { |v| v.custom_field = field }
        html = field.format.edit_tag(view, "cf_#{field.id}", "issue[custom_field_values][#{field.id}]", value)
        Nokogiri::HTML.fragment(html)
      end

      def keys(field, *names)
        names.map { |n| kit_key(field, n) }
      end

      it 'renders a stored disallowed value as one selected option in the select style' do
        html = render_tag(child, kit_issue(project, parent => 'A', child => 'b1'))
        expect(html.css('option').pluck('value')).to eq([''] + keys(child, 'a1', 'a2', 'b1'))
        expect(html.css('option[selected]').pluck('value')).to eq(keys(child, 'b1'))
        expect(html.css('option[hidden], option[style]')).to be_empty
      end

      it 'renders a stored inactive value once and an unstored inactive id not at all in the select style' do
        deactivate(child, 'b1')
        stored = render_tag(child, kit_issue(project, parent => 'B', child => 'b1'))
        expect(stored.css('option').pluck('value')).to eq([''] + keys(child, 'a1', 'a2', 'b1'))
        expect(stored.css('option[selected]').pluck('value')).to eq(keys(child, 'b1'))
        unstored = render_tag(child, kit_issue(project, parent => 'B'))
        expect(unstored.css('option').pluck('value')).to eq([''] + keys(child, 'a1', 'a2'))
        expect(stored.css('option[hidden], option[style]')).to be_empty
        expect(unstored.css('option[hidden], option[style]')).to be_empty
      end

      # Before WP-08 the server hid every option here (the parent allows
      # nothing). Until WP-16 to WP-18 (M2) the browser does not filter them
      # either: the legacy script finds no parent input. A pick is still
      # rejected with 'is invalid' (UD-05).
      it 'renders every active value, none hidden, when the parent is not available for the tracker' do
        issue = kit_issue(project, child => [])
        expect(issue.available_custom_fields).to include(child)
        expect(issue.available_custom_fields).not_to include(parent)
        html = render_tag(child, issue)
        expect(html.css('option').pluck('value')).to eq([''] + keys(child, 'a1', 'a2', 'b1'))
        expect(html.css('option[hidden], option[style]')).to be_empty
        issue.custom_field_values = { child.id.to_s => kit_key(child, 'a1') }
        expect(errors_for(issue, child)).to eq([invalid])
      end

      it 'renders a stored disallowed value as one checked radio in the check box style' do
        child.update!(edit_tag_style: 'check_box')
        field = CustomField.find(child.id)
        html = render_tag(field, kit_issue(project, parent => 'A', child => 'b1'))
        expect(html.css('input[type=radio]').pluck('value')).to eq([''] + keys(field, 'a1', 'a2', 'b1'))
        expect(html.css('input[type=radio][checked]').pluck('value')).to eq(keys(field, 'b1'))
      end

      it 'renders each stored value of a multiple child as one checked check box' do
        parent, child = build_kit(:enumeration, multiple: true)
        child.update!(edit_tag_style: 'check_box')
        field = CustomField.find(child.id)
        html = render_tag(field, kit_issue(project, parent => 'A', child => %w[b1 a1]))
        expect(html.css('input[type=checkbox]').pluck('value')).to eq(keys(field, 'a1', 'a2', 'b1'))
        expect(html.css('input[type=checkbox][checked]').pluck('value')).to eq(keys(field, 'a1', 'b1'))
      end
    end
  end

  describe '#validate_custom_value' do
    [:list, :enumeration].each do |kind|
      context "for a depending #{kind}" do
        let(:kit) { build_kit(kind) }
        let(:parent) { kit.first }
        let(:child) { kit.last }
        let(:fmt) { child.format }
        let(:core) { kind == :list ? Redmine::FieldFormat::ListFormat.instance : Redmine::FieldFormat::EnumerationFormat.instance }

        # A value set as acts_as_customizable loads it (no setter normalization).
        def loaded_value(field, value, customized = nil)
          custom_value = CustomFieldValue.new(custom_field: field, customized: customized)
          custom_value.instance_variable_set(:@value, value)
          custom_value
        end

        it 'assigns the non-blank values back through the setter, also without an object' do
          expect(loaded_value(child, nil).tap { |cv| fmt.validate_custom_value(cv) }.value).to eq('')
          expect(loaded_value(child, ['', kit_key(child, 'a1')]).tap { |cv| fmt.validate_custom_value(cv) }.value)
            .to eq(kit_key(child, 'a1'))
          child.update!(multiple: true)
          field = CustomField.find(child.id)
          expect(loaded_value(field, []).tap { |cv| fmt.validate_custom_value(cv) }.value).to eq([''])
          a1 = kit_key(child, 'a1')
          expect(loaded_value(field, [a1, '', nil, a1]).tap { |cv| fmt.validate_custom_value(cv) }.value).to eq([a1])
        end

        it 'gives the core result without an object, with no lookup and no memo entry' do
          field = CustomField.find(child.id)
          value = 'zz'
          result = nil
          overhead = dcf_count_queries { result = fmt.validate_custom_value(CustomFieldValue.new(custom_field: field, value: value)) } -
                     dcf_count_queries { core.validate_custom_value(CustomFieldValue.new(custom_field: field, value: value)) }
          expect(overhead).to eq(0)
          expect(result).to eq([inclusion])
          expect(result).to eq(core.validate_custom_value(CustomFieldValue.new(custom_field: field, value: value)))
          expect(field.instance_variable_get(:@dcf_memo).to_h.keys.map(&:first)).not_to include(:parent_record)
        end

        # WP-08: core accepts the active a1 for both formats (the enumeration
        # edit options are no longer filtered), so only the rule rejects it.
        it 'checks the whole set against today\'s raw union: a blank link counts as a link' do
          field = write_store(child, 'value_dependencies' => { kit_key(parent, 'A') => [''] })
          issue = kit_new_issue(project, parent => 'A', child => 'a1')
          expect(fmt.validate_custom_value(value_of(issue, field).tap { |v| v.custom_field = field })).to eq([invalid])
        end

        # Flipped by WP-10 (UD-35): was "checks a stored self-parent against
        # the field's own sanitized value" ([invalid] for a2).
        it 'gives the core result for a stored self-parent' do
          field = write_store(child, 'parent_custom_field_id' => child.id,
                                     'value_dependencies' => { kit_key(child, 'a1') => [kit_key(child, 'a1')] })
          valid = value_of(kit_new_issue(project, child => 'a1'), child).tap { |v| v.custom_field = field }
          wrong = value_of(kit_new_issue(project, child => 'a2'), child).tap { |v| v.custom_field = field }
          expect(fmt.validate_custom_value(valid)).to eq([])
          expect(fmt.validate_custom_value(wrong)).to eq([])
          expect(fmt.validate_custom_value(wrong)).to eq(core.validate_custom_value(wrong))
        end

        # Flipped by WP-10: was "rejects a non-blank value under a stored
        # parent of another custom field type" ([invalid] for a1).
        it 'gives the core result under a stored parent of another custom field type' do
          field = write_store(child, 'parent_custom_field_id' => other_type_field(kind).id)
          filled = value_of(kit_new_issue(project, parent => 'A', child => 'a1'), child).tap { |v| v.custom_field = field }
          blank = value_of(kit_new_issue(project, parent => 'A', child => []), child).tap { |v| v.custom_field = field }
          expect(fmt.validate_custom_value(filled)).to eq([])
          expect(fmt.validate_custom_value(filled)).to eq(core.validate_custom_value(filled))
          expect(fmt.validate_custom_value(blank)).to eq([])
        end

        # WP-10 (UD-08, UD-35, server design section 8 rules 4 and 5): core
        # validation only in or below a stored cycle.
        it 'accepts any value core accepts in the members of a stored cycle and the fields below them' do
          world = dcf_stored_cycles(kind)
          issue = kit_new_issue(project, world.x => 'x2', world.y => 'y2', world.child => 'c2',
                                         world.self_parent => 's2', world.below_self_parent => 'd2')
          [world.x, world.y, world.child, world.self_parent, world.below_self_parent].each do |field|
            expect(errors_for(issue, field)).to eq([]), field.name
          end
          expect(issue.valid?).to be(true), issue.errors.full_messages.inspect
        end

        it 'gives the core result for a dangling parent' do
          field = write_store(child, 'parent_custom_field_id' => CustomField.maximum(:id).to_i + 1_000)
          issue = kit_new_issue(project, parent => 'A', child => 'b1')
          value = value_of(issue, child).tap { |v| v.custom_field = field }
          expect(fmt.validate_custom_value(value)).to eq(core.validate_custom_value(value))
        end

        it 'reads an available parent without a parent lookup' do
          issue = kit_new_issue(project, parent => 'B', child => 'a1')
          value = value_of(issue, child)
          allow(CustomField).to receive(:find_by).and_call_original
          allow(rules).to receive(:find_parent).and_call_original
          fmt.validate_custom_value(value)
          expect(CustomField).not_to have_received(:find_by)
          expect(rules).not_to have_received(:find_parent)
        end

        # WP-08 (PC-13, UN-09): validation runs inside with_locale, as the
        # messages are translated when the value is validated. WP-09 (UD-06):
        # a copy of a legacy combination is accepted (was: one message), a
        # copy whose parent then changes to C (allows nothing) gets the one
        # message.
        it 'gives a disallowed new value one message in en and de, and accepts a copy of a legacy combination' do
          source = kit_issue(project, parent => 'A', child => 'b1')
          { en: 'is invalid', de: 'ist nicht gültig' }.each do |locale, message|
            I18n.with_locale(locale) do
              expect(errors_for(kit_new_issue(project, parent => 'B', child => 'a1'), child)).to eq([message]), locale.to_s
              copy = Issue.new.copy_from(source)
              expect(errors_for(copy, child)).to eq([]), locale.to_s
              copy.custom_field_values = { parent.id.to_s => kit_key(parent, 'C') }
              expect(errors_for(copy, child)).to eq([message]), locale.to_s
            end
          end
        end

        # WP-08: core messages first, then the dependency error unless core
        # already gave the same message; super's Array is not changed. Core
        # never returns 'is invalid', so super is a stand-in returning a
        # frozen Array (the module itself is the real one).
        it 'merges the dependency error into the core errors without repeating a message' do
          core_errors = nil
          stand_in = Class.new { def self.field_attributes(*); end }
          stand_in.define_method(:validate_custom_value) { |_custom_value| core_errors.dup.freeze }
          merging = Class.new(stand_in).tap { |k| k.include(described_class) }.new
          disallowed = value_of(kit_new_issue(project, parent => 'B', child => 'a1'), child)
          allowed = value_of(kit_new_issue(project, parent => 'A', child => 'a1'), child)
          { [invalid] => [invalid], [inclusion] => [inclusion, invalid], [] => [invalid] }.each do |core_result, expected|
            core_errors = core_result
            expect(merging.validate_custom_value(disallowed)).to eq(expected), core_result.inspect
            expect(merging.validate_custom_value(allowed)).to eq(core_result), core_result.inspect
          end
        end
      end
    end

    # WP-08: only value_was extends the enumeration edit options, so an
    # inactive id is accepted by core only while it is the stored value.
    context 'for a depending enumeration with an inactive value' do
      let(:kit) { build_kit(:enumeration) }
      let(:parent) { kit.first }
      let(:child) { kit.last }
      let(:b1) { kit_key(child, 'b1') }

      before { child.enumerations.detect { |e| e.name == 'b1' }.update!(active: false) }

      it 'rejects a crafted inactive id that is not stored, also when the parent allows it (QA-21)' do
        fresh = kit_new_issue(project, parent => 'B', child => 'b1')
        expect(errors_for(fresh, child)).to eq([inclusion])
        expect(fresh.valid?).to be(false)
        changed = kit_issue(project, parent => 'B', child => 'a1')
        changed.custom_field_values = { child.id.to_s => b1 }
        expect(errors_for(changed, child)).to eq([inclusion])
        expect(errors_for(kit_new_issue(project, parent => 'A', child => 'b1'), child)).to eq([inclusion, invalid])
        unknown = kit_new_issue(project, parent => 'B')
        unknown.custom_field_values = { child.id.to_s => (CustomFieldEnumeration.maximum(:id).to_i + 1_000).to_s }
        expect(errors_for(unknown, child)).to include(inclusion)
      end

      it 'rejects a copy of a stored inactive id like core: a copy has no stored value' do
        copy = Issue.new.copy_from(kit_issue(project, parent => 'B', child => 'b1'))
        expect(value_of(copy, child).value).to eq(b1)
        expect(errors_for(copy, child)).to eq([inclusion])
      end

      # WP-09 (D1): the stored id is kept while the parent is unchanged, also
      # under a parent value that does not allow it (was: [invalid]); a
      # parent change makes it strict.
      it 'leaves a stored inactive id assigned unchanged to the dependency rule' do
        allowed = kit_issue(project, parent => 'B', child => 'b1')
        allowed.custom_field_values = { child.id.to_s => b1 }
        expect(errors_for(allowed, child)).to eq([])
        disallowed = kit_issue(project, parent => 'A', child => 'b1')
        disallowed.custom_field_values = { child.id.to_s => b1 }
        expect(errors_for(disallowed, child)).to eq([])
        disallowed.custom_field_values = { parent.id.to_s => kit_key(parent, 'C') }
        expect(errors_for(disallowed, child)).to eq([invalid])
      end

      # The issue form posts every editable custom field, so a notes-only
      # save assigns the stored inactive id unchanged and validates it.
      it 'keeps a stored inactive id on a notes-only save that posts it unchanged' do
        issue = kit_issue(project, parent => 'B', child => 'b1')
        issue.init_journal(dcf_admin, 'A note')
        issue.custom_field_values = { child.id.to_s => b1 }
        expect(issue.save).to be(true), issue.errors.full_messages.inspect
        expect(Issue.find(issue.id).custom_field_value(child)).to eq(b1)
        expect(issue.journals.reload.last.notes).to eq('A note')
      end
    end

    # The issue validation path reads every parent from the issue (G6): the
    # same number of queries for 1 or 5 depending children of distinct
    # parents. The children are not required (since WP-09 the required
    # bypass in CustomFieldPatch reads the parent through
    # DependencyRules.no_options?, plus one memoized existence lookup per
    # field record; spec/patches/custom_field_required_validation_spec.rb).
    describe 'query invariance of issue validation' do
      # Each world has its own tracker and project (a Project instance
      # memoizes its custom fields).
      def build_world(family, managed)
        tracker = dcf_tracker
        project = dcf_create_project
        project.trackers << tracker unless project.trackers.include?(tracker)
        parents = Array.new(5) { same_family_field(family, %w[A B]) }
        children = parents.each_with_index.map do |p, i|
          linked = i < managed
          child = if family == :list
                    dcf_list_field(format: 'depending_list', values: %w[a1 b1], parent: linked ? p : nil)
                  else
                    dcf_enum_field(format: 'depending_enumeration', names: %w[a1 b1], parent: linked ? p : nil)
                  end
          linked ? dcf_set_dependencies(child, value_dependencies: { kit_key(p, 'A') => [kit_key(child, 'a1')] }) : child
        end
        (parents + children).each { |f| tracker.custom_fields << f }
        priority = IssuePriority.first || IssuePriority.create!(name: 'Normal')
        issue = Issue.new(project: project, tracker: tracker, subject: 'S', author: dcf_admin,
                          status: tracker.default_status, priority: priority)
        issue.custom_field_values = parents.to_h { |p| [p.id.to_s, kit_key(p, 'A')] }
        issue.save!
        [Issue.find(issue.id), children]
      end

      # Counted after one warm-up run: core looks a builtin role up once,
      # in whichever world runs first.
      def validation_queries(issue, children)
        issue.custom_field_values
        issue.custom_field_values = children.to_h { |c| [c.id.to_s, kit_key(c, 'a1')] }
        issue.valid?
        checked = 0
        allow(rules).to receive(:parent_state).and_wrap_original do |original, *args|
          checked += 1
          original.call(*args)
        end
        count = dcf_count_queries { issue.valid? }
        expect(issue.errors.full_messages).to eq([])
        expect(checked).to be >= children.size
        count
      end

      [:list, :enumeration].each do |family|
        it "runs the same number of queries for 1 and 5 managed #{family} children" do
          one = build_world(family, 1)
          five = build_world(family, 5)
          expect(validation_queries(*five)).to eq(validation_queries(*one))
        end
      end
    end
  end

  describe '#validate_custom_field' do
    it 'returns the core list format errors' do
      field = IssueCustomField.new(name: 'L', field_format: 'depending_list')
      expect(field.format.validate_custom_field(field)).to eq([[:possible_values, :blank]])
      expect(field.format.validate_custom_field(field))
        .to eq(Redmine::FieldFormat::ListFormat.instance.validate_custom_field(field))
    end

    it 'returns the core enumeration format errors' do
      field = IssueCustomField.new(name: 'E', field_format: 'depending_enumeration')
      field.url_pattern = 'http://exa mple.test/%value%'
      expect(field.format.validate_custom_field(field)).to eq([[:url_pattern, :invalid]])
      expect(field.format.validate_custom_field(field))
        .to eq(Redmine::FieldFormat::EnumerationFormat.instance.validate_custom_field(field))
    end

    # WP-10: was "adds no parent check and no query"; the parent check runs
    # only when the normalized parent id changes (D9 refinement, UD-08), so
    # a stored self-parent saved unchanged still gives [] without a query.
    it 'adds no parent check and no query while the parent id is unchanged' do
      kit = build_kit(:list)
      field = write_store(kit.last, 'parent_custom_field_id' => kit.last.id)
      expect(dcf_count_queries { expect(field.format.validate_custom_field(field)).to eq([]) }).to eq(0)
      expect(field.valid?).to be(true)
      field.parent_custom_field_id = kit.last.id.to_s
      expect(dcf_count_queries { expect(field.format.validate_custom_field(field)).to eq([]) }).to eq(0)
    end

    # WP-10: core pairs first, then the cycle pair of DependencyRules.parent_errors.
    it 'adds the circular dependency pair after the core errors when the parent changes' do
      [[:list, [[:possible_values, :blank]]], [:enumeration, [[:url_pattern, :invalid]]]].each do |kind, core_pairs|
        field = CustomField.find(build_kit(kind).last.id)
        field.possible_values = [] if kind == :list
        field.url_pattern = 'http://exa mple.test/%value%' if kind == :enumeration
        field.parent_custom_field_id = field.id
        expect(field.format.validate_custom_field(field))
          .to eq(core_pairs + [[:parent_custom_field_id, :dcf_circular_dependency]]), kind.to_s
      end
    end
  end

  describe '#value_from_keyword' do
    # 0.0.16's algorithm over the core list (depending_list_format.rb before
    # WP-06): a linear casecmp? search per keyword.
    def keyword_oracle(field, keyword)
      return if keyword.blank?

      opts = core_base(field)
      keywords = field.multiple? ? keyword.split(/[;,]/).map(&:strip).reject(&:blank?) : [keyword.strip]
      matched = keywords.filter_map do |kw|
        hit = opts.find do |opt|
          label, _val = opt.is_a?(Array) ? opt.take(2) : [opt, opt]
          label.to_s.strip.casecmp?(kw)
        end
        hit.is_a?(Array) ? hit[1] : hit
      end
      field.multiple? ? matched.presence : matched.first
    end

    grid_names = ['a1', 'a2', 'b1', 'c,d', 'Straße', 'ÉCOLE', 'kilo', 'ΣΟΦΟΣ', 'office']
    # Unicode case folding: sharp s, the Kelvin sign, final sigma, the ffi ligature.
    grid_keywords = [' A1 ', 'a1', 'A1;b1, a2', 'a1,a1', 'a1,A1', 'c,d', 'zz', '', '   ', ',', 'zz;yy', ';a1', 'a1;;b1',
                     'STRASSE', 'strasse', 'école', ' École ', "\u212Ailo", 'σοφος', "o\uFB03ce", "a1\nb1"]

    [:list, :enumeration].each do |kind|
      [false, true].each do |multiple|
        it "matches like 0.0.16 for a #{multiple ? 'multiple' : 'single'} #{kind} child, whatever the object" do
          parent, child = build_kit(kind, multiple: multiple, child_names: grid_names)
          customized = [nil, kit_issue(project, parent => 'A'), kit_issue(project, parent => [], child => []), project]
          customized.each do |object|
            grid_keywords.each do |keyword|
              expect(child.format.value_from_keyword(child, keyword, object))
                .to eq(keyword_oracle(child, keyword)), "#{keyword.inspect} with #{object.class}"
            end
          end
          expected = multiple ? [kit_key(child, 'Straße')] : kit_key(child, 'Straße')
          expect(child.format.value_from_keyword(child, 'STRASSE', nil)).to eq(expected)
        end
      end

      it "goes through CustomField#value_from_keyword for a #{kind} child and ignores the object" do
        parent, child = build_kit(kind)
        issue = kit_issue(project, parent => 'B')
        expect(child.value_from_keyword('A1', issue)).to eq(kit_key(child, 'a1'))
        fresh = Issue.find(issue.id)
        overhead = dcf_count_queries { child.format.value_from_keyword(child, 'a1', fresh) } -
                   dcf_count_queries { child.format.value_from_keyword(child, 'a1', nil) }
        expect(overhead).to eq(0)
      end

      it "reads the option list once per call for a #{kind} child" do
        _parent, child = build_kit(kind, multiple: true)
        expect(child.format).to receive(:possible_values_options).with(child).once.and_call_original
        expect(child.format.value_from_keyword(child, 'a1;a2;b1;a1', nil).size).to eq(4)
      end
    end

    it 'keeps the first of two labels that differ only by case' do
      field = IssueCustomField.new(name: 'D', field_format: 'depending_list', possible_values: %w[Dup dup Other])
      expect(field.format.value_from_keyword(field, 'DUP', nil)).to eq('Dup')
      expect(field.format.value_from_keyword(field, 'dup', nil)).to eq('Dup')
    end

    it 'matches active enumeration names only' do
      _parent, child = build_kit(:enumeration)
      child.enumerations.detect { |e| e.name == 'b1' }.update!(active: false)
      field = CustomField.find(child.id)
      expect(field.format.value_from_keyword(field, 'b1', nil)).to be_nil
      expect(field.format.value_from_keyword(field, 'a1', nil)).to eq(kit_key(field, 'a1'))
    end

    it 'returns nil for an empty option list' do
      field = IssueCustomField.new(name: 'E', field_format: 'depending_list', possible_values: [])
      expect(field.format.value_from_keyword(field, 'x', nil)).to be_nil
    end

    it 'returns nil for a binary keyword with high bytes' do
      field = IssueCustomField.new(name: 'B', field_format: 'depending_list', possible_values: %w[a1 Straße])
      expect(field.format.value_from_keyword(field, "Stra\xC3\x9Fe".b, nil)).to be_nil
    end

    context 'with 100,000 keywords against 5,570 options' do
      let(:names) { DcfLargeList.names(5570, tricky_every: 97) }
      let(:field) { IssueCustomField.new(name: 'Large', field_format: 'depending_list', multiple: true, possible_values: names) }
      let(:oracle) { names.index_by { |v| v.downcase(:fold) } }
      let(:keywords) do
        usable = names.reject { |v| v.include?(',') || v.include?(';') }
        Array.new(100_000) { |i| i.odd? ? usable[i % usable.size].upcase : usable[i % usable.size] }
      end
      let(:keyword) { keywords.join(';') }

      def fastest_run_ms
        field.format.value_from_keyword(field, keyword, nil)
        GC.start
        Array.new(3) do
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          field.format.value_from_keyword(field, keyword, nil)
          (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
        end.min
      end

      it 'returns every match in order with duplicates, in linear time', :large do
        expect(oracle.size).to eq(names.size)
        expect(field.format.value_from_keyword(field, keyword, nil)).to eq(keywords.map { |k| oracle[k.downcase(:fold)] })
        expect(fastest_run_ms).to be < 2_000
      end

      it 'stays within the 200 ms budget', :large, :perf do
        ms = fastest_run_ms
        RSpec.configuration.reporter.message(format('DCF PERF value_from_keyword 100000 keywords x 5570 options: %.1f ms', ms))
        expect(ms).to be < 200
      end
    end
  end

  # Flipped by WP-18 (UD-14, server design 7.1): was '#after_custom_field_save
  # deletes the mapping cache key on save'; the hook and the cache are gone.
  describe 'no after_custom_field_save' do
    [:list, :enumeration].each do |kind|
      it "saves a depending #{kind} without the hook and without touching the cache" do
        child = build_kit(kind).last
        expect(child.format).not_to respond_to(:after_custom_field_save)
        expect(Rails.cache).not_to receive(:delete)
        expect(Rails.cache).not_to receive(:delete_matched)
        CustomField.find(child.id).update!(name: "#{child.name} renamed")
      end
    end
  end

  # WP-16: edit_tag and bulk_edit_tag add the data-dcf-* attributes of
  # ClientData to the element core passes options to and call core List with
  # the merged options, so the markup is core's plus those attributes.
  describe '#edit_tag and #bulk_edit_tag (data contract)' do
    let(:client) { RedmineDependingCustomFields::ClientData }
    let(:view) { ActionView::Base.empty.tap { |v| v.extend(CustomFieldsHelper) } }

    def dcf_attribute_names(node)
      node.attribute_nodes.map(&:name).grep(/\Adata-dcf-/)
    end

    # Every element without its data-dcf-* attributes, as canonical HTML.
    def without_dcf(html)
      doc = Nokogiri::HTML.fragment(html)
      doc.traverse { |n| dcf_attribute_names(n).each { |name| n.remove_attribute(name) } if n.element? }
      doc.to_html
    end

    def labelled(issue, field)
      view.custom_field_tag_with_label(:issue, value_of(issue, field)).to_str
    end

    def stubbed
      allow(client).to receive(:attributes_for).and_return({})
      yield
    ensure
      allow(client).to receive(:attributes_for).and_call_original
    end

    def locales
      %w[en de fr nl]
    end

    def styled(kind, style, multiple: false, required: false)
      parent, child = build_kit(kind, multiple: multiple)
      child.update!(edit_tag_style: style, is_required: required)
      [parent, CustomField.find(child.id)]
    end

    [:list, :enumeration].each do |kind|
      context "for a depending #{kind}" do
        it 'puts the attributes on the select of the drop-down style and keeps label for= on a single select' do
          parent, child = styled(kind, '')
          issue = kit_issue(project, parent => 'A', child => 'a1')
          html = labelled(issue, child)
          doc = Nokogiri::HTML.fragment(html)
          select = doc.at_css('select')

          expect(select['data-dcf-field']).to eq(child.id.to_s)
          expect(select['data-dcf-parent']).to eq(parent.id.to_s)
          expect(select['data-dcf-context']).to eq('form')
          expect(doc.css('[data-dcf-field]').size).to eq(1)
          expect(html.scan(/ id="(.+?)"/).size).to eq(1)
          expect(doc.at_css('label')['for']).to eq(select['id'])
        end

        # Flipped by WP-19: the only input with a data-dcf-* attribute is the
        # id-less blank sentinel before a single radio group (data-dcf-blank
        # only); was no input with one and no sentinel. Check boxes: none.
        it 'puts the attributes on span.check_box_group for radios and check boxes, never on a choice input' do
          [[false, 'radio'], [true, 'checkbox']].each do |multiple, type|
            parent, child = styled(kind, 'check_box', multiple: multiple)
            issue = kit_issue(project, parent => 'A', child => multiple ? %w[a1] : 'a1')
            doc = Nokogiri::HTML.fragment(labelled(issue, child))

            expect(doc.css('span.check_box_group[data-dcf-field]').size).to eq(1), type
            expect(doc.css("input[type=#{type}]").size).to be > 1
            expect(doc.css("input[type=#{type}]").map { |input| dcf_attribute_names(input) }.flatten).to eq([]), type
            expect(doc.css('input').map { |input| dcf_attribute_names(input) }.flatten)
              .to eq(multiple ? [] : ['data-dcf-blank']), type
            expect(doc.css('input[data-dcf-blank]').size).to eq(multiple ? 0 : 1), type
            expect(doc.at_css('label')['for']).to be_nil
          end
        end

        # Flipped by WP-19: a single radio group also gets the id-less blank
        # sentinel (the only element the override adds), so the comparison
        # removes it; was byte-identical for every variant. The id list and
        # label for= stay core's.
        it 'only adds data-dcf-* attributes and the sentinel of a single radio group: ids, label for= and every other byte stay core output' do
          variants = [['', false, false], ['', true, false], ['', false, true], ['check_box', false, false],
                      ['check_box', true, false], ['check_box', false, true], ['', true, true], ['check_box', true, true]]
          variants.each do |style, multiple, required|
            parent, child = styled(kind, style, multiple: multiple, required: required)
            issue = kit_issue(project, parent => 'A', child => multiple ? %w[a1] : 'a1')
            real = labelled(issue, child)
            bare = stubbed { labelled(Issue.find(issue.id), child) }

            label = [style, multiple, required].inspect
            fragment = Nokogiri::HTML.fragment(real)
            expect(fragment.css('[data-dcf-field]').size).to eq(1), label
            expect(fragment.css('input[data-dcf-blank]').size).to eq(style == 'check_box' && !multiple ? 1 : 0), label
            fragment.css('input[data-dcf-blank]').each(&:remove)
            expect(without_dcf(fragment.to_html)).to eq(Nokogiri::HTML.fragment(bare).to_html), label
            expect(real.scan(/ id="(.+?)"/)).to eq(bare.scan(/ id="(.+?)"/)), label
            expect(fragment.at_css('label')['for']).to eq(Nokogiri::HTML.fragment(bare).at_css('label')['for']), label
          end
        end

        # Flipped by WP-19 (UD-10): a required child gets core's (none)
        # option marked data-dcf-required-none right after (No change),
        # nothing else changes (drift guard); was core output without (none).
        # The non-required half is unchanged.
        it 'renders bulk tags as core List#bulk_edit_tag plus the bulk attributes, and the marked (none) for a required child' do
          [false, true].each do |required|
            parent, child = styled(kind, 'check_box', required: required)
            issues = [kit_issue(project, parent => 'A', child => 'a1')]
            real = view.custom_field_tag_for_bulk_edit('issue', child, issues, '').to_str
            bare = stubbed { view.custom_field_tag_for_bulk_edit('issue', child, issues, '').to_str }
            fragment = Nokogiri::HTML.fragment(real)
            select = fragment.at_css('select')

            expect(select['data-dcf-context']).to eq('bulk')
            expect(select['data-dcf-parent']).to eq(parent.id.to_s)
            expect(select['data-dcf-parent-values']).to be_nil
            expect(select['data-dcf-stored']).to be_nil
            expect(fragment.css('input')).to be_empty
            values = select.css('option').map { |o| o['value'] }
            expect(values.count('__none__')).to eq(1)
            expect(values.first(2)).to eq(['', '__none__'])
            marked = select.css('option[data-dcf-required-none]')
            expect(marked.map { |o| [o['value'], o['data-dcf-required-none'], o.text] })
              .to eq(required ? [['__none__', '1', I18n.t(:label_none)]] : [])
            # The option and the newline options_for_select joins it with.
            marked.each do |option|
              option.next.remove if option.next&.text? && option.next.text == "\n"
              option.remove
            end
            expect(without_dcf(fragment.to_html)).to eq(Nokogiri::HTML.fragment(bare).to_html)
          end
        end

        # WP-19: the id-less blank sentinel (server design 2.2), so a single
        # radio group posts '' when no radio is checked; the checked radio
        # comes later and wins (last-wins parsing).
        it 'prepends one id-less blank sentinel to a managed single radio group, required or not' do
          [false, true].each do |required|
            parent, child = styled(kind, 'check_box', required: required)
            issue = kit_issue(project, parent => 'A', child => 'a1')
            html = child.format.edit_tag(view, 'tag', "issue[custom_field_values][#{child.id}]", value_of(issue, child))
            doc = Nokogiri::HTML.fragment(html)
            sentinel = doc.at_css('input[data-dcf-blank]')

            expect(html).to be_a(ActiveSupport::SafeBuffer)
            expect(doc.css('input[data-dcf-blank]').size).to eq(1)
            expect(sentinel.attribute_nodes.map(&:name)).to eq(%w[type name value data-dcf-blank autocomplete])
            expect([sentinel['type'], sentinel['name'], sentinel['value'], sentinel['data-dcf-blank']])
              .to eq(['hidden', "issue[custom_field_values][#{child.id}]", '', '1'])
            expect(doc.element_children.first).to eq(sentinel)
            expect(sentinel.next_element.matches?('span.check_box_group[data-dcf-field][data-dcf-parent]')).to be(true)
            expect(doc.css('input[type=radio]').map { |radio| radio['name'] }.uniq).to eq([sentinel['name']])
            expect(html.scan(' id="')).to eq([])
          end
        end

        # WP-19, open input from WP-17: core omits the '' option of a required
        # single select with a default value (only fields saved before the
        # clear-on-save rule hold one), so the runtime's selectedIndex = -1
        # would post nothing; the sentinel posts '' instead.
        it 'prepends the sentinel to a managed required single select without a blank option, keeping label for=' do
          parent, child = styled(kind, '', required: true)
          child.update_column(:default_value, kit_key(child, 'a1'))
          child = CustomField.find(child.id)
          issue = kit_issue(project, parent => 'A', child => 'a1')
          html = labelled(issue, child)
          doc = Nokogiri::HTML.fragment(html)
          select = doc.at_css('select')
          sentinel = doc.at_css('input[data-dcf-blank]')

          expect(select.css('option').map { |o| o['value'] }).not_to include('')
          expect(sentinel.next_element).to eq(select)
          expect([sentinel['name'], sentinel['value'], sentinel['id']]).to eq([select['name'], '', nil])
          expect(html.scan(' id="').size).to eq(1)
          expect(doc.at_css('label')['for']).to eq(select['id'])
          bare = stubbed { labelled(Issue.find(issue.id), child) }
          doc.css('input[data-dcf-blank]').each(&:remove)
          expect(without_dcf(doc.to_html)).to eq(Nokogiri::HTML.fragment(bare).to_html)

          child.update_column(:default_value, nil)
          html = labelled(Issue.find(issue.id), CustomField.find(child.id))
          expect(Nokogiri::HTML.fragment(html).css('input[data-dcf-blank]')).to be_empty
        end

        it 'adds neither the sentinel nor the marked (none) without parent data (unmanaged or ClientData failing)' do
          parent, hidden_parent_child = styled(kind, 'check_box', required: true)
          member = dcf_create_user("wp19-#{SecureRandom.hex(3)}")
          dcf_add_member(member, project, dcf_create_role(permissions: [:view_issues, :edit_issues]))
          parent.update!(visible: false, role_ids: [dcf_create_role(permissions: [:view_issues]).id])
          x, y = build_cycle(kind)
          own = styled(kind, 'check_box', required: true).last
          dangling = styled(kind, 'check_box', required: true).last
          variants = {
            'role-invisible parent' => hidden_parent_child,
            'self-parent' => write_store(own, 'parent_custom_field_id' => own.id),
            'dangling parent' => write_store(dangling, 'parent_custom_field_id' => CustomField.maximum(:id).to_i + 1_000),
            'cycle member' => write_store(x, 'edit_tag_style' => 'check_box'),
            'other cycle member' => write_store(y, 'edit_tag_style' => 'check_box'),
            'ClientData failing' => styled(kind, 'check_box', required: true).last
          }
          variants.each do |label, field|
            field.update_column(:is_required, true)
            field = CustomField.find(field.id)
            issue = kit_issue(project, field => [])
            allow(User).to receive(:current).and_return(label == 'role-invisible parent' ? member : dcf_admin)
            if label == 'ClientData failing'
              allow(rules).to receive(:mapping).and_raise(RuntimeError)
              allow(Rails.logger).to receive(:warn)
            end
            html = labelled(issue, field)
            bulk = view.custom_field_tag_for_bulk_edit('issue', field, [issue], '').to_str

            expect(field.edit_tag_style).to eq('check_box'), label
            expect(html).not_to include('data-dcf-blank'), label
            expect(html).not_to include('data-dcf-parent'), label
            expect(bulk).not_to include('__none__'), label
            expect(bulk).not_to include('data-dcf-required-none'), label
          end
        end

        # WP-19 drift guard: the reimplemented body of a required child gives
        # core's own output for the same field when it is not required, plus
        # the data attributes; '__none__' sits in the same slot.
        it 'renders the marked (none) exactly where core puts its own (none), single and multi' do
          [false, true].each do |multiple|
            parent, child = styled(kind, '', multiple: multiple, required: true)
            issues = [kit_issue(project, parent => 'A', child => multiple ? %w[a1] : 'a1'),
                      kit_issue(project, parent => 'B', child => multiple ? %w[b1] : 'b1')]
            real = view.custom_field_tag_for_bulk_edit('issue', child, issues, '').to_str
            optional = CustomField.find(child.id)
            optional.is_required = false
            core = stubbed { view.custom_field_tag_for_bulk_edit('issue', optional, issues, '').to_str }
            options = Nokogiri::HTML.fragment(real).css('option')

            label = multiple ? 'multi' : 'single'
            expect(without_dcf(real)).to eq(Nokogiri::HTML.fragment(core).to_html), label
            expect(options.map { |o| o['value'] }.first(multiple ? 1 : 2)).to eq(multiple ? ['__none__'] : ['', '__none__']), label
            expect(options.select { |o| o['data-dcf-required-none'] }.map { |o| o['value'] }).to eq(['__none__']), label
            expect(real).to include('<option data-dcf-required-none="1" value="__none__">'), label
            selected = view.custom_field_tag_for_bulk_edit('issue', child, issues, '__none__').to_str
            expect(Nokogiri::HTML.fragment(selected).css('option[selected]').map { |o| o['value'] }).to eq(['__none__']), label
          end
        end

        it 'labels the marked (none) with the core label_none of the current locale' do
          parent, child = styled(kind, '', required: true)
          issues = [kit_issue(project, parent => 'A', child => 'a1')]
          locales.each do |locale|
            text = I18n.with_locale(locale) do
              Nokogiri::HTML.fragment(view.custom_field_tag_for_bulk_edit('issue', child, issues, '').to_str)
                        .at_css('option[data-dcf-required-none]').text
            end
            expect(text).to eq(I18n.t(:label_none, locale: locale)), locale
            expect(text).not_to match(/translation.missing/i), locale
          end
        end

        it 'asks ClientData once per edit tag and per bulk tag' do
          parent, child = styled(kind, 'check_box', required: true)
          issue = kit_issue(project, parent => 'A', child => 'a1')
          allow(client).to receive(:attributes_for).and_call_original
          labelled(issue, child)
          view.custom_field_tag_for_bulk_edit('issue', child, [issue], '')

          expect(client).to have_received(:attributes_for).with(child, hash_including(context: :form)).once
          expect(client).to have_received(:attributes_for).with(child, hash_including(context: :bulk)).once
        end
      end
    end

    it 'never changes the caller options and keeps the caller data keys' do
      parent, child = build_kit(:list)
      issue = kit_issue(project, parent => 'A', child => 'a1')
      value = value_of(issue, child)
      caller_data = { foo: 1 }.freeze
      options = { class: 'x', data: caller_data }.freeze
      html = child.format.edit_tag(view, 'tag', "issue[custom_field_values][#{child.id}]", value, options)
      select = Nokogiri::HTML.fragment(html).at_css('select')

      expect(select['data-foo']).to eq('1')
      expect(select['data-dcf-field']).to eq(child.id.to_s)
      expect(options).to eq(class: 'x', data: { foo: 1 })
      expect(caller_data).to eq(foo: 1)
      [{ data: nil }, {}].each do |opts|
        html = child.format.edit_tag(view, 'tag', "issue[custom_field_values][#{child.id}]", value, opts)
        expect(Nokogiri::HTML.fragment(html).at_css('select')['data-dcf-field']).to eq(child.id.to_s)
      end
      html = child.format.edit_tag(view, 'tag', "issue[custom_field_values][#{child.id}]", value)
      expect(Nokogiri::HTML.fragment(html).at_css('select')['data-dcf-field']).to eq(child.id.to_s)
    end

    it 'renders the field without any data-dcf-* attribute when ClientData fails (fail open)' do
      parent, child = build_kit(:list)
      issue = kit_issue(project, parent => 'A', child => 'a1')
      allow(rules).to receive(:mapping).and_raise(RuntimeError)
      allow(Rails.logger).to receive(:warn)
      html = labelled(issue, child)
      doc = Nokogiri::HTML.fragment(html)

      expect(doc.at_css('select')).not_to be_nil
      expect(html).not_to include('data-dcf-')
      expect(doc.at_css('label')['for']).to eq(doc.at_css('select')['id'])
      expect(Rails.logger).to have_received(:warn).with(/\[DCF\].*RuntimeError/)
    end

    # G5: every interpolation is escaped once; the decoded attributes parse
    # back to the source data.
    it 'escapes keys, values and the parent name exactly once and keeps the JSON parseable' do
      tricky = ['<b>"x"&', '[x]', 'a]', 'semi;colon', '"><script>alert(1)</script>', '</script>', "O'Brien",
                "Ünïcødé ñ", ' id="x"', "tab\tin"]
      parent = dcf_list_field(values: tricky, name: 'x" id="evil <b>&')
      child = dcf_list_field(format: 'depending_list', values: tricky, parent: parent)
      mapping = tricky.to_h { |value| [value, tricky.reverse] }
      child.update_column(:format_store, child.format_store.merge('value_dependencies' => mapping,
                                                                 'default_value_dependencies' => { tricky.first => tricky.last }))
      issue = kit_issue(project, parent => tricky.first, child => tricky.last)
      html = labelled(issue, CustomField.find(child.id))
      select = Nokogiri::HTML.fragment(html).at_css('select')

      expect(JSON.parse(select['data-dcf-map'])).to eq(mapping)
      expect(JSON.parse(select['data-dcf-defaults'])).to eq(tricky.first => tricky.last)
      expect(JSON.parse(select['data-dcf-parent-values'])).to eq([tricky.first])
      expect(JSON.parse(select['data-dcf-stored'])).to eq('child' => [tricky.last], 'parent' => [tricky.first])
      expect(select['data-dcf-parent-label']).to eq(parent.name)
      expect(html).not_to include('&amp;quot;')
      expect(html).not_to include('&amp;amp;')
      expect(html).not_to include('&amp;lt;')
      expect(html).not_to include('<script>')
      expect(html).not_to include('<b>')
      expect(html.scan(/ id="(.+?)"/).size).to eq(1)
      expect(Nokogiri::HTML.fragment(html).at_css('label')['for']).to eq(select['id'])
      html.scan(/ data-dcf-[a-z-]+="([^"]*)"/).flatten.each { |raw| expect(raw).not_to include('<') }
    end

    it 'escapes the parent name derived from an unusual tag name exactly once' do
      parent, child = build_kit(:list)
      issue = kit_issue(project, parent => 'A', child => 'a1')
      prefix = 'x"<y> &z'
      html = child.format.edit_tag(view, 'tag', "#{prefix}[custom_field_values][#{child.id}]", value_of(issue, child))
      select = Nokogiri::HTML.fragment(html).at_css('select')

      expect(select['data-dcf-parent-name']).to eq("#{prefix}[custom_field_values][#{parent.id}]")
      expect(html).to include("data-dcf-parent-name=\"x&quot;&lt;y&gt; &amp;z[custom_field_values][#{parent.id}]\"")
      expect(html).not_to include('&amp;quot;')
    end

    it 'escapes the sentinel name of an unusual tag name exactly once (WP-19)' do
      parent, child = build_kit(:list)
      child.update!(edit_tag_style: 'check_box')
      child = CustomField.find(child.id)
      issue = kit_issue(project, parent => 'A', child => 'a1')
      name = "x\"<y> &z[custom_field_values][#{child.id}]"
      html = child.format.edit_tag(view, 'tag', name, value_of(issue, child))
      sentinel = Nokogiri::HTML.fragment(html).at_css('input[data-dcf-blank]')

      expect(sentinel['name']).to eq(name)
      expect(html).to include("<input type=\"hidden\" name=\"x&quot;&lt;y&gt; &amp;z[custom_field_values][#{child.id}]\" value=\"\"")
      expect(html).not_to include('&amp;quot;')
      expect(html).not_to include('<y>')
    end

    # WP-19: bulk_edit_tag reimplements core List#bulk_edit_tag for required
    # managed children; a change of core's body (identical on 5.1 to 7.0)
    # must fail here first.
    it 'pins the core List#bulk_edit_tag body it reimplements for required children' do
      file, line = Redmine::FieldFormat::List.instance_method(:bulk_edit_tag).source_location
      lines = File.readlines(file)[(line - 1)..]
      indent = lines.first[/\A */]
      body = lines.take_while.with_index { |text, i| i.zero? || !text.start_with?("#{indent}end") }
      source = (body + [lines[body.size]]).map(&:strip).join("\n")

      expect(source).to include("opts << [l(:label_none), '__none__'] unless custom_field.is_required?")
      # The same 11 stripped lines on 5.1, 6.0, 6.1 and 7.0.
      expect(Digest::SHA256.hexdigest(source)).to eq('399c63f4f7dec0ecf5958609eb7e13b55c4e7b4840fd4212a6fd2764725797d6')
    end
  end

  # WP-06 also removed QueryCustomFieldColumnPatch, a no-op: core sets
  # sortable from order_statement and ignores options[:sortable].
  describe 'query columns without QueryCustomFieldColumnPatch' do
    before { allow(User).to receive(:current).and_return(dcf_admin) }

    it 'keeps core sortability for every list-like custom field column' do
      expect(defined?(RedmineDependingCustomFields::Patches::QueryCustomFieldColumnPatch)).to be_nil
      init = File.read(File.expand_path('../../init.rb', __dir__))
      expect(init).not_to match(/QueryCustomFieldColumn|^Query$/)

      parent, child = build_kit(:list)
      enum_child = build_kit(:enumeration).last
      multiple = dcf_list_field(values: %w[x y], multiple: true)
      columns = IssueQuery.new(name: '_').available_columns
      expect(QueryCustomFieldColumn.ancestors.map(&:to_s).grep(/RedmineDependingCustomFields/)).to eq([])
      [parent, child, enum_child, multiple].each do |field|
        column = columns.detect { |c| c.name == :"cf_#{field.id}" }
        expect(column.sortable).to eq(field.order_statement || false), field.field_format
      end
      issue_column = TimeEntryQuery.new(name: '_').available_columns.detect { |c| c.name == :"issue.cf_#{child.id}" }
      expect(issue_column.sortable).to be(false)
    end
  end
end
