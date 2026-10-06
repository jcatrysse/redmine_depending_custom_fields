# frozen_string_literal: true

require 'set'

module RedmineDependingCustomFields
  # The single topology helper for depending fields (server design section 4).
  #
  # Parent ids are read from the raw format_store YAML with an anchored regex,
  # so building an index never deserializes format_store. Rows come from loaded
  # records (no query) or from one raw select; unknown ids are fetched in one
  # batched query per #ensure call, so a walk costs at most one query per
  # chain level it does not know yet. An index built by FieldIndex.load with
  # its default scope knows every depending field, so its walks never fetch:
  # any other id is non-depending or missing and has no pointer. Walks follow
  # the stored (raw) pointers of depending rows through any type and family
  # (only the first hop of effective_parent_id_for is validated), keep a
  # visited Set and stop after WALK_CAP ids.
  #
  # One index serves one operation: there is no class-level state and nothing
  # is written onto the records it reads.
  class FieldIndex
    # A top-level key only: nested keys, block scalars and folded lines are indented.
    PARENT_RE = /^parent_custom_field_id: *(?:'(\d*)'|"(\d*)"|(\d*)) *$/.freeze
    PARENT_KEY = 'parent_custom_field_id'
    COLUMNS = [:id, :type, :field_format, :format_store].freeze
    QUERY_NAME = 'DCF FieldIndex'
    WALK_CAP = 1_000

    # parent_id is the normalized stored pointer; nil for non-depending rows.
    Row = Struct.new(:id, :type, :field_format, :parent_id)

    # Every depending field (or every field of +scope+) in one raw select, with
    # no type casting and no deserialization.
    def self.load(scope = nil)
      return new.send(:load_scope, scope, false) if scope

      new.send(:load_scope, CustomField.where(field_format: DependencyRules::DEPENDING_FORMATS), true)
    end

    # The stored parent id of a raw format_store value as a positive Integer,
    # or nil, mirroring the to_i of the accessor value. The value is
    # deserialized only when the key text is present but the regex misses or
    # does not apply (shapes ActiveRecord does not write: symbol keys, flow
    # style, CRLF, no header). Never raises.
    #
    # The regex runs only on values with the '---' header ActiveRecord always
    # writes; anything else goes through the coder of the running Rails, as
    # the accessor does (Rails 6.1 reads YAML without the header as {}).
    # Hand-written rows the regex reads differently from Psych (not written by
    # ActiveRecord): an unquoted leading zero ('010' is octal 8 for Psych) and
    # a repeated top-level key (Psych keeps the last one).
    def self.parent_id_from_raw(raw)
      return parent_id_in(raw) if raw.is_a?(Hash)
      return nil unless raw.is_a?(String) && !raw.empty?

      text = raw.valid_encoding? ? raw : raw.b
      if text.start_with?('---')
        match = PARENT_RE.match(text)
        return DependencyRules.normalize_id(match[1] || match[2] || match[3]) if match
      end
      return nil unless text.include?(PARENT_KEY)

      parent_id_in(CustomField.type_for_attribute('format_store').deserialize(raw))
    rescue StandardError
      nil
    end

    def self.parent_id_in(store)
      return nil unless store.is_a?(Hash)

      DependencyRules.normalize_id(store.key?(PARENT_KEY) ? store[PARENT_KEY] : store[PARENT_KEY.to_sym])
    end
    private_class_method :parent_id_in

    # records: id => CustomField loaded from the database and not modified in
    # memory (the raw column is the stored state). rows: id => Row. Lazy: no
    # query and no record read until a row is needed.
    def initialize(records: {}, rows: {})
      @records = records
      @rows = rows.dup
      @children_map = nil
      @depending_complete = false
    end

    # Makes the rows of +ids+ known: from the loaded records first (no query),
    # the rest in one raw select without format or type filter. Ids that do not
    # exist are remembered as missing.
    def ensure(ids)
      wanted = normalize_ids(ids).reject { |id| @rows.key?(id) }
      return self if wanted.empty?

      rest = wanted.reject { |id| materialize(id) }
      unless rest.empty?
        fetched = select_rows(CustomField.where(id: rest))
        rest.each { |id| @rows[id] = fetched[id] }
      end
      @children_map = nil
      self
    end

    def row(id)
      key = DependencyRules.normalize_id(id)
      return nil unless key

      self.ensure([key]) unless @rows.key?(key)
      @rows[key]
    end

    # The raw stored pointer, without validity check.
    def parent_id(id)
      row(id)&.parent_id
    end

    def exists?(id)
      !row(id).nil?
    end

    # Ids of the known rows whose stored pointer is +id+ (raw equality: any
    # type, any family, a self-parent included), ascending. Complete only on an
    # index built by FieldIndex.load, which knows every depending field.
    def children_ids(id)
      key = DependencyRules.normalize_id(id)
      return [] unless key

      children_map.fetch(key, []).dup
    end

    # All descendants of +id+, level by level with ascending ids within each
    # level, without +id+ itself, at most WALK_CAP ids (the first ones in that
    # order). Needs a FieldIndex.load index.
    def descendant_ids(id)
      start = DependencyRules.normalize_id(id)
      return [] unless start

      out = []
      seen = Set[start]
      level = [start]
      until level.empty?
        following = []
        level.each { |pid| children_ids(pid).each { |child| following << child if seen.add?(child) } }
        following.sort!
        following.each do |child|
          out << child
          return out if out.size >= WALK_CAP
        end
        level = following
      end
      out
    end

    # The stored pointer chain of +id+, nearest first, each id once. It ends
    # after a field without a pointer of its own (a plain list or enumeration
    # root, listed), before an id that does not exist (not listed), on a field
    # already listed, and after returning to +id+ (A->B->A gives [B, A] for A,
    # A->A gives [A], C->A<->B gives [A, B] for C). At most WALK_CAP ids.
    def ancestor_ids(id)
      start = DependencyRules.normalize_id(id)
      return [] unless start

      out = []
      listed = Set.new
      current = pointer_of(start)
      while current && !listed.include?(current) && exists?(current)
        out << current
        listed << current
        break if current == start || out.size >= WALK_CAP

        current = pointer_of(current)
      end
      out
    end

    # Effective parent (server design 2.1): +pid+ (the child's pointer, given by
    # the caller) as an Integer when it is not the child itself, names an
    # existing field of +child_type+ in the family of +child_format+, and the
    # chain from it never revisits a field (the child included). A chain that
    # reaches a cycle anywhere, a self-parent ancestor (a cycle of one) or more
    # than WALK_CAP hops give nil (unconstrained). The child's own row is never
    # read, so new records and in-memory pointers work.
    def effective_parent_id_for(child_id, child_type, child_format, pid)
      family = DependencyRules::PARENT_FORMATS[child_format]
      parent = DependencyRules.normalize_id(pid)
      child = DependencyRules.normalize_id(child_id)
      return nil unless family && parent && parent != child

      record = row(parent)
      return nil unless record && record.type == child_type && family.include?(record.field_format)

      acyclic_from?(parent, child) ? parent : nil
    end

    # Members of the cycle that the stored chain of +id+ is on or reaches, each
    # once, in walk order from the first member met ([A, B] for A in A<->B,
    # [A, B] for C->A<->B, [A] for A->A). [] when the chain ends, for unknown
    # ids and after WALK_CAP hops.
    def cycle_from(id)
      current = DependencyRules.normalize_id(id)
      path = []
      position = {}
      while current
        return path[position[current]..-1] if position.key?(current)
        return [] if path.size >= WALK_CAP

        position[current] = path.size
        path << current
        current = pointer_of(current)
      end
      []
    end

    private

    def load_scope(scope, depending_complete)
      @rows.update(select_rows(scope))
      @depending_complete = depending_complete
      self
    end

    # The stored pointer for a walk hop. On an index that knows every
    # depending field, an id it does not hold has no pointer, so no fetch.
    def pointer_of(id)
      return @rows[id]&.parent_id if @rows.key?(id)
      return nil if @depending_complete

      parent_id(id)
    end

    def normalize_ids(ids)
      Array(ids).filter_map { |id| DependencyRules.normalize_id(id) }.uniq
    end

    def materialize(id)
      record = @records[id]
      return false unless record&.id

      @rows[id] = build_row(record.id, record.type, record.field_format,
                            record.read_attribute_before_type_cast('format_store'))
      true
    end

    def select_rows(scope)
      sql = scope.select(*COLUMNS).to_sql
      result = CustomField.connection_pool.with_connection { |conn| conn.select_all(sql, QUERY_NAME) }
      result.each_with_object({}) do |hash, rows|
        row = build_row(hash['id'], hash['type'], hash['field_format'], hash['format_store'])
        rows[row.id] = row
      end
    end

    def build_row(id, type, field_format, raw)
      parent = DependencyRules::DEPENDING_FORMATS.include?(field_format) ? self.class.parent_id_from_raw(raw) : nil
      Row.new(id.to_i, type, field_format, parent)
    end

    def acyclic_from?(parent, child)
      seen = Set.new
      seen << child if child
      current = parent
      WALK_CAP.times do
        return false unless seen.add?(current)

        current = pointer_of(current)
        return true unless current
      end
      false
    end

    # parent id => child ids, rebuilt after #ensure adds rows.
    def children_map
      @children_map ||= build_children_map
    end

    def build_children_map
      map = {}
      @rows.each_value do |row|
        (map[row.parent_id] ||= []) << row.id if row&.parent_id
      end
      map.each_value(&:sort!)
      map
    end
  end
end
