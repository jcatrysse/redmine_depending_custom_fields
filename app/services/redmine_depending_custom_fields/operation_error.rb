module RedmineDependingCustomFields
  # Raised by configuration services for any rejected operation. Carries the
  # I18n error key, the HTTP status the controller should map to, and the audit
  # status used when recording the rejected attempt. summary is the audit
  # changes_summary of the failure row, interpolations are the flash values
  # (escaped by the controller) and payload is kept for a re-render. None of
  # them is part of the message, which stays the key.
  class OperationError < StandardError
    attr_reader :key, :http_status, :audit_status, :summary, :interpolations, :payload

    def initialize(key, http_status: :unprocessable_entity, audit_status: 'validation_failed',
                   summary: nil, interpolations: nil, payload: nil)
      @key = key
      @http_status = http_status
      @audit_status = audit_status
      @summary = summary
      @interpolations = interpolations || {}
      @payload = payload
      super(key.to_s)
    end
  end
end
