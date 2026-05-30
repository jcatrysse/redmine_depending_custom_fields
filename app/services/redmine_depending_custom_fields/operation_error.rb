module RedmineDependingCustomFields
  # Raised by configuration services for any rejected operation. Carries the
  # I18n error key, the HTTP status the controller should map to, and the audit
  # status used when recording the rejected attempt.
  class OperationError < StandardError
    attr_reader :key, :http_status, :audit_status

    def initialize(key, http_status: :unprocessable_entity, audit_status: 'validation_failed')
      @key = key
      @http_status = http_status
      @audit_status = audit_status
      super(key.to_s)
    end
  end
end
