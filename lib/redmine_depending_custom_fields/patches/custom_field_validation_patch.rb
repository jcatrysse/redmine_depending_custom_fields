# frozen_string_literal: true

module RedmineDependingCustomFields
  module Patches
    # Every new CustomField callback of this plugin lives here, registered as
    # a Symbol so a second prepend (init.rb run twice) keeps one of each.
    # CustomFieldPatch registers none (its after_save dispatch went with the
    # cache in WP-18, quality S1).
    module CustomFieldValidationPatch
      def self.prepended(base)
        base.validate :dcf_validate_storage_limits
      end

      private

      def dcf_validate_storage_limits
        RedmineDependingCustomFields::StorageLimits.validate(self)
      end
    end
  end
end
