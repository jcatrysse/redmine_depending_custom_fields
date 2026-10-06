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

    # Enumerations are stored by id; core allows a shared name, so do we.
    it 'allows an enumeration with an existing name (T-ADD-3)' do
      field = dcf_enum_field(names: %w[X])
      expect { add(field, value: 'X') }.to change { field.enumerations.where(name: 'X').count }.from(1).to(2)
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

    it 'allows renaming an enumeration onto an existing name (T-REN-4)' do
      field = dcf_enum_field(names: %w[X Y])
      x, _y = field.enumerations.order(:position).to_a
      rename(field, enumeration_id: x.id, new_value: 'Y')
      expect(x.reload.name).to eq('Y')
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

    # Duplicate names are allowed, as in core: the value is the id, and a
    # depending field can offer the same label under different parents.
    it 'reactivates a value whose name an active one also holds (T-ACT-6)' do
      field = dcf_enum_field(names: %w[X])
      stale = field.enumerations.first
      stale.update!(active: false)
      add(field, value: 'X')
      save_enums(field, stale.id => { active: true })
      expect(stale.reload.active).to be true
      expect(field.enumerations.where(name: 'X', active: true).count).to eq(2)
    end

    it 'allows a rename onto a sibling name within the same save (T-ACT-24)' do
      field = dcf_enum_field(names: %w[X Y])
      x, y = field.enumerations.order(:position).to_a
      save_enums(field, x.id => { name: 'Y' })
      expect(x.reload.name).to eq('Y')
      expect(y.reload.name).to eq('Y')
    end

    it 'reorders and renames around a duplicate already in the data (T-ACT-27)' do
      field = dcf_enum_field(names: %w[X Y X])
      x1, y, x2 = field.enumerations.order(:position).to_a
      save_enums(field, x1.id => { position: 3 }, y.id => { name: 'Y2', position: 1 }, x2.id => { position: 2 })
      expect(field.reload.enumerations.order(:position).map(&:id)).to eq([y.id, x2.id, x1.id])
      expect(y.reload.name).to eq('Y2')
    end

    # The submitted name is stripped, so a stored name with stray whitespace
    # must not count as renamed (nor be rewritten) on every save.
    it 'does not treat a whitespace-only difference as a rename (T-ACT-27)' do
      field = dcf_enum_field(names: %w[X Y])
      x, y = field.enumerations.order(:position).to_a
      x.update_column(:name, 'X ')
      save_enums(field, x.id => { position: 2 }, y.id => { position: 1 })
      expect(x.reload.name).to eq('X ')
      event = RedmineDependingCustomFields::ConfigAuditEvent
              .where(action: 'update_enumerations', status: 'success').order(:id).last
      expect(event.changes_summary).not_to include('renamed')
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
