# frozen_string_literal: true

module RedmineDependingCustomFields
  # Raised when a destructive change has cross-project / in-use / dependency
  # impact and the user has not yet confirmed: a rename or a removal, and
  # (WP-34, UD-23) a dependency save or a sort of a field shared with other
  # projects or global. Not an error and not audited; the controller
  # re-renders the values page with the impact panel, or the dependency page
  # with the confirmation checkbox.
  class ConfirmationRequired < StandardError
    attr_reader :impact

    def initialize(impact)
      @impact = impact
      super('needs_confirmation')
    end
  end
end
