# frozen_string_literal: true

module RedmineDependingCustomFields
  # Read-only query object of the project values page (project design 5,
  # UD-21): the rows of DependencyRules.value_options, the token search of
  # ValueCollation and the page. One object per request, built eagerly; not a
  # BaseService. Labels are folded only when a search filters, once each.
  class ValuesPage
    UNPAGINATED_MAX = 500 # at or below: one page, drag allowed when unfiltered
    MAX_PER_PAGE    = 500 # cap on per_page_option (Rack budget, project design 8)
    FILTER_MIN      = 25  # search box above this many values, or when q is present
    DEFAULT_PER_PAGE = 25
    QUERY_MAX = 255

    Row = Struct.new(:key, :label, :active, :index, keyword_init: true)

    attr_reader :total, :filtered_count, :query, :tokens, :paginator, :rows, :page, :per_page

    # A String q cut to QUERY_MAX characters; anything else is no query.
    def self.coerce_query(value)
      value.is_a?(String) ? ValueCollation.text(value)[0, QUERY_MAX] : nil
    end

    # An Integer or a String read like core's to_i; anything else (an Array or
    # a Hash param) is page 1. At least 1, not clamped above.
    def self.coerce_page(value)
      page = value.is_a?(Integer) || value.is_a?(String) ? value.to_i : 1
      [page, 1].max
    end

    # per_page within 1..MAX_PER_PAGE; nil or junk gives the default.
    def self.coerce_per_page(value)
      number = if value.is_a?(Integer)
                 value
               elsif value.is_a?(String) && value.strip.match?(/\A[+-]?\d+\z/)
                 value.to_i
               else
                 DEFAULT_PER_PAGE
               end
      number.clamp(1, MAX_PER_PAGE)
    end

    # Search and page to keep in redirects: q only when it filters, page only
    # above 1 (the page of the next GET clamps it).
    def self.state_for(q, page)
      state = {}
      query = coerce_query(q)
      state[:q] = query if query && !ValueCollation.tokens(query).empty?
      number = coerce_page(page)
      state[:page] = number if number > 1
      state
    end

    # The 1-based page that holds the 0-based +index+, or 1 when the list is
    # not paginated.
    def self.page_for_index(index, total, per_page)
      return 1 if total.to_i <= UNPAGINATED_MAX || !index.is_a?(Integer) || index.negative?

      index / coerce_per_page(per_page) + 1
    end

    def initialize(field, q: nil, page: nil, per_page: DEFAULT_PER_PAGE)
      @enum_family = FieldRelevance.enum_family?(field)
      @all_rows = DependencyRules.value_options(field).each_with_index.map do |(key, label, active), index|
        Row.new(key: key, label: label, active: active, index: index)
      end
      @total = @all_rows.size
      @query = self.class.coerce_query(q)
      @tokens = @query.nil? ? [] : ValueCollation.tokens(@query)
      matching = filtered? ? @all_rows.select { |row| ValueCollation.match?(ValueCollation.key(row.label), @tokens) } : @all_rows
      @filtered_count = matching.size
      paginate(matching, page, per_page)
    end

    # QA-17: a q whose key is empty is unfiltered.
    def filtered?
      !tokens.empty?
    end

    def paginated?
      total > UNPAGINATED_MAX
    end

    def sortable?
      !filtered? && !paginated? && total > 1
    end

    def batch_scope
      filtered? || paginated? ? 'page' : nil
    end

    def show_filter?
      total > FILTER_MIN || query.present?
    end

    def empty_match?
      filtered? && filtered_count.zero?
    end

    # The default-value select over every value, not the page: list values,
    # or the active enumerations as [name, id].
    def default_options
      rows = @enum_family ? @all_rows.select(&:active) : @all_rows
      rows.map { |row| [row.label, row.key] }
    end

    # The list state of this page for forms and links: q when it filters,
    # the clamped page when above 1.
    def list_state
      state = {}
      state[:q] = query if filtered?
      state[:page] = page if page > 1
      state
    end

    private

    # Unpaginated pages show every matching row. A paginated page is clamped
    # to 1..last_page (core's Paginator clamps only below 1).
    def paginate(matching, page, per_page)
      if paginated?
        @per_page = self.class.coerce_per_page(per_page)
        last_page = [(filtered_count - 1) / @per_page + 1, 1].max
        @page = self.class.coerce_page(page).clamp(1, last_page)
        @rows = matching[(@page - 1) * @per_page, @per_page] || []
      else
        @per_page = MAX_PER_PAGE
        @page = 1
        @rows = matching
      end
      @paginator = Redmine::Pagination::Paginator.new(filtered_count, @per_page, @page)
    end
  end
end
