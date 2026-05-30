module RedmineDependingCustomFields
  # Raised when a destructive change has cross-project / in-use / dependency
  # impact and the user has not yet confirmed. Not an error and not audited;
  # the controller re-renders the edit screen with the impact panel.
  class ConfirmationRequired < StandardError
    attr_reader :impact

    def initialize(impact)
      @impact = impact
      super('needs_confirmation')
    end
  end
end
