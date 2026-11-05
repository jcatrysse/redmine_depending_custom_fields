module RedmineDependingCustomFields
  # Operation E — batch editor for enumeration values, mirroring
  # `CustomFieldEnumerations#update_each`: one form for the whole table, one
  # Save, applying names + positions + active flags together.
  #
  # This is the submit model core uses on the screen we are copying
  # (`custom_field_enumerations#index`): the drag handle only rewrites the hidden
  # position inputs and the single Save commits everything. Core's *other*
  # reorder pattern (`reorder_handle` + `positionedItems`, used for trackers /
  # issue statuses / roles) does submit per drag — that is the one this plugin
  # borrowed for the list family, and it stays there.
  #
  # Enumeration family only: `list`/`depending_list` values are plain strings in
  # `possible_values` with no id, position or active flag, and keep the
  # per-operation endpoints (§A–§D).
  #
  # Params: `enumerations` => { "<id>" => { name:, position:, active: } } and
  # `batch_scope`: absent or blank is full mode (every row, positions applied);
  # exactly 'page' is page mode (WP-30): a subset of the rows, names and
  # active flags only, positions never read or written.
  #
  # Deactivating a value is non-destructive and reversible: it removes the value
  # from every picker (`possible_values_records` scopes to `enumerations.active`)
  # while existing `CustomValue` ids keep resolving to the name, and the field's
  # own dependency store and the parent keys of dependent fields are left intact
  # so reactivating restores the previous behaviour. Unlike Remove (§C) this runs
  # no prune and no parent-side cascade — see Operations Spec §E.
  class UpdateEnumerationsService < BaseService
    def audit_action
      'update_enumerations'
    end

    private

    def perform!
      raise OperationError.new(:error_format_unsupported) unless enum_family?
      return perform_page! if page_mode?

      rows = submitted_rows
      validate_names!(rows)
      validate_no_active_duplicates!(rows)

      delta = apply!(rows, positions: true)
      clear_dangling_default!(delta[:deactivated_ids])

      Outcome.new(before: delta[:before], after: delta[:after],
                  summary: summary_for(rows, delta),
                  affected_projects_count: affected_projects_count,
                  affected_values_count: deactivated_usage(delta[:deactivated_ids]))
    end

    # Page mode: the submitted rows are checked together with the stored
    # names of every row not submitted, so a page cannot create an active
    # duplicate with a value on another page.
    def perform_page!
      stored = field.enumerations.reorder(:position, :id).pluck(:id, :name, :active)
      rows = page_rows(stored)
      validate_names!(rows)
      validate_no_active_duplicates!(rows + unsubmitted_rows(stored, rows))

      delta = apply!(rows, positions: false)
      clear_dangling_default!(delta[:deactivated_ids])
      delta[:after][:scope] = 'page'
      delta[:after][:rows] = rows.length

      Outcome.new(before: delta[:before], after: delta[:after],
                  summary: "Saved #{rows.length} of #{stored.length} enumeration value(s) (page): " \
                           "#{summary_detail(delta)}",
                  affected_projects_count: affected_projects_count,
                  affected_values_count: deactivated_usage(delta[:deactivated_ids]))
    end

    # Only a blank scope selects full mode and only the String 'page' page
    # mode; anything else is refused. The posted value is never stored.
    def page_mode?
      scope = @params[:batch_scope]
      return false if scope.nil? || (scope.is_a?(String) && scope.strip.empty?)
      return true if scope.is_a?(String) && scope == 'page'

      raise OperationError.new(:error_reorder_mismatch)
    end

    # The submitted rows in stored order, each with its record. The keys must
    # be a non-empty set of this field's ids, compared as strings (no to_i),
    # each with a Hash of attributes; any other key refuses the whole save.
    def page_rows(stored)
      submitted = @params[:enumerations]
      submitted = submitted.to_unsafe_h if submitted.respond_to?(:to_unsafe_h)
      raise OperationError.new(:error_reorder_mismatch) unless submitted.is_a?(Hash) && submitted.any?

      by_key = submitted.each_with_object({}) do |(key, attrs), out|
        raise OperationError.new(:error_reorder_mismatch) if out.key?(key.to_s) || !attrs.is_a?(Hash)

        out[key.to_s] = attrs
      end
      ids = stored.map { |id, _name, _active| id.to_s }
      raise OperationError.new(:error_reorder_mismatch) unless (by_key.keys - ids).empty?

      records = field.enumerations.where(id: by_key.keys.map(&:to_i)).index_by { |enum| enum.id.to_s }
      raise OperationError.new(:error_reorder_mismatch) unless records.size == by_key.size

      ids.select { |id| by_key.key?(id) }.map do |id|
        attrs = by_key[id]
        {
          enum:   records.fetch(id),
          name:   normalize(attrs['name'] || attrs[:name]),
          active: ActiveModel::Type::Boolean.new.cast(attrs['active'] || attrs[:active]) || false
        }
      end
    end

    # The stored name and active flag of every row not submitted, normalized
    # as a full-mode submit of the same row would be.
    def unsubmitted_rows(stored, rows)
      submitted = rows.to_h { |row| [row[:enum].id, true] }
      stored.reject { |id, _name, _active| submitted.key?(id) }
            .map { |_id, name, active| { name: normalize(name), active: active } }
    end

    # Rows in the submitted display order, each paired with its record. The
    # submitted id set must match the field's exactly: a partial or tampered
    # submit is rejected whole rather than applied in part. A concurrent add or
    # delete is caught earlier by the state hash, so this never fires on a
    # legitimate save. A body that is no Hash of Hashes is refused as in page
    # mode (WP-32).
    def submitted_rows
      submitted = @params[:enumerations]
      submitted = submitted.to_unsafe_h if submitted.respond_to?(:to_unsafe_h)
      raise OperationError.new(:error_reorder_mismatch) unless submitted.nil? || submitted.is_a?(Hash)

      submitted = (submitted || {}).to_h

      enums = field.enumerations.to_a
      unless submitted.keys.map(&:to_s).sort == enums.map { |e| e.id.to_s }.sort
        raise OperationError.new(:error_reorder_mismatch)
      end

      rows = enums.map do |enum|
        attrs = submitted[enum.id.to_s] || submitted[enum.id]
        raise OperationError.new(:error_reorder_mismatch) unless attrs.is_a?(Hash)

        {
          enum:     enum,
          name:     normalize(attrs['name'] || attrs[:name]),
          active:   ActiveModel::Type::Boolean.new.cast(attrs['active'] || attrs[:active]) || false,
          position: (attrs['position'] || attrs[:position]).to_i
        }
      end
      # The hidden position inputs carry the dragged order; ties fall back to the
      # current position, then to input order, so an untouched table keeps its
      # order exactly.
      rows.each_with_index
          .sort_by { |r, i| [r[:position], r[:enum].position.to_i, i] }
          .map(&:first)
    end

    # A changed name has at most core's 60 characters (full review of
    # 2026-11-05, project-pages-4); a stored name may stay.
    def validate_names!(rows)
      raise OperationError.new(:error_value_blank) if rows.any? { |r| r[:name].blank? }

      rows.each { |r| check_enum_name_length!(r[:name]) unless r[:enum] && r[:name] == r[:enum].name }
    end

    # Checked against the RESULTING state, not the stored one: a save that
    # renames one value onto another's name, or reactivates a value whose name is
    # already taken, must be refused as a whole. Add (§A) and Rename (§B) enforce
    # the same active-name uniqueness; core has no such validation.
    def validate_no_active_duplicates!(rows)
      active_names = rows.select { |r| r[:active] }.map { |r| r[:name] }
      raise OperationError.new(:error_value_duplicate) if active_names.uniq.length != active_names.length
    end

    # positions: true (full mode) renumbers the rows 1..N in the given
    # order; false (page mode) never writes a position.
    def apply!(rows, positions:)
      renamed = []
      activated = []
      deactivated = []
      deactivated_ids = []
      reordered = false

      rows.each_with_index do |row, idx|
        enum = row[:enum]
        changes = {}
        position = idx + 1

        if row[:name] != enum.name
          renamed << { from: enum.name, to: row[:name] }
          changes[:name] = row[:name]
        end
        if row[:active] != enum.active?
          if row[:active]
            activated << row[:name]
          else
            deactivated << row[:name]
            deactivated_ids << enum.id
          end
          changes[:active] = row[:active]
        end
        if positions && enum.position.to_i != position
          reordered = true
          changes[:position] = position
        end

        enum.update!(changes) if changes.any?
      end

      {
        deactivated_ids: deactivated_ids,
        before: { renamed: capped(renamed.map { |r| r[:from] }) }.reject { |_, v| v.blank? },
        after: {
          renamed:     capped(renamed.map { |r| r[:to] }),
          activated:   capped(activated),
          deactivated: capped(deactivated),
          reordered:   reordered
        }.reject { |_, v| v.blank? && v != true }
      }
    end

    # A deactivated value is no longer offered by the field format, so leaving it
    # as `default_value` would pre-select an option no picker shows — and the
    # default picker on this screen lists active values only, so the stale
    # default would be invisible there. Clear it instead (named in the summary).
    def clear_dangling_default!(deactivated_ids)
      return false if deactivated_ids.empty?
      return false unless deactivated_ids.map(&:to_s).include?(field.default_value.to_s)

      field.default_value = nil
      save_field!(field)
      @default_cleared = true
    end

    # Blast radius: stored values now pointing at a deactivated option. One
    # capped COUNT for all deactivated values (full review of 2026-11-05,
    # project-pages-8: was one per value), capped like usage_total.
    def deactivated_usage(deactivated_ids)
      return 0 if deactivated_ids.empty?

      UsageCalculator.value_rows(field, deactivated_ids.map(&:to_s)).limit(UsageCalculator::USAGE_CAP + 1).count
    end

    def summary_for(rows, delta)
      "Saved #{rows.length} enumeration value(s): #{summary_detail(delta)}"
    end

    def summary_detail(delta)
      after = delta[:after]
      parts = []
      parts << "renamed #{after[:renamed].length}" if after[:renamed].present?
      parts << "activated #{after[:activated].length}" if after[:activated].present?
      parts << "deactivated #{after[:deactivated].length}" if after[:deactivated].present?
      parts << 'reordered' if after[:reordered]
      parts << 'default value cleared' if @default_cleared
      parts.any? ? parts.join(', ') : 'no changes'
    end
  end
end
