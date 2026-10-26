# frozen_string_literal: true

require_relative '../rails_helper'

# WP-10 (point 5 server, UD-08, UD-35): a save refuses a parent that is the
# field itself or one of its dependent fields, only for persisted fields
# whose normalized parent id changes (D9 refinement), and fields in or below
# a stored cycle are unconstrained. Stored cycles come from
# spec/support/dcf_stored_cycle.rb (written without validation).
RSpec.describe 'Custom field cycle validation' do
  include DcfStoredCycle

  fixtures :users

  let(:circular) { [{ error: :dcf_circular_dependency }] }

  # The registry texts after the label field_parent_custom_field (F4).
  full_messages = {
    en: 'Depends on refers to this field or to one of its dependent fields, which would create a circular dependency',
    de: 'Abhängig von verweist auf dieses Feld oder auf eines seiner abhängigen Felder, ' \
        'wodurch eine zirkuläre Abhängigkeit entstünde',
    fr: 'Dépend de désigne ce champ ou l\'un de ses champs dépendants, ce qui créerait une dépendance circulaire',
    nl: 'Afhankelijk van verwijst naar dit veld of naar een van zijn afhankelijke velden, ' \
        'wat een circulaire afhankelijkheid zou veroorzaken'
  }.freeze

  def rules
    RedmineDependingCustomFields::DependencyRules
  end

  def stored_parent(field)
    CustomField.find(field.id).parent_custom_field_id
  end

  def plain(kind, names = %w[p1 p2])
    kind == :list ? dcf_list_field(values: names) : dcf_enum_field(names: names)
  end

  describe 'DependencyRules.parent_changed?' do
    let(:parent) { dcf_list_field(values: %w[A]) }
    let(:field) { CustomField.find(dcf_list_field(format: 'depending_list', values: %w[a], parent: parent).id) }

    it 'is true for a new record' do
      expect(rules.parent_changed?(IssueCustomField.new(field_format: 'depending_list'))).to be(true)
    end

    it 'is false without a query when format_store is not changed' do
      field.name = 'Renamed'
      expect(dcf_count_queries { expect(rules.parent_changed?(field)).to be(false) }).to eq(0)
    end

    it 'compares normalized ids: a String id, a blank and a zero are no change' do
      field.parent_custom_field_id = parent.id.to_s
      expect(rules.parent_changed?(field)).to be(false)

      blank = CustomField.find(dcf_list_field(format: 'depending_list', values: %w[a]).id)
      blank.parent_custom_field_id = ''
      expect(rules.parent_changed?(blank)).to be(false)
      blank.parent_custom_field_id = 0
      expect(rules.parent_changed?(blank)).to be(false)
      blank.parent_custom_field_id = 'abc'
      expect(rules.parent_changed?(blank)).to be(false)
    end

    it 'is false for a change of the mappings only, true for a real change' do
      field.value_dependencies = { 'A' => %w[a] }
      expect(field.will_save_change_to_attribute?('format_store')).to be(true)
      expect(rules.parent_changed?(field)).to be(false)
      field.parent_custom_field_id = ''
      expect(rules.parent_changed?(field)).to be(true)
      field.parent_custom_field_id = dcf_list_field.id
      expect(rules.parent_changed?(field)).to be(true)
    end

    # tests-r2-1: rows may hold the pointer as a String ('12', FieldIndex
    # PARENT_RE). Both sides are normalized, so a mapping-only save of such a
    # stored-cycle member runs no cycle check and keeps working (D9, UD-08).
    it 'compares the stored side normalized too: a pointer stored as a String is no change' do
      world = dcf_stored_cycles(:list)
      x = dcf_store_parent(world.x, world.y.id.to_s)
      expect(x.parent_custom_field_id).to eq(world.y.id.to_s)

      x.value_dependencies = { 'y2' => %w[x2] }
      expect(x.will_save_change_to_attribute?('format_store')).to be(true)
      expect(rules.parent_changed?(x)).to be(false)
      expect(x.save).to be(true), x.errors.full_messages.inspect
      expect(x.errors[:parent_custom_field_id]).to eq([])
      expect(stored_parent(x)).to eq(world.y.id)

      x = dcf_store_parent(world.x, world.y.id.to_s)
      x.parent_custom_field_id = world.y.id
      expect(x.will_save_change_to_attribute?('format_store')).to be(true)
      expect(rules.parent_changed?(x)).to be(false)
    end

    it 'never asks the store dirty helpers (F1)' do
      field.parent_custom_field_id = parent.id.to_s
      allow(field).to receive(:parent_custom_field_id_changed?).and_call_original
      allow(field).to receive(:parent_custom_field_id_was).and_call_original
      rules.parent_changed?(field)
      expect(field).not_to have_received(:parent_custom_field_id_changed?)
      expect(field).not_to have_received(:parent_custom_field_id_was)
    end
  end

  [:list, :enumeration].each do |kind|
    context "for a depending #{kind}" do
      let(:root) { plain(kind) }

      describe 'a parent change that would close a cycle' do
        it 'refuses the field itself and stores nothing' do
          field = CustomField.find(dcf_cycle_field(kind, %w[a1], parent: root).id)
          field.parent_custom_field_id = field.id

          expect(field.save).to be(false)
          expect(field.errors.details[:parent_custom_field_id]).to eq(circular)
          expect(stored_parent(field)).to eq(root.id)
        end

        it 'refuses the field itself given as a String, without loading the topology' do
          field = CustomField.find(dcf_cycle_field(kind, %w[a1]).id)
          field.parent_custom_field_id = field.id.to_s
          allow(RedmineDependingCustomFields::FieldIndex).to receive(:load).and_call_original

          expect(field.valid?).to be(false)
          expect(field.errors.details[:parent_custom_field_id]).to eq(circular)
          expect(RedmineDependingCustomFields::FieldIndex).not_to have_received(:load)
        end

        it 'refuses closing a -> b -> a' do
          a = CustomField.find(dcf_cycle_field(kind, %w[a1]).id)
          b = dcf_cycle_field(kind, %w[b1], parent: a)
          a.parent_custom_field_id = b.id

          expect(a.save).to be(false)
          expect(a.errors.details[:parent_custom_field_id]).to eq(circular)
          expect(stored_parent(a)).to be_nil
        end

        it 'refuses closing a 3-level cycle (b names a, c names b, then a names c)' do
          a = CustomField.find(dcf_cycle_field(kind, %w[a1], parent: root).id)
          b = dcf_cycle_field(kind, %w[b1], parent: a)
          c = dcf_cycle_field(kind, %w[c1], parent: b)
          a.parent_custom_field_id = c.id.to_s

          expect(a.save).to be(false)
          expect(a.errors.details[:parent_custom_field_id]).to eq(circular)
          expect(stored_parent(a)).to eq(root.id)
        end

        it 'runs the resolve query once, shared with before_save, and loads the topology once' do
          a = CustomField.find(dcf_cycle_field(kind, %w[a1]).id)
          other = plain(kind)
          a.parent_custom_field_id = other.id.to_s
          allow(CustomField).to receive(:find_by).and_call_original
          allow(RedmineDependingCustomFields::FieldIndex).to receive(:load).and_call_original

          a.save!

          expect(CustomField).to have_received(:find_by).with(hash_including(id: other.id, type: a.type)).once
          expect(RedmineDependingCustomFields::FieldIndex).to have_received(:load).once
          expect(stored_parent(a)).to eq(other.id)
        end
      end

      describe 'saves without a cycle check' do
        it 'keeps the same parent id posted as a String, without a query' do
          field = CustomField.find(dcf_cycle_field(kind, %w[a1], parent: root).id)
          field.parent_custom_field_id = root.id.to_s
          expect(dcf_count_queries { expect(rules.parent_errors(field)).to eq([]) }).to eq(0)
          field.save!
          expect(stored_parent(field)).to eq(root.id)
        end

        it 'stores nil for an unresolvable parent without an error (D9)' do
          field = CustomField.find(dcf_cycle_field(kind, %w[a1], parent: root).id)
          other_type = kind == :list ? dcf_list_field(type: ProjectCustomField) : dcf_enum_field(type: ProjectCustomField)
          other_family = kind == :list ? dcf_enum_field : dcf_list_field
          [CustomField.maximum(:id).to_i + 1_000, other_type.id, other_family.id].each do |pid|
            field = CustomField.find(field.id)
            field.parent_custom_field_id = pid
            expect(field.save).to be(true), field.errors.full_messages.inspect
            expect(stored_parent(field)).to be_nil
            dcf_store_parent(field, root)
          end
        end

        # tests-r2-2: the new-record guard of parent_errors is the only thing
        # that skips the check on create (a new record never matches a walk);
        # without it every create pays a FieldIndex.load.
        it 'never refuses a new record, also one below a stored cycle or copied from a cycle member, without a topology load' do
          world = dcf_stored_cycles(kind)
          allow(RedmineDependingCustomFields::FieldIndex).to receive(:load).and_call_original
          fresh = dcf_cycle_field(kind, %w[n1], parent: world.x)
          expect(stored_parent(fresh)).to eq(world.x.id)
          expect(rules.parent_errors(IssueCustomField.new(field_format: world.x.field_format))).to eq([])

          copy = IssueCustomField.new.copy_from(CustomField.find(world.x.id))
          copy.name = "Copy-#{SecureRandom.hex(3)}"
          expect(copy.save).to be(true), copy.errors.full_messages.inspect
          expect(stored_parent(copy)).to eq(world.y.id)
          expect(RedmineDependingCustomFields::FieldIndex).not_to have_received(:load)
        end

        it 'accepts a parent below another stored cycle: the field is then unconstrained, without a warning' do
          world = dcf_stored_cycles(kind)
          field = CustomField.find(dcf_cycle_field(kind, %w[n1], parent: root).id)
          field.parent_custom_field_id = world.child.id

          expect(field.save).to be(true), field.errors.full_messages.inspect
          field = CustomField.find(field.id)
          expect(rules.effective_parent_id(field)).to be_nil
          expect(rules.in_cycle?(field)).to be(false)
        end
      end

      # D9 refinement (UD-08): saves that keep the normalized parent id of a
      # stored-cycle member succeed.
      describe 'saves of the members of a stored cycle' do
        let(:world) { dcf_stored_cycles(kind) }

        it 'keep a position-only save, a name change, a mapping and default change and the same id as a String' do
          x = CustomField.find(world.x.id)
          x.update!(position: x.position + 5)
          x.update!(name: "#{x.name}-renamed")
          dcf_set_dependencies(x, value_dependencies: { kit_key(world.y, 'y2') => [kit_key(x, 'x2')] },
                                  default_value_dependencies: { kit_key(world.y, 'y2') => kit_key(x, 'x2') })
          self_parent = CustomField.find(world.self_parent.id)
          self_parent.parent_custom_field_id = self_parent.id.to_s
          self_parent.save!

          expect(stored_parent(x)).to eq(world.y.id)
          expect(stored_parent(self_parent)).to eq(world.self_parent.id)
          expect(CustomField.find(x.id).value_dependencies).to eq(kit_key(world.y, 'y2') => [kit_key(x, 'x2')])
        end

        it 'break the cycle with a parent outside the descendants or with a blank parent' do
          x = CustomField.find(world.x.id)
          x.update!(parent_custom_field_id: root.id)
          expect(stored_parent(x)).to eq(root.id)
          expect(rules.in_cycle?(CustomField.find(world.y.id))).to be(false)
          expect(rules.effective_parent_id(CustomField.find(world.y.id))).to eq(world.x.id)

          b = CustomField.find(world.b.id)
          b.update!(parent_custom_field_id: '')
          expect(stored_parent(b)).to eq('')
          expect(rules.in_cycle?(CustomField.find(world.a.id))).to be(false)
        end

        it 'refuse a new parent among the descendants, the field itself included' do
          [world.child.id, world.x.id].each do |pid|
            x = CustomField.find(world.x.id)
            x.parent_custom_field_id = pid
            expect(x.save).to be(false), pid.inspect
            expect(x.errors.details[:parent_custom_field_id]).to eq(circular)
          end
          expect(stored_parent(world.x)).to eq(world.y.id)
        end

        if kind == :list
          it 'keep a RenameValueService cascade through a cycle member' do
            project = dcf_create_project
            x = CustomField.find(world.x.id)
            x.update!(is_for_all: false)
            x.projects = [project]
            RedmineDependingCustomFields::RenameValueService
              .new(project: project, field: CustomField.find(x.id), user: dcf_admin,
                   params: { old_value: 'x1', new_value: 'x9', confirm: '1' }).call

            expect(CustomField.find(x.id).possible_values).to eq(%w[x9 x2])
            expect(CustomField.find(world.y.id).value_dependencies).to eq('x9' => %w[y1])
            expect(CustomField.find(world.child.id).value_dependencies).to eq('x9' => %w[c1])
            expect(stored_parent(x)).to eq(world.y.id)
          end

          it 'keep a DependencyMappingService save of a cycle member' do
            project = dcf_create_project
            RedmineDependingCustomFields::DependencyMappingService
              .new(project: project, field: CustomField.find(world.y.id), user: dcf_admin,
                   params: { value_dependencies: { 'x2' => %w[y2] }, default_value_dependencies: { 'x2' => 'y2' } }).call

            expect(CustomField.find(world.y.id).value_dependencies).to eq('x2' => %w[y2])
            expect(stored_parent(world.y)).to eq(world.x.id)
          end
        end
      end

      # UD-08, UD-35, server design section 8 rules 4 and 5.
      describe 'validation in and below a stored cycle' do
        let(:world) { dcf_stored_cycles(kind) }
        let(:project) { dcf_create_project }
        let(:unconstrained) { world.depending }

        # Flipped by WP-18 (WP-10 open input): no_options? (the required
        # bypass) reads only the effective parent, so it is false for every
        # field here (semantics-r2-1 kept the 0.0.16 parent read for the
        # legacy script, which was true for a, b and c, whose blank partner
        # value allows nothing).
        it 'has no effective parent, no parent state and no required bypass for any member or field below one' do
          issue = kit_issue(project, world.x => 'x1', world.y => 'y1', world.child => 'c1',
                                     world.self_parent => 's1', world.below_self_parent => 'd1')
          unconstrained.each do |field|
            fresh = CustomField.find(field.id)
            expect(rules.effective_parent_id(fresh, rules.lookup_records(issue))).to be_nil, field.name
            expect(rules.parent_state(fresh, issue)).to be_nil, field.name
            expect(rules.no_options?(fresh, issue)).to be(false), field.name
          end
        end

        it 'accepts values that no mapping allows' do
          issue = kit_new_issue(project, world.x => 'x2', world.y => 'y2', world.child => 'c2',
                                         world.self_parent => 's2', world.below_self_parent => 'd2')
          expect(issue.valid?).to be(true), issue.errors.full_messages.inspect
        end

        # Flipped back by WP-18 (WP-10 open input): "keeps the core required
        # check on a required member (no bypass without a parent state)", as
        # before semantics-r2-1, which dropped the blank error while the
        # stored partner value allowed nothing (legacy script).
        it 'keeps the core required check on a required member, whatever its stored partner value' do
          y = CustomField.find(world.y.id)
          y.update!(is_required: true)
          blank = I18n.t('activerecord.errors.messages.blank')
          expect(errors_for(kit_new_issue(project, world.x => 'x2', y => []), y)).to eq([blank])
          expect(errors_for(kit_new_issue(project, world.x => 'x1', y => []), y)).to eq([blank])
          expect(errors_for(kit_new_issue(project, world.x => 'x2', y => 'y2'), y)).to eq([])
        end

        # Flipped by WP-18: was 'drops the blank error of a required
        # self-parent and of required fields below a cycle in the same way'.
        it 'keeps the core required check on a required self-parent and on required fields below a cycle' do
          required = [world.self_parent, world.below_self_parent, world.child].map do |field|
            CustomField.find(field.id).tap { |f| f.update!(is_required: true) }
          end
          blank = I18n.t('activerecord.errors.messages.blank')
          issue = kit_new_issue(project, required.to_h { |f| [f, []] }.merge(world.x => 'x2'))
          expect(required.map { |f| errors_for(issue, f) }).to eq([[blank], [blank], [blank]])
          issue = kit_new_issue(project, required.to_h { |f| [f, []] }.merge(world.x => 'x1'))
          expect(required.map { |f| errors_for(issue, f) }).to eq([[blank], [blank], [blank]])
        end

        it 'does not judge non-editable members whose cycle partner changes (WP-09b)' do
          issue = kit_issue(project, world.x => 'x1', world.y => 'y1')
          issue.custom_field_values = { world.x.id.to_s => kit_key(world.x, 'x2') }
          allow(issue).to receive(:editable_custom_field_values).and_return([])
          RedmineDependingCustomFields::NonEditableDependencies.validate(issue, dcf_admin)
          expect(issue.errors.full_messages).to eq([])
        end

        # WP-15 (SelectionGraph) and WP-16 (ClientData) build on these.
        it 'agrees with FieldIndex#effective_parent_id_for and parent_state for every depending field' do
          issue = kit_issue(project, world.x => 'x1', world.y => 'y1', world.child => 'c1',
                                     world.self_parent => 's1', world.below_self_parent => 'd1')
          lookup = rules.lookup_records(issue)
          index = RedmineDependingCustomFields::FieldIndex.new(records: lookup)
          plain_child = dcf_cycle_field(kind, %w[z1], parent: root)
          (world.depending + [plain_child]).each do |field|
            fresh = CustomField.find(field.id)
            from_index = index.effective_parent_id_for(fresh.id, fresh.type, fresh.field_format, index.parent_id(fresh.id))
            expect(rules.effective_parent_id(fresh, lookup)).to eq(from_index), field.name
            expect(rules.parent_state(fresh, issue).nil?).to eq(from_index.nil?), field.name
          end
          expect(rules.effective_parent_id(CustomField.find(plain_child.id), lookup)).to eq(root.id)
        end
      end

      describe 'full messages' do
        full_messages.each do |locale, message|
          it "reads the circular dependency error in #{locale}" do
            field = CustomField.find(dcf_cycle_field(kind, %w[a1]).id)
            field.parent_custom_field_id = field.id
            I18n.with_locale(locale) do
              field.valid?
              expect(field.errors.full_messages).to eq([message])
            end
          end
        end
      end
    end
  end

  # jc-redmine_extended_api writes through safe_attributes= and then saves.
  it 'refuses a circular parent assigned through safe_attributes=' do
    field = CustomField.find(dcf_list_field(format: 'depending_list', values: %w[a1]).id)
    field.safe_attributes = { 'parent_custom_field_id' => field.id.to_s }
    expect(field.save).to be(false)
    expect(field.errors.details[:parent_custom_field_id]).to eq(circular)
    expect(stored_parent(field)).to be_nil
  end
end
