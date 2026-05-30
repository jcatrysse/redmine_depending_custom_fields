module RedmineDependingCustomFields
  # Writes audit rows. Success rows are written by the caller INSIDE the change
  # transaction (so an audit failure rolls the change back). Failure rows are
  # written in their OWN top-level transaction so they persist even though the
  # rejected operation never happened. See Audit Spec §6/§10.
  class AuditRecorder
    def initialize(project:, field:, user: User.current, request: nil)
      @project = project
      @field = field
      @user = user
      @request = request
    end

    # Called within the surrounding change transaction.
    def record_success!(action:, before: nil, after: nil, summary: nil,
                         affected_projects_count: nil, affected_values_count: nil,
                         affected_child_field_ids: nil)
      ConfigAuditEvent.create!(
        base_attrs(action, 'success').merge(
          before_value:             serialize(before),
          after_value:              serialize(after),
          changes_summary:          summary&.to_s&.slice(0, 1000),
          affected_projects_count:  affected_projects_count,
          affected_values_count:    affected_values_count,
          affected_child_field_ids: serialize_ids(affected_child_field_ids)
        )
      )
    end

    # Called from a rescue, OUTSIDE/after the change transaction has rolled back.
    def record_failure!(action:, status:, error_message: nil, summary: nil)
      ActiveRecord::Base.transaction do
        ConfigAuditEvent.create!(
          base_attrs(action, status).merge(
            error_message:   error_message&.to_s,
            changes_summary: summary&.to_s&.slice(0, 1000)
          )
        )
      end
    end

    private

    def base_attrs(action, status)
      {
        project_id:        @project&.id,
        custom_field_id:   @field&.id,
        custom_field_name: @field&.name&.to_s&.slice(0, 255),
        acting_user_id:    @user&.id,
        acting_user_name:  actor_name,
        action:            action.to_s,
        status:            status.to_s,
        ip_address:        @request&.remote_ip&.to_s&.slice(0, 45),
        user_agent:        @request&.user_agent&.to_s&.slice(0, 512),
        request_id:        @request&.request_id&.to_s&.slice(0, 64),
        created_at:        Time.now
      }
    end

    def actor_name
      return unless @user

      (@user.respond_to?(:name) ? @user.name : @user.to_s).to_s.slice(0, 255)
    end

    def serialize(value)
      return if value.nil?

      ActiveSupport::JSON.encode(value)
    end

    def serialize_ids(ids)
      return if ids.nil?

      ActiveSupport::JSON.encode(Array(ids))
    end
  end
end
