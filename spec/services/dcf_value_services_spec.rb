require_relative '../rails_helper'

RSpec.describe 'DCF value operation services' do
  include RedmineDependingCustomFields

  let(:project) { dcf_create_project }
  let(:user) { dcf_admin }

  def add(field, params)
    RedmineDependingCustomFields::AddValueService
      .new(project: project, field: field, user: user, params: params).call
  end

  def rename(field, params)
    RedmineDependingCustomFields::RenameValueService
      .new(project: project, field: field, user: user, params: params).call
  end

  def remove(field, params)
    RedmineDependingCustomFields::RemoveValueService
      .new(project: project, field: field, user: user, params: params).call
  end

  def reorder(field, params)
    RedmineDependingCustomFields::ReorderValuesService
      .new(project: project, field: field, user: user, params: params).call
  end

  def set_default(field, params)
    RedmineDependingCustomFields::SetDefaultValueService
      .new(project: project, field: field, user: user, params: params).call
  end

  # The payload the batch enumeration form submits: every row, with the given
  # per-enumeration overrides applied on top of the current state.
  def enum_payload(field, overrides = {})
    payload = {}
    field.enumerations.order(:position).each_with_index do |enum, idx|
      over = overrides[enum.id] || overrides[enum.id.to_s] || {}
      payload[enum.id.to_s] = {
        'name'     => (over.key?(:name) ? over[:name] : enum.name),
        'position' => (over.key?(:position) ? over[:position] : idx + 1).to_s,
        'active'   => ((over.key?(:active) ? over[:active] : enum.active?) ? '1' : '0')
      }
    end
    payload
  end

  def save_enums(field, overrides = {}, extra = {})
    RedmineDependingCustomFields::UpdateEnumerationsService
      .new(project: project, field: field, user: user,
           params: { enumerations: enum_payload(field, overrides) }.merge(extra)).call
  end

  # --- Add (T-ADD) -------------------------------------------------------
  describe 'AddValueService' do
    it 'appends a list value (T-ADD-1)' do
      field = dcf_list_field(values: %w[A B])
      add(field, value: 'C')
      expect(field.reload.possible_values).to eq(%w[A B C])
    end

    it 'creates an enumeration (T-ADD-1)' do
      field = dcf_enum_field(names: %w[X])
      expect { add(field, value: 'Y') }.to change { field.enumerations.count }.by(1)
      expect(field.enumerations.where(active: true).pluck(:name)).to include('Y')
    end

    it 'rejects a blank value (T-ADD-2)' do
      field = dcf_list_field
      expect { add(field, value: '  ') }
        .to raise_error(RedmineDependingCustomFields::OperationError) { |e| expect(e.key).to eq(:error_value_blank) }
    end

    it 'rejects a duplicate value (T-ADD-3)' do
      field = dcf_list_field(values: %w[A])
      expect { add(field, value: 'A') }
        .to raise_error(RedmineDependingCustomFields::OperationError) { |e| expect(e.key).to eq(:error_value_duplicate) }
    end

    it 'inserts at a position (T-ADD-4)' do
      field = dcf_list_field(values: %w[A B])
      add(field, value: 'X', position: 1)
      expect(field.reload.possible_values).to eq(%w[A X B])
    end
  end

  # --- Rename (T-REN / T-DEF / T-CAS) ------------------------------------
  describe 'RenameValueService' do
    it 'rewrites possible_values and CustomValue rows for a list (T-REN-1)' do
      field = dcf_list_field(values: %w[A B], is_for_all: false, projects: [project])
      cv = dcf_custom_value(field, 'A')
      rename(field, old_value: 'A', new_value: 'A2', confirm: '1')
      expect(field.reload.possible_values).to eq(%w[A2 B])
      expect(cv.reload.value).to eq('A2')
    end

    it 'rewrites own dependency entries for depending_list (T-REN-2)' do
      parent = dcf_list_field(name: 'Parent', values: %w[P], is_for_all: false, projects: [project])
      field = dcf_list_field(format: 'depending_list', name: 'Child', values: %w[A B],
                             parent: parent, is_for_all: false, projects: [project])
      dcf_set_dependencies(field, value_dependencies: { 'P' => %w[A B] },
                                  default_value_dependencies: { 'P' => 'A' })
      rename(field, old_value: 'A', new_value: 'A2', confirm: '1')
      expect(field.reload.value_dependencies).to eq('P' => %w[A2 B])
      expect(field.default_value_dependencies).to eq('P' => 'A2')
    end

    it 'leaves no dependency store for a standard list rename (T-REN-2)' do
      field = dcf_list_field(values: %w[A B], is_for_all: false, projects: [project])
      rename(field, old_value: 'A', new_value: 'A2', confirm: '1')
      expect(field.reload.value_dependencies).to be_blank
    end

    it 'renames only the enumeration name and leaves CustomValue intact (T-REN-3)' do
      field = dcf_enum_field(names: %w[X Y])
      enum = field.enumerations.first
      cv = dcf_custom_value(field, enum.id)
      rename(field, enumeration_id: enum.id, new_value: 'X2')
      expect(enum.reload.name).to eq('X2')
      expect(cv.reload.value).to eq(enum.id.to_s)
    end

    it 'rejects a rename to a duplicate (T-REN-4)' do
      field = dcf_list_field(values: %w[A B], is_for_all: false, projects: [project])
      expect { rename(field, old_value: 'A', new_value: 'B', confirm: '1') }
        .to raise_error(RedmineDependingCustomFields::OperationError) { |e| expect(e.key).to eq(:error_value_duplicate) }
    end

    it 'requires confirmation for a cross-project (global) rename (T-REN-5)' do
      field = dcf_list_field(values: %w[A B], is_for_all: true)
      expect { rename(field, old_value: 'A', new_value: 'A2') }
        .to raise_error(RedmineDependingCustomFields::ConfirmationRequired)
    end

    it 'rewrites default_value when renaming it (T-DEF-1)' do
      field = dcf_list_field(values: %w[A B], default_value: 'A', is_for_all: false, projects: [project])
      rename(field, old_value: 'A', new_value: 'A2', confirm: '1')
      expect(field.reload.default_value).to eq('A2')
    end

    it 'cascades a standard-list parent rename into a depending_list child (T-CAS-1)' do
      parent = dcf_list_field(name: 'Parent', values: %w[A B], is_for_all: false, projects: [project])
      child = dcf_list_field(format: 'depending_list', name: 'Child', values: %w[c1 c2],
                             parent: parent, is_for_all: false, projects: [project])
      dcf_set_dependencies(child, value_dependencies: { 'A' => %w[c1] },
                                  default_value_dependencies: { 'A' => 'c1' })
      outcome = rename(parent, old_value: 'A', new_value: 'A2', confirm: '1')
      expect(child.reload.value_dependencies).to eq('A2' => %w[c1])
      expect(child.default_value_dependencies).to eq('A2' => 'c1')
      expect(outcome.affected_child_field_ids).to include(child.id)
    end

    it 'does NOT touch child keys when renaming an enumeration parent (id-stable) (T-CAS-4)' do
      parent = dcf_enum_field(name: 'EnumParent', names: %w[P1 P2])
      pid = parent.enumerations.first.id.to_s
      child = dcf_enum_field(format: 'depending_enumeration', name: 'EnumChild', names: %w[c1])
      child.update!(parent_custom_field_id: parent.id)
      cid = child.enumerations.first.id.to_s
      dcf_set_dependencies(child, value_dependencies: { pid => [cid] })
      rename(parent, enumeration_id: pid, new_value: 'P1x')
      expect(child.reload.value_dependencies).to eq(pid => [cid])
    end
  end

  # --- Remove (T-RM / T-ENU / T-CAS) -------------------------------------
  describe 'RemoveValueService' do
    it 'prunes own deps and keeps CustomValue rows for depending_list (T-RM-1)' do
      parent = dcf_list_field(name: 'Parent', values: %w[P], is_for_all: false, projects: [project])
      field = dcf_list_field(format: 'depending_list', name: 'Child', values: %w[A B],
                             parent: parent, is_for_all: false, projects: [project])
      dcf_set_dependencies(field, value_dependencies: { 'P' => %w[A B] })
      cv = dcf_custom_value(field, 'A')
      remove(field, value: 'A', confirm: '1')
      expect(field.reload.possible_values).to eq(%w[B])
      expect(field.value_dependencies).to eq('P' => %w[B])
      expect(CustomValue.exists?(cv.id)).to be true
    end

    it 'leaves CustomValue orphaned and touches no dep store for a standard list (T-RM-1b)' do
      field = dcf_list_field(values: %w[A B], is_for_all: false, projects: [project])
      cv = dcf_custom_value(field, 'A')
      remove(field, value: 'A', confirm: '1')
      expect(field.reload.possible_values).to eq(%w[B])
      expect(cv.reload.value).to eq('A')
    end

    it 'blocks removal of an in-use value when block_removal_when_used is set (T-RM-3)' do
      allow(Setting).to receive(:plugin_redmine_depending_custom_fields)
        .and_return('block_removal_when_used' => '1')
      field = dcf_list_field(values: %w[A B], is_for_all: false, projects: [project])
      dcf_issue_with_value(project, field, 'A')
      expect { remove(field, value: 'A', confirm: '1') }
        .to raise_error(RedmineDependingCustomFields::OperationError) { |e| expect(e.key).to eq(:error_value_in_use) }
    end

    it 'clears default_value when removing it (T-DEF-2)' do
      field = dcf_list_field(values: %w[A B], default_value: 'A', is_for_all: false, projects: [project])
      remove(field, value: 'A', confirm: '1')
      expect(field.reload.default_value).to be_blank
    end

    it 'deactivates an in-use enumeration (T-ENU-1)' do
      field = dcf_enum_field(names: %w[X Y])
      enum = field.enumerations.first
      dcf_issue_with_value(project, field, enum.id)
      remove(field, enumeration_id: enum.id, confirm: '1')
      expect(enum.reload.active).to be false
    end

    it 'hard-destroys an unused enumeration (T-ENU-2)' do
      field = dcf_enum_field(names: %w[X Y])
      enum = field.enumerations.first
      expect { remove(field, enumeration_id: enum.id, confirm: '1') }
        .to change { field.enumerations.count }.by(-1)
    end

    it 'prunes the removed parent value from depending children (T-CAS-3)' do
      parent = dcf_list_field(name: 'Parent', values: %w[A B], is_for_all: false, projects: [project])
      child = dcf_list_field(format: 'depending_list', name: 'Child', values: %w[c1],
                             parent: parent, is_for_all: false, projects: [project])
      dcf_set_dependencies(child, value_dependencies: { 'A' => %w[c1], 'B' => %w[c1] })
      remove(parent, value: 'A', confirm: '1')
      expect(child.reload.value_dependencies).to eq('B' => %w[c1])
    end
  end

  # --- Reorder (T-ORD) ---------------------------------------------------
  describe 'ReorderValuesService' do
    it 'reorders list values (T-ORD-1)' do
      field = dcf_list_field(values: %w[A B C], is_for_all: false, projects: [project])
      reorder(field, ordered_values: %w[C A B])
      expect(field.reload.possible_values).to eq(%w[C A B])
    end

    it 'reorders enumeration positions (T-ORD-2)' do
      field = dcf_enum_field(names: %w[X Y Z])
      ids = field.enumerations.order(:position).map(&:id).map(&:to_s)
      reorder(field, ordered_values: ids.reverse)
      expect(field.enumerations.order(:position).map(&:name)).to eq(%w[Z Y X])
    end

    it 'rejects a missing value (T-ORD-3)' do
      field = dcf_list_field(values: %w[A B C], is_for_all: false, projects: [project])
      expect { reorder(field, ordered_values: %w[A B]) }
        .to raise_error(RedmineDependingCustomFields::OperationError) { |e| expect(e.key).to eq(:error_reorder_mismatch) }
    end

    it 'rejects a duplicated value (T-ORD-5)' do
      field = dcf_list_field(values: %w[A B C], is_for_all: false, projects: [project])
      expect { reorder(field, ordered_values: %w[A A B C]) }
        .to raise_error(RedmineDependingCustomFields::OperationError) { |e| expect(e.key).to eq(:error_reorder_mismatch) }
    end

    # WP-29: additive audit keys; the reorder contract is unchanged.
    def order_digest(keys)
      Digest::SHA256.hexdigest(JSON.generate(keys))
    end

    def last_row(field)
      RedmineDependingCustomFields::ConfigAuditEvent.where(custom_field_id: field.id).order(:id).last
    end

    it 'stores the SHA-256 of the old and the new order of a list (T-ORD-A)' do
      field = dcf_list_field(values: %w[A B C], is_for_all: false, projects: [project])
      reorder(field, ordered_values: %w[C A B])
      row = last_row(field)
      expect([row.action, row.status, row.changes_summary]).to eq(%w[reorder_values success] + ['Reordered values'])
      expect(JSON.parse(row.before_value)).to eq('order_sha256' => order_digest(%w[A B C]))
      expect(JSON.parse(row.after_value))
        .to eq('order' => %w[C A B], 'truncated' => false, 'order_sha256' => order_digest(%w[C A B]))
    end

    it 'stores the SHA-256 of the enumeration ids in [position, id] order, inactive included (T-ORD-A)' do
      field = dcf_enum_field(names: %w[X Y Z])
      x, y, z = field.enumerations.order(:position).to_a
      y.update!(active: false)
      x.update_column(:position, 1)
      y.update_column(:position, 1)
      z.update_column(:position, 2)
      old_keys = [x, y].sort_by(&:id).map { |e| e.id.to_s } + [z.id.to_s]
      submitted = [z, y, x].map { |e| e.id.to_s }
      reorder(field, ordered_values: submitted)
      row = last_row(field)
      expect(JSON.parse(row.before_value)).to eq('order_sha256' => order_digest(old_keys))
      expect(JSON.parse(row.after_value))
        .to eq('order' => submitted, 'truncated' => false, 'order_sha256' => order_digest(submitted))
      expect(field.enumerations.order(:position).pluck(:name, :position, :active))
        .to eq([['Z', 1, true], ['Y', 2, false], ['X', 3, true]])
    end

    it 'keeps the first 20 entries and truncated next to the digest of the full order (T-ORD-A)' do
      values = (1..25).map { |i| format('V%02d', i) }
      field = dcf_list_field(values: values, is_for_all: false, projects: [project])
      reorder(field, ordered_values: values.reverse)
      after = JSON.parse(last_row(field).after_value)
      expect(after).to eq('order' => values.last(20).reverse, 'truncated' => true,
                          'order_sha256' => order_digest(values.reverse))
    end

    it 'chains the digests: the reorder before equals the sort after' do
      field = dcf_enum_field(names: %w[c a b])
      RedmineDependingCustomFields::SortValuesService
        .new(project: project, field: field, user: user, params: { direction: 'asc' }).call
      sort_after = JSON.parse(last_row(field).after_value)['order_sha256']
      ids = field.enumerations.order(:position).map { |e| e.id.to_s }
      reorder(field, ordered_values: ids.reverse)
      expect(JSON.parse(last_row(field).before_value)['order_sha256']).to eq(sort_after)
    end

    it 'refuses the ids of another field padded to the same length; nothing changes' do
      field = dcf_enum_field(names: %w[X Y Z])
      other = dcf_enum_field(names: %w[P Q R])
      before = field.enumerations.order(:position).pluck(:id, :position)
      foreign = other.enumerations.order(:position).map { |e| e.id.to_s }
      expect { reorder(field, ordered_values: foreign) }
        .to raise_error(RedmineDependingCustomFields::OperationError) { |e| expect(e.key).to eq(:error_reorder_mismatch) }
      expect(field.enumerations.order(:position).pluck(:id, :position)).to eq(before)
      expect([last_row(field).status, last_row(field).error_message]).to eq(%w[validation_failed error_reorder_mismatch])
    end
  end

  # --- Sort A-Z / Z-A (T-SORT-10..18, WP-29) ------------------------------
  # Project design 6, UD-23 (no server confirmation), UD-24 (inactive
  # enumerations sorted together with the active ones).
  describe 'SortValuesService (WP-29)' do
    let(:klass) { RedmineDependingCustomFields::SortValuesService }
    let(:events) { RedmineDependingCustomFields::ConfigAuditEvent }

    # The project first, so its INSERT and nested-set UPDATE stay out of the
    # captured statements and the stubs.
    before { project }

    def sort(field, params)
      RedmineDependingCustomFields::SortValuesService
        .new(project: project, field: field, user: user, params: params).call
    end

    def digest(keys)
      Digest::SHA256.hexdigest(JSON.generate(keys))
    end

    def rows(field)
      events.where(custom_field_id: field.id).order(:id)
    end

    def own_list(values)
      dcf_list_field(values: values, is_for_all: false, projects: [project])
    end

    def enum_state(field)
      CustomFieldEnumeration.where(custom_field_id: field.id).order(:position, :id).pluck(:name, :position, :active)
    end

    def enum_ids(field)
      CustomFieldEnumeration.where(custom_field_id: field.id).order(:position, :id).pluck(:id).map(&:to_s)
    end

    def raw_store(field)
      CustomField.where(id: field.id).pluck(Arel.sql('format_store')).first
    end

    # The SQL statements of the block (schema, cache and transaction ones
    # left out).
    def statements(&block)
      sqls = []
      callback = lambda do |*, payload|
        next if payload[:name].to_s.match?(/\A(?:SCHEMA|CACHE|TRANSACTION)\z/)
        next if payload[:sql].to_s.match?(/\A\s*(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i)

        sqls << payload[:sql].to_s
      end
      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &block)
      sqls
    end

    def updates_of(sqls, table)
      sqls.grep(/\AUPDATE\s+[`"]?#{table}[`"]?\s/i)
    end

    def expect_refused(key)
      raise_error(RedmineDependingCustomFields::OperationError) { |e| expect(e.key).to eq(key) }
    end

    describe 'list family' do
      it 'sorts a list stably, ignoring case and accents (T-SORT-10, T-SORT-11)' do
        field = own_list(['b', 'A', 'a', "\u00E9", 'e', 'B'])
        sort(field, direction: 'asc')
        expect(field.reload.possible_values).to eq(['A', 'a', 'b', 'B', "\u00E9", 'e'])
        sort(field, direction: 'desc')
        expect(field.reload.possible_values).to eq(["\u00E9", 'e', 'b', 'B', 'A', 'a'])
      end

      it 'folds accents and compares the folded keys lexicographically' do
        field = own_list(['Zebra', "\u00E9cole", 'Apple', 'eagle', '2', '10'])
        sort(field, direction: 'asc')
        expect(field.reload.possible_values).to eq(['10', '2', 'Apple', 'eagle', "\u00E9cole", 'Zebra'])
      end

      # Project#all_issue_custom_fields is memoized: every field first.
      it 'keeps the stored order of ties for desc too, so desc is not asc reversed (T-SORT-11)' do
        desc_field = own_list(%w[b a B])
        asc_field = own_list(%w[b a B])
        lodz = own_list(["\u0141\u00F3d\u017A", 'lodz'])
        sort(desc_field, direction: 'desc')
        expect(desc_field.reload.possible_values).to eq(%w[b B a])
        sort(asc_field, direction: 'asc')
        expect(asc_field.reload.possible_values).to eq(%w[a b B])
        sort(lodz, direction: 'asc')
        expect(lodz.reload.possible_values).to eq(["\u0141\u00F3d\u017A", 'lodz'])
        sort(lodz, direction: 'desc')
        expect(lodz.reload.possible_values).to eq(["\u0141\u00F3d\u017A", 'lodz'])
      end

      it 'keeps stored duplicates' do
        field = own_list(%w[B A C])
        field.update_column(:possible_values, %w[B A B])
        sort(field, direction: 'asc')
        expect(field.reload.possible_values).to eq(%w[A B B])
      end

      it 'saves the field once and rewrites no CustomValue, default or dependency store (T-SORT-13)' do
        parent = dcf_list_field(values: %w[C B A], is_for_all: false, projects: [project], default_value: 'B')
        child = dcf_list_field(format: 'depending_list', name: "Child-#{SecureRandom.hex(3)}", values: %w[c1 c2],
                               parent: parent, is_for_all: false, projects: [project])
        dcf_set_dependencies(child, value_dependencies: { 'A' => %w[c1], 'C' => %w[c2] },
                                    default_value_dependencies: { 'A' => 'c1' })
        dcf_issue_with_value(project, parent, 'B')
        dcf_custom_value(parent, 'C')
        values_before = CustomValue.where(custom_field_id: parent.id).order(:id).pluck(:id, :value)
        child_before = raw_store(child)
        sqls = statements { sort(parent, direction: 'asc') }
        parent.reload
        expect(parent.possible_values).to eq(%w[A B C])
        expect(parent.default_value).to eq('B')
        expect(CustomValue.where(custom_field_id: parent.id).order(:id).pluck(:id, :value)).to eq(values_before)
        expect(raw_store(child)).to eq(child_before)
        expect(updates_of(sqls, 'custom_values')).to be_empty
        expect(updates_of(sqls, 'custom_fields').size).to eq(1)
        expect(rows(parent).last.affected_child_field_ids).to be_nil
      end

      it 'keeps the own dependency store of a depending list' do
        parent = dcf_list_field(values: %w[P1 P2], is_for_all: false, projects: [project])
        child = dcf_list_field(format: 'depending_list', name: "Child-#{SecureRandom.hex(3)}", values: %w[z y x],
                               parent: parent, is_for_all: false, projects: [project])
        dcf_set_dependencies(child, value_dependencies: { 'P1' => %w[z x], 'P2' => %w[y] },
                                    default_value_dependencies: { 'P1' => 'x' })
        sort(child, direction: 'asc')
        child.reload
        expect(child.possible_values).to eq(%w[x y z])
        expect(child.value_dependencies).to eq('P1' => %w[z x], 'P2' => %w[y])
        expect(child.default_value_dependencies).to eq('P1' => 'x')
      end
    end

    describe 'enumeration family' do
      it 'gives every enumeration a position 1..N, inactive ones interleaved (T-SORT-12, UD-24)' do
        field = dcf_enum_field(names: %w[c B a])
        field.enumerations.find_by(name: 'B').update!(active: false)
        names_before = CustomFieldEnumeration.where(custom_field_id: field.id).order(:id).pluck(:id, :name)
        sort(field, direction: 'asc')
        expect(enum_state(field)).to eq([['a', 1, true], ['B', 2, false], ['c', 3, true]])
        expect(CustomFieldEnumeration.where(custom_field_id: field.id).order(:id).pluck(:id, :name)).to eq(names_before)
      end

      it 'keeps the stored order of ties and sorts desc on the same keys' do
        field = dcf_enum_field(names: ['C', 'b', 'A', "\u00E4"])
        field.enumerations.where(name: ['b', "\u00E4"]).update_all(active: false)
        sort(field, direction: 'asc')
        expect(enum_state(field)).to eq([['A', 1, true], ["\u00E4", 2, false], ['b', 3, false], ['C', 4, true]])
        sort(field, direction: 'desc')
        expect(enum_state(field)).to eq([['C', 1, true], ['b', 2, false], ['A', 3, true], ["\u00E4", 4, false]])
      end

      it 'renumbers gapped positions and counts the rows written as moved' do
        field = dcf_enum_field(names: %w[a b c])
        field.enumerations.order(:position).each_with_index { |e, i| e.update_column(:position, [2, 5, 7][i]) }
        sort(field, direction: 'asc')
        expect(enum_state(field)).to eq([['a', 1, true], ['b', 2, true], ['c', 3, true]])
        expect(JSON.parse(rows(field).last.after_value)['moved']).to eq(3)
      end

      it 'reads tied positions in [position, id] order' do
        field = dcf_enum_field(names: %w[b a c])
        field.enumerations.update_all(position: 1)
        old_keys = enum_ids(field)
        expect(old_keys).to eq(CustomFieldEnumeration.where(custom_field_id: field.id).order(:id).pluck(:id).map(&:to_s))
        sort(field, direction: 'asc')
        expect(enum_state(field).map(&:first)).to eq(%w[a b c])
        expect(JSON.parse(rows(field).last.before_value)['order_sha256']).to eq(digest(old_keys))
      end

      it 'updates only the changed rows, one CASE statement per CHUNK, saving no field (T-SORT-17)' do
        stub_const('RedmineDependingCustomFields::SortValuesService::CHUNK', 2)
        field = dcf_enum_field(names: %w[E D C B A])
        middle = field.enumerations.find_by(name: 'C').id
        sqls = statements { sort(field, direction: 'asc') }
        expect(enum_state(field)).to eq([['A', 1, true], ['B', 2, true], ['C', 3, true], ['D', 4, true], ['E', 5, true]])
        updates = updates_of(sqls, 'custom_field_enumerations')
        expect(updates.size).to eq((4 / 2.0).ceil)
        updates.each do |sql|
          expect(sql).to match(/SET\s+position\s*=\s*CASE\s+id(\s+WHEN\s+\d+\s+THEN\s+\d+)+\s+ELSE\s+position\s+END/i)
          expect(sql).to include('custom_field_id')
          expect(sql.scan(/WHEN\s+(\d+)\s+THEN/).flatten).not_to include(middle.to_s)
        end
        expect(updates_of(sqls, 'custom_fields')).to be_empty
        expect(updates_of(sqls, 'custom_values')).to be_empty
        expect(JSON.parse(rows(field).last.after_value)['moved']).to eq(4)
      end

      it 'sends the last chunk too when the changed rows do not fill it' do
        stub_const('RedmineDependingCustomFields::SortValuesService::CHUNK', 2)
        field = dcf_enum_field(names: %w[B C D E A])
        sqls = statements { sort(field, direction: 'asc') }
        expect(enum_state(field).map(&:first)).to eq(%w[A B C D E])
        expect(updates_of(sqls, 'custom_field_enumerations').size).to eq((5 / 2.0).ceil)
      end

      it 'builds the SQL from integers only, whatever the labels' do
        field = dcf_enum_field(names: ["x' THEN 0 END; DROP TABLE users; --", '%{a} ?', 'a'])
        sqls = statements { sort(field, direction: 'asc') }
        updates = updates_of(sqls, 'custom_field_enumerations')
        expect(updates).not_to be_empty
        updates.each do |sql|
          expect(sql).not_to include('DROP TABLE')
          expect(sql).not_to include('%{a}')
        end
        expect(enum_state(field).map(&:first)).to eq(['%{a} ?', 'a', "x' THEN 0 END; DROP TABLE users; --"])
        expect(User.where(id: 1)).to exist
      end

      it 'rewrites no CustomValue of an enumeration field (T-SORT-13)' do
        field = dcf_enum_field(names: %w[c b a])
        b = field.enumerations.find_by(name: 'b')
        dcf_issue_with_value(project, field, b.id)
        before = CustomValue.where(custom_field_id: field.id).pluck(:id, :value)
        sqls = statements { sort(field, direction: 'asc') }
        expect(CustomValue.where(custom_field_id: field.id).pluck(:id, :value)).to eq(before)
        expect(before.first.last).to eq(b.id.to_s)
        expect(updates_of(sqls, 'custom_values')).to be_empty
      end

      it 'relies on CustomFieldEnumeration having no update callback (update_all skips none)' do
        callbacks = (CustomFieldEnumeration._save_callbacks.to_a + CustomFieldEnumeration._update_callbacks.to_a)
                    .map { |callback| callback.filter.to_s }
        expect(callbacks.reject { |name| name.start_with?('autosave_associated_records_for_') }).to eq([])
      end
    end

    describe 'no-op' do
      it 'writes nothing for an already sorted list and still audits it with moved 0 (T-SORT-14)' do
        field = own_list(%w[A b C])
        hash_before = RedmineDependingCustomFields::BaseService.state_hash(field)
        sqls = statements { sort(field, direction: 'asc') }
        expect(sqls.grep(/\AUPDATE/i)).to be_empty
        expect(sqls.grep(/\AINSERT/i).size).to eq(1)
        expect(sqls.grep(/\AINSERT/i).first).to include('dcf_config_audit_events')
        expect(RedmineDependingCustomFields::BaseService.state_hash(field.reload)).to eq(hash_before)
        row = rows(field).last
        before = JSON.parse(row.before_value)
        after = JSON.parse(row.after_value)
        expect([row.action, row.status, row.changes_summary]).to eq(['sort_values', 'success', 'Sorted 3 value(s) A-Z (0 moved)'])
        expect(after['moved']).to eq(0)
        expect(after['order_sha256']).to eq(before['order_sha256'])
      end

      it 'writes nothing for a list stored in reverse when sorted desc' do
        field = own_list(%w[c B a])
        sqls = statements { sort(field, direction: 'desc') }
        expect(sqls.grep(/\AUPDATE/i)).to be_empty
        expect(rows(field).last.changes_summary).to eq('Sorted 3 value(s) Z-A (0 moved)')
      end

      it 'writes nothing for enumerations already at 1..N in sorted order' do
        field = dcf_enum_field(names: %w[a B c])
        field.enumerations.find_by(name: 'B').update!(active: false)
        sqls = statements { sort(field, direction: 'asc') }
        expect(sqls.grep(/\AUPDATE/i)).to be_empty
        expect(JSON.parse(rows(field).last.after_value)['moved']).to eq(0)
      end

      it 'audits a field with one value or none as a no-op' do
        [own_list(%w[Only]), dcf_enum_field(names: [])].each do |field|
          sqls = statements { sort(field, direction: 'desc') }
          expect(sqls.grep(/\AUPDATE/i)).to be_empty
          expect(rows(field).last.status).to eq('success')
        end
      end
    end

    describe 'audit row (T-SORT-18)' do
      it 'stores counts, direction, moved and the SHA-256 of the old and the new list order' do
        field = own_list(%w[D a c b])
        sort(field, direction: 'desc')
        row = rows(field).last
        before = JSON.parse(row.before_value)
        after = JSON.parse(row.after_value)
        expect(before.keys.sort).to eq(%w[count order_sha256])
        expect(after.keys.sort).to eq(%w[count direction moved order_sha256])
        expect(before).to eq('count' => 4, 'order_sha256' => digest(%w[D a c b]))
        expect(after).to eq('direction' => 'desc', 'count' => 4, 'moved' => 3, 'order_sha256' => digest(%w[D c b a]))
        expect(row.changes_summary).to eq('Sorted 4 value(s) Z-A (3 moved)')
        expect(row.affected_child_field_ids).to be_nil
        expect([row.action, row.status, row.error_message]).to eq(['sort_values', 'success', nil])
      end

      it 'digests enumeration ids as Strings, inactive included, and counts every value' do
        field = dcf_enum_field(names: %w[c a b])
        field.enumerations.find_by(name: 'a').update!(active: false)
        old_keys = enum_ids(field)
        sort(field, direction: 'asc')
        new_keys = enum_ids(field)
        row = rows(field).last
        expect(JSON.parse(row.before_value)).to eq('count' => 3, 'order_sha256' => digest(old_keys))
        expect(JSON.parse(row.after_value))
          .to eq('direction' => 'asc', 'count' => 3, 'moved' => 3, 'order_sha256' => digest(new_keys))
        expect(row.changes_summary).to eq('Sorted 3 value(s) A-Z (3 moved)')
      end

      it 'keeps labels out of the row' do
        field = own_list(%w[SECRET-B SECRET-A])
        sort(field, direction: 'asc')
        row = rows(field).last
        [row.before_value, row.after_value, row.changes_summary].each { |text| expect(text).not_to include('SECRET') }
      end

      it 'computes the digest with ::JSON.generate over the keys (golden values)' do
        expect(klass.order_sha256([])).to eq('4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945')
        keys = ['10', '2', 'a"b', 'c\\d', 'x/y', '<b>', "\u00E9", "\u2028"]
        expect(klass.order_sha256(keys)).to eq('05a34bb27c72e5d2a301baa232021c1df7daf1865b183d97f4f77fce6e4d81fb')
      end

      it 'never raises on a binary or invalid key' do
        expect(klass.order_sha256(["\xC5\x81".b])).to eq(klass.order_sha256(["\u0141"]))
        expect { klass.order_sha256(["\xFF\xFEx".b, (+"\xC3").force_encoding('UTF-8')]) }.not_to raise_error
      end
    end

    describe 'refusals' do
      it 'refuses any direction but asc or desc with 422 and one validation_failed row (T-SORT-15)' do
        field = own_list(%w[b a])
        [nil, '', 'ASC', ' asc', 'up', :asc, %w[asc], { 'x' => 'asc' }].each do |direction|
          expect { sort(field, direction: direction) }.to expect_refused(:error_reorder_mismatch)
          row = rows(field).last
          expect([row.action, row.status, row.error_message, row.changes_summary])
            .to eq(['validation_failed', 'validation_failed', 'error_reorder_mismatch', nil])
        end
        expect { sort(field, {}) }.to expect_refused(:error_reorder_mismatch)
        expect(field.reload.possible_values).to eq(%w[b a])
        expect(rows(field).where(status: 'success')).to be_empty
      end

      it 'refuses a stale state_hash with 409 and applies nothing; a blank one is not checked (T-SORT-16)' do
        field = dcf_enum_field(names: %w[c b a])
        before = enum_state(field)
        expect { sort(field, direction: 'asc', state_hash: 'stale') }.to raise_error(
          RedmineDependingCustomFields::OperationError
        ) { |e| expect([e.key, e.http_status]).to eq([:error_stale_edit, :conflict]) }
        expect(enum_state(field)).to eq(before)
        expect([rows(field).last.status, rows(field).last.error_message]).to eq(%w[validation_failed error_stale_edit])
        expect { sort(field, direction: 'up', state_hash: 'stale') }.to expect_refused(:error_stale_edit)
        sort(field, direction: 'asc', state_hash: '')
        expect(enum_state(field).map(&:first)).to eq(%w[a b c])
        sort(field, direction: 'desc', state_hash: RedmineDependingCustomFields::BaseService.state_hash(field))
        expect(enum_state(field).map(&:first)).to eq(%w[c b a])
      end

      it 'refuses a user without the permission with one authorization_failed row (T-SORT-17)' do
        field = own_list(%w[b a])
        stranger = dcf_plain_member(project)
        expect do
          klass.new(project: project, field: field, user: stranger, params: { direction: 'asc' }).call
        end.to raise_error(RedmineDependingCustomFields::OperationError) { |e| expect(e.http_status).to eq(:forbidden) }
        row = rows(field).last
        expect([row.action, row.status, row.error_message]).to eq(%w[authorization_failed authorization_failed error_forbidden])
        expect(rows(field).count).to eq(1)
        expect(field.reload.possible_values).to eq(%w[b a])
      end

      # Core refuses every action on an archived project, the administrator
      # included, so the preamble's permission check answers there.
      it 'refuses a closed or an archived project with 403 and writes nothing' do
        { closed: :error_project_archived, archived: :error_forbidden }.each do |status, key|
          other = dcf_create_project(name: "P-#{status}", status: status)
          field = dcf_enum_field(names: %w[c b a])
          before = enum_state(field)
          expect do
            klass.new(project: other, field: field, user: dcf_admin, params: { direction: 'asc' }).call
          end.to raise_error(RedmineDependingCustomFields::OperationError) { |e|
            expect([e.key, e.http_status]).to eq([key, :forbidden])
          }
          expect(enum_state(field)).to eq(before)
        end
      end

      it 'asks no confirmation for a global or a shared field and ignores confirm (UD-23)' do
        global = dcf_list_field(values: %w[c b a], is_for_all: true)
        shared = dcf_list_field(values: %w[c b a], is_for_all: false, projects: [project, dcf_create_project(name: 'O')])
        [[global, nil], [shared, '0']].each do |field, confirm|
          expect { sort(field, direction: 'asc', confirm: confirm) }.not_to raise_error
          expect(field.reload.possible_values).to eq(%w[a b c])
        end
      end
    end

    describe 'transaction and storage errors' do
      it 'rolls every chunk back when the audit insert fails' do
        stub_const('RedmineDependingCustomFields::SortValuesService::CHUNK', 2)
        field = dcf_enum_field(names: %w[E D C B A])
        list = own_list(%w[c b a])
        before = enum_state(field)
        allow_any_instance_of(RedmineDependingCustomFields::AuditRecorder)
          .to receive(:record_success!).and_raise(StandardError, 'boom')
        expect { sort(field, direction: 'asc') }.to raise_error(StandardError, 'boom')
        expect(enum_state(field)).to eq(before)
        expect { sort(list, direction: 'asc') }.to raise_error(StandardError, 'boom')
        expect(list.reload.possible_values).to eq(%w[c b a])
      end

      it 'maps ValueTooLong to a save_failed row without SQL or a value' do
        field = dcf_enum_field(names: %w[c b a])
        before = enum_state(field)
        allow_any_instance_of(ActiveRecord::Relation).to receive(:update_all)
          .and_raise(ActiveRecord::ValueTooLong, "PG::Error: SECRET-SQL 'Label X'")
        expect { sort(field, direction: 'asc') }.to expect_refused(:error_dcf_value_too_long)
        row = rows(field).last
        expect([row.status, row.error_message]).to eq(%w[save_failed error_dcf_value_too_long])
        expect(row.attributes.values.join(' ')).not_to include('SECRET-SQL')
        expect(enum_state(field)).to eq(before)
      end

      it 'lets any other database error propagate unaudited, without its message in a row' do
        field = dcf_enum_field(names: %w[c b a])
        before = enum_state(field)
        allow_any_instance_of(ActiveRecord::Relation).to receive(:update_all)
          .and_raise(ActiveRecord::StatementInvalid, "PG::Error: SECRET-SQL 'Label X'")
        expect { sort(field, direction: 'asc') }.to raise_error(ActiveRecord::StatementInvalid)
        expect(enum_state(field)).to eq(before)
        expect(events.all.map { |row| row.attributes.values.join(' ') }.join).not_to include('SECRET-SQL')
      end
    end

    describe 'hidden children' do
      it 'leaves a role-invisible child byte-identical and out of the row' do
        other_role = dcf_create_role
        parent = own_list(%w[B A])
        child = dcf_list_field(format: 'depending_list', name: "HIDDEN-CHILD-#{SecureRandom.hex(3)}",
                               values: %w[SECRET-V], parent: parent, is_for_all: false, projects: [project])
        dcf_set_dependencies(child, value_dependencies: { 'A' => %w[SECRET-V], 'B' => %w[SECRET-V] })
        child.update!(visible: false, role_ids: [other_role.id])
        before = raw_store(child)
        sort(parent, direction: 'asc')
        expect(raw_store(child)).to eq(before)
        row = rows(parent).last
        expect(row.affected_child_field_ids).to be_nil
        expect(row.attributes.values.join(' ')).not_to include('HIDDEN-CHILD')
        expect(row.attributes.values.join(' ')).not_to include('SECRET-V')
      end
    end

    # G6: the invariance and exact-relation forms, never absolute counts.
    describe 'query shape (G6)' do
      def reversed_enums(count)
        field = dcf_enum_field(names: [])
        CustomFieldEnumeration.insert_all(
          (1..count).map { |i| { custom_field_id: field.id, name: format('N%04d', count + 1 - i), position: i, active: true } }
        )
        CustomField.find(field.id)
      end

      it 'issues ceil(moved / CHUNK) UPDATE statements and the same other statements for 30 and 300 values' do
        stub_const('RedmineDependingCustomFields::SortValuesService::CHUNK', 10)
        small = reversed_enums(30)
        large = reversed_enums(300)
        sort(own_list(%w[b a]), direction: 'asc')
        small_sqls = statements { sort(small, direction: 'asc') }
        large_sqls = statements { sort(large, direction: 'asc') }
        expect(updates_of(small_sqls, 'custom_field_enumerations').size).to eq(30 / 10)
        expect(updates_of(large_sqls, 'custom_field_enumerations').size).to eq(300 / 10)
        expect(enum_state(large).map(&:first).first(2)).to eq(%w[N0001 N0002])
        rest = ->(sqls) { sqls.grep_v(/\AUPDATE/i).size }
        expect(rest.call(large_sqls)).to eq(rest.call(small_sqls))
      end

      it 'sorts 25,000 enumerations with 50 UPDATE statements; the sort itself under 1 s', :perf do
        field = reversed_enums(25_000)
        labels = CustomFieldEnumeration.where(custom_field_id: field.id).pluck(:name)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        RedmineDependingCustomFields::ValueCollation.sort(labels)
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        sqls = statements { sort(field, direction: 'asc') }
        puts format('DCF PERF sort 25000 labels %.3f s', elapsed)
        expect(updates_of(sqls, 'custom_field_enumerations').size).to eq(25_000 / 500)
        expect(elapsed).to be < 1.0
      end
    end
  end

  # --- Set default value (T-DEF-3) ---------------------------------------
  describe 'SetDefaultValueService' do
    it 'sets the default value on a standard list field (T-DEF-3)' do
      field = dcf_list_field(values: %w[A B], is_for_all: false, projects: [project])
      set_default(field, default_value: 'B')
      expect(field.reload.default_value).to eq('B')
    end

    it 'sets the default value on a parent depending_list field (T-DEF-3)' do
      parent = dcf_list_field(format: 'depending_list', name: 'Parent', values: %w[A B],
                              is_for_all: false, projects: [project])
      set_default(parent, default_value: 'A')
      expect(parent.reload.default_value).to eq('A')
    end

    it 'sets the default to an enumeration id (T-DEF-3)' do
      field = dcf_enum_field(names: %w[X Y])
      enum = field.enumerations.order(:position).last
      set_default(field, default_value: enum.id.to_s)
      expect(field.reload.default_value).to eq(enum.id.to_s)
    end

    it 'clears the default value when a blank value is submitted (T-DEF-3)' do
      field = dcf_list_field(values: %w[A B], default_value: 'A', is_for_all: false, projects: [project])
      set_default(field, default_value: '')
      expect(field.reload.default_value).to be_blank
    end

    it 'rejects a default value that is not one of the field values (T-DEF-3)' do
      field = dcf_list_field(values: %w[A B], is_for_all: false, projects: [project])
      expect { set_default(field, default_value: 'ZZ') }
        .to raise_error(RedmineDependingCustomFields::OperationError) { |e| expect(e.key).to eq(:error_invalid_default_value) }
      expect(field.reload.default_value).to be_blank
    end

    it 'refuses to set a plain default on a depending child field (T-DEF-3)' do
      parent = dcf_list_field(name: 'Parent', values: %w[P], is_for_all: false, projects: [project])
      child = dcf_list_field(format: 'depending_list', name: 'Child', values: %w[A B],
                             parent: parent, is_for_all: false, projects: [project])
      expect { set_default(child, default_value: 'A') }
        .to raise_error(RedmineDependingCustomFields::OperationError) { |e| expect(e.key).to eq(:error_format_unsupported) }
    end
  end

  # --- Enumeration batch editor (T-ACT) ----------------------------------
  describe 'UpdateEnumerationsService' do
    it 'deactivates a value and hides it from the pickers (T-ACT-1)' do
      field = dcf_enum_field(names: %w[X Y])
      enum = field.enumerations.order(:position).first
      save_enums(field, enum.id => { active: false })
      expect(enum.reload.active).to be false
      expect(field.reload.format.possible_values_options(field).map(&:last)).not_to include(enum.id.to_s)
    end

    it 'reactivates a deactivated value (T-ACT-2)' do
      field = dcf_enum_field(names: %w[X Y])
      enum = field.enumerations.order(:position).first
      enum.update!(active: false)
      save_enums(field, enum.id => { active: true })
      expect(enum.reload.active).to be true
    end

    it 'works the same on a depending_enumeration field (T-ACT-1)' do
      parent = dcf_enum_field(name: 'Parent', names: %w[P])
      field = dcf_enum_field(format: 'depending_enumeration', name: 'Child', names: %w[X Y], parent: parent)
      enum = field.enumerations.order(:position).first
      save_enums(field, enum.id => { active: false })
      expect(enum.reload.active).to be false
    end

    it 'rejects a list-family field, which has no enumerations (T-ACT-3)' do
      field = dcf_list_field(values: %w[A B], is_for_all: false, projects: [project])
      expect { save_enums(field) }
        .to raise_error(RedmineDependingCustomFields::OperationError) { |e| expect(e.key).to eq(:error_format_unsupported) }
    end

    # The submitted id set must match the field's exactly, so a payload carrying
    # a foreign id is refused as a whole rather than partly applied.
    it 'rejects a payload naming an enumeration of another field (T-ACT-4)' do
      field = dcf_enum_field(names: %w[X])
      other = dcf_enum_field(name: 'Other', names: %w[Z])
      alien = other.enumerations.first
      payload = { alien.id.to_s => { 'name' => 'Hacked', 'position' => '1', 'active' => '0' } }
      expect do
        RedmineDependingCustomFields::UpdateEnumerationsService
          .new(project: project, field: field, user: user, params: { enumerations: payload }).call
      end.to raise_error(RedmineDependingCustomFields::OperationError) { |e| expect(e.key).to eq(:error_reorder_mismatch) }
      expect(alien.reload).to have_attributes(name: 'Z', active: true)
    end

    it 'rejects a partial submit without applying any of it (T-ACT-21)' do
      field = dcf_enum_field(names: %w[X Y Z])
      first = field.enumerations.order(:position).first
      payload = enum_payload(field, first.id => { name: 'Renamed' })
      payload.delete(field.enumerations.order(:position).last.id.to_s)
      expect do
        RedmineDependingCustomFields::UpdateEnumerationsService
          .new(project: project, field: field, user: user, params: { enumerations: payload }).call
      end.to raise_error(RedmineDependingCustomFields::OperationError) { |e| expect(e.key).to eq(:error_reorder_mismatch) }
      expect(first.reload.name).to eq('X')
    end

    it 'clears a dangling default_value when its value is deactivated (T-ACT-5)' do
      field = dcf_enum_field(names: %w[X Y])
      enum = field.enumerations.order(:position).first
      field.update!(default_value: enum.id.to_s)
      save_enums(field, enum.id => { active: false })
      expect(field.reload.default_value).to be_blank
    end

    it 'keeps the default_value when a different value is deactivated (T-ACT-5)' do
      field = dcf_enum_field(names: %w[X Y])
      keep, drop = field.enumerations.order(:position).to_a
      field.update!(default_value: keep.id.to_s)
      save_enums(field, drop.id => { active: false })
      expect(field.reload.default_value).to eq(keep.id.to_s)
    end

    it 'refuses to reactivate a value whose name is taken by an active one (T-ACT-6)' do
      field = dcf_enum_field(names: %w[X])
      stale = field.enumerations.first
      stale.update!(active: false)
      add(field, value: 'X')
      expect { save_enums(field, stale.id => { active: true }) }
        .to raise_error(RedmineDependingCustomFields::OperationError) { |e| expect(e.key).to eq(:error_value_duplicate) }
      expect(stale.reload.active).to be false
    end

    # The duplicate check looks at the RESULTING state, so a rename onto a
    # sibling's name inside the same save is caught too.
    it 'refuses a rename that collides within the same save (T-ACT-24)' do
      field = dcf_enum_field(names: %w[X Y])
      x, y = field.enumerations.order(:position).to_a
      expect { save_enums(field, x.id => { name: 'Y' }) }
        .to raise_error(RedmineDependingCustomFields::OperationError) { |e| expect(e.key).to eq(:error_value_duplicate) }
      expect(x.reload.name).to eq('X')
      expect(y.reload.name).to eq('Y')
    end

    it 'allows a name that duplicates an INACTIVE value (T-ACT-24)' do
      field = dcf_enum_field(names: %w[X Y])
      x, y = field.enumerations.order(:position).to_a
      x.update!(active: false)
      save_enums(field, y.id => { name: 'X' })
      expect(y.reload.name).to eq('X')
    end

    it 'rejects a blank name without applying the rest of the save (T-ACT-22)' do
      field = dcf_enum_field(names: %w[X Y])
      x, y = field.enumerations.order(:position).to_a
      expect { save_enums(field, x.id => { name: '  ' }, y.id => { active: false }) }
        .to raise_error(RedmineDependingCustomFields::OperationError) { |e| expect(e.key).to eq(:error_value_blank) }
      expect(x.reload.name).to eq('X')
      expect(y.reload.active).to be true
    end

    # A name the model rejects (max 60 chars) must roll the whole save back, not
    # leave the rows before it in the loop already written.
    it 'rolls the whole save back when a row fails model validation (T-ACT-22)' do
      field = dcf_enum_field(names: %w[X Y])
      x, y = field.enumerations.order(:position).to_a
      expect { save_enums(field, x.id => { active: false }, y.id => { name: 'N' * 61 }) }
        .to raise_error(RedmineDependingCustomFields::OperationError) { |e| expect(e.key).to eq(:error_save_failed) }
      expect(x.reload.active).to be true
      expect(y.reload.name).to eq('Y')
    end

    it 'applies the submitted positions (T-ACT-23)' do
      field = dcf_enum_field(names: %w[X Y Z])
      x, y, z = field.enumerations.order(:position).to_a
      save_enums(field, x.id => { position: 3 }, y.id => { position: 1 }, z.id => { position: 2 })
      expect(field.reload.enumerations.order(:position).map(&:name)).to eq(%w[Y Z X])
    end

    # The whole point of the batch form: one Save, one operation, one audit row.
    it 'applies a rename, a deactivation and a reorder in one save (T-ACT-20)' do
      field = dcf_enum_field(names: %w[X Y Z])
      x, y, z = field.enumerations.order(:position).to_a
      expect do
        save_enums(field,
                   x.id => { name: 'X2', position: 3 },
                   y.id => { active: false, position: 1 },
                   z.id => { position: 2 })
      end.to change {
        RedmineDependingCustomFields::ConfigAuditEvent.where(action: 'update_enumerations', status: 'success').count
      }.by(1)
      expect(field.reload.enumerations.order(:position).map(&:name)).to eq(%w[Y Z X2])
      expect(y.reload.active).to be false
    end

    it 'leaves own and child dependency entries untouched (T-ACT-7)' do
      parent = dcf_enum_field(name: 'Parent', names: %w[P1 P2])
      child = dcf_enum_field(format: 'depending_enumeration', name: 'Child', names: %w[C1], parent: parent)
      p1, p2 = parent.enumerations.order(:position).to_a
      c1 = child.enumerations.first
      dcf_set_dependencies(child, value_dependencies: { p1.id.to_s => [c1.id.to_s], p2.id.to_s => [c1.id.to_s] })
      save_enums(parent, p1.id => { active: false })
      expect(child.reload.value_dependencies)
        .to eq(p1.id.to_s => [c1.id.to_s], p2.id.to_s => [c1.id.to_s])
    end

    it 'keeps existing issue values resolvable after deactivation (T-ACT-8)' do
      field = dcf_enum_field(names: %w[X Y])
      enum = field.enumerations.order(:position).first
      dcf_issue_with_value(project, field, enum.id)
      save_enums(field, enum.id => { active: false })
      expect(CustomValue.where(custom_field_id: field.id, value: enum.id.to_s).count).to eq(1)
      expect(CustomFieldEnumeration.find(enum.id).name).to eq('X')
    end

    it 'rejects a stale state_hash (T-ACT-9)' do
      field = dcf_enum_field(names: %w[X Y])
      enum = field.enumerations.order(:position).first
      expect { save_enums(field, { enum.id => { active: false } }, state_hash: 'stale') }
        .to raise_error(RedmineDependingCustomFields::OperationError) do |e|
          expect(e.key).to eq(:error_stale_edit)
          expect(e.http_status).to eq(:conflict)
        end
      expect(enum.reload.active).to be true
    end

    # The digest covers name, position and active, so a hash captured before an
    # earlier save must not be accepted afterwards.
    it 'invalidates a state_hash captured before an earlier save (T-ACT-9)' do
      field = dcf_enum_field(names: %w[X Y])
      first, second = field.enumerations.order(:position).to_a
      stale_hash = RedmineDependingCustomFields::BaseService.state_hash(field)
      save_enums(field, first.id => { active: false })
      expect { save_enums(field, { second.id => { active: false } }, state_hash: stale_hash) }
        .to raise_error(RedmineDependingCustomFields::OperationError) { |e| expect(e.key).to eq(:error_stale_edit) }
      expect(second.reload.active).to be true
    end

    it 'summarises what the save changed in the audit row (T-ACT-10)' do
      field = dcf_enum_field(names: %w[X Y])
      x = field.enumerations.order(:position).first
      save_enums(field, x.id => { name: 'X2', active: false })
      event = RedmineDependingCustomFields::ConfigAuditEvent
              .where(action: 'update_enumerations', status: 'success').last
      expect(event).to be_present
      expect(event.changes_summary).to eq('Saved 2 enumeration value(s): renamed 1, deactivated 1')
    end

    it 'records how many stored values a deactivation affects (T-ACT-10)' do
      field = dcf_enum_field(names: %w[X Y])
      enum = field.enumerations.order(:position).first
      2.times { |i| dcf_custom_value(field, enum.id, customized_id: 900_000 + i) }
      save_enums(field, enum.id => { active: false })
      event = RedmineDependingCustomFields::ConfigAuditEvent.where(action: 'update_enumerations').last
      expect(event.affected_values_count).to eq(2)
    end

    it 'notes the cleared default in the audit summary (T-ACT-10)' do
      field = dcf_enum_field(names: %w[X])
      enum = field.enumerations.first
      field.update!(default_value: enum.id.to_s)
      save_enums(field, enum.id => { active: false })
      event = RedmineDependingCustomFields::ConfigAuditEvent.where(action: 'update_enumerations').last
      expect(event.changes_summary).to include('default value cleared')
    end

    # Checkbox semantics: an unticked box submits only the hidden "0", and a row
    # that omits the param entirely means the same thing.
    it 'treats a missing active param as unticked (T-ACT-11)' do
      field = dcf_enum_field(names: %w[X])
      enum = field.enumerations.first
      payload = { enum.id.to_s => { 'name' => 'X', 'position' => '1' } }
      RedmineDependingCustomFields::UpdateEnumerationsService
        .new(project: project, field: field, user: user, params: { enumerations: payload }).call
      expect(enum.reload.active).to be false
    end

    it 'accepts a save that changes nothing (T-ACT-11)' do
      field = dcf_enum_field(names: %w[X Y])
      expect { save_enums(field) }.not_to raise_error
      event = RedmineDependingCustomFields::ConfigAuditEvent.where(action: 'update_enumerations').last
      expect(event.changes_summary).to include('no changes')
    end

    # --- The production contract of "deactivate, don't delete" ------------
    # These exercise Redmine's real validation path, not just CustomValue rows.
    # They are the guard against a future prune being added here.
    it 'keeps an issue holding a deactivated value saveable and readable (T-ACT-17)' do
      field = dcf_enum_field(names: %w[X Y])
      enum = field.enumerations.order(:position).first
      issue = dcf_real_issue(project, { field => enum.id.to_s })
      expect(issue.custom_field_value(field)).to eq(enum.id.to_s)

      save_enums(field, enum.id => { active: false })

      reloaded = Issue.find(issue.id)
      reloaded.subject = 'edited after deactivation'
      expect(reloaded.save).to be true
      expect(reloaded.custom_field_value(field)).to eq(enum.id.to_s)
      # Core re-adds the stored value to the options of the record that holds
      # it, so the name still renders and an edit cannot silently drop it.
      cv = reloaded.custom_field_values.detect { |v| v.custom_field_id == field.id }
      expect(field.format.possible_custom_value_options(cv).map(&:last)).to include(enum.id.to_s)
      expect(field.format.cast_value(field, cv.value).to_s).to eq('X')
    end

    it 'stops a new issue from selecting a deactivated value (T-ACT-18)' do
      field = dcf_enum_field(names: %w[X Y])
      enum = field.enumerations.order(:position).first
      dcf_real_issue(project, { field => enum.id.to_s }) # links the field to the tracker
      save_enums(field, enum.id => { active: false })

      tracker, status, priority = dcf_issue_infra(project)
      fresh = Issue.new(project: project, tracker: tracker, subject: 'new',
                        author: dcf_admin, status: status, priority: priority)
      fresh.custom_field_values = { field.id => enum.id.to_s }
      expect(fresh.save).to be false
    end

    # Only true because deactivation does not prune the mapping: pruning would
    # leave an issue already on that parent with no allowed child options.
    it 'keeps a child field usable on issues already on a deactivated parent (T-ACT-19)' do
      parent = dcf_enum_field(name: 'Parent', names: %w[P1 P2])
      child = dcf_enum_field(format: 'depending_enumeration', name: 'Child',
                             names: %w[C1 C2], parent: parent)
      p1 = parent.enumerations.order(:position).first
      c1 = child.enumerations.order(:position).first
      dcf_set_dependencies(child, value_dependencies: { p1.id.to_s => [c1.id.to_s] })
      issue = dcf_real_issue(project, { parent => p1.id.to_s, child => c1.id.to_s })

      save_enums(parent, p1.id => { active: false })

      reloaded = Issue.find(issue.id)
      reloaded.subject = 'edited after parent deactivation'
      expect(reloaded.save).to be true
      # C1 stays selectable for this issue; C2 stays hidden, exactly as before.
      visible = child.format.possible_values_options(child, reloaded)
                     .reject { |o| o.is_a?(Array) && o[2].is_a?(Hash) }
      expect(visible.map(&:last)).to eq([c1.id.to_s])
    end

    it 'rejects the operation for a user without the permission (T-ACT-12)' do
      field = dcf_enum_field(names: %w[X])
      enum = field.enumerations.first
      expect do
        RedmineDependingCustomFields::UpdateEnumerationsService
          .new(project: project, field: field, user: dcf_plain_member(project),
               params: { enumerations: enum_payload(field, enum.id => { active: false }) }).call
      end.to raise_error(RedmineDependingCustomFields::OperationError) do |e|
        expect(e.http_status).to eq(:forbidden)
      end
      expect(enum.reload.active).to be true
    end
  end

  # --- Audit (T-AUD) -----------------------------------------------------
  describe 'audit integration' do
    it 'writes exactly one success event (T-AUD-1)' do
      field = dcf_list_field(values: %w[A], is_for_all: false, projects: [project])
      expect { add(field, value: 'B') }
        .to change { RedmineDependingCustomFields::ConfigAuditEvent.where(action: 'add_value', status: 'success').count }.by(1)
    end

    it 'rolls back the change when the audit insert fails (T-AUD-2)' do
      field = dcf_list_field(values: %w[A], is_for_all: false, projects: [project])
      allow_any_instance_of(RedmineDependingCustomFields::AuditRecorder)
        .to receive(:record_success!).and_raise(StandardError, 'boom')
      expect { add(field, value: 'B') }.to raise_error(StandardError)
      expect(field.reload.possible_values).to eq(%w[A])
    end

    it 'records an authorization_failed event for an unauthorized user (T-AUD-3)' do
      field = dcf_list_field(values: %w[A], is_for_all: false, projects: [project])
      stranger = dcf_plain_member(project)
      expect do
        RedmineDependingCustomFields::AddValueService
          .new(project: project, field: field, user: stranger, params: { value: 'B' }).call
      end.to raise_error(RedmineDependingCustomFields::OperationError)
      expect(RedmineDependingCustomFields::ConfigAuditEvent.where(status: 'authorization_failed').count).to eq(1)
    end

    it 'records a validation_failed event on a rejected input (T-AUD-4)' do
      field = dcf_list_field(values: %w[A], is_for_all: false, projects: [project])
      expect { add(field, value: '') }.to raise_error(RedmineDependingCustomFields::OperationError)
      expect(RedmineDependingCustomFields::ConfigAuditEvent.where(status: 'validation_failed').count).to eq(1)
    end
  end
end
