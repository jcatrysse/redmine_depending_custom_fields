require 'digest'

module RedmineDependingCustomFields
  # Common preamble + transaction + audit wrapper shared by every configuration
  # operation service. Subclasses implement #audit_action and #perform!, the
  # latter returning an Outcome describing the change for the audit row.
  #
  # Services never call safe_attributes=; they mutate only the specific surface
  # and persist via the model's save! so the plugin's sanitizer/cache callbacks
  # run. See Operations Spec §0.
  class BaseService
    PERMISSION = :manage_project_custom_field_configuration

    Outcome = Struct.new(
      :before, :after, :summary,
      :affected_projects_count, :affected_values_count, :affected_child_field_ids,
      keyword_init: true
    )

    # Cross-project / in-use / dependency impact, surfaced to the user before a
    # destructive change is confirmed.
    Impact = Struct.new(
      :value, :usage_here, :usage_other, :own_dep_refs, :parent_key_refs,
      :affected_child_fields, :shared,
      keyword_init: true
    )

    # Compact digest of the field's value-set + own dependency store, used for
    # optimistic concurrency (Operations Spec §0 / Data Model §6).
    def self.state_hash(field)
      data =
        if FieldRelevance::ENUM_FAMILY.include?(field.field_format)
          field.enumerations.order(:position).pluck(:id, :name, :position, :active)
        else
          Array(field.possible_values)
        end
      payload = [field.field_format, data, field.value_dependencies, field.default_value_dependencies]
      Digest::SHA256.hexdigest(ActiveSupport::JSON.encode(payload))
    end

    def initialize(project:, field:, user: User.current, params: {}, request: nil)
      @project = project
      @field = field
      @user = user
      @params = params || {}
      @request = request
      @recorder = AuditRecorder.new(project: project, field: field, user: user, request: request)
    end

    # Returns the Outcome on success; raises OperationError or ConfirmationRequired.
    # Every rejected call writes exactly one failure row: each mapped error is
    # raised inside its rescue clause, which sibling clauses do not catch.
    def call
      preamble!
      outcome = nil
      ActiveRecord::Base.transaction do
        outcome = perform!
        @recorder.record_success!(
          action:                   audit_action,
          before:                   outcome.before,
          after:                    outcome.after,
          summary:                  outcome.summary,
          affected_projects_count:  outcome.affected_projects_count,
          affected_values_count:    outcome.affected_values_count,
          affected_child_field_ids: outcome.affected_child_field_ids
        )
      end
      outcome
    rescue ConfirmationRequired
      raise
    rescue OperationError => e
      record_failure(e.audit_status, e.key.to_s, e.summary)
      raise
    rescue ActiveRecord::RecordInvalid => e
      violation = storage_violation(e.record)
      if violation
        error = storage_error(violation)
        record_failure(error.audit_status, error.key.to_s, error.summary)
        raise error if nameable_field?(e.record)

        # A cascaded field the acting user cannot see is never named.
        raise OperationError.new(:error_save_failed, summary: error.summary)
      end
      record_failure('save_failed', AuditPayload.error_message(e.message))
      raise OperationError.new(:error_save_failed)
    rescue ActiveRecord::ValueTooLong => e
      # Safety net for a limit the app does not know (SP-09): the row, the
      # flash and the raised error never carry e.message, the SQL or a value.
      record_failure('save_failed', 'error_dcf_value_too_long', value_too_long_summary(e))
      raise OperationError.new(:error_dcf_value_too_long, audit_status: 'save_failed'), cause: nil
    end

    private

    attr_reader :project, :field, :user, :params

    def preamble!
      unless @user.allowed_to?(PERMISSION, project)
        raise OperationError.new(:error_forbidden, http_status: :forbidden, audit_status: 'authorization_failed')
      end
      unless FieldRelevance.relevant?(field, project)
        raise OperationError.new(:error_field_not_found, http_status: :not_found)
      end
      unless FieldRelevance.supported_format?(field)
        raise OperationError.new(:error_format_unsupported)
      end
      if dependency_op? && !FieldRelevance.dependency_capable?(field)
        raise OperationError.new(:error_format_unsupported)
      end
      if write_op? && !project.active?
        raise OperationError.new(:error_project_archived, http_status: :forbidden)
      end
      check_state_hash!
    end

    def check_state_hash!
      return unless write_op?
      return if @params[:state_hash].blank?

      if @params[:state_hash] != self.class.state_hash(field)
        raise OperationError.new(:error_stale_edit, http_status: :conflict)
      end
    end

    def record_failure(status, error_message, summary = nil)
      @recorder.record_failure!(action: failure_action(status), status: status,
                                error_message: error_message, summary: summary)
    rescue StandardError
      # Audit table missing / unwritable: never mask the original failure.
      nil
    end

    # The first storage violation of a CustomField that failed validation;
    # nil for any other record (enumerations, audit rows, none).
    def storage_violation(record)
      return nil unless record.is_a?(CustomField)

      StorageLimits.violation_in(record)
    rescue StandardError
      nil
    end

    # Limits design 5.2: the flash names the field and both sizes; the audit
    # summary holds only the column, the byte counts and the field id.
    def storage_error(violation)
      key = violation.column == 'possible_values' ? :error_dcf_values_too_large : :error_dcf_mapping_too_large
      OperationError.new(
        key,
        summary: "#{violation.column}: #{violation.bytes} bytes exceeds #{violation.limit} " \
                 "(custom field ##{violation.custom_field_id})",
        interpolations: { field: violation.custom_field_name.to_s,
                          size: StorageLimits.delimited(violation.bytes),
                          limit: StorageLimits.delimited(violation.limit) }
      )
    end

    # The edited field, or one the user may see in this project (fail closed).
    def nameable_field?(record)
      return true if record.id == field.id || user.admin?

      FieldRelevance.in_project?(record, project) && record.visible_by?(project, user)
    rescue StandardError
      false
    end

    # Limits design 5.3: the class name, a known column name, the field id
    # and the byte counts of the edited field (the error carries no record).
    def value_too_long_summary(error)
      column = error.message.to_s[/column '([A-Za-z0-9_]{1,64})'/, 1]
      column = 'unknown' unless column && known_column?(column)
      sizes = StorageLimits::COLUMNS.keys.map { |c| "#{c}_bytes=#{StorageLimits.preview_bytes(field, c)}" }
      "ActiveRecord::ValueTooLong column=#{column} field_id=#{field&.id} #{sizes.join(' ')}"
    rescue StandardError
      'ActiveRecord::ValueTooLong'
    end

    def known_column?(name)
      [CustomField, CustomValue, CustomFieldEnumeration, ConfigAuditEvent].any? do |model|
        model.column_names.include?(name)
      end
    end

    def failure_action(status)
      case status
      when 'authorization_failed' then 'authorization_failed'
      when 'save_failed'          then 'save_failed'
      else                             'validation_failed'
      end
    end

    # --- overridable hooks -------------------------------------------------
    def dependency_op?
      false
    end

    def write_op?
      true
    end

    # --- shared helpers ----------------------------------------------------
    def normalize(value)
      value.to_s.strip
    end

    def list_family?
      FieldRelevance.list_family?(field)
    end

    def enum_family?
      FieldRelevance.enum_family?(field)
    end

    def depending?
      FieldRelevance.depending_format?(field)
    end

    def possible_values
      Array(field.possible_values)
    end

    def shared_or_global?
      return true if field.is_a?(ProjectCustomField)
      return true if field.is_for_all?

      others = field.projects.reject { |p| p.id == project.id }
      others.any?
    end

    def affected_projects_count
      return Project.active.count if field.is_a?(ProjectCustomField) || field.is_for_all?

      field.projects.size
    end

    def confirmed?
      ActiveModel::Type::Boolean.new.cast(@params[:confirm])
    end

    def block_removal_when_used?
      raw = Setting.plugin_redmine_depending_custom_fields['block_removal_when_used']
      raw.nil? ? false : ActiveModel::Type::Boolean.new.cast(raw)
    end

    # The stored value keys of a field: option strings for list families,
    # enumeration ids (strings) for enum families.
    def value_keys_of(cf)
      if FieldRelevance.enum_family?(cf)
        cf.enumerations.pluck(:id).map(&:to_s)
      else
        Array(cf.possible_values).map(&:to_s)
      end
    end

    def build_impact(value, usage_here, usage_other, own_refs, parent_refs, affected)
      Impact.new(
        value: value, usage_here: usage_here, usage_other: usage_other,
        own_dep_refs: own_refs, parent_key_refs: parent_refs,
        affected_child_fields: affected, shared: shared_or_global?
      )
    end

    # Rewrite this depending_list field's OWN dependency store when one of its
    # (child) option strings is renamed. Keys are parent values (unchanged);
    # the value appears inside the allowed-child arrays and default values.
    def rewrite_own_list_deps!(old, nv)
      vd = (field.value_dependencies || {}).deep_dup
      vd.each { |k, arr| vd[k] = Array(arr).map { |x| x.to_s == old.to_s ? nv : x } }
      field.value_dependencies = vd

      dd = (field.default_value_dependencies || {}).deep_dup
      dd.each do |k, val|
        dd[k] = if val.is_a?(Array)
                  val.map { |x| x.to_s == old.to_s ? nv : x }
                else
                  val.to_s == old.to_s ? nv : val
                end
      end
      field.default_value_dependencies = dd
    end

    # Prune a removed (child) value/id from this depending field's OWN store.
    def prune_own_deps!(value)
      v = value.to_s
      vd = (field.value_dependencies || {}).deep_dup
      vd.each { |k, arr| vd[k] = Array(arr).reject { |x| x.to_s == v } }
      field.value_dependencies = vd

      dd = (field.default_value_dependencies || {}).deep_dup
      dd.keys.each do |k|
        val = dd[k]
        if val.is_a?(Array)
          dd[k] = val.reject { |x| x.to_s == v }
        elsif val.to_s == v
          dd.delete(k)
        end
      end
      field.default_value_dependencies = dd
    end

    # Rewrite/prune a parent key across every depending child of this field.
    # mode: :rename rewrites old->new; :remove deletes the key. Returns the ids
    # of children that were touched (for the audit row).
    def cascade_parent_key!(old_key, new_key, mode)
      touched = []
      FieldRelevance.children_of(field).each do |child|
        changed = false
        vd = (child.value_dependencies || {}).deep_dup
        dd = (child.default_value_dependencies || {}).deep_dup

        [vd, dd].each do |store|
          next unless store.key?(old_key.to_s)

          value = store.delete(old_key.to_s)
          if mode == :rename
            store[new_key.to_s] = value
          end
          changed = true
        end

        next unless changed

        child.value_dependencies = vd
        child.default_value_dependencies = dd
        child.save!
        touched << child.id
      end
      touched
    end
  end
end
