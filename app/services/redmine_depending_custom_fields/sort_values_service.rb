# frozen_string_literal: true

require 'digest'

module RedmineDependingCustomFields
  # Operation J: sort every value A-Z or Z-A (project design 6, WP-29). A
  # stable sort on the ValueCollation key, so case and accents are ignored and
  # ties keep their order in both directions. Lists save the sorted
  # possible_values once; enumerations, inactive ones included (UD-24), get
  # positions 1..N through one CASE update per CHUNK of changed rows. No
  # CustomValue rewrite, no cascade. A field shared with other projects or
  # global needs confirm after the direction check, before any write, also
  # when already sorted (UD-23, WP-34). An already sorted field writes
  # nothing and is still audited.
  class SortValuesService < BaseService
    CHUNK = 500
    DIRECTIONS = %w[asc desc].freeze

    # SHA-256 of ::JSON.generate over the ordered keys (list values, or
    # enumeration ids as Strings). Keys are scrubbed to valid UTF-8 first,
    # so the digest never raises. Shared with ReorderValuesService.
    def self.order_sha256(keys)
      Digest::SHA256.hexdigest(::JSON.generate(Array(keys).map { |key| ValueCollation.text(key) }))
    end

    def audit_action
      'sort_values'
    end

    private

    def perform!
      direction = @params[:direction]
      unless direction.is_a?(String) && DIRECTIONS.include?(direction)
        raise OperationError.new(:error_reorder_mismatch)
      end

      confirm_shared_change!

      desc = direction == 'desc'
      old_keys, new_keys, moved = list_family? ? sort_list!(desc) : sort_enumerations!(desc)
      count = old_keys.size
      Outcome.new(
        before: { count: count, order_sha256: self.class.order_sha256(old_keys) },
        after: { direction: desc ? 'desc' : 'asc', count: count, moved: moved,
                 order_sha256: self.class.order_sha256(new_keys) },
        summary: "Sorted #{count} value(s) #{desc ? 'Z-A' : 'A-Z'} (#{moved} moved)"
      )
    end

    # The raw stored values, duplicates kept (value_options would uniq them).
    def sort_list!(desc)
      current = possible_values.map(&:to_s)
      sorted = ValueCollation.sort(current, desc: desc)
      moved = current.each_index.count { |i| current[i] != sorted[i] }
      if moved.positive?
        field.possible_values = sorted
        save_field!(field)
      end
      [current, sorted, moved]
    end

    # Read once in [position, id] order, as the page shows them; moved counts
    # the rows whose stored position changes, so gaps are renumbered too.
    def sort_enumerations!(desc)
      rows = CustomFieldEnumeration.where(custom_field_id: field.id).pluck(:id, :name, :position)
                                   .sort_by { |(id, _name, position)| [position.to_i, id] }
      sorted = ValueCollation.sort(rows, desc: desc) { |_id, name, _position| name }
      changes = []
      sorted.each_with_index do |(id, _name, position), index|
        changes << [Integer(id), index + 1] unless position.to_i == index + 1
      end
      update_positions!(changes)
      [rows.map { |row| row[0].to_s }, sorted.map { |row| row[0].to_s }, changes.size]
    end

    # One UPDATE per slice, integers only, scoped to this field; ELSE keeps a
    # row the CASE does not name. CustomFieldEnumeration has no update
    # callbacks in Redmine 5.1 to 7.0, so update_all skips none.
    def update_positions!(changes)
      changes.each_slice(CHUNK) do |slice|
        assignment = "position = CASE id#{' WHEN ? THEN ?' * slice.size} ELSE position END"
        CustomFieldEnumeration.where(custom_field_id: field.id, id: slice.map(&:first))
                              .update_all([assignment, *slice.flatten])
      end
    end
  end
end
