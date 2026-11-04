require_relative '../rails_helper'

RSpec.describe RedmineDependingCustomFields::UsageCalculator do
  let(:project) { dcf_create_project(name: 'A') }
  let(:other)   { dcf_create_project(name: 'B') }

  describe 'CustomValue usage counts (T-USE-1/2)' do
    it 'counts usage in this project and in other projects separately' do
      field = dcf_list_field(values: %w[A B], is_for_all: true)
      dcf_issue_with_value(project, field, 'A')
      dcf_issue_with_value(project, field, 'A')
      dcf_issue_with_value(other, field, 'A')

      expect(described_class.usage_here(field, 'A', project)).to eq(2)
      expect(described_class.usage_other(field, 'A', project)).to eq(1)
      expect(described_class.usage_total(field, 'A')).to eq(3)
    end
  end

  describe 'dependency reference counts on both sides (T-USE-4)' do
    it 'counts own-side child refs and parent-side refs' do
      parent = dcf_list_field(name: 'Parent', values: %w[A B], is_for_all: true)
      child = dcf_list_field(format: 'depending_list', name: 'Child', values: %w[c1 c2],
                             parent: parent, is_for_all: true)
      dcf_set_dependencies(child, value_dependencies: { 'A' => %w[c1], 'B' => %w[c1] })

      # 'c1' appears twice as a child value in the child's own store.
      expect(described_class.own_dep_refs(child, 'c1')).to eq(2)
      # 'A' is used as a parent key in one depending child.
      expect(described_class.parent_key_refs(parent, 'A')).to eq(1)
      expect(described_class.affected_child_fields(parent, 'A').map(&:id)).to eq([child.id])
    end
  end
end

# WP-28 (project design 5 'Show usage', T-USE-7, SD-16).
RSpec.describe 'RedmineDependingCustomFields::UsageCalculator (WP-28)' do
  let(:calculator) { RedmineDependingCustomFields::UsageCalculator }
  let(:project) { dcf_create_project(name: 'A') }
  let(:other)   { dcf_create_project(name: 'B') }

  def per_value(field, key, in_project)
    [calculator.usage_here(field, key, in_project), calculator.usage_other(field, key, in_project),
     calculator.own_dep_refs(field, key) + calculator.parent_key_refs(field, key)]
  end

  def page_form(field, keys, in_project)
    calculator.page_usage(field, keys, in_project).transform_values { |u| [u.here, u.other, u.refs] }
  end

  describe '.page_usage (T-USE-7)' do
    it 'equals the per-value methods for an issue field with children and own references' do
      grand = dcf_list_field(name: 'Grand', values: %w[G1 G2])
      field = dcf_list_field(format: 'depending_list', name: 'Parent', values: %w[A B C D], parent: grand)
      dcf_set_dependencies(field, value_dependencies: { 'G1' => %w[A B], 'G2' => %w[A] },
                                  default_value_dependencies: { 'G1' => 'A', 'G2' => %w[A B] })
      child = dcf_list_field(format: 'depending_list', name: 'Child', values: %w[c1 c2], parent: field)
      dcf_set_dependencies(child, value_dependencies: { 'A' => %w[c1], 'B' => %w[c2] },
                                  default_value_dependencies: { 'A' => 'c1' })
      hidden = dcf_list_field(format: 'depending_list', name: 'Hidden', values: %w[h1], parent: field)
      dcf_set_dependencies(hidden, value_dependencies: { 'A' => %w[h1], 'C' => %w[h1] },
                                   default_value_dependencies: { 'C' => 'h1' })
      hidden.update!(visible: false, role_ids: [dcf_create_role.id])
      2.times { dcf_issue_with_value(project, field, 'A') }
      dcf_issue_with_value(other, field, 'A')
      dcf_issue_with_value(other, field, 'B')
      dcf_issue_with_value(project, field, 'C')
      field = CustomField.find(field.id)
      keys = %w[A B C D]

      expected = keys.to_h { |key| [key, per_value(field, key, project)] }
      expect(page_form(field, keys, project)).to eq(expected)
      expect(expected['A']).to eq([2, 1, 3 + 4])
      expect(expected['D']).to eq([0, 0, 0])
    end

    it 'equals the per-value methods for a ProjectCustomField' do
      field = dcf_list_field(type: ProjectCustomField, values: %w[P Q R])
      CustomValue.create!(customized_type: 'Project', customized_id: project.id, custom_field_id: field.id, value: 'P')
      CustomValue.create!(customized_type: 'Project', customized_id: other.id, custom_field_id: field.id, value: 'P')
      CustomValue.create!(customized_type: 'Project', customized_id: other.id, custom_field_id: field.id, value: 'Q')
      keys = %w[P Q R]

      expect(page_form(field, keys, project)).to eq(keys.to_h { |key| [key, per_value(field, key, project)] })
      expect(page_form(field, keys, project)['P']).to eq([1, 1, 0])
    end

    it 'counts exactly, without the per-value cap' do
      stub_const('RedmineDependingCustomFields::UsageCalculator::USAGE_CAP', 1)
      field = dcf_list_field(values: %w[A])
      3.times { dcf_issue_with_value(project, field, 'A') }
      expect(page_form(field, %w[A], project)).to eq('A' => [3, 0, 0])
    end

    it 'answers every requested key, zeros included, and nothing for no keys' do
      field = dcf_list_field(values: %w[A B])
      expect(page_form(field, %w[A B], project)).to eq('A' => [0, 0, 0], 'B' => [0, 0, 0])
      expect(calculator.page_usage(field, [], project)).to eq({})
    end

    it 'runs the same number of queries for 2 and for 25 keys' do
      field = dcf_list_field(values: (1..25).map { |i| "V#{i}" })
      child = dcf_list_field(format: 'depending_list', name: 'Child', values: %w[c1], parent: field)
      dcf_set_dependencies(child, value_dependencies: { 'V1' => %w[c1] })
      field = CustomField.find(field.id)
      calculator.page_usage(field, %w[V1], project)
      small = dcf_count_queries { calculator.page_usage(field, %w[V1 V2], project) }
      large = dcf_count_queries { calculator.page_usage(field, field.possible_values, project) }
      expect(large).to eq(small)
    end

    # MySQL and MariaDB compare TEXT with a case- and accent-insensitive
    # collation; the counts stay byte-exact on every database.
    it 'counts values that differ only in case or accents apart' do
      field = dcf_list_field(values: ['A', 'a', 'Muller', "Müller"])
      2.times { dcf_issue_with_value(project, field, 'A') }
      dcf_issue_with_value(project, field, 'a')
      dcf_issue_with_value(other, field, 'a')
      dcf_issue_with_value(other, field, "Müller")
      expect(page_form(field, ['A', 'a', 'Muller', "Müller"], project))
        .to eq('A' => [2, 0, 0], 'a' => [1, 1, 0], 'Muller' => [0, 0, 0], "Müller" => [0, 1, 0])
      expect(page_form(field, ['a'], project)).to eq('a' => [1, 1, 0])
    end

    it 'groups by the bytes of the value on MySQL and reads the keys back as UTF-8' do
      allow(Redmine::Database).to receive(:mysql?).and_return(true)
      grouped = instance_double(ActiveRecord::Relation, count: { 'A'.b => 2, "Müller".b => 1 })
      scope = instance_double(ActiveRecord::Relation)
      # Changed by WP-33: the shared byte expression, UTF-8 bytes whatever the column character set.
      expect(scope).to receive(:group).with('CAST(CONVERT(custom_values.value USING utf8mb4) AS BINARY)').and_return(grouped)
      counts = calculator.grouped_value_counts(scope)
      expect(counts).to eq('A' => 2, "Müller" => 1)
      expect(counts.keys.map(&:encoding).uniq).to eq([Encoding::UTF_8])
    end

    it 'groups by the value column elsewhere' do
      allow(Redmine::Database).to receive(:mysql?).and_return(false)
      grouped = instance_double(ActiveRecord::Relation, count: { 'A' => 1 })
      scope = instance_double(ActiveRecord::Relation)
      expect(scope).to receive(:group).with(:value).and_return(grouped)
      expect(calculator.grouped_value_counts(scope)).to eq('A' => 1)
    end
  end

  describe '.nameable_child? (SD-16)' do
    let(:manager) { dcf_manager(project) }
    let(:parent) { dcf_list_field(name: 'Parent', values: %w[A]) }

    def child(name, **options)
      dcf_list_field(format: 'depending_list', name: name, values: %w[c1], parent: parent, **options)
    end

    def service_rule(record, user)
      service = RedmineDependingCustomFields::RenameValueService.new(project: project, field: parent, user: user,
                                                                      params: {})
      service.send(:nameable_field?, record)
    end

    it 'follows the WP-12 rule of BaseService#nameable_field? for every case' do
      visible = child('Visible')
      hidden = child('Hidden')
      hidden.update!(visible: false, role_ids: [dcf_create_role.id])
      outside = child('Outside', is_for_all: false, projects: [other])
      own_role = manager.members.first.roles.first
      restricted = child('Restricted')
      restricted.update!(visible: false, role_ids: [own_role.id])
      time_entry = TimeEntryCustomField.create!(name: 'Spent', field_format: 'list', possible_values: %w[x])
      records = [parent, visible, hidden, outside, restricted, time_entry]

      [manager, dcf_admin].each do |user|
        records.each do |record|
          expect(calculator.nameable_child?(record, parent, project, user)).to eq(service_rule(record, user)),
                                                                                "#{record.name} for #{user.login}"
        end
      end
      expect(records.select { |r| calculator.nameable_child?(r, parent, project, manager) }.map(&:name))
        .to eq(%w[Parent Visible Restricted])
      expect(records.all? { |r| calculator.nameable_child?(r, parent, project, dcf_admin) }).to be(true)
    end

    it 'fails closed when a check raises' do
      record = child('Broken')
      allow(record).to receive(:visible_by?).and_raise(StandardError)
      expect(calculator.nameable_child?(record, parent, project, manager)).to be(false)
    end
  end
end

# WP-33 (SD-17): one helper selects the CustomValue rows of a value byte for
# byte; usage_here, usage_other, usage_total, page_usage and the rename go
# through it.
RSpec.describe 'RedmineDependingCustomFields::UsageCalculator exact values (WP-33)' do
  let(:calculator) { RedmineDependingCustomFields::UsageCalculator }
  let(:project) { dcf_create_project(name: 'A') }
  let(:other)   { dcf_create_project(name: 'B') }
  let(:field) { dcf_list_field(values: ['A', 'a', "\u00c1", 'Muller', "M\u00fcller"]) }
  let(:binary) { 'CAST(CONVERT(custom_values.value USING utf8mb4) AS BINARY)' }

  def per_value(key)
    [calculator.usage_here(field, key, project), calculator.usage_other(field, key, project),
     calculator.own_dep_refs(field, key) + calculator.parent_key_refs(field, key)]
  end

  it 'gives the same counts per value and per page for keys that differ only in case, accents or a trailing space' do
    2.times { dcf_issue_with_value(project, field, 'A') }
    dcf_issue_with_value(project, field, 'a')
    dcf_issue_with_value(other, field, 'a')
    dcf_issue_with_value(other, field, "\u00c1")
    dcf_issue_with_value(project, field, 'A ')
    dcf_issue_with_value(other, field, "M\u00fcller")
    keys = ['A', 'a', "\u00c1", 'A ', 'Muller', "M\u00fcller"]
    page = calculator.page_usage(field, keys, project).transform_values { |u| [u.here, u.other, u.refs] }
    expect(page).to eq(keys.to_h { |key| [key, per_value(key)] })
    expect(page).to eq('A' => [2, 0, 0], 'a' => [1, 1, 0], "\u00c1" => [0, 1, 0], 'A ' => [1, 0, 0],
                       'Muller' => [0, 0, 0], "M\u00fcller" => [0, 1, 0])
    expect(calculator.usage_total(field, 'A')).to eq(2)
  end

  it 'compares the bytes on MySQL and MariaDB, one value or a list, values bound as strings' do
    allow(Redmine::Database).to receive(:mysql?).and_return(true)
    plain = CustomValue.where(custom_field_id: field.id, value: 'A').to_sql
    one = calculator.value_rows(field, 'A').to_sql
    expect(one).to start_with(plain)
    expect(one).to include("#{binary} = 'A'")
    list = calculator.value_rows(field, ['A', 12]).to_sql
    expect(list).to match(/#{Regexp.escape(binary)} IN \('A', ?'12'\)/)
    expect(calculator.value_rows(field, 12).to_sql).to include("#{binary} = '12'")
  end

  it 'is the plain value predicate elsewhere' do
    allow(Redmine::Database).to receive(:mysql?).and_return(false)
    expect(calculator.value_rows(field, 'A').to_sql).to eq(CustomValue.where(custom_field_id: field.id, value: 'A').to_sql)
    expect(calculator.value_rows(field, ['A', 12]).to_sql)
      .to eq(CustomValue.where(custom_field_id: field.id, value: %w[A 12]).to_sql)
    expect(calculator.value_rows(field, 'A').to_sql).not_to include('CAST')
  end

  # Every code line of app/ and lib/ that names CustomValue, custom_values or
  # a value key, listed exactly: a new lookup of stored values by value, in
  # any shape or file type, fails here until it goes through value_rows and
  # a reviewer adds its line. Changed by WP-38: the line of
  # time_entry_validation_patch.rb reads the rows the entry already loaded
  # (no lookup by value).
  it 'is the only lookup of stored values by value in app/ and lib/ (static)' do
    root = File.expand_path('../..', __dir__)
    pattern = Regexp.union(/\bvalue:/, /\[:value\]/, /\(\s*:value\b/, /\bcustom_values\b/, /\bCustomValue\b/,
                           /['"]value\s*(?:=|IN\b)/)
    hits = Dir[File.join(root, '{app,lib}/**/*.{rb,rake,erb}')].sort.flat_map do |file|
      File.read(file, encoding: 'UTF-8').gsub(/<%#.*?%>/m, '').lines
          .reject { |line| line.lstrip.start_with?('#') }.grep(pattern)
          .map { |line| "#{File.basename(file)}: #{line.strip}" }
    end
    listed = <<~'LINES'.lines(chomp: true)
      context_menu_wizard_controller.rb: val = permitted[:value]
      project_custom_field_configuration_controller.rb: added = value_params[:value].to_s.strip
      project_custom_field_configuration_controller.rb: out = params.permit(:value, :position, :old_value, :new_value, :enumeration_id,
      add_value_service.rb: v = normalize(@params[:value])
      base_service.rb: [CustomField, CustomValue, CustomFieldEnumeration, ConfigAuditEvent].any? do |model|
      base_service.rb: raise OperationError.new(:error_dcf_value_length, summary: "value: #{value.length} characters exceeds #{max}",
      base_service.rb: value: value, usage_here: usage_here, usage_other: usage_other,
      remove_value_service.rb: value = @params[:value].to_s
      rename_value_service.rb: rows = UsageCalculator.value_rows(field, old).update_all(value: nv)
      usage_calculator.rb: rows = CustomValue.where(custom_field_id: field.id, value: values)
      usage_calculator.rb: "CAST(CONVERT(#{CustomValue.table_name}.value USING utf8mb4) AS BINARY)"
      usage_calculator.rb: return scope.group(:value).count unless Redmine::Database.mysql?
      show.html.erb: params: { value: row.key, state_hash: @state_hash }.merge(list_state),
      dependency_rules.rb: if customized.respond_to?(:custom_values)
      dependency_rules.rb: stored = customized.custom_values.any? { |cv| cv.custom_field_id == field_id && cv.persisted? }
      non_editable_dependencies.rb: def id_set(custom_values)
      non_editable_dependencies.rb: Set.new(custom_values.map(&:custom_field_id))
      time_entry_validation_patch.rb: saved = entry.custom_values.select(&:persisted?)
    LINES
    expect(hits).to eq(listed), "not listed:\n#{(hits - listed).join("\n")}\nno longer found:\n#{(listed - hits).join("\n")}"
  end

  # No DDL: one derived row per stored value and collation, aliased as
  # custom_values, so the helper's own predicate runs under each collation
  # and character set (focus: PAD SPACE, ignorable and supplementary
  # characters, latin1 and utf8mb3 columns).
  describe 'collations and character sets', :mysql do
    let(:connection) { ActiveRecord::Base.connection }
    let(:pairs) do
      [%w[A A], %w[A a], ['A', "\u00c1"], ['A', 'A '], ['A', "A\u00a0"], ['A', "A\u0000"], ['A', "A\u200b"],
       ['A', "\uff21"], ["\u00df", 'ss'], ["\u{1F34E}", "\u{1F350}"], ["\u{1F34E}", "\u{1F34E}"], ["M\u00fcller", "M\u00fcller"]]
    end

    # MariaDB lists the UCA 14 collations without a charset prefix; asking
    # the server covers both spellings.
    def available(names)
      names.select do |name|
        connection.select_value("SELECT CONVERT('a' USING #{name.split('_').first}) COLLATE #{name}")
        true
      rescue ActiveRecord::StatementInvalid
        false
      end
    end

    def count(scope, charset, collation, stored)
      table = "(SELECT CONVERT(#{connection.quote(stored)} USING #{charset}) COLLATE #{collation} AS value, " \
              "#{field.id} AS custom_field_id) custom_values"
      scope.from(Arel.sql(table)).count
    end

    it 'matches exactly the same bytes under every utf8mb4 collation, where the plain predicate does not' do
      collations = available(%w[utf8mb4_general_ci utf8mb4_unicode_ci utf8mb4_unicode_520_ci utf8mb4_bin
                                utf8mb4_uca1400_ai_ci utf8mb4_0900_ai_ci])
      expect(collations).to include('utf8mb4_general_ci', 'utf8mb4_unicode_ci', 'utf8mb4_bin')
      collations.each do |collation|
        loose = 0
        pairs.each do |stored, probe|
          exact = stored.b == probe.b ? 1 : 0
          expect(count(calculator.value_rows(field, probe), 'utf8mb4', collation, stored)).to eq(exact),
                                                                                              "#{collation} #{stored.inspect} #{probe.inspect}"
          loose += 1 if count(CustomValue.where(custom_field_id: field.id, value: probe), 'utf8mb4', collation, stored) != exact
        end
        expect(loose).to be_positive, "#{collation} has a collation-equal pair"
      end
    end

    it 'compares the UTF-8 bytes on utf8mb3 and latin1 columns without an error' do
      values = [%w[A A], %w[A a], ["\u00c1", "\u00c1"], ["\u00c1", "\u00e1"], ['A', 'A ']]
      [%w[utf8mb3 utf8mb3_general_ci], %w[latin1 latin1_swedish_ci]].each do |charset, collation|
        next if available([collation]).empty?

        values.each do |stored, probe|
          expect(count(calculator.value_rows(field, probe), charset, collation, stored)).to eq(stored == probe ? 1 : 0),
                                                                                              "#{collation} #{stored.inspect} #{probe.inspect}"
        end
      end
    end

    it 'keeps the access path of the plain predicate (the byte compare is a residual filter)' do
      %w[A a B].each { |value| 3.times { dcf_issue_with_value(project, field, value) } }
      explain = ->(scope) { connection.select_all("EXPLAIN #{scope.to_sql}").to_a.first.slice('type', 'key') }
      expect(explain.call(calculator.value_rows(field, 'A')))
        .to eq(explain.call(CustomValue.where(custom_field_id: field.id, value: 'A')))
    end
  end
end
