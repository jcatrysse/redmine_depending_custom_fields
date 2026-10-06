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
  # Params: `enumerations` => { "<id>" => { name:, position:, active: } }.
  #
  # Deactivating a value is non-destructive and reversible: it removes the value
  # from every picker (`possible_values_records` scopes to `enumerations.active`)
  # while existing `CustomValue` ids keep resolving to the name, and the field's
  # own dependency store and the parent keys of dependent fields are left intact
  # so reactivating restores the previous behaviour. Unlike Remove (§C) this runs
  # no prune and no parent-side cascade — see Operations Spec §E.
  class UpdateEnumerationsService < BaseService
    # Keep audit rows small on fields with many values (Audit Spec §3).
    DELTA_CAP = 20

    def audit_action
      'update_enumerations'
    end

    private

    def perform!
      raise OperationError.new(:error_format_unsupported) unless enum_family?

      rows = submitted_rows
      validate_names!(rows)
      validate_no_active_duplicates!(rows)

      delta = apply!(rows)
      clear_dangling_default!(delta[:deactivated_ids])

      Outcome.new(before: delta[:before], after: delta[:after],
                  summary: summary_for(rows, delta),
                  affected_projects_count: affected_projects_count,
                  affected_values_count: deactivated_usage(delta[:deactivated_ids]))
    end

    # Rows in the submitted display order, each paired with its record. The
    # submitted id set must match the field's exactly: a partial or tampered
    # submit is rejected whole rather than applied in part. A concurrent add or
    # delete is caught earlier by the state hash, so this never fires on a
    # legitimate save.
    def submitted_rows
      submitted = @params[:enumerations]
      submitted = submitted.to_unsafe_h if submitted.respond_to?(:to_unsafe_h)
      submitted = (submitted || {}).to_h

      enums = field.enumerations.to_a
      unless submitted.keys.map(&:to_s).sort == enums.map { |e| e.id.to_s }.sort
        raise OperationError.new(:error_reorder_mismatch)
      end

      rows = enums.map do |enum|
        attrs = submitted[enum.id.to_s] || submitted[enum.id]
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

    def validate_names!(rows)
      raise OperationError.new(:error_value_blank) if rows.any? { |r| r[:name].blank? }
    end

    # Checked against the RESULTING state, not the stored one: a save that
    # renames one value onto another's name, or reactivates a value whose name is
    # already taken, must be refused as a whole. Add (§A) and Rename (§B) enforce
    # the same active-name uniqueness; core has no such validation.
    #
    # Only a collision this save creates is refused: one where a row in it was
    # renamed or reactivated. Core's own enumeration editor allows duplicates, so
    # a field can already hold two active values with the same name; rejecting
    # those would block every save on the table, including the rename or
    # deactivation that resolves the duplicate.
    def validate_no_active_duplicates!(rows)
      clash = rows.select { |r| r[:active] }.group_by { |r| r[:name] }.values.any? do |group|
        group.length > 1 && group.any? { |r| touched?(r) }
      end
      raise OperationError.new(:error_value_duplicate) if clash
    end

    # The row ends up active under a name it did not already hold while active.
    def touched?(row)
      !row[:enum].active? || name_changed?(row)
    end

    # Compared on the normalized stored name: the submitted name is always
    # stripped, so a stored name with stray whitespace is not a rename.
    def name_changed?(row)
      row[:name] != normalize(row[:enum].name)
    end

    def apply!(rows)
      renamed = []
      activated = []
      deactivated = []
      deactivated_ids = []
      reordered = false

      rows.each_with_index do |row, idx|
        enum = row[:enum]
        changes = {}
        position = idx + 1

        if name_changed?(row)
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
        if enum.position.to_i != position
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

    def capped(list)
      return list if list.length <= DELTA_CAP

      list.first(DELTA_CAP) + ["(+#{list.length - DELTA_CAP} more)"]
    end

    # A deactivated value is no longer offered by the field format, so leaving it
    # as `default_value` would pre-select an option no picker shows — and the
    # default picker on this screen lists active values only, so the stale
    # default would be invisible there. Clear it instead (named in the summary).
    def clear_dangling_default!(deactivated_ids)
      return false if deactivated_ids.empty?
      return false unless deactivated_ids.map(&:to_s).include?(field.default_value.to_s)

      field.default_value = nil
      field.save!
      @default_cleared = true
    end

    # Blast radius: stored values now pointing at a deactivated option. One
    # capped COUNT per deactivated value (usually none or one).
    def deactivated_usage(deactivated_ids)
      deactivated_ids.sum { |id| UsageCalculator.usage_total(field, id) }
    end

    def summary_for(rows, delta)
      after = delta[:after]
      parts = []
      parts << "renamed #{after[:renamed].length}" if after[:renamed].present?
      parts << "activated #{after[:activated].length}" if after[:activated].present?
      parts << "deactivated #{after[:deactivated].length}" if after[:deactivated].present?
      parts << 'reordered' if after[:reordered]
      parts << 'default value cleared' if @default_cleared
      detail = parts.any? ? parts.join(', ') : 'no changes'
      "Saved #{rows.length} enumeration value(s): #{detail}"
    end
  end
end
