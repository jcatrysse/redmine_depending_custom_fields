# frozen_string_literal: true

require_relative '../rails_helper'

# WP-16: ClientData, the issue-form data contract of one depending field
# (server design 2.2 and 6). Unit assertions on the Hash only; the rendered
# markup is pinned by spec/frontend/markup_fixtures_spec.rb and the requests
# by spec/requests/issue_form_contract_spec.rb.
RSpec.describe RedmineDependingCustomFields::ClientData do
  include DcfFormatCharacterization
  include DcfStoredCycle

  fixtures :users

  let(:client) { described_class }
  let(:rules) { RedmineDependingCustomFields::DependencyRules }
  let(:project) { dcf_create_project }
  let(:role) { dcf_create_role(permissions: [:view_issues, :edit_issues]) }
  let(:other_role) { dcf_create_role(permissions: [:view_issues]) }
  let(:member) do
    user = dcf_create_user("cd-#{SecureRandom.hex(3)}")
    dcf_add_member(user, project, role)
    user
  end

  def value_of(record, field)
    record.custom_field_values.detect { |v| v.custom_field_id == field.id }
  end

  def tag_name_for(field, prefix = 'issue')
    name = "#{prefix}[custom_field_values][#{field.id}]"
    field.multiple? ? "#{name}[]" : name
  end

  # attributes_for in form context for +field+ on +record+, with the
  # instance core renders (the record's custom field value).
  def form_data(record, field, user: dcf_admin, tag_name: nil)
    cv = value_of(record, field)
    client.attributes_for(cv.custom_field, context: :form, customized: record, custom_value: cv,
                                           tag_name: tag_name || tag_name_for(field), user: user)
  end

  def bulk_data(objects, field, user: dcf_admin)
    client.attributes_for(field, context: :bulk, objects: objects, tag_name: tag_name_for(field), user: user)
  end

  def every_field(field, context = 'form')
    data = { dcf_field: field.id, dcf_context: context, dcf_kind: rules.kind(field) }
    data[:dcf_multiple] = 1 if field.multiple?
    data
  end

  def restrict(field)
    field.update!(visible: false, role_ids: [other_role.id])
    CustomField.find(field.id)
  end

  describe '.attributes_for' do
    it 'returns nothing for fields that are not depending' do
      [dcf_list_field, dcf_enum_field, dcf_list_field(format: 'string', values: [])].each do |field|
        expect(client.attributes_for(field, context: :form)).to eq({})
        expect(client.attributes_for(field, context: :bulk, objects: [])).to eq({})
      end
    end

    [:list, :enumeration].each do |kind|
      context "for a depending #{kind}" do
        let(:kit) { build_kit(kind) }
        let(:parent) { kit.first }
        let(:child) { kit.last }

        it 'emits only the every-field attributes for a field without a parent, a multi field adds multiple' do
          single = kind == :list ? dcf_list_field(format: 'depending_list') : dcf_enum_field(format: 'depending_enumeration')
          multi = kind == :list ? dcf_list_field(format: 'depending_list', multiple: true) : dcf_enum_field(format: 'depending_enumeration')
          multi.update!(multiple: true)
          issue = kit_issue(project, single => [], multi => [])

          expect(form_data(issue, single)).to eq(every_field(single))
          expect(form_data(issue, multi)).to eq(every_field(CustomField.find(multi.id)))
          expect(form_data(issue, multi)[:dcf_multiple]).to eq(1)
          expect(bulk_data([issue], single)).to eq(every_field(single, 'bulk'))
        end

        it 'emits the managed form attributes in the contract order for a persisted issue' do
          issue = kit_issue(project, parent => 'A', child => 'a1')
          data = form_data(issue, child)

          expect(data.keys).to eq([:dcf_field, :dcf_context, :dcf_kind, :dcf_parent, :dcf_parent_name, :dcf_map,
                                   :dcf_defaults, :dcf_parent_values, :dcf_parent_label, :dcf_stored])
          expect(data[:dcf_parent]).to eq(parent.id)
          expect(data[:dcf_parent_name]).to eq("issue[custom_field_values][#{parent.id}]")
          expect(data[:dcf_parent_values]).to eq([kit_key(parent, 'A')])
          expect(data[:dcf_parent_label]).to eq(parent.name)
          expect(data[:dcf_stored]).to eq('child' => [kit_key(child, 'a1')], 'parent' => [kit_key(parent, 'A')])
          expect(data[:dcf_context]).to eq('form')
        end

        it 'carries the sanitized, unpruned mapping, with canonical enumeration ids as integers' do
          mapping = rules.mapping(child).merge('orphan-key' => [kit_key(child, 'b1')])
          child.update_column(:format_store, child.format_store.merge('value_dependencies' => mapping))
          issue = kit_issue(project, parent => 'A', child => 'a1')
          data = form_data(issue, child)
          expected = mapping.transform_values do |values|
            kind == :list ? values : values.map(&:to_i)
          end

          expect(data[:dcf_map]).to eq(expected)
          expect(data[:dcf_map].keys).to all(be_a(String))
          expect(data[:dcf_defaults]).to eq(kit_key(parent, 'A') => (kind == :list ? 'a2' : kit_key(child, 'a2').to_i))
        end

        it 'emits hide only when hide_when_disabled is set, in both contexts' do
          issue = kit_issue(project, parent => 'A', child => 'a1')
          expect(form_data(issue, child)).not_to have_key(:dcf_hide)

          child.update!(hide_when_disabled: '1')
          issue = Issue.find(issue.id)
          expect(form_data(issue, child)[:dcf_hide]).to eq(1)
          expect(bulk_data([issue], CustomField.find(child.id))[:dcf_hide]).to eq(1)
        end

        it 'emits no defaults key when the stored defaults are empty and {} for an empty map' do
          child.update_column(:format_store, child.format_store.merge('value_dependencies' => {},
                                                                     'default_value_dependencies' => {}))
          issue = kit_issue(project, parent => 'A', child => [])
          data = form_data(issue, child)

          expect(data[:dcf_map]).to eq({})
          expect(data).not_to have_key(:dcf_defaults)
        end

        it 'gives [] parent values for a blank parent and stores [] for it' do
          issue = kit_issue(project, parent => [], child => [])
          data = form_data(issue, child)

          expect(data[:dcf_parent_values]).to eq([])
          expect(data[:dcf_stored]).to eq('child' => [], 'parent' => [])
        end

        it 'stores the legacy value from value_was, not the posted one' do
          issue = kit_issue(project, parent => 'A', child => 'b1')
          issue.custom_field_values = { child.id.to_s => kit_key(child, 'a1') }
          data = form_data(issue, child)

          expect(data[:dcf_stored]).to eq('child' => [kit_key(child, 'b1')], 'parent' => [kit_key(parent, 'A')])
        end

        it 'keeps the stored parent baseline when the parent value changed on the record (updateIssueFrom)' do
          issue = kit_issue(project, parent => 'A', child => 'a1')
          issue.custom_field_values = { parent.id.to_s => kit_key(parent, 'B') }
          data = form_data(issue, child)

          expect(data[:dcf_parent_values]).to eq([kit_key(parent, 'B')])
          expect(data[:dcf_stored]).to eq('child' => [kit_key(child, 'a1')], 'parent' => [kit_key(parent, 'A')])
        end

        it 'gives [] parent values and an empty child baseline while the parent is not available on the issue' do
          issue = kit_issue(project, parent => 'A', child => 'b1')
          issue.tracker.custom_fields.delete(parent)
          issue = Issue.find(issue.id)
          expect(value_of(issue, parent)).to be_nil
          data = form_data(issue, child)

          expect(data[:dcf_parent]).to eq(parent.id)
          expect(data[:dcf_parent_values]).to eq([])
          expect(data[:dcf_parent_label]).to eq(parent.name)
          expect(data[:dcf_stored]).to eq('child' => [], 'parent' => [])
        end

        it 'stores the copy source values for an issue copy and nothing for a plain new issue' do
          source = kit_issue(project, parent => 'A', child => 'b1')
          copy = Issue.new.copy_from(source)
          plain = kit_new_issue(project, parent => 'A', child => 'b1')

          expect(form_data(copy, child)[:dcf_stored]).to eq('child' => [kit_key(child, 'b1')],
                                                            'parent' => [kit_key(parent, 'A')])
          expect(form_data(plain, child)).not_to have_key(:dcf_stored)
          expect(form_data(plain, child)[:dcf_parent_values]).to eq([kit_key(parent, 'A')])
        end

        it 'gives the child an empty baseline when it has no saved row' do
          issue = kit_issue(project, parent => 'A')
          issue.tracker.custom_fields << child
          issue = Issue.find(issue.id)
          expect(issue.custom_values.map(&:custom_field_id)).not_to include(child.id)

          expect(form_data(issue, child)[:dcf_stored]).to eq('child' => [], 'parent' => [kit_key(parent, 'A')])
        end

        it 'emits only the every-field attributes for a role-invisible parent, the full set for an admin' do
          restricted = restrict(parent)
          issue = kit_issue(project, restricted => 'A', child => 'a1')

          expect(form_data(issue, child, user: member)).to eq(every_field(child))
          expect(form_data(Issue.find(issue.id), child, user: dcf_admin)[:dcf_parent]).to eq(parent.id)
        end

        it 'emits the parent attributes for a member who holds one of the parent roles' do
          parent.update!(visible: false, role_ids: [role.id])
          issue = kit_issue(project, CustomField.find(parent.id) => 'A', child => 'a1')

          expect(form_data(issue, child, user: member)[:dcf_parent]).to eq(parent.id)
        end

        # Their values come from another project: a copy's from the source,
        # a moved issue's stored baseline from the old project.
        it 'requires the parent to be visible in the source project of a copy and the old project of a move' do
          second_project = dcf_create_project
          dcf_issue_infra(second_project)
          dcf_add_member(member, second_project, other_role)
          restricted = restrict(parent) # other_role, held in second_project only
          in_first = kit_issue(project, restricted => 'A', child => 'a1')
          in_second = kit_issue(second_project, restricted => 'A', child => 'a1')
          copy = Issue.new.copy_from(in_first)
          copy.project = second_project
          same = Issue.new.copy_from(in_second)
          same.project = second_project
          moved = Issue.find(in_first.id)
          moved.project = second_project

          expect(form_data(copy, child, user: member)).to eq(every_field(child))
          expect(form_data(same, child, user: member)[:dcf_stored]).to eq('child' => [kit_key(child, 'a1')],
                                                                          'parent' => [kit_key(parent, 'A')])
          expect(form_data(moved, child, user: member)).to eq(every_field(child))
          expect(form_data(Issue.find(in_second.id), child, user: member)[:dcf_parent]).to eq(parent.id)
          expect(form_data(copy, child, user: dcf_admin)[:dcf_parent]).to eq(parent.id)
        end

        it 'counts a raising visible_by? as not visible (fail closed) and logs the class only' do
          issue = kit_issue(project, parent => 'A', child => 'a1')
          allow(value_of(issue, parent).custom_field).to receive(:visible_by?).and_raise(RuntimeError, 'boom')
          allow(Rails.logger).to receive(:warn)

          expect(form_data(issue, child)).to eq(every_field(child))
          expect(Rails.logger).to have_received(:warn)
            .with(/\A\[DCF\] client data visibility check failed for custom field ##{parent.id}: RuntimeError\z/)
          expect(Rails.logger).not_to have_received(:warn).with(/boom/)
        end

        it 'fails open: an error in the computation gives no attribute and logs the class only' do
          issue = kit_issue(project, parent => 'A', child => 'a1')
          allow(rules).to receive(:mapping).and_raise(RuntimeError, 'secret SQL and stored value')
          allow(Rails.logger).to receive(:warn)

          expect(form_data(issue, child)).to eq({})
          expect(Rails.logger).to have_received(:warn).with(/\A\[DCF\] .*##{child.id}: RuntimeError\z/)
          expect(Rails.logger).not_to have_received(:warn).with(/secret/)
        end

        it 'never loads the global field index' do
          issue = kit_issue(project, parent => 'A', child => 'a1')
          expect(RedmineDependingCustomFields::FieldIndex).not_to receive(:load)

          form_data(issue, child)
          bulk_data([issue], child)
        end

        # G6 forms: a carried parent costs what a field without a parent costs
        # (invariance); a parent the issue does not carry costs one query on
        # the first call and none on the second, measured against the same
        # call on a fresh record with the parent lookup stubbed (differential).
        it 'does not query for a parent carried by the issue and reuses the memoized lookup of one that is not' do
          admin = dcf_admin
          loaded = lambda do |id|
            record = Issue.find(id)
            record.custom_field_values
            record
          end
          cost = lambda do |record, field|
            cv = value_of(record, field)
            dcf_count_queries do
              client.attributes_for(cv.custom_field, context: :form, customized: record, custom_value: cv, user: admin)
            end
          end
          stubbed = lambda do |id|
            allow(rules).to receive(:parent_record).and_return(CustomField.find(parent.id))
            count = cost.call(loaded.call(id), child)
            allow(rules).to receive(:parent_record).and_call_original
            count
          end
          plain = kind == :list ? dcf_list_field(format: 'depending_list') : dcf_enum_field(format: 'depending_enumeration')
          issue = kit_issue(project, parent => 'A', child => 'a1', plain => [])
          record = loaded.call(issue.id)
          expect(cost.call(record, child)).to eq(cost.call(record, plain))

          issue.tracker.custom_fields.delete(parent)
          record = loaded.call(issue.id)
          expect(value_of(record, parent)).to be_nil
          first = cost.call(record, child)
          second = cost.call(record, child)
          baseline = stubbed.call(issue.id)
          expect([first - baseline, second - baseline]).to eq([1, 0])
        end
      end
    end

    describe 'topologies without an effective parent (UD-08, UD-35)' do
      [:list, :enumeration].each do |kind|
        it "emits only the every-field attributes for #{kind} cycle members, fields below a cycle and self-parents" do
          world = dcf_stored_cycles(kind)
          issue = kit_issue(project, world.depending.index_with([]))

          world.depending.each do |field|
            expect(form_data(issue, field)).to eq(every_field(field)), field.name
            expect(bulk_data([issue], CustomField.find(field.id))).to eq(every_field(field, 'bulk')), field.name
          end
        end

        it "emits only the every-field attributes for a dangling #{kind} parent" do
          _parent, child = build_kit(kind)
          child = dcf_store_parent(child, CustomField.maximum(:id).to_i + 1_000)
          issue = kit_issue(project, child => [])

          expect(form_data(issue, child)).to eq(every_field(child))
        end

        it "emits only the every-field attributes for a #{kind} parent of another type or family" do
          _parent, child = build_kit(kind)
          foreign_type = kind == :list ? dcf_list_field(type: ProjectCustomField) : dcf_enum_field(type: ProjectCustomField)
          foreign_family = kind == :list ? dcf_enum_field : dcf_list_field
          [foreign_type, foreign_family].each do |foreign|
            stored = dcf_store_parent(child, foreign)
            issue = kit_issue(project, stored => [])
            expect(form_data(issue, stored)).to eq(every_field(stored)), foreign.class.name
          end
        end
      end

      it 'keeps a child of a valid parent managed when the grandparent pointer dangles' do
        grand = dcf_list_field(values: %w[G])
        parent = dcf_list_field(format: 'depending_list', values: %w[A B], parent: grand)
        child = dcf_list_field(format: 'depending_list', values: %w[a1], parent: parent)
        dcf_store_parent(parent, CustomField.maximum(:id).to_i + 1_000)
        issue = kit_issue(project, CustomField.find(parent.id) => 'A', child => [])

        expect(form_data(issue, child)[:dcf_parent]).to eq(parent.id)
      end
    end

    describe 'the parent name' do
      let(:kit) { build_kit(:list) }

      it 'derives the parent name from the tag name, without [] and only when the name parses' do
        parent, child = kit
        issue = kit_issue(project, parent => 'A', child => 'a1')
        table = {
          "issue[custom_field_values][#{child.id}]" => "issue[custom_field_values][#{parent.id}]",
          "issue[custom_field_values][#{child.id}][]" => "issue[custom_field_values][#{parent.id}]",
          "time_entry[custom_field_values][#{child.id}]" => "time_entry[custom_field_values][#{parent.id}]",
          "project[custom_field_values][#{child.id}]" => "project[custom_field_values][#{parent.id}]",
          'weird' => nil,
          "issue[custom_field_values][#{child.id}][x]" => nil
        }
        table.each do |tag_name, expected|
          data = form_data(issue, child, tag_name: tag_name)
          expect(data[:dcf_parent_name]).to eq(expected), tag_name
          expect(data[:dcf_map]).not_to be_nil
        end
      end
    end

    describe 'enumeration encoding' do
      it 'turns canonical ids into integers, recursively, and keeps every other value a string' do
        parent, child = build_kit(:enumeration)
        child.update!(multiple: true)
        vd = { '1' => ['12', '007', '0', '-1', ' 12', '12.0', 'abc', '9007199254740991', '9007199254740992'] }
        dd = { '1' => ['12', '007'], '2' => '13' }
        child.update_column(:format_store, child.format_store.merge('value_dependencies' => vd,
                                                                   'default_value_dependencies' => dd))
        issue = kit_issue(project, parent => 'A', child => [])
        data = form_data(issue, child)

        expect(data[:dcf_map]).to eq('1' => [12, '007', '0', '-1', ' 12', '12.0', 'abc', 9_007_199_254_740_991,
                                             '9007199254740992'])
        expect(data[:dcf_defaults]).to eq('1' => [12, '007'], '2' => 13)
        expect(JSON.parse(data[:dcf_map].to_json)).to eq(data[:dcf_map])
      end

      it 'keeps numeric list values as strings' do
        parent = dcf_list_field(values: %w[1 2])
        child = dcf_list_field(format: 'depending_list', values: %w[12 02], parent: parent)
        child = dcf_set_dependencies(child, value_dependencies: { '1' => %w[12 02] },
                                            default_value_dependencies: { '1' => '12' })
        issue = kit_issue(project, parent => '1', child => '12')
        data = form_data(issue, child)

        expect(data[:dcf_map]).to eq('1' => %w[12 02])
        expect(data[:dcf_defaults]).to eq('1' => '12')
        expect(data[:dcf_stored]).to eq('child' => ['12'], 'parent' => ['1'])
        expect(data[:dcf_parent_values]).to eq(['1'])
      end

      it 'keeps stored and parent values as strings for enumerations' do
        parent, child = build_kit(:enumeration)
        issue = kit_issue(project, parent => 'A', child => 'a1')
        data = form_data(issue, child)

        expect(data[:dcf_stored]).to eq('child' => [kit_key(child, 'a1')], 'parent' => [kit_key(parent, 'A')])
        expect(data[:dcf_parent_values]).to eq([kit_key(parent, 'A')])
      end
    end

    describe 'bulk context' do
      let(:kit) { build_kit(:list) }
      let(:parent) { kit.first }
      let(:child) { kit.last }
      let(:second_project) { dcf_create_project }

      it 'never emits parent values, the parent label or the stored baseline' do
        issue = kit_issue(project, parent => 'A', child => 'a1')
        data = bulk_data([issue, kit_issue(project, parent => 'B', child => 'b1')], child)

        expect(data.keys).to eq([:dcf_field, :dcf_context, :dcf_kind, :dcf_parent, :dcf_parent_name, :dcf_map,
                                 :dcf_defaults])
        expect(data[:dcf_context]).to eq('bulk')
      end

      it 'gates the parent on every selected project and fails closed without objects' do
        parent.update!(visible: false, role_ids: [role.id])
        dcf_add_member(member, second_project, other_role)
        restricted = CustomField.find(parent.id)
        in_first = kit_issue(project, restricted => 'A', child => 'a1')
        in_second = kit_issue(second_project, restricted => 'A', child => 'a1')

        expect(bulk_data([in_first], child, user: member)[:dcf_parent]).to eq(parent.id)
        expect(bulk_data([in_first, in_second], child, user: member)).to eq(every_field(child, 'bulk'))
        expect(bulk_data([], child, user: member)).to eq(every_field(child, 'bulk'))
        expect(bulk_data(nil, child, user: member)).to eq(every_field(child, 'bulk'))
        expect(bulk_data([], child, user: dcf_admin)[:dcf_parent]).to eq(parent.id)
      end

      it 'gives the same Hash for a relation and the same records in an Array' do
        a = kit_issue(project, parent => 'A', child => 'a1')
        b = kit_issue(project, parent => 'B', child => 'b1')
        relation = Issue.where(id: [a.id, b.id]).order(:id)

        expect(bulk_data(relation, child)).to eq(bulk_data(relation.to_a, child))
      end

      it 'costs the same queries for 1 and 10 selected issues' do
        admin = dcf_admin
        counts = [1, 10].map do |n|
          issues = Array.new(n) { kit_issue(project, parent => 'A', child => 'a1') }
          loaded = Issue.where(id: issues.map(&:id)).preload(:project, :tracker).to_a
          field = CustomField.find(child.id)
          dcf_count_queries { bulk_data(loaded, field, user: admin) }
        end

        expect(counts.uniq.size).to eq(1)
      end
    end

    describe 'user forms (base rule, QA-23)' do
      # The base rule ignores the roles of a user field: the member holds
      # the parent's role in a project and still does not see it.
      it 'manages a child of a role-restricted parent hidden from non-admins for an admin only' do
        parent = dcf_list_field(values: %w[A B], type: UserCustomField)
        parent.update!(visible: false, role_ids: [role.id])
        expect(member.roles_for_project(project)).to include(role)
        child = dcf_list_field(format: 'depending_list', values: %w[a1 b1], type: UserCustomField, parent: parent)
        child = dcf_set_dependencies(child, value_dependencies: { 'A' => %w[a1] })
        person = User.find(member.id)

        expect(form_data(person, child, user: member, tag_name: tag_name_for(child, 'user'))).to eq(every_field(child))
        admin_data = form_data(User.find(member.id), child, user: dcf_admin, tag_name: tag_name_for(child, 'user'))
        expect(admin_data[:dcf_parent]).to eq(parent.id)
        expect(admin_data[:dcf_parent_name]).to eq("user[custom_field_values][#{parent.id}]")
        expect(admin_data[:dcf_stored]).to eq('child' => [], 'parent' => [])
      end
    end

    it 'gives each user their own visibility result for one parent instance (no shared memo)' do
      parent, child = build_kit(:list)
      restricted = restrict(parent)
      issue = kit_issue(project, restricted => 'A', child => 'a1')

      expect(form_data(issue, child, user: dcf_admin)).to have_key(:dcf_map)
      expect(form_data(issue, child, user: member)).not_to have_key(:dcf_map)
      expect(form_data(issue, child, user: dcf_admin)).to have_key(:dcf_map)
    end

    it 'accepts a custom value without a record' do
      parent, child = build_kit(:list)
      data = client.attributes_for(child, context: :form, customized: nil, custom_value: CustomValue.new(custom_field: child),
                                          tag_name: tag_name_for(child), user: dcf_admin)

      expect(data[:dcf_parent]).to eq(parent.id)
      expect(data.keys & [:dcf_parent_values, :dcf_parent_label, :dcf_stored]).to eq([])
    end

    it 'keeps no state on the module' do
      parent, child = build_kit(:list)
      issue = kit_issue(project, parent => 'A', child => 'a1')
      form_data(issue, child)
      bulk_data([issue], child)
      client.locked_children(issue)

      expect(client.instance_variables).to eq([])
    end
  end

  # The legacy scripts (untouched until WP-18) read and write their state
  # through dataset keys and data-* names; no contract or carrier attribute
  # may map onto one of them. WP-17 renamed the legacy script to
  # depending_custom_fields_legacy.js (the new runtime took the old name).
  it 'uses no attribute name the legacy scripts read or write' do
    names = %w[dcf_field dcf_context dcf_kind dcf_multiple dcf_parent dcf_parent_name dcf_map dcf_defaults dcf_hide
               dcf_parent_values dcf_parent_label dcf_stored dcf_locked_parent dcf_locked_stored dcf_locked_allowed_by]
    root = File.expand_path('../..', __dir__)
    files = %w[assets/javascripts/depending_custom_fields_legacy.js assets/javascripts/context_menu_wizard.js]
    legacy = files.map do |path|
      File.read(File.join(root, path))
    end.join("\n")
    keys = legacy.scan(/dataset\.([A-Za-z]+)/).flatten.uniq
    attributes = legacy.scan(/data-([a-z-]+)/).flatten.uniq
    expect(keys).to include('dcfInit', 'valueMap', 'fieldId')

    names.each do |name|
      expect(keys).not_to include(name.camelize(:lower)), name
      expect(attributes).not_to include(name.dasherize), name
    end
    expect(names.map(&:dasherize) & %w[dcf-locked-parent]).to eq(['dcf-locked-parent'])
    expect(names.grep(/\Adcf_locked/).map(&:dasherize)).to all(satisfy { |n| !n.start_with?('dcf-parent') })
  end

  it 'loads its new files under the eager loader with the constants their names give' do
    lib = File.expand_path('../../lib', __dir__)
    expect { Rails.autoloaders.main.eager_load_dir(lib) }.not_to raise_error
    {
      'client_data.rb' => 'RedmineDependingCustomFields::ClientData',
      'hooks/read_only_carrier_hook.rb' => 'RedmineDependingCustomFields::Hooks::ReadOnlyCarrierHook'
    }.each do |file, constant|
      path = File.join(lib, 'redmine_depending_custom_fields', file)
      expect(Rails.autoloaders.main.cpath_expected_at(path)).to eq(constant)
    end
  end

  describe '.merge_options' do
    let(:data) { { dcf_field: 7, dcf_context: 'form' } }

    it 'merges into the caller data without changing the caller hashes' do
      caller_data = { foo: 1 }.freeze
      options = { class: 'x', data: caller_data }.freeze
      merged = client.merge_options(options, data)

      expect(merged).to eq(class: 'x', data: { foo: 1, dcf_field: 7, dcf_context: 'form' })
      expect(options).to eq(class: 'x', data: { foo: 1 })
      expect(caller_data).to eq(foo: 1)
    end

    it 'accepts data: nil, a non-Hash data and no data key' do
      expect(client.merge_options({ data: nil }, data)).to eq(data: data)
      expect(client.merge_options({ data: 'x' }, data)).to eq(data: data)
      expect(client.merge_options({}, data)).to eq(data: data)
    end

    it 'returns the caller options themselves when there is nothing to add' do
      options = { class: 'x', data: nil }.freeze
      expect(client.merge_options(options, {})).to equal(options)
    end
  end

  describe '.locked_children (UD-37)' do
    it 'applies the generic rule visible minus editable to a project field' do
      parent = dcf_list_field(values: %w[A B], type: ProjectCustomField)
      child = dcf_list_field(format: 'depending_list', values: %w[a1 b1], type: ProjectCustomField, parent: parent)
      child = dcf_set_dependencies(child, value_dependencies: { 'A' => %w[a1], 'B' => %w[a1 b1] })
      project.custom_field_values = { parent.id.to_s => 'A', child.id.to_s => 'b1' }
      project.save!(validate: false)
      record = Project.find(project.id)

      expect(client.locked_children(record)).to eq([])
      visible = record.visible_custom_field_values
      allow(record).to receive(:editable_custom_field_values).and_return(visible.reject { |v| v.custom_field_id == child.id })

      expect(client.locked_children(record)).to eq(
        [{ dcf_locked_parent: parent.id, dcf_locked_stored: ['A'], dcf_locked_allowed_by: [['B']] }]
      )
    end
  end
end
