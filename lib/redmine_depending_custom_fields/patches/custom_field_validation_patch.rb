# frozen_string_literal: true

module RedmineDependingCustomFields
  module Patches
    # Every new CustomField callback of this plugin lives here, registered as
    # a Symbol so a second prepend (init.rb run twice) keeps one of each.
    # CustomFieldPatch registers none (its after_save dispatch went with the
    # cache in WP-18, quality S1).
    #
    # WP-22 adds the admin JSON transport of the dependency mapping, the
    # write-only safe attribute dependencies_json (editor design 3.1). It is
    # applied before validation, when every attribute of the same
    # safe_attributes= call is assigned, and validated before the storage
    # check, which so measures the pruned mapping. Its state lives on the
    # record: the raw value, a round bumped by each assignment and save (the
    # dcf_memo key of the parse and of the stored digest), and the error.
    module CustomFieldValidationPatch
      PAYLOAD_MEMO = :dcf_dependencies_payload
      DIGEST_MEMO = :dcf_stored_dependencies_digest

      def self.prepended(base)
        base.before_validation :dcf_apply_dependencies_json
        base.validate :dcf_validate_dependencies_json
        base.validate :dcf_validate_storage_limits
        base.after_save :dcf_reset_dependencies_json
      end

      # Stores the raw value only (any object); before_validation reads it.
      def dependencies_json=(raw)
        dcf_forget_dependencies_json
        @dcf_dependencies_json = raw
      end

      # Submitted input is never echoed (SP-11).
      def dependencies_json
        nil
      end

      # The posted version, parsed but not pruned, when the last validation
      # refused it as stale (UD-17); nil otherwise. A new copy on each call.
      def dcf_dependencies_conflict
        return nil unless @dcf_dependencies_error == :dcf_stale_dependencies

        result = dcf_dependencies_payload
        { 'value_dependencies' => result.value_dependencies,
          'default_value_dependencies' => result.default_value_dependencies,
          'source' => result.source,
          'import' => result.import }.deep_dup
      end

      private

      def dcf_validate_storage_limits
        RedmineDependingCustomFields::StorageLimits.validate(self)
      end

      # Nothing posted keeps the mapping; an unreadable, oversize or stale
      # payload applies nothing. Otherwise both mappings are replaced by the
      # payload pruned against the parent this save keeps (D6, BC-02: the
      # only pruning) and the field's own values, inactive ones included.
      def dcf_apply_dependencies_json
        @dcf_dependencies_error = nil
        # Asked of nil: the raw value may be any object (WP-21 never reads it).
        return if nil.equal?(@dcf_dependencies_json)

        rules = RedmineDependingCustomFields::DependencyRules
        return unless rules.depending?(self)

        result = dcf_dependencies_payload
        return if result.nil?

        unless result.ok?
          @dcf_dependencies_error = if result.error == :too_large
                                      :dcf_dependencies_too_large_to_send
                                    else
                                      :dcf_invalid_dependencies_payload
                                    end
          return
        end
        if result.base && persisted? && result.base != dcf_stored_dependencies_digest
          @dcf_dependencies_error = :dcf_stale_dependencies
          return
        end

        parent = rules.resolve_parent_for_save(self)
        links, defaults = rules.prune_mapping(result.value_dependencies, result.default_value_dependencies,
                                              parent_keys: parent ? rules.value_keys(parent) : nil,
                                              child_keys: rules.value_keys(self),
                                              multiple: multiple?)
        self.value_dependencies = links
        self.default_value_dependencies = defaults
      end

      def dcf_validate_dependencies_json
        case @dcf_dependencies_error
        when nil
          nil
        when :dcf_dependencies_too_large_to_send
          limits = RedmineDependingCustomFields::StorageLimits
          bytes = dcf_dependencies_payload.bytes
          max_bytes = RedmineDependingCustomFields::DependencyPayload::MAX_BYTES
          errors.add(:value_dependencies, :dcf_dependencies_too_large_to_send,
                     size: limits.delimited(bytes), limit: limits.delimited(max_bytes),
                     bytes: bytes, max_bytes: max_bytes)
        else
          errors.add(:value_dependencies, @dcf_dependencies_error)
        end
      end

      def dcf_reset_dependencies_json
        dcf_forget_dependencies_json
        @dcf_dependencies_json = nil
      end

      # Parsed once per assigned value (SP-17). A refused payload is logged
      # here, once, with its code and size only, never its content.
      def dcf_dependencies_payload
        dcf_memo(PAYLOAD_MEMO, @dcf_dependencies_round) do
          result = RedmineDependingCustomFields::DependencyPayload.parse(@dcf_dependencies_json)
          if result && !result.ok?
            Rails.logger.warn("[DCF] custom field ##{id || 'new'} dependencies_json rejected: " \
                              "#{result.error} (#{result.bytes} bytes)")
          end
          result
        end
      end

      # The digest of the stored mapping, read once per round: a save starts
      # a new round, so it is never older than the row this record wrote.
      def dcf_stored_dependencies_digest
        dcf_memo(DIGEST_MEMO, @dcf_dependencies_round) do
          RedmineDependingCustomFields::DependencyPayload.stored_digest(self)
        end
      end

      # Drops this round's memo entries (dcf_memo keys are [name, key]) and
      # the error, and starts a new round.
      def dcf_forget_dependencies_json
        round = @dcf_dependencies_round
        @dcf_memo&.delete([PAYLOAD_MEMO, round])
        @dcf_memo&.delete([DIGEST_MEMO, round])
        @dcf_dependencies_round = round.to_i + 1
        @dcf_dependencies_error = nil
      end
    end
  end
end
