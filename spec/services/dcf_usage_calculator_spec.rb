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
      expect(scope).to receive(:group).with('CAST(custom_values.value AS BINARY)').and_return(grouped)
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
