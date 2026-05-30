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
      record_failure(e.audit_status, e.key.to_s)
      raise
    rescue ActiveRecord::RecordInvalid => e
      record_failure('save_failed', e.message)
      raise OperationError.new(:error_save_failed)
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

    def record_failure(status, error_message)
      @recorder.record_failure!(action: failure_action(status), status: status, error_message: error_message)
    rescue StandardError
      # Audit table missing / unwritable: never mask the original failure.
      nil
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
