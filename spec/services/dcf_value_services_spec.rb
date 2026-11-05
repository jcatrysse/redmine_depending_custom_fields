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

  # --- Exact value matching (SD-17, WP-33) -------------------------------
  # MySQL and MariaDB compare TEXT with the column collation (case and
  # accents ignored, trailing spaces padded); the services match the stored
  # bytes on every database. Untagged, so PostgreSQL runs them too. Rows are
  # read back by id and compared in Ruby (where(value:) would itself follow
  # the collation).
  describe 'exact value matching (SD-17, WP-33)' do
    let(:other) { dcf_create_project(name: 'Other') }
    let(:near) { ['a', "\u00c1", "A\u00a0", "\u{1F34E}", "\u{1F350}", 'B'] }

    def stored(field)
      CustomValue.where(custom_field_id: field.id).order(:id).pluck(:value)
    end

    def usage(field, value)
      calc = RedmineDependingCustomFields::UsageCalculator
      [calc.usage_here(field, value, project), calc.usage_other(field, value, project)]
    end

    def last_event(field)
      RedmineDependingCustomFields::ConfigAuditEvent.where(custom_field_id: field.id).order(:id).last
    end

    # Stored 'A' x2 here and x1 elsewhere, every near miss once, and 'A '
    # (trailing space, written directly: core strips possible values).
    def near_miss_field(is_for_all: true, projects: nil)
      field = dcf_list_field(values: ['A'] + near, is_for_all: is_for_all, projects: projects)
      2.times { dcf_issue_with_value(project, field, 'A') }
      dcf_issue_with_value(other, field, 'A')
      (near + ['A ']).each_with_index { |value, i| dcf_issue_with_value(i.even? ? project : other, field, value) }
      field
    end

    it 'renames only the rows stored exactly as the old value; the counts match the rewritten rows' do
      field = near_miss_field
      before = stored(field)
      expect(usage(field, 'A')).to eq([2, 1])
      outcome = rename(field, old_value: 'A', new_value: 'C', confirm: '1')
      expect(stored(field)).to eq(before.map { |value| value == 'A' ? 'C' : value })
      expect(stored(field).count('C')).to eq(3)
      expect(outcome.affected_values_count).to eq(3)
      expect(last_event(field).affected_values_count).to eq(3)
      expect(field.reload.possible_values).to eq(['C'] + near)
    end

    it 'counts every near miss on its own and renames one emoji without the other' do
      field = near_miss_field
      expect(near.map { |value| usage(field, value) }).to eq([[1, 0], [0, 1], [1, 0], [0, 1], [1, 0], [0, 1]])
      expect(usage(field, 'A ')).to eq([1, 0])
      expect(RedmineDependingCustomFields::UsageCalculator.usage_total(field, 'A')).to eq(3)
      before = stored(field)
      rename(field, old_value: "\u{1F34E}", new_value: 'Apple', confirm: '1')
      expect(stored(field)).to eq(before.map { |value| value == "\u{1F34E}" ? 'Apple' : value })
    end

    it 'leaves the near misses untouched on a rename to the same value' do
      field = near_miss_field
      before = stored(field)
      outcome = rename(field, old_value: 'A', new_value: 'A', confirm: '1')
      expect(stored(field)).to eq(before)
      expect(outcome.affected_values_count).to eq(3)
    end

    it "renames 'A' to 'a' when 'a' is no possible value, rewriting only the 'A' rows" do
      field = dcf_list_field(values: ['A', "\u00c1", 'B'], is_for_all: false, projects: [project])
      %w[A a].each { |value| dcf_issue_with_value(project, field, value) }
      dcf_issue_with_value(project, field, "\u00c1")
      rename(field, old_value: 'A', new_value: 'a', confirm: '1')
      expect(stored(field)).to eq(['a', 'a', "\u00c1"])
      expect(field.reload.possible_values).to eq(['a', "\u00c1", 'B'])
    end

    it "still refuses renaming 'A' to 'a' while 'a' is a possible value" do
      field = dcf_list_field(values: %w[A a], is_for_all: false, projects: [project])
      dcf_issue_with_value(project, field, 'a')
      expect { rename(field, old_value: 'A', new_value: 'a', confirm: '1') }
        .to raise_error(RedmineDependingCustomFields::OperationError) { |e| expect(e.key).to eq(:error_value_duplicate) }
      expect(stored(field)).to eq(%w[a])
    end

    it 'asks no confirmation when only a value differing in case is used in another project' do
      field = dcf_list_field(values: %w[A a], is_for_all: false, projects: [project])
      dcf_issue_with_value(project, field, 'A')
      dcf_issue_with_value(other, field, 'a')
      expect(usage(field, 'A')).to eq([1, 0])
      outcome = rename(field, old_value: 'A', new_value: 'C')
      expect(stored(field)).to eq(%w[C a])
      expect(outcome.affected_values_count).to eq(1)
    end

    it 'removes a value with block_removal_when_used while only a value differing in accents is stored' do
      allow(Setting).to receive(:plugin_redmine_depending_custom_fields)
        .and_return('block_removal_when_used' => '1')
      field = dcf_list_field(values: ['A', "\u00c1", 'B'], is_for_all: false, projects: [project])
      dcf_issue_with_value(project, field, 'A')
      outcome = remove(field, value: "\u00c1")
      expect(field.reload.possible_values).to eq(%w[A B])
      expect(outcome.affected_values_count).to eq(0)
      expect { remove(field, value: 'A', confirm: '1') }
        .to raise_error(RedmineDependingCustomFields::OperationError) { |e| expect(e.key).to eq(:error_value_in_use) }
    end

    it 'counts an enumeration id by its string, not a longer or padded one' do
      field = dcf_enum_field(names: %w[X Y])
      enum = field.enumerations.order(:position).first
      [enum.id.to_s, "#{enum.id}0", "#{enum.id} "].each { |value| dcf_issue_with_value(project, field, value) }
      expect(RedmineDependingCustomFields::UsageCalculator.usage_total(field, enum.id)).to eq(1)
      outcome = remove(field, enumeration_id: enum.id, confirm: '1')
      expect(outcome.affected_values_count).to eq(1)
      expect(enum.reload.active).to be(false)
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

    # Changed by WP-34 (UD-23): confirm '1' on the global (dcf_enum_field) sort; was no confirm.
    it 'chains the digests: the reorder before equals the sort after' do
      field = dcf_enum_field(names: %w[c a b])
      RedmineDependingCustomFields::SortValuesService
        .new(project: project, field: field, user: user, params: { direction: 'asc', confirm: '1' }).call
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
      # Changed by WP-34 (UD-23): confirm '1' on the global (dcf_enum_field) sort; was no confirm.
      it 'gives every enumeration a position 1..N, inactive ones interleaved (T-SORT-12, UD-24)' do
        field = dcf_enum_field(names: %w[c B a])
        field.enumerations.find_by(name: 'B').update!(active: false)
        names_before = CustomFieldEnumeration.where(custom_field_id: field.id).order(:id).pluck(:id, :name)
        sort(field, direction: 'asc', confirm: '1')
        expect(enum_state(field)).to eq([['a', 1, true], ['B', 2, false], ['c', 3, true]])
        expect(CustomFieldEnumeration.where(custom_field_id: field.id).order(:id).pluck(:id, :name)).to eq(names_before)
      end

      # Changed by WP-32: the rows are picked by exact name in Ruby; where(name:)
      # also matched 'A' under the case- and accent-insensitive MariaDB collation.
      # Changed by WP-34 (UD-23): confirm '1' on the global (dcf_enum_field) sort; was no confirm.
      it 'keeps the stored order of ties and sorts desc on the same keys' do
        field = dcf_enum_field(names: ['C', 'b', 'A', "\u00E4"])
        ids = field.enumerations.select { |enum| ['b', "\u00E4"].include?(enum.name) }.map(&:id)
        CustomFieldEnumeration.where(id: ids).update_all(active: false)
        expect(enum_state(field)).to eq([['C', 1, true], ['b', 2, false], ['A', 3, true], ["\u00E4", 4, false]])
        sort(field, direction: 'asc', confirm: '1')
        expect(enum_state(field)).to eq([['A', 1, true], ["\u00E4", 2, false], ['b', 3, false], ['C', 4, true]])
        sort(field, direction: 'desc', confirm: '1')
        expect(enum_state(field)).to eq([['C', 1, true], ['b', 2, false], ['A', 3, true], ["\u00E4", 4, false]])
      end

      # Changed by WP-34 (UD-23): confirm '1' on the global (dcf_enum_field) sort; was no confirm.
      it 'renumbers gapped positions and counts the rows written as moved' do
        field = dcf_enum_field(names: %w[a b c])
        field.enumerations.order(:position).each_with_index { |e, i| e.update_column(:position, [2, 5, 7][i]) }
        sort(field, direction: 'asc', confirm: '1')
        expect(enum_state(field)).to eq([['a', 1, true], ['b', 2, true], ['c', 3, true]])
        expect(JSON.parse(rows(field).last.after_value)['moved']).to eq(3)
      end

      # Changed by WP-34 (UD-23): confirm '1' on the global (dcf_enum_field) sort; was no confirm.
      it 'reads tied positions in [position, id] order' do
        field = dcf_enum_field(names: %w[b a c])
        field.enumerations.update_all(position: 1)
        old_keys = enum_ids(field)
        expect(old_keys).to eq(CustomFieldEnumeration.where(custom_field_id: field.id).order(:id).pluck(:id).map(&:to_s))
        sort(field, direction: 'asc', confirm: '1')
        expect(enum_state(field).map(&:first)).to eq(%w[a b c])
        expect(JSON.parse(rows(field).last.before_value)['order_sha256']).to eq(digest(old_keys))
      end

      # Changed by WP-32: Rails 7.2 and later quote the bound integers on MySQL
      # (WHEN '12' THEN '1'), so both patterns accept optional quotes and the
      # ids of every statement are counted, never an empty scan.
      # Changed by WP-34 (UD-23): confirm '1' on the global (dcf_enum_field) sort; was no confirm.
      it 'updates only the changed rows, one CASE statement per CHUNK, saving no field (T-SORT-17)' do
        stub_const('RedmineDependingCustomFields::SortValuesService::CHUNK', 2)
        field = dcf_enum_field(names: %w[E D C B A])
        middle = field.enumerations.find_by(name: 'C').id
        sqls = statements { sort(field, direction: 'asc', confirm: '1') }
        expect(enum_state(field)).to eq([['A', 1, true], ['B', 2, true], ['C', 3, true], ['D', 4, true], ['E', 5, true]])
        updates = updates_of(sqls, 'custom_field_enumerations')
        expect(updates.size).to eq((4 / 2.0).ceil)
        updates.each do |sql|
          expect(sql).to match(/SET\s+position\s*=\s*CASE\s+id(\s+WHEN\s+'?\d+'?\s+THEN\s+'?\d+'?)+\s+ELSE\s+position\s+END/i)
          expect(sql).to include('custom_field_id')
          ids = sql.scan(/WHEN\s+'?(\d+)'?\s+THEN/).flatten
          expect(ids.size).to eq(2)
          expect(ids).not_to include(middle.to_s)
        end
        expect(updates_of(sqls, 'custom_fields')).to be_empty
        expect(updates_of(sqls, 'custom_values')).to be_empty
        expect(JSON.parse(rows(field).last.after_value)['moved']).to eq(4)
      end

      # Changed by WP-34 (UD-23): confirm '1' on the global (dcf_enum_field) sort; was no confirm.
      it 'sends the last chunk too when the changed rows do not fill it' do
        stub_const('RedmineDependingCustomFields::SortValuesService::CHUNK', 2)
        field = dcf_enum_field(names: %w[B C D E A])
        sqls = statements { sort(field, direction: 'asc', confirm: '1') }
        expect(enum_state(field).map(&:first)).to eq(%w[A B C D E])
        expect(updates_of(sqls, 'custom_field_enumerations').size).to eq((5 / 2.0).ceil)
      end

      # Changed by WP-34 (UD-23): confirm '1' on the global (dcf_enum_field) sort; was no confirm.
      it 'builds the SQL from integers only, whatever the labels' do
        field = dcf_enum_field(names: ["x' THEN 0 END; DROP TABLE users; --", '%{a} ?', 'a'])
        sqls = statements { sort(field, direction: 'asc', confirm: '1') }
        updates = updates_of(sqls, 'custom_field_enumerations')
        expect(updates).not_to be_empty
        updates.each do |sql|
          expect(sql).not_to include('DROP TABLE')
          expect(sql).not_to include('%{a}')
        end
        expect(enum_state(field).map(&:first)).to eq(['%{a} ?', 'a', "x' THEN 0 END; DROP TABLE users; --"])
        expect(User.where(id: 1)).to exist
      end

      # Changed by WP-34 (UD-23): confirm '1' on the global (dcf_enum_field) sort; was no confirm.
      it 'rewrites no CustomValue of an enumeration field (T-SORT-13)' do
        field = dcf_enum_field(names: %w[c b a])
        b = field.enumerations.find_by(name: 'b')
        dcf_issue_with_value(project, field, b.id)
        before = CustomValue.where(custom_field_id: field.id).pluck(:id, :value)
        sqls = statements { sort(field, direction: 'asc', confirm: '1') }
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

      # Changed by WP-34 (UD-23): confirm '1' on the global (dcf_enum_field) sort; was no confirm.
      it 'writes nothing for enumerations already at 1..N in sorted order' do
        field = dcf_enum_field(names: %w[a B c])
        field.enumerations.find_by(name: 'B').update!(active: false)
        sqls = statements { sort(field, direction: 'asc', confirm: '1') }
        expect(sqls.grep(/\AUPDATE/i)).to be_empty
        expect(JSON.parse(rows(field).last.after_value)['moved']).to eq(0)
      end

      # Changed by WP-34 (UD-23): confirm '1' on the global (dcf_enum_field) sort; was no confirm.
      it 'audits a field with one value or none as a no-op' do
        [own_list(%w[Only]), dcf_enum_field(names: [])].each do |field|
          sqls = statements { sort(field, direction: 'desc', confirm: '1') }
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

      # Changed by WP-34 (UD-23): confirm '1' on the global (dcf_enum_field) sort; was no confirm.
      it 'digests enumeration ids as Strings, inactive included, and counts every value' do
        field = dcf_enum_field(names: %w[c a b])
        field.enumerations.find_by(name: 'a').update!(active: false)
        old_keys = enum_ids(field)
        sort(field, direction: 'asc', confirm: '1')
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

      # Changed by WP-34 (UD-23): confirm '1' on the global (dcf_enum_field) sort; was no confirm.
      it 'refuses a stale state_hash with 409 and applies nothing; a blank one is not checked (T-SORT-16)' do
        field = dcf_enum_field(names: %w[c b a])
        before = enum_state(field)
        expect { sort(field, direction: 'asc', state_hash: 'stale') }.to raise_error(
          RedmineDependingCustomFields::OperationError
        ) { |e| expect([e.key, e.http_status]).to eq([:error_stale_edit, :conflict]) }
        expect(enum_state(field)).to eq(before)
        expect([rows(field).last.status, rows(field).last.error_message]).to eq(%w[validation_failed error_stale_edit])
        expect { sort(field, direction: 'up', state_hash: 'stale') }.to expect_refused(:error_stale_edit)
        sort(field, direction: 'asc', state_hash: '', confirm: '1')
        expect(enum_state(field).map(&:first)).to eq(%w[a b c])
        sort(field, direction: 'desc', state_hash: RedmineDependingCustomFields::BaseService.state_hash(field), confirm: '1')
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

      # Flipped by WP-34 (UD-23 changed by the owner on 2026-11-02): a global
      # or a shared field asks for the confirmation unless confirm is '1';
      # was 'asks no confirmation for a global or a shared field and ignores
      # confirm (UD-23)', sorted with confirm nil and '0'.
      it 'asks the confirmation for a global or a shared field unless confirm is 1 (UD-23, WP-34)' do
        global = dcf_list_field(values: %w[c b a], is_for_all: true)
        shared = dcf_list_field(values: %w[c b a], is_for_all: false, projects: [project, dcf_create_project(name: 'O')])
        [[global, nil], [shared, '0']].each do |field, confirm|
          expect { sort(field, direction: 'asc', confirm: confirm) }
            .to raise_error(RedmineDependingCustomFields::ConfirmationRequired)
          expect(field.reload.possible_values).to eq(%w[c b a])
          expect(rows(field)).to be_empty
          sort(field, direction: 'asc', confirm: '1')
          expect(field.reload.possible_values).to eq(%w[a b c])
          expect(rows(field).pluck(:action, :status)).to eq([%w[sort_values success]])
        end
      end

      # WP-34: the direction check comes first (an audited 422, never the
      # confirmation), then the confirmation, then any write; also for an
      # already sorted field; positions and possible values stay unchanged
      # and no row is written while it waits.
      it 'asks a global enumeration and a list without writing, after the direction check, also when sorted' do
        enum = dcf_enum_field(names: %w[c b a])
        list = dcf_list_field(values: %w[c b a], is_for_all: true)
        sorted = dcf_list_field(values: %w[a b c], is_for_all: true)
        before = enum_state(enum)
        store = raw_store(list)
        sqls = statements do
          [enum, list, sorted].each do |field|
            expect { sort(field, direction: 'desc') }.to raise_error(RedmineDependingCustomFields::ConfirmationRequired)
          end
        end
        expect(updates_of(sqls, 'custom_field_enumerations') + updates_of(sqls, 'custom_fields')).to eq([])
        expect([enum_state(enum), raw_store(list), sorted.reload.possible_values]).to eq([before, store, %w[a b c]])
        [enum, list, sorted].each { |field| expect(rows(field)).to be_empty }

        expect { sort(enum, direction: 'up') }.to expect_refused(:error_reorder_mismatch)
        expect(rows(enum).pluck(:status, :error_message)).to eq([%w[validation_failed error_reorder_mismatch]])

        sort(enum, direction: 'desc', confirm: '1')
        expect(enum_state(enum).map(&:first)).to eq(%w[c b a])
        sort(sorted, direction: 'asc', confirm: '1')
        expect(rows(sorted).pluck(:action, :status)).to eq([%w[sort_values success]])
        expect(JSON.parse(rows(sorted).last.after_value)['moved']).to eq(0)
      end

      it 'sorts a project-only field without confirm and ignores confirm (WP-34)' do
        # All fields first: Project#all_issue_custom_fields is memoized on project.
        fields = Array.new(4) { own_list(%w[c b a]) }
        [nil, '0', ['1'], '1'].zip(fields).each do |confirm, field|
          params = { direction: 'asc' }
          params[:confirm] = confirm unless confirm.nil?
          sort(field, params)
          expect(field.reload.possible_values).to eq(%w[a b c])
        end
      end
    end

    # WP-34: BaseService#confirmed? is the one confirm rule of rename,
    # remove, sort and the dependency save: the String 1 or true (case and
    # surrounding white space ignored). Every other String, refusal words
    # included, an Array, a Hash, Parameters, an Integer or true never
    # confirm (strong params drop the containers for rename, remove and sort;
    # the dependency save passes confirm raw).
    # Changed by WP-34 review round 1 (security-r1-1): the refusal words and
    # yes, on and a blank were added; they confirmed through
    # ActiveModel::Type::Boolean before.
    describe 'the confirm rule (WP-34)' do
      let(:refused) do
        [nil, '', ' ', '0', 'false', 'off', 'no', 'n', 'none', 'null', 'nil', 'yes', 'on', 'False off ', "1\xFF",
         ['1'], { 'a' => '1' }, ActionController::Parameters.new('a' => '1'), 1, true]
      end
      let(:accepted) { ['1', 'true', ' TRUE '] }

      def global_list(values = %w[b a])
        dcf_list_field(values: values, is_for_all: true)
      end

      it 'confirms a rename and a removal on a global field with 1 or true only' do
        # All fields first: Project#all_issue_custom_fields is memoized on project.
        fields = Array.new(refused.size) { global_list }
        confirmed = Array.new(accepted.size) { global_list }
        refused.zip(fields).each do |confirm, field|
          expect { rename(field, old_value: 'a', new_value: 'z', confirm: confirm) }
            .to raise_error(RedmineDependingCustomFields::ConfirmationRequired), confirm.inspect
          expect { remove(field, value: 'a', confirm: confirm) }
            .to raise_error(RedmineDependingCustomFields::ConfirmationRequired), confirm.inspect
          expect(field.reload.possible_values).to eq(%w[b a])
        end
        accepted.zip(confirmed).each do |confirm, field|
          rename(field, old_value: 'a', new_value: 'z', confirm: confirm)
          remove(field, value: 'b', confirm: confirm)
          expect(field.reload.possible_values).to eq(%w[z])
        end
      end

      it 'confirms a sort on a global field with 1 or true only' do
        fields = Array.new(refused.size) { global_list }
        confirmed = Array.new(accepted.size) { global_list }
        refused.zip(fields).each do |confirm, field|
          expect { sort(field, direction: 'asc', confirm: confirm) }
            .to raise_error(RedmineDependingCustomFields::ConfirmationRequired), confirm.inspect
          expect(field.reload.possible_values).to eq(%w[b a])
        end
        accepted.zip(confirmed).each do |confirm, field|
          sort(field, direction: 'asc', confirm: confirm)
          expect(field.reload.possible_values).to eq(%w[a b])
        end
      end

      it 'is defined once in BaseService and used by the four services' do
        dir = File.expand_path('../../app/services/redmine_depending_custom_fields', __dir__)
        sources = Dir[File.join(dir, '*.rb')].to_h { |path| [File.basename(path), File.read(path)] }
        expect(sources.select { |_name, text| text.include?('def confirmed?') }.keys).to eq(['base_service.rb'])
        expect(sources.select { |_name, text| text.include?('params[:confirm]') }.keys).to eq(['base_service.rb'])
        users = sources.select { |_name, text| text.include?('confirmed?') }.keys.sort
        expect(users).to eq(%w[base_service.rb remove_value_service.rb rename_value_service.rb])
        # The dependency save and the sort ask through the one scope rule.
        scoped = sources.select { |_name, text| text.include?('confirm_shared_change!') }.keys.sort
        expect(scoped).to eq(%w[base_service.rb dependency_mapping_service.rb sort_values_service.rb])
      end
    end

    describe 'transaction and storage errors' do
      # Changed by WP-34 (UD-23): confirm '1' on the global (dcf_enum_field) sort; was no confirm.
      it 'rolls every chunk back when the audit insert fails' do
        stub_const('RedmineDependingCustomFields::SortValuesService::CHUNK', 2)
        field = dcf_enum_field(names: %w[E D C B A])
        list = own_list(%w[c b a])
        before = enum_state(field)
        allow_any_instance_of(RedmineDependingCustomFields::AuditRecorder)
          .to receive(:record_success!).and_raise(StandardError, 'boom')
        expect { sort(field, direction: 'asc', confirm: '1') }.to raise_error(StandardError, 'boom')
        expect(enum_state(field)).to eq(before)
        expect { sort(list, direction: 'asc') }.to raise_error(StandardError, 'boom')
        expect(list.reload.possible_values).to eq(%w[c b a])
      end

      # Changed by WP-34 (UD-23): confirm '1' on the global (dcf_enum_field) sort; was no confirm.
      it 'maps ValueTooLong to a save_failed row without SQL or a value' do
        field = dcf_enum_field(names: %w[c b a])
        before = enum_state(field)
        allow_any_instance_of(ActiveRecord::Relation).to receive(:update_all)
          .and_raise(ActiveRecord::ValueTooLong, "PG::Error: SECRET-SQL 'Label X'")
        expect { sort(field, direction: 'asc', confirm: '1') }.to expect_refused(:error_dcf_value_too_long)
        row = rows(field).last
        expect([row.status, row.error_message]).to eq(%w[save_failed error_dcf_value_too_long])
        expect(row.attributes.values.join(' ')).not_to include('SECRET-SQL')
        expect(enum_state(field)).to eq(before)
      end

      # Changed by WP-34 (UD-23): confirm '1' on the global (dcf_enum_field) sort; was no confirm.
      it 'lets any other database error propagate unaudited, without its message in a row' do
        field = dcf_enum_field(names: %w[c b a])
        before = enum_state(field)
        allow_any_instance_of(ActiveRecord::Relation).to receive(:update_all)
          .and_raise(ActiveRecord::StatementInvalid, "PG::Error: SECRET-SQL 'Label X'")
        expect { sort(field, direction: 'asc', confirm: '1') }.to raise_error(ActiveRecord::StatementInvalid)
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

      # Changed by WP-34 (UD-23): confirm '1' on the global (dcf_enum_field) sort; was no confirm.
      it 'issues ceil(moved / CHUNK) UPDATE statements and the same other statements for 30 and 300 values' do
        stub_const('RedmineDependingCustomFields::SortValuesService::CHUNK', 10)
        small = reversed_enums(30)
        large = reversed_enums(300)
        sort(own_list(%w[b a]), direction: 'asc')
        small_sqls = statements { sort(small, direction: 'asc', confirm: '1') }
        large_sqls = statements { sort(large, direction: 'asc', confirm: '1') }
        expect(updates_of(small_sqls, 'custom_field_enumerations').size).to eq(30 / 10)
        expect(updates_of(large_sqls, 'custom_field_enumerations').size).to eq(300 / 10)
        expect(enum_state(large).map(&:first).first(2)).to eq(%w[N0001 N0002])
        rest = ->(sqls) { sqls.grep_v(/\AUPDATE/i).size }
        expect(rest.call(large_sqls)).to eq(rest.call(small_sqls))
      end

      # Changed by WP-34 (UD-23), missed then as the example is opt-in: confirm '1' on the global
      # (dcf_enum_field) sort; was no confirm.
      it 'sorts 25,000 enumerations with 50 UPDATE statements; the sort itself under 1 s', :perf do
        field = reversed_enums(25_000)
        labels = CustomFieldEnumeration.where(custom_field_id: field.id).pluck(:name)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        RedmineDependingCustomFields::ValueCollation.sort(labels)
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        sqls = statements { sort(field, direction: 'asc', confirm: '1') }
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

    # WP-32 (WP-30 input 4): full mode refuses a body that is no Hash of
    # Hashes, as page mode does, instead of raising TypeError.
    it 'refuses an Array enumerations and a row that is not a Hash in full mode (WP-32)' do
      field = dcf_enum_field(names: %w[X Y])
      x, y = field.enumerations.order(:position).to_a
      row = { 'name' => 'Y', 'position' => '2', 'active' => '1' }
      [[{ 'name' => 'x' }], 'junk', { x.id.to_s => 'junk', y.id.to_s => row }, { x.id.to_s => ['x'], y.id.to_s => row },
       { x.id.to_s => nil, y.id.to_s => row }].each do |enumerations|
        expect do
          RedmineDependingCustomFields::UpdateEnumerationsService
            .new(project: project, field: field, user: user, params: { enumerations: enumerations }).call
        end.to raise_error(RedmineDependingCustomFields::OperationError) { |e| expect(e.key).to eq(:error_reorder_mismatch) }
      end
      expect(field.enumerations.order(:position).pluck(:name, :active)).to eq([['X', true], ['Y', true]])
      rows = RedmineDependingCustomFields::ConfigAuditEvent.where(custom_field_id: field.id)
      expect(rows.pluck(:status, :error_message).uniq).to eq([%w[validation_failed error_reorder_mismatch]])
      expect(rows.count).to eq(5)
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
    # leave the rows before it in the loop already written. Changed by the
    # full review of 2026-11-05 (project-pages-4): the length is checked
    # before any write, with its own message (was error_save_failed).
    it 'rolls the whole save back when a row fails model validation (T-ACT-22)' do
      field = dcf_enum_field(names: %w[X Y])
      x, y = field.enumerations.order(:position).to_a
      expect { save_enums(field, x.id => { active: false }, y.id => { name: 'N' * 61 }) }
        .to raise_error(RedmineDependingCustomFields::OperationError) { |e| expect(e.key).to eq(:error_dcf_value_length) }
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

  # --- Update enumerations, page mode (T-ENP, WP-30) ----------------------
  describe 'UpdateEnumerationsService page mode (WP-30)' do
    let(:klass) { RedmineDependingCustomFields::UpdateEnumerationsService }
    let(:events) { RedmineDependingCustomFields::ConfigAuditEvent }

    # The project first, so its statements stay out of the captured ones.
    before { project }

    def page_save(field, rows, extra = {})
      klass.new(project: project, field: field, user: user,
                params: { batch_scope: 'page', enumerations: rows }.merge(extra)).call
    end

    # The rows the page-mode form posts for +enums+: name and active, no
    # position; overrides by enumeration id.
    def page_rows(enums, overrides = {})
      enums.each_with_object({}) do |enum, out|
        over = overrides[enum.id] || {}
        active = over.key?(:active) ? over[:active] : enum.active?
        out[enum.id.to_s] = { 'name' => over.key?(:name) ? over[:name] : enum.name, 'active' => active ? '1' : '0' }
      end
    end

    def ordered(field)
      CustomFieldEnumeration.where(custom_field_id: field.id).order(:position, :id).to_a
    end

    def enum_state(field)
      CustomFieldEnumeration.where(custom_field_id: field.id).order(:id).pluck(:id, :name, :position, :active)
    end

    def rows_of(field)
      events.where(custom_field_id: field.id).order(:id)
    end

    def after_of(row)
      JSON.parse(row.after_value)
    end

    def expect_refused(key)
      raise_error(RedmineDependingCustomFields::OperationError) { |e| expect(e.key).to eq(key) }
    end

    def many(count)
      field = dcf_enum_field(names: [])
      CustomFieldEnumeration.insert_all(
        (1..count).map { |i| { custom_field_id: field.id, name: format('N%04d', i), position: i, active: true } }
      )
      CustomField.find(field.id)
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

    def enum_updates(sqls)
      sqls.grep(/\AUPDATE\s+[`"]?custom_field_enumerations[`"]?\s/i)
    end

    it 'applies a subset and leaves the other rows untouched, with one success row (T-ENP-1)' do
      field = dcf_enum_field(names: %w[X Y Z W])
      x, y, z, w = ordered(field)
      untouched = enum_state(field).values_at(2, 3)
      expect { page_save(field, page_rows([x, y], x.id => { name: 'X2' }, y.id => { active: false })) }
        .to change { rows_of(field).where(action: 'update_enumerations', status: 'success').count }.by(1)
      expect(x.reload.name).to eq('X2')
      expect(y.reload.active).to be false
      expect(enum_state(field).values_at(2, 3)).to eq(untouched)
      expect([z.reload.name, w.reload.name]).to eq(%w[Z W])
    end

    it 'ignores posted positions and never renumbers stored ones (T-ENP-2)' do
      field = dcf_enum_field(names: %w[X Y Z W])
      enums = ordered(field)
      enums.zip([2, 5, 7, 11]).each { |enum, position| enum.update_column(:position, position) }
      x, y = enums
      rows = page_rows([x, y], x.id => { name: 'X2' })
      rows[x.id.to_s]['position'] = '3'
      rows[y.id.to_s]['position'] = '1'
      sqls = statements { page_save(field, rows) }
      expect(ordered(field).map(&:position)).to eq([2, 5, 7, 11])
      expect(ordered(field).map(&:name)).to eq(%w[X2 Y Z W])
      expect(enum_updates(sqls).grep(/position/i)).to be_empty
      row = rows_of(field).last
      expect(after_of(row)).not_to have_key('reordered')
      expect(row.changes_summary).not_to include('reordered')
    end

    it 'leaves the state hash unchanged on an untouched page save and accepts any position value' do
      field = dcf_enum_field(names: %w[X Y Z])
      field.enumerations.order(:position).last.update_column(:position, 9)
      before = RedmineDependingCustomFields::BaseService.state_hash(field)
      ['', 'abc', '-1', '9' * 20, nil].each do |position|
        rows = page_rows(ordered(field).first(2))
        rows.each_value { |attrs| attrs['position'] = position }
        page_save(field, rows)
      end
      page_save(field, page_rows(ordered(field).reverse))
      expect(RedmineDependingCustomFields::BaseService.state_hash(field.reload)).to eq(before)
      expect(ordered(field).map(&:position)).to eq([1, 2, 9])
    end

    it 'refuses a foreign id and applies none of the save (T-ENP-3)' do
      field = dcf_enum_field(names: %w[X Y])
      other = dcf_enum_field(name: 'Other', names: %w[Z])
      own = ordered(field).first
      alien = other.enumerations.first
      rows = page_rows([own], own.id => { name: 'Renamed' })
            .merge(alien.id.to_s => { 'name' => 'Hacked', 'active' => '0' })
      expect { page_save(field, rows) }.to expect_refused(:error_reorder_mismatch)
      expect(own.reload.name).to eq('X')
      expect(alien.reload).to have_attributes(name: 'Z', active: true)
      row = rows_of(field).last
      expect([row.action, row.status, row.error_message, row.changes_summary])
        .to eq(['validation_failed', 'validation_failed', 'error_reorder_mismatch', nil])
    end

    it 'refuses an empty, missing or non-Hash enumerations param (T-ENP-3, G5)' do
      field = dcf_enum_field(names: %w[X Y])
      before = enum_state(field)
      [{}, nil, [], 'x', [{ 'name' => 'x' }], ActionController::Parameters.new({})].each do |value|
        expect { page_save(field, value) }.to expect_refused(:error_reorder_mismatch)
      end
      expect do
        klass.new(project: project, field: field, user: user, params: { batch_scope: 'page' }).call
      end.to expect_refused(:error_reorder_mismatch)
      expect(enum_state(field)).to eq(before)
      expect(rows_of(field).where(status: 'validation_failed').count).to eq(7)
    end

    it 'refuses unknown, malformed, foreign and duplicate keys without an existence oracle (T-ENP-3, SP-20c)' do
      parent = dcf_enum_field(name: 'Parent', names: %w[P])
      field = dcf_enum_field(format: 'depending_enumeration', name: 'Mid', names: %w[X Y], parent: parent)
      child = dcf_enum_field(format: 'depending_enumeration', name: 'Kid', names: %w[C], parent: field)
      x, = ordered(field)
      max = CustomFieldEnumeration.maximum(:id)
      bad = [(max + 1000).to_s, '0', '-5', "00#{x.id}", "#{x.id}abc", "#{x.id}.0", ' ' + x.id.to_s,
             parent.enumerations.first.id.to_s, child.enumerations.first.id.to_s]
      allow(CustomFieldEnumeration).to receive(:find).and_call_original
      bad.each do |key|
        rows = page_rows([x], x.id => { name: 'Renamed' }).merge(key => { 'name' => 'Junk', 'active' => '1' })
        expect { page_save(field, rows) }.to expect_refused(:error_reorder_mismatch)
        row = rows_of(field).last
        expect([row.error_message, row.changes_summary, row.before_value, row.after_value])
          .to eq(['error_reorder_mismatch', nil, nil, nil])
      end
      expect { page_save(field, { x.id => { 'name' => 'A' }, x.id.to_s => { 'name' => 'B' } }) }
        .to expect_refused(:error_reorder_mismatch)
      expect(CustomFieldEnumeration).not_to have_received(:find)
      expect(x.reload.name).to eq('X')
      expect([parent, child].map { |f| f.enumerations.first.reload.name }).to eq(%w[P C])
    end

    it 'refuses a row that is not a Hash with 422, never a TypeError (G5)' do
      field = dcf_enum_field(names: %w[X Y])
      x, y = ordered(field)
      [{ x.id.to_s => 'x' }, { x.id.to_s => ['x'] }, page_rows([y]).merge(x.id.to_s => nil)].each do |rows|
        expect { page_save(field, rows) }.to expect_refused(:error_reorder_mismatch)
      end
      expect(enum_state(field).map { |r| r[1] }).to eq(%w[X Y])
    end

    it 'accepts Integer and String keys, symbol attributes and ids from different pages' do
      field = many(30)
      first, *, last = ordered(field)
      page_save(field, { first.id => { name: 'First' }, last.id.to_s => { 'name' => 'Last', 'active' => '1' } })
      expect(first.reload).to have_attributes(name: 'First', active: false)
      expect(last.reload).to have_attributes(name: 'Last', active: true)
    end

    it 'treats a missing active param as unticked, as in full mode' do
      field = dcf_enum_field(names: %w[X Y])
      x = ordered(field).first
      page_save(field, { x.id.to_s => { 'name' => 'X' } })
      expect(x.reload.active).to be false
    end

    it 'refuses a rename onto the active name of a row not submitted (T-ENP-4)' do
      field = dcf_enum_field(names: %w[X Y Z])
      x, y = ordered(field)
      expect { page_save(field, page_rows([x, y], x.id => { name: ' Z ' }, y.id => { active: false })) }
        .to expect_refused(:error_value_duplicate)
      expect(x.reload.name).to eq('X')
      expect(y.reload.active).to be true
    end

    it 'refuses reactivating a submitted row whose name an unsubmitted active row holds (T-ENP-4)' do
      field = dcf_enum_field(names: %w[X Y X])
      stale = ordered(field).first
      stale.update_column(:active, false)
      expect { page_save(field, page_rows([stale], stale.id => { active: true })) }
        .to expect_refused(:error_value_duplicate)
      expect(stale.reload.active).to be false
    end

    it 'accepts a rename onto an inactive name, a swap and deactivating one of a duplicate pair (T-ENP-4)' do
      field = dcf_enum_field(names: %w[X Y Z W W])
      x, y, z, w1, w2 = ordered(field)
      page_save(field, page_rows([w2], w2.id => { active: false }))
      expect([w1.reload.active, w2.reload.active]).to eq([true, false])
      z.update_column(:active, false)
      page_save(field, page_rows([x], x.id => { name: 'Z' }))
      expect(x.reload.name).to eq('Z')
      page_save(field, page_rows([x.reload, y], x.id => { name: 'Y' }, y.id => { name: 'Z' }))
      expect([x.reload.name, y.reload.name]).to eq(%w[Y Z])
    end

    it 'refuses two submitted rows ending with the same active name' do
      field = dcf_enum_field(names: %w[X Y Z])
      x, y = ordered(field)
      expect { page_save(field, page_rows([x, y], x.id => { name: 'Q' }, y.id => { name: 'Q' })) }
        .to expect_refused(:error_value_duplicate)
      expect([x.reload.name, y.reload.name]).to eq(%w[X Y])
    end

    # Decision (WP-30): the merged state is checked whole, as full mode does,
    # so an active duplicate already stored among rows not submitted blocks
    # the page until one of them is renamed or deactivated.
    it 'refuses a save while two unsubmitted active rows share a name, as full mode does' do
      field = dcf_enum_field(names: %w[X D D])
      x, d1 = ordered(field)
      expect { page_save(field, page_rows([x], x.id => { name: 'X2' })) }.to expect_refused(:error_value_duplicate)
      expect { save_enums(field, x.id => { name: 'X2' }) }.to expect_refused(:error_value_duplicate)
      page_save(field, page_rows([d1], d1.id => { name: 'D1' }))
      expect(d1.reload.name).to eq('D1')
    end

    it 'refuses a blank name and applies nothing else of the page' do
      field = dcf_enum_field(names: %w[X Y Z])
      x, y = ordered(field)
      expect { page_save(field, page_rows([x, y], x.id => { name: '  ' }, y.id => { active: false })) }
        .to expect_refused(:error_value_blank)
      expect([x.reload.name, y.reload.active]).to eq(['X', true])
    end

    # Changed by the full review of 2026-11-05 (project-pages-4): the length
    # error of the services (was error_save_failed).
    it 'rolls the whole page back when a row fails model validation' do
      field = dcf_enum_field(names: %w[X Y Z])
      x, y = ordered(field)
      expect { page_save(field, page_rows([x, y], x.id => { active: false }, y.id => { name: 'N' * 61 })) }
        .to expect_refused(:error_dcf_value_length)
      expect([x.reload.active, y.reload.name]).to eq([true, 'Y'])
      row = rows_of(field).last
      expect([row.action, row.status]).to eq(%w[validation_failed validation_failed])
      expect(row.error_message).to eq('error_dcf_value_length')
      expect(row.changes_summary).to eq('value: 61 characters exceeds 60')
    end

    it 'refuses every scope but a blank one or exactly page, never storing it (T-ENP-5)' do
      field = dcf_enum_field(names: %w[X Y Z])
      x = ordered(field).first
      before = enum_state(field)
      ['full', 'PAGE', 'Page', ' page', "page\n", 'pages', 'SCOPE-JUNK', :page, 1, ['page'], { 'x' => 'page' }].each do |scope|
        expect { page_save(field, page_rows([x], x.id => { name: 'R' }), batch_scope: scope) }
          .to expect_refused(:error_reorder_mismatch)
        row = rows_of(field).last
        expect([row.action, row.status, row.error_message, row.changes_summary, row.before_value, row.after_value])
          .to eq(['validation_failed', 'validation_failed', 'error_reorder_mismatch', nil, nil, nil])
      end
      expect(rows_of(field).map { |r| r.attributes.values.join(' ') }.join).not_to include('SCOPE-JUNK')
      expect { save_enums(field, { x.id => { position: 3 } }, batch_scope: 'full') }.to expect_refused(:error_reorder_mismatch)
      expect(enum_state(field)).to eq(before)
    end

    it 'audits scope page and the submitted row count; N counts every value (T-ENP-6)' do
      field = dcf_enum_field(names: %w[X Y Z W])
      x, y, z = ordered(field)
      z.update_column(:active, false)
      page_save(field, page_rows([x, y], x.id => { name: 'X2' }))
      row = rows_of(field).last
      expect([row.action, row.status]).to eq(%w[update_enumerations success])
      expect(row.changes_summary).to eq('Saved 2 of 4 enumeration value(s) (page): renamed 1')
      expect(after_of(row)).to eq('renamed' => ['X2'], 'scope' => 'page', 'rows' => 2)
      expect(JSON.parse(row.before_value)).to eq('renamed' => ['X'])
      expect(row.affected_child_field_ids).to be_nil
      page_save(field, page_rows([x.reload, y], x.id => { active: false }, y.id => { name: 'Y2' }))
      expect(rows_of(field).last.changes_summary).to eq('Saved 2 of 4 enumeration value(s) (page): renamed 1, deactivated 1')
      page_save(field, page_rows(ordered(field).first(3)))
      row = rows_of(field).last
      expect(row.changes_summary).to eq('Saved 3 of 4 enumeration value(s) (page): no changes')
      expect(after_of(row)).to eq('scope' => 'page', 'rows' => 3)
    end

    it 'caps the audit lists at DELTA_CAP in page mode' do
      field = many(30)
      enums = ordered(field).first(25)
      page_save(field, page_rows(enums, enums.to_h { |e| [e.id, { active: false }] }))
      after = after_of(rows_of(field).last)
      expect(after['deactivated'].size).to eq(klass::DELTA_CAP + 1)
      expect(after['deactivated'].last).to eq('(+5 more)')
      expect(after['rows']).to eq(25)
    end

    it 'keeps the full-mode audit shape: no scope or rows key' do
      field = dcf_enum_field(names: %w[X Y])
      x = ordered(field).first
      save_enums(field, x.id => { name: 'X2' })
      row = rows_of(field).last
      expect(row.changes_summary).to eq('Saved 2 enumeration value(s): renamed 1')
      expect(after_of(row).keys).to eq(['renamed'])
    end

    it 'clears the default when page mode deactivates its value, and keeps it otherwise (T-ENP-7)' do
      field = dcf_enum_field(names: %w[X Y Z])
      x, y, z = ordered(field)
      field.update!(default_value: y.id.to_s)
      page_save(field, page_rows([x, z], x.id => { active: false }))
      expect(field.reload.default_value).to eq(y.id.to_s)
      page_save(field, page_rows([y, z]))
      expect(field.reload.default_value).to eq(y.id.to_s)
      2.times { |i| dcf_custom_value(field, y.id, customized_id: 910_000 + i) }
      page_save(field, page_rows([y, z], y.id => { active: false }))
      expect(field.reload.default_value).to be_blank
      row = rows_of(field).last
      expect(row.changes_summary).to eq('Saved 2 of 3 enumeration value(s) (page): deactivated 1, default value cleared')
      expect(row.affected_values_count).to eq(2)
    end

    it 'keeps full mode strict: a blank or absent scope with a partial payload is refused (T-ENP-8)' do
      field = dcf_enum_field(names: %w[X Y Z])
      x = ordered(field).first
      [{}, { batch_scope: nil }, { batch_scope: '' }, { batch_scope: '  ' }].each do |extra|
        partial = enum_payload(field, x.id => { name: 'Renamed' })
        partial.delete(ordered(field).last.id.to_s)
        expect do
          klass.new(project: project, field: field, user: user, params: { enumerations: partial }.merge(extra)).call
        end.to expect_refused(:error_reorder_mismatch)
      end
      expect(x.reload.name).to eq('X')
      field.enumerations.order(:position).last.update_column(:position, 9)
      save_enums(field.reload, {}, batch_scope: '')
      expect(ordered(field).map(&:position)).to eq([1, 2, 3])
      expect(rows_of(field).last.changes_summary).to eq('Saved 3 enumeration value(s): reordered')
    end

    # Changed by WP-34 (UD-23): confirm '1' on the global (dcf_enum_field) sort; was no confirm.
    it 'refuses a stale state_hash with 409 before the scope and id checks (T-ENP-9)' do
      field = dcf_enum_field(names: %w[c b a])
      a = ordered(field).last
      stale = RedmineDependingCustomFields::BaseService.state_hash(field)
      RedmineDependingCustomFields::SortValuesService
        .new(project: project, field: field, user: user, params: { direction: 'asc', confirm: '1' }).call
      before = enum_state(field)
      expect { page_save(field, page_rows([a.reload], a.id => { name: 'A' }), state_hash: stale) }
        .to raise_error(RedmineDependingCustomFields::OperationError) { |e|
          expect([e.key, e.http_status]).to eq([:error_stale_edit, :conflict])
        }
      expect(enum_state(field)).to eq(before)
      row = rows_of(field).last
      expect([row.status, row.error_message]).to eq(%w[validation_failed error_stale_edit])
      expect { page_save(field, {}, state_hash: 'stale', batch_scope: 'junk') }.to expect_refused(:error_stale_edit)
      expect { page_save(field, { '0' => { 'name' => 'x' } }, state_hash: 'stale') }.to expect_refused(:error_stale_edit)
      page_save(field, page_rows([a.reload], a.id => { name: 'A' }), state_hash: '')
      expect(a.reload.name).to eq('A')
    end

    it 'gives 409 to a page opened before a save on another page' do
      field = many(30)
      first, *, last = ordered(field)
      opened = RedmineDependingCustomFields::BaseService.state_hash(field)
      page_save(field, page_rows([last], last.id => { name: 'Elsewhere' }), state_hash: opened)
      expect { page_save(field, page_rows([first], first.id => { name: 'Mine' }), state_hash: opened) }
        .to expect_refused(:error_stale_edit)
      expect(first.reload.name).to eq('N0001')
    end

    it 'refuses a list-family field in page mode with error_format_unsupported (T-ACT-3)' do
      list = dcf_list_field(values: %w[A B], is_for_all: false, projects: [project])
      expect { page_save(list, { '1' => { 'name' => 'x' } }, batch_scope: 'junk') }
        .to expect_refused(:error_format_unsupported)
      expect(list.reload.possible_values).to eq(%w[A B])
    end

    it 'refuses a user without the permission in page mode' do
      field = dcf_enum_field(names: %w[X Y])
      x = ordered(field).first
      expect do
        klass.new(project: project, field: field, user: dcf_plain_member(project),
                  params: { batch_scope: 'page', enumerations: page_rows([x], x.id => { active: false }) }).call
      end.to raise_error(RedmineDependingCustomFields::OperationError) { |e| expect(e.http_status).to eq(:forbidden) }
      expect(x.reload.active).to be true
    end

    it 'leaves a role-invisible child byte-identical and out of every row' do
      other_role = dcf_create_role
      parent = dcf_enum_field(name: 'Parent', names: %w[P1 P2 P3])
      child = dcf_enum_field(format: 'depending_enumeration', name: "HIDDEN-CHILD-#{SecureRandom.hex(3)}",
                             names: %w[SECRET-V], parent: parent)
      p1, p2 = ordered(parent)
      secret = child.enumerations.first
      dcf_set_dependencies(child, value_dependencies: { p1.id.to_s => [secret.id.to_s], p2.id.to_s => [secret.id.to_s] })
      child.update!(visible: false, role_ids: [other_role.id])
      store = CustomField.where(id: child.id).pluck(Arel.sql('format_store')).first
      page_save(parent, page_rows([p1], p1.id => { active: false }))
      expect { page_save(parent, page_rows([p1.reload, p2], p2.id => { name: 'P3' })) }
        .to expect_refused(:error_value_duplicate)
      expect(CustomField.where(id: child.id).pluck(Arel.sql('format_store')).first).to eq(store)
      rows_of(parent).each do |row|
        expect(row.affected_child_field_ids).to be_nil
        expect(row.attributes.values.join(' ')).not_to include('HIDDEN-CHILD')
        expect(row.attributes.values.join(' ')).not_to include('SECRET-V')
      end
    end

    # G6: the invariance form, never absolute counts.
    it 'runs the same statements for 600 and 6,000 values; an untouched page writes nothing' do
      small = many(600)
      large = many(6_000)
      warm = dcf_enum_field(names: %w[V W])
      page_save(warm, page_rows(ordered(warm), ordered(warm).first.id => { name: 'V2' }))
      counts = [small, large].map do |field|
        enums = ordered(field)[100, 25]
        sqls = statements { page_save(field, page_rows(enums, enums.first.id => { name: 'Renamed' })) }
        [enum_updates(sqls).size, sqls.size]
      end
      expect(counts.first).to eq(counts.last)
      expect(counts.first.first).to eq(1)
      sqls = statements { page_save(large, page_rows(ordered(large)[200, 25])) }
      expect(enum_updates(sqls)).to be_empty
    end

    # G6 on the submitted side: no lookup or write per submitted row.
    it 'runs the same statements for 25 and 500 submitted rows; 500 untouched rows write nothing' do
      field = many(1_200)
      warm = dcf_enum_field(names: %w[V W])
      page_save(warm, page_rows(ordered(warm), ordered(warm).first.id => { name: 'V2' }))
      counts = [[0, 25, 'R1'], [600, 500, 'R2']].map do |start, size, name|
        enums = ordered(field)[start, size]
        sqls = statements { page_save(field, page_rows(enums, enums.first.id => { name: name })) }
        expect(rows_of(field).last.changes_summary).to eq("Saved #{size} of 1200 enumeration value(s) (page): renamed 1")
        [enum_updates(sqls).size, sqls.size]
      end
      expect(counts.last).to eq(counts.first)
      expect(counts.first.first).to eq(1)
      sqls = statements { page_save(field, page_rows(ordered(field)[100, 500])) }
      expect(rows_of(field).last.changes_summary).to eq('Saved 500 of 1200 enumeration value(s) (page): no changes')
      expect(enum_updates(sqls)).to be_empty
    end
  end

  # --- Project storage ceiling and value length cap (WP-31, UD-22) ------
  # The ceiling is stubbed through ProjectStoragePolicy.ceiling_bytes (the
  # spec seam). Stubbed ceilings are far below MySQL TEXT, so the examples
  # behave the same on PostgreSQL and MariaDB.
  describe 'project storage ceiling (WP-31)' do
    let(:policy) { RedmineDependingCustomFields::ProjectStoragePolicy }
    let(:limits) { RedmineDependingCustomFields::StorageLimits }
    let(:events) { RedmineDependingCustomFields::ConfigAuditEvent }

    before { project }

    def stub_ceiling(bytes)
      allow(policy).to receive(:ceiling_bytes).and_return(bytes)
    end

    def raw(field, column)
      CustomField.connection.select_value(CustomField.where(id: field.id).select(column).to_sql)
    end

    def yaml_bytes(values)
      limits.serialized_bytesize(CustomField, 'possible_values', values)
    end

    def own_list(values)
      dcf_list_field(values: values, is_for_all: false, projects: [project])
    end

    def refusal
      yield
      raise 'expected an OperationError'
    rescue RedmineDependingCustomFields::OperationError => e
      e
    end

    def rows(field)
      events.where(custom_field_id: field.id).order(:id)
    end

    def sort(field, params)
      RedmineDependingCustomFields::SortValuesService
        .new(project: project, field: field, user: user, params: params).call
    end

    def map(field, params)
      RedmineDependingCustomFields::DependencyMappingService
        .new(project: project, field: field, user: user, params: params).call
    end

    def save_enums_page(field, overrides)
      payload = enum_payload(field, overrides).slice(*overrides.keys.map(&:to_s))
      RedmineDependingCustomFields::UpdateEnumerationsService
        .new(project: project, field: field, user: user,
             params: { enumerations: payload, batch_scope: 'page' }).call
    end

    # Every IssueCustomField save! of the block: [record, ceiling during it].
    def watch_saves
      seen = []
      allow_any_instance_of(IssueCustomField).to receive(:save!).and_wrap_original do |original, *args|
        seen << [original.receiver, original.receiver.dcf_storage_ceiling]
        original.call(*args)
      end
      seen
    end

    def updates_of_custom_fields(&block)
      sqls = []
      callback = ->(*, payload) { sqls << payload[:sql].to_s }
      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &block)
      sqls.grep(/\AUPDATE\s+[`"]?custom_fields[`"]?\s/i)
    end

    describe 'max(ceiling, persisted bytes) (T-SIZE-6)' do
      it 'lets a field below the ceiling grow up to it and refuses one byte more with the ceiling as limit' do
        field = own_list(%w[A B])
        stored = raw(field, 'possible_values').bytesize
        stub_ceiling(yaml_bytes(%w[A B CC]))
        add(field, value: 'CC')
        expect(field.reload.possible_values).to eq(%w[A B CC])

        bytes = yaml_bytes(%w[A B CC D])
        ceiling = bytes - 1
        stub_ceiling(ceiling)
        error = nil
        expect { error = refusal { add(CustomField.find(field.id), value: 'D') } }.to change(events, :count).by(1)
        expect(error.key).to eq(:error_dcf_values_too_large)
        expect(error.interpolations)
          .to eq(field: field.name, size: limits.delimited(bytes), limit: limits.delimited(ceiling))
        row = rows(field).last
        expect([row.action, row.status, row.error_message])
          .to eq(%w[validation_failed validation_failed error_dcf_values_too_large])
        expect(row.changes_summary)
          .to eq("possible_values: #{bytes} bytes exceeds #{ceiling} (custom field ##{field.id})")
        expect(field.reload.possible_values).to eq(%w[A B CC])
        expect(stored).to be < ceiling
      end

      it 'uses the persisted bytes as the limit of a field stored above the ceiling: it shrinks or keeps size, never grows' do
        field = own_list(%w[Alpha Bravo Charlie Delta])
        stored = raw(field, 'possible_values').bytesize
        stub_ceiling(10)

        error = refusal { add(CustomField.find(field.id), value: 'Echo') }
        expect(error.key).to eq(:error_dcf_values_too_large)
        expect(error.interpolations[:limit]).to eq(limits.delimited(stored))
        expect(rows(field).last.changes_summary)
          .to eq("possible_values: #{yaml_bytes(%w[Alpha Bravo Charlie Delta Echo])} bytes exceeds #{stored} " \
                 "(custom field ##{field.id})")

        rename(CustomField.find(field.id), old_value: 'Alpha', new_value: 'Omega', confirm: '1')
        expect(raw(field, 'possible_values').bytesize).to eq(stored)
        reorder(CustomField.find(field.id), ordered_values: %w[Delta Charlie Bravo Omega])
        sort(CustomField.find(field.id), direction: 'asc')
        expect(CustomField.find(field.id).possible_values).to eq(%w[Bravo Charlie Delta Omega])

        grow = refusal { rename(CustomField.find(field.id), old_value: 'Omega', new_value: 'Omega2', confirm: '1') }
        expect([grow.key, grow.interpolations[:limit]]).to eq([:error_dcf_values_too_large, limits.delimited(stored)])

        remove(CustomField.find(field.id), value: 'Delta', confirm: '1')
        expect(CustomField.find(field.id).possible_values).to eq(%w[Bravo Charlie Omega])
        expect(rows(field).where(status: 'success').pluck(:action))
          .to eq(%w[rename_value reorder_values sort_values remove_value])
      end

      # UD-22: a mapping stored before default_value_dependencies existed is
      # rewritten by any save, which changes no value; the ceiling never
      # refuses such a write.
      it 'sorts, reorders and sets the default of a depending list above the ceiling whose stored mapping a save rewrites' do
        parent = own_list(%w[P Q])
        child = dcf_list_field(format: 'depending_list', name: "Dep-#{SecureRandom.hex(3)}", values: %w[c b a],
                               parent: parent, is_for_all: false, projects: [project])
        dcf_set_dependencies(child, value_dependencies: { 'P' => %w[a b], 'Q' => %w[c] })
        # A plain default exists only without a parent field.
        orphan = dcf_list_field(format: 'depending_list', name: "Orphan-#{SecureRandom.hex(3)}", values: %w[x y],
                                is_for_all: false, projects: [project])
        stale = CustomField.find(child.id).format_store.to_hash.except('default_value_dependencies')
        child.update_column(:format_store, stale)
        expect(raw(child, 'format_store')).not_to include('default_value_dependencies')
        orphan_stale = CustomField.find(orphan.id).format_store.to_hash.except('default_value_dependencies')
        orphan.update_column(:format_store, orphan_stale)
        expect(raw(orphan, 'format_store')).not_to include('default_value_dependencies')
        stub_ceiling(1)

        sort(CustomField.find(child.id), direction: 'asc')
        expect(CustomField.find(child.id).possible_values).to eq(%w[a b c])
        child.update_column(:format_store, stale)
        reorder(CustomField.find(child.id), ordered_values: %w[c a b])
        expect(CustomField.find(child.id).possible_values).to eq(%w[c a b])
        expect(CustomField.find(child.id).value_dependencies).to eq('P' => %w[a b], 'Q' => %w[c])
        expect(raw(child, 'format_store')).to include('default_value_dependencies')
        expect(rows(child).pluck(:action, :status)).to eq([%w[sort_values success], %w[reorder_values success]])

        set_default(CustomField.find(orphan.id), default_value: 'y')
        expect(CustomField.find(orphan.id).default_value).to eq('y')
        expect(raw(orphan, 'format_store')).to include('default_value_dependencies')
        expect(rows(orphan).pluck(:action, :status)).to eq([%w[set_default_value success]])
      end

      # Review round 2 (contracts-r2-1, semantics-r2-1): a mapping stored
      # without default_value_dependencies gains that key on any save, so a
      # write is measured against the row as a save of it would store it.
      def strip_defaults(field)
        stale = CustomField.find(field.id).format_store.to_hash.except('default_value_dependencies')
        field.update_column(:format_store, stale)
        expect(raw(field, 'format_store')).not_to include('default_value_dependencies')
        stale
      end

      # The bytes a save of the stored row writes: the key added as {}.
      def normalized_bytes(stale)
        limits.serialized_bytesize(CustomField, 'format_store', stale.merge('default_value_dependencies' => {}))
      end

      it 'removes and renames values of a depending list above the ceiling whose stored mapping lacks the defaults' do
        parent = own_list(%w[P Q])
        child = dcf_list_field(format: 'depending_list', name: "Dep-#{SecureRandom.hex(3)}",
                               values: %w[a b c y z], parent: parent, is_for_all: false, projects: [project])
        dcf_set_dependencies(child, value_dependencies: { 'P' => %w[a b], 'Q' => %w[c] })
        strip_defaults(child)
        stub_ceiling(1)

        remove(CustomField.find(child.id), value: 'z', confirm: '1')
        expect(CustomField.find(child.id).possible_values).to eq(%w[a b c y])
        strip_defaults(child)
        rename(CustomField.find(child.id), old_value: 'y', new_value: 'x', confirm: '1')
        expect(CustomField.find(child.id).possible_values).to eq(%w[a b c x])
        strip_defaults(child)
        remove(CustomField.find(child.id), value: 'b', confirm: '1')
        expect(CustomField.find(child.id).value_dependencies).to eq('P' => %w[a], 'Q' => %w[c])
        strip_defaults(child)
        rename(CustomField.find(child.id), old_value: 'a', new_value: 'e', confirm: '1')
        expect(CustomField.find(child.id).value_dependencies).to eq('P' => %w[e], 'Q' => %w[c])
        expect(rows(child).pluck(:action, :status))
          .to eq([%w[remove_value success], %w[rename_value success], %w[remove_value success],
                  %w[rename_value success]])

        stale = strip_defaults(child)
        values_bytes = raw(child, 'possible_values').bytesize
        stub_ceiling(values_bytes + 20)
        expect(raw(child, 'format_store').bytesize).to be > values_bytes + 20
        grow = refusal { rename(CustomField.find(child.id), old_value: 'c', new_value: 'c-longer', confirm: '1') }
        expect([grow.key, grow.interpolations[:limit]])
          .to eq([:error_dcf_mapping_too_large, limits.delimited(normalized_bytes(stale))])
        expect(normalized_bytes(stale)).to be > raw(child, 'format_store').bytesize
        expect(CustomField.find(child.id).possible_values).to eq(%w[e c x])
      end

      # contracts-r2-1: a mapping the write does not change is not assigned,
      # so format_store stays as stored and the ceiling never measures it.
      it 'leaves format_store unchanged when a remove, a rename or a resubmit does not change the mapping' do
        parent = own_list(%w[P Q])
        child = dcf_list_field(format: 'depending_list', name: "Dep-#{SecureRandom.hex(3)}",
                               values: %w[a b y z], parent: parent, is_for_all: false, projects: [project])
        mapping = { 'P' => %w[a], 'Q' => %w[b] }
        dcf_set_dependencies(child, value_dependencies: mapping)
        enum_parent = dcf_enum_field(names: %w[N S])
        enum_child = dcf_enum_field(format: 'depending_enumeration', names: %w[x y], parent: enum_parent)
        north = enum_parent.enumerations.find_by(name: 'N').id.to_s
        x_id, y_id = %w[x y].map { |name| enum_child.enumerations.find_by(name: name).id }
        dcf_set_dependencies(enum_child, value_dependencies: { north => [x_id.to_s] })
        [child, enum_child].each { |field| strip_defaults(field) }
        seen = []
        allow_any_instance_of(IssueCustomField).to receive(:save!).and_wrap_original do |original, *args|
          seen << original.receiver.will_save_change_to_attribute?('format_store')
          original.call(*args)
        end

        remove(CustomField.find(child.id), value: 'z', confirm: '1')
        strip_defaults(child)
        rename(CustomField.find(child.id), old_value: 'y', new_value: 'x', confirm: '1')
        strip_defaults(child)
        map(CustomField.find(child.id),
            dependencies_json: JSON.generate('value_dependencies' => mapping, 'default_value_dependencies' => {}))
        remove(CustomField.find(enum_child.id), enumeration_id: y_id, confirm: '1')

        expect(seen).to eq([false, false, false, false])
        expect(CustomField.find(child.id).possible_values).to eq(%w[a b x])
        expect(CustomField.find(child.id).value_dependencies).to eq(mapping)
      end

      it 'removes a linked and an unlinked entry of a depending enumeration above the ceiling whose mapping lacks ' \
         'the defaults' do
        parent = dcf_enum_field(names: %w[N S])
        child = dcf_enum_field(format: 'depending_enumeration', names: %w[x y z], parent: parent)
        north = parent.enumerations.find_by(name: 'N').id.to_s
        x_id, y_id, z_id = %w[x y z].map { |name| child.enumerations.find_by(name: name).id }
        dcf_set_dependencies(child, value_dependencies: { north => [x_id.to_s, y_id.to_s] })
        strip_defaults(child)
        stub_ceiling(1)

        remove(CustomField.find(child.id), enumeration_id: z_id, confirm: '1')
        expect(CustomField.find(child.id).enumerations.pluck(:id)).not_to include(z_id)
        strip_defaults(child)
        remove(CustomField.find(child.id), enumeration_id: x_id, confirm: '1')
        expect(CustomField.find(child.id).value_dependencies).to eq(north => [y_id.to_s])
        expect(rows(child).pluck(:action, :status)).to eq([%w[remove_value success], %w[remove_value success]])
      end

      it 'removes and same-length renames a parent value whose children above the ceiling lack the defaults, ' \
         'a role-invisible child included' do
        parent = own_list(%w[A B C])
        visible = dcf_list_field(format: 'depending_list', name: "Dep-#{SecureRandom.hex(3)}", values: %w[a1 b1],
                                 parent: parent, is_for_all: false, projects: [project])
        dcf_set_dependencies(visible, value_dependencies: { 'A' => %w[a1], 'B' => %w[b1] })
        hidden = dcf_list_field(format: 'depending_list', name: 'HIDDEN-LEGACY-CHILD', values: %w[h1],
                                parent: parent)
        dcf_set_dependencies(hidden, value_dependencies: { 'A' => %w[h1] })
        hidden.update!(visible: false, role_ids: [dcf_create_role.id])
        [visible, hidden].each { |child| strip_defaults(child) }
        manager = dcf_manager(project)
        stub_ceiling(1)

        RedmineDependingCustomFields::RenameValueService
          .new(project: project, field: CustomField.find(parent.id), user: manager,
               params: { old_value: 'A', new_value: 'Z', confirm: '1' }).call
        expect(CustomField.find(visible.id).value_dependencies).to eq('B' => %w[b1], 'Z' => %w[a1])
        expect(CustomField.find(hidden.id).value_dependencies).to eq('Z' => %w[h1])

        [visible, hidden].each { |child| strip_defaults(child) }
        RedmineDependingCustomFields::RemoveValueService
          .new(project: project, field: CustomField.find(parent.id), user: manager,
               params: { value: 'Z', confirm: '1' }).call
        expect(CustomField.find(parent.id).possible_values).to eq(%w[B C])
        expect(CustomField.find(visible.id).value_dependencies).to eq('B' => %w[b1])
        expect(CustomField.find(hidden.id).value_dependencies).to eq({})
        expect(rows(parent).pluck(:action, :status)).to eq([%w[rename_value success], %w[remove_value success]])
      end

      it 'measures the persisted bytes only above the ceiling: one dump below it, two above it' do
        field = own_list(%w[A B])
        allow(limits).to receive(:persisted_bytes).and_call_original
        allow(limits).to receive(:serialized_bytesize).and_call_original
        stub_ceiling(1_000)
        add(CustomField.find(field.id), value: 'C')
        expect(limits).not_to have_received(:persisted_bytes)
        expect(limits).to have_received(:serialized_bytesize).once

        stub_ceiling(5)
        refusal { add(CustomField.find(field.id), value: 'D') }
        expect(limits).to have_received(:persisted_bytes).once
        expect(limits).to have_received(:serialized_bytesize).exactly(3).times
      end

      # Changed by the WP-31 review round 2 (tests-r2-1, was: the ceiling at
      # the child's stored size, a tie): the ceiling lies between the
      # parent's grown list and the child's stored mapping.
      it 'measures each cascaded child against its own persisted bytes' do
        parent = own_list(%w[A B])
        child = dcf_list_field(format: 'depending_list', name: "Child-#{SecureRandom.hex(3)}", values: %w[a1],
                               parent: parent, is_for_all: false, projects: [project])
        dcf_set_dependencies(child, value_dependencies: { 'A' => %w[a1] })
        child_stored = raw(child, 'format_store').bytesize
        ceiling = yaml_bytes(%w[Z-longer B])
        expect(ceiling).to be < child_stored
        stub_ceiling(ceiling)

        rename(CustomField.find(parent.id), old_value: 'A', new_value: 'Z', confirm: '1')
        expect(CustomField.find(child.id).value_dependencies).to eq('Z' => %w[a1])
        expect(raw(child, 'format_store').bytesize).to eq(child_stored)

        error = refusal { rename(CustomField.find(parent.id), old_value: 'Z', new_value: 'Z-longer', confirm: '1') }
        expect([error.key, error.interpolations[:field]]).to eq([:error_dcf_mapping_too_large, child.name])
        expect(error.interpolations[:limit]).to eq(limits.delimited(child_stored))
        expect(error.summary).to end_with("(custom field ##{child.id})")
        expect(CustomField.find(parent.id).possible_values).to eq(%w[Z B])

        remove(CustomField.find(parent.id), value: 'Z', confirm: '1')
        expect(CustomField.find(parent.id).possible_values).to eq(%w[B])
        expect(CustomField.find(child.id).value_dependencies).to eq({})
      end
    end

    describe 'save_field! (T-SIZE-7)' do
      it 'leaves the accessor nil after a save, a refusal and an unmapped error' do
        field = CustomField.find(own_list(%w[A B]).id)
        add(field, value: 'C')
        expect(field.dcf_storage_ceiling).to be_nil

        stub_ceiling(5)
        refusal { add(field, value: 'D') }
        expect(field.dcf_storage_ceiling).to be_nil

        allow(field).to receive(:save!).and_raise(RuntimeError, 'boom')
        expect { add(field, value: 'E') }.to raise_error(RuntimeError, 'boom')
        expect(field.dcf_storage_ceiling).to be_nil
      end

      it 'leaves the field unlimited for a later save of the same object' do
        field = CustomField.find(own_list(%w[A B]).id)
        stub_ceiling(5)
        refusal { add(field, value: 'C') }
        field.reload
        field.possible_values = %w[A B C D E F]
        expect(field.save).to be(true), field.errors.full_messages.inspect
      end

      it 'stores through save_field! in every project service, children of a cascade included' do
        stub_ceiling(4_000_000)
        parent = own_list(%w[A B C])
        child = dcf_list_field(format: 'depending_list', name: "Child-#{SecureRandom.hex(3)}", values: %w[a1 b1],
                               parent: parent, is_for_all: false, projects: [project])
        dcf_set_dependencies(child, value_dependencies: { 'A' => %w[a1], 'B' => %w[b1] })
        enum_parent = dcf_enum_field(names: %w[N S])
        enum_child = dcf_enum_field(format: 'depending_enumeration', names: %w[x y], parent: enum_parent)
        north = enum_parent.enumerations.find_by(name: 'N').id.to_s
        x_id = enum_child.enumerations.find_by(name: 'x').id
        dcf_set_dependencies(enum_child, value_dependencies: { north => [x_id.to_s] })
        default_enum = dcf_enum_field(names: %w[D1 D2])
        d1 = default_enum.enumerations.find_by(name: 'D1')
        default_enum.update!(default_value: d1.id.to_s)
        page_enum = dcf_enum_field(names: %w[P1 P2])
        p1 = page_enum.enumerations.find_by(name: 'P1')
        page_enum.update!(default_value: p1.id.to_s)

        operations = {
          'add' => -> { add(CustomField.find(parent.id), value: 'D') },
          'rename with cascade' => lambda {
            rename(CustomField.find(parent.id), old_value: 'A', new_value: 'A2', confirm: '1')
          },
          'remove list' => -> { remove(CustomField.find(parent.id), value: 'C', confirm: '1') },
          'remove depending enumeration' => lambda {
            remove(CustomField.find(enum_child.id), enumeration_id: x_id, confirm: '1')
          },
          'reorder list' => -> { reorder(CustomField.find(parent.id), ordered_values: %w[D B A2]) },
          'sort list' => -> { sort(CustomField.find(parent.id), direction: 'asc') },
          'set default' => -> { set_default(CustomField.find(parent.id), default_value: 'B') },
          'clear default (full mode)' => -> { save_enums(CustomField.find(default_enum.id), d1.id => { active: false }) },
          'clear default (page mode)' => -> { save_enums_page(CustomField.find(page_enum.id), p1.id => { active: false }) },
          'mapping' => -> { map(CustomField.find(child.id), value_dependencies: { 'B' => %w[a1 b1] }) }
        }
        expected_ids = { 'rename with cascade' => [parent.id, child.id], 'remove depending enumeration' => [enum_child.id],
                         'clear default (full mode)' => [default_enum.id], 'clear default (page mode)' => [page_enum.id],
                         'mapping' => [child.id] }
        operations.each do |name, operation|
          seen = watch_saves
          operation.call
          expect(seen.map { |record, _| record.id }).to eq(expected_ids.fetch(name, [parent.id])), name
          expect(seen.map(&:last).uniq).to eq([4_000_000]), name
          expect(seen.map { |record, _| record.dcf_storage_ceiling }.uniq).to eq([nil]), name
        end
      end

      # Changed by WP-34 (UD-23): confirm '1' on the global (dcf_enum_field) sort; was no confirm.
      it 'never stores through save_field! when sorting or reordering enumerations' do
        stub_ceiling(1)
        field = dcf_enum_field(names: %w[c b a])
        seen = watch_saves
        sort(CustomField.find(field.id), direction: 'asc', confirm: '1')
        ids = CustomField.find(field.id).enumerations.order(:position).pluck(:id).map(&:to_s)
        reorder(CustomField.find(field.id), ordered_values: ids.reverse)
        expect(seen).to eq([])
        expect(policy).not_to have_received(:ceiling_bytes)
      end

      it 'sorts and reorders a list stored above the ceiling with one UPDATE of custom_fields each' do
        field = own_list(%w[Delta Alpha Charlie Bravo])
        stub_ceiling(1)
        updates = updates_of_custom_fields { sort(CustomField.find(field.id), direction: 'asc') }
        expect(updates.size).to eq(1)
        updates = updates_of_custom_fields do
          reorder(CustomField.find(field.id), ordered_values: %w[Delta Charlie Bravo Alpha])
        end
        expect(updates.size).to eq(1)
        expect(CustomField.find(field.id).possible_values).to eq(%w[Delta Charlie Bravo Alpha])
      end

      it 'removes from a list and a depending list stored above the ceiling, and clears a default above it' do
        stub_ceiling(1)
        list = own_list(%w[A B C])
        parent = own_list(%w[P Q])
        depending = dcf_list_field(format: 'depending_list', name: "Dep-#{SecureRandom.hex(3)}", values: %w[a b],
                                   parent: parent, is_for_all: false, projects: [project])
        dcf_set_dependencies(depending, value_dependencies: { 'P' => %w[a b], 'Q' => %w[b] },
                                        default_value_dependencies: { 'P' => 'a' })
        enum = dcf_enum_field(names: %w[X Y])
        x = enum.enumerations.find_by(name: 'X')
        enum.update!(default_value: x.id.to_s)

        remove(CustomField.find(list.id), value: 'B', confirm: '1')
        remove(CustomField.find(depending.id), value: 'a', confirm: '1')
        save_enums(CustomField.find(enum.id), x.id => { active: false })

        expect(CustomField.find(list.id).possible_values).to eq(%w[A C])
        expect(CustomField.find(depending.id).value_dependencies).to eq('P' => %w[b], 'Q' => %w[b])
        expect(CustomField.find(enum.id).default_value).to be_blank
      end

      it 'refuses a mapping that grows a depending field above the ceiling and accepts a smaller one' do
        parent = own_list(%w[P Q])
        child = dcf_list_field(format: 'depending_list', name: "Dep-#{SecureRandom.hex(3)}", values: %w[a b],
                               parent: parent, is_for_all: false, projects: [project])
        dcf_set_dependencies(child, value_dependencies: { 'P' => %w[a b] })
        stub_ceiling(raw(child, 'format_store').bytesize)

        error = refusal { map(CustomField.find(child.id), value_dependencies: { 'P' => %w[a b], 'Q' => %w[a b] }) }
        expect(error.key).to eq(:error_dcf_mapping_too_large)
        expect(error.interpolations[:limit]).to eq(limits.delimited(raw(child, 'format_store').bytesize))

        map(CustomField.find(child.id), value_dependencies: { 'P' => %w[a] })
        expect(CustomField.find(child.id).value_dependencies).to eq('P' => %w[a])
      end
    end

    # G6, differential form: the ceiling reads a cached setting and measures
    # in memory, so a project save runs the same statements without it.
    describe 'query shape (G6)' do
      it 'runs the same number of queries for a project save with and without the ceiling' do
        parent = own_list(%w[P Q])
        fields = Array.new(3) do
          child = dcf_list_field(format: 'depending_list', name: "Dep-#{SecureRandom.hex(3)}", values: %w[a b],
                                 parent: parent, is_for_all: false, projects: [project])
          dcf_set_dependencies(child, value_dependencies: { 'P' => %w[a] })
        end
        policy.ceiling_bytes
        add(CustomField.find(fields[0].id), value: 'c')

        with = dcf_count_queries { add(CustomField.find(fields[1].id), value: 'c') }
        allow(policy).to receive(:ceiling_bytes).and_return(nil)
        without = dcf_count_queries { add(CustomField.find(fields[2].id), value: 'c') }

        expect(with).to eq(without)
        expect(CustomField.find(fields[1].id).possible_values).to eq(%w[a b c])
      end

      # Review round 2 (tests-r2-2): above the ceiling a save also measures
      # the stored value, in memory as well.
      it 'runs the same number of queries for a project save above the ceiling with and without it' do
        parent = own_list(%w[P Q])
        fields = Array.new(3) do
          child = dcf_list_field(format: 'depending_list', name: "Dep-#{SecureRandom.hex(3)}", values: %w[a b c],
                                 parent: parent, is_for_all: false, projects: [project])
          dcf_set_dependencies(child, value_dependencies: { 'P' => %w[a b], 'Q' => %w[c] })
        end
        stub_ceiling(1)
        remove(CustomField.find(fields[0].id), value: 'b', confirm: '1')

        with = dcf_count_queries { remove(CustomField.find(fields[1].id), value: 'b', confirm: '1') }
        stub_ceiling(nil)
        without = dcf_count_queries { remove(CustomField.find(fields[2].id), value: 'b', confirm: '1') }

        expect(with).to eq(without)
        expect(CustomField.find(fields[1].id).value_dependencies).to eq('P' => %w[a], 'Q' => %w[c])
      end
    end

    describe 'a role-invisible child (security)' do
      it 'is never named when the ceiling refuses its cascade, and nothing is written' do
        parent = dcf_list_field(name: "Parent-#{SecureRandom.hex(3)}", values: %w[A B])
        child = dcf_list_field(format: 'depending_list', name: 'HIDDEN-CEILING-CHILD', values: %w[SECRET-V1],
                               parent: parent)
        dcf_set_dependencies(child, value_dependencies: { 'A' => %w[SECRET-V1] })
        child.update!(visible: false, role_ids: [dcf_create_role.id])
        raw_child = raw(child, 'format_store')
        value = dcf_custom_value(parent, 'A')
        stub_ceiling(raw_child.bytesize)
        manager = dcf_manager(project)

        error = nil
        expect do
          error = refusal do
            RedmineDependingCustomFields::RenameValueService
              .new(project: project, field: CustomField.find(parent.id), user: manager,
                   params: { old_value: 'A', new_value: "A#{'2' * 20}", confirm: '1' }).call
          end
        end.to change(events, :count).by(1)

        expect(error.key).to eq(:error_save_failed)
        expect(error.interpolations).to eq({})
        row = events.order(:id).last
        expect([row.status, row.error_message]).to eq(%w[validation_failed error_dcf_mapping_too_large])
        # Changed by the full review of 2026-11-05 (project-pages-7): no id of
        # the hidden field; was '... (custom field #<id>)'.
        expect(row.changes_summary).to match(/\Aformat_store: \d+ bytes exceeds #{raw_child.bytesize}\z/)
        text = row.attributes.values.join(' ')
        expect(text).not_to include('HIDDEN-CEILING-CHILD')
        expect(text).not_to include('SECRET-V1')
        expect(raw(child, 'format_store')).to eq(raw_child)
        expect(CustomField.find(parent.id).possible_values).to eq(%w[A B])
        expect(value.reload.value).to eq('A')
      end
    end

    describe 'value length cap (T-LEN-1)' do
      def expect_length_refusal(field, &block)
        error = nil
        expect { error = refusal(&block) }.to change(events, :count).by(1)
        expect([error.key, error.interpolations, error.http_status, error.audit_status])
          .to eq([:error_dcf_value_length, { max: 255 }, :unprocessable_entity, 'validation_failed'])
        row = rows(field).last
        expect([row.action, row.status, row.error_message])
          .to eq(%w[validation_failed validation_failed error_dcf_value_length])
        row
      end

      %w[list depending_list].each do |format|
        it "accepts 255 characters and refuses 256 on add for a #{format} field, counting characters" do
          field = dcf_list_field(format: format, values: %w[A], is_for_all: false, projects: [project])
          add(CustomField.find(field.id), value: 'a' * 255)
          add(CustomField.find(field.id), value: "é" * 255)
          add(CustomField.find(field.id), value: "\u{1F600}" * 255)
          add(CustomField.find(field.id), value: "  #{'b' * 255}  ")
          values = CustomField.find(field.id).possible_values
          expect(values.drop(1).map(&:length)).to eq([255, 255, 255, 255])
          expect(values.last).to eq('b' * 255)

          ['z' * 256, "é" * 256, "#{'y' * 255} "].each do |value|
            row = expect_length_refusal(field) { add(CustomField.find(field.id), value: value) }
            expect(row.attributes.values.join(' ')).not_to include(value[0, 40])
          end
          expect(CustomField.find(field.id).possible_values).to eq(values)
        end
      end

      it 'checks the length before the duplicate check' do
        field = own_list(['A'])
        field.update_column(:possible_values, ['A', 'q' * 256])
        expect_length_refusal(field) { add(CustomField.find(field.id), value: 'q' * 256) }
      end

      it 'checks a rename length before the not-found and the duplicate check' do
        field = own_list(%w[A B])
        expect_length_refusal(field) do
          rename(CustomField.find(field.id), old_value: 'Missing', new_value: 'm' * 256, confirm: '1')
        end
        field.update_column(:possible_values, ['A', 'q' * 256])
        expect_length_refusal(field) do
          rename(CustomField.find(field.id), old_value: 'A', new_value: 'q' * 256, confirm: '1')
        end
        expect(CustomField.find(field.id).possible_values).to eq(['A', 'q' * 256])
      end

      it 'refuses a 256-character rename before the confirmation and before any write, also on a shared field' do
        field = dcf_list_field(values: %w[A B], is_for_all: true)
        value = dcf_custom_value(field, 'A')
        expect_length_refusal(field) { rename(CustomField.find(field.id), old_value: 'A', new_value: 'r' * 256) }
        expect(value.reload.value).to eq('A')
        expect(CustomField.find(field.id).possible_values).to eq(%w[A B])

        rename(CustomField.find(field.id), old_value: 'A', new_value: 'r' * 255, confirm: '1')
        expect(value.reload.value).to eq('r' * 255)
      end

      it 'leaves longer values stored before untouched and lets them be removed, sorted or renamed to at most 255 characters' do
        long = 'x' * 300
        other = 'w' * 300
        field = own_list([long, 'B', other])
        value = dcf_custom_value(field, long)
        add(CustomField.find(field.id), value: 'C')
        sort(CustomField.find(field.id), direction: 'asc')
        set_default(CustomField.find(field.id), default_value: long)
        reorder(CustomField.find(field.id), ordered_values: [long, other, 'B', 'C'])
        expect(CustomField.find(field.id).possible_values).to eq([long, other, 'B', 'C'])

        rename(CustomField.find(field.id), old_value: long, new_value: long, confirm: '1')
        expect_length_refusal(field) do
          rename(CustomField.find(field.id), old_value: long, new_value: 'y' * 256, confirm: '1')
        end
        rename(CustomField.find(field.id), old_value: long, new_value: 'Short', confirm: '1')
        record = CustomField.find(field.id)
        expect(record.possible_values).to eq(['Short', other, 'B', 'C'])
        expect(record.default_value).to eq('Short')
        expect(value.reload.value).to eq('Short')

        remove(CustomField.find(field.id), value: other, confirm: '1')
        expect(CustomField.find(field.id).possible_values).to eq(%w[Short B C])
      end

      # Changed by the full review of 2026-11-05 (project-pages-4): the
      # services check core's 60-character limit themselves and say so
      # (error_dcf_value_length with max 60; was the generic error_save_failed).
      it 'keeps the core 60-character limit for enumeration names, never the list cap' do
        field = dcf_enum_field(names: %w[X])
        add(CustomField.find(field.id), value: 'e' * 60)
        [61, 256].each do |length|
          error = refusal { add(CustomField.find(field.id), value: 'f' * length) }
          expect([error.key, error.interpolations]).to eq([:error_dcf_value_length, { max: 60 }])
        end
        enum = field.enumerations.find_by(name: 'X')
        error = refusal { rename(CustomField.find(field.id), enumeration_id: enum.id, new_value: 'g' * 256) }
        expect([error.key, error.interpolations]).to eq([:error_dcf_value_length, { max: 60 }])
        expect(field.enumerations.pluck(:name)).to contain_exactly('X', 'e' * 60)
      end
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
