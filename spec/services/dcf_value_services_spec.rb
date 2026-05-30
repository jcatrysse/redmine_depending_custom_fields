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
