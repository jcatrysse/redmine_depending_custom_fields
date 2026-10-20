# frozen_string_literal: true

require 'set'

module RedmineDependingCustomFields
  # The topology of the custom fields of one context-menu selection (server
  # design 7.2, WP-15). Candidates are the union of the selected objects'
  # available custom fields; children are the depending candidates with an
  # effective parent (FieldIndex#effective_parent_id_for), so dangling,
  # wrong-type, wrong-family and self parents, stored cycle members and
  # fields below a cycle are no children (UD-08, UD-35).
  #
  # One instance serves one request. Pointers are read from the raw
  # format_store of the loaded candidates (no deserialization); parents and
  # ancestors outside the selection are fetched level by level in one raw
  # select per level. Uses only available_custom_fields and the CustomField
  # API, so other customized objects work too (SD-03).
  class SelectionGraph
    def initialize(issues)
      @issues = Array(issues).compact
    end

    # Union of available_custom_fields, first instance per id: no query once
    # core loaded them (editable_custom_fields in the context menu).
    def candidate_fields
      @candidate_fields ||= DependencyRules.lookup_records(@issues).values
    end

    def index
      @index ||= FieldIndex.new(records: by_id)
    end

    def children
      @children ||= begin
        deps = candidate_fields.select { |cf| DependencyRules.depending?(cf) }
        prefetch_chains(deps.map { |cf| index.parent_id(cf.id) })
        deps.select { |cf| index.effective_parent_id_for(cf.id, cf.type, cf.field_format, index.parent_id(cf.id)) }
      end
    end

    def child_ids
      @child_ids ||= Set.new(children.map(&:id))
    end

    # The effective parents of the children; a parent outside the selection
    # is included, but field(id) is nil for it.
    def parent_ids
      @parent_ids ||= Set.new(children.map { |cf| index.parent_id(cf.id) })
    end

    def hidden_field_ids
      child_ids | parent_ids
    end

    def root_parent_ids
      parent_ids - child_ids
    end

    def children_of(parent_id)
      children.select { |cf| index.parent_id(cf.id) == parent_id }.sort_by { |cf| [cf.position || 0, cf.id] }
    end

    def field(id)
      by_id[id]
    end

    # True when the graph was built for the objects with the ids of +objects+.
    def built_for?(objects)
      Set.new(@issues.map(&:id)) == Set.new(Array(objects).compact.map(&:id))
    end

    private

    def by_id
      @by_id ||= candidate_fields.index_by(&:id)
    end

    # Makes the stored chains above +ids+ known, one level per FieldIndex#ensure
    # (rows of loaded candidates cost nothing), so effective_parent_id_for
    # walks without a query per child. Stops on a known id and after
    # WALK_CAP levels.
    def prefetch_chains(ids)
      seen = Set.new
      level = ids.compact.uniq
      FieldIndex::WALK_CAP.times do
        level = level.select { |id| seen.add?(id) }
        break if level.empty?

        index.ensure(level)
        level = level.filter_map { |id| index.parent_id(id) }.uniq
      end
    end
  end
end
