# frozen_string_literal: true

require_relative 'dependency_rules'
require_relative 'client_data'

module RedmineDependingCustomFields
  # The methods DependingListFormat and DependingEnumerationFormat share
  # (server design section 5). Included, not prepended, so super reaches the
  # core list and enumeration formats; the class bodies keep add,
  # form_partial, label and query_filter_values.
  #
  # Format objects are process-wide singletons: nothing here assigns instance
  # variables. Lookups are cached only on CustomField records, through
  # CustomFieldPatch#dcf_memo (DependencyRules).
  module DependingFormatMethods
    def self.included(base)
      base.field_attributes :parent_custom_field_id, :value_dependencies, :default_value_dependencies, :hide_when_disabled
    end

    # The format_store pairs before_save assigns, in order: the parent id when
    # one is given (a String id becomes the Integer id, an id that names no
    # field of the same type and family becomes nil), then both mappings,
    # sanitized. Never prunes (BC-02).
    def normalized_store_pairs(custom_field)
      pairs = []
      if custom_field.parent_custom_field_id.present?
        pairs << ['parent_custom_field_id', DependencyRules.resolve_parent_for_save(custom_field)&.id]
      end
      pairs << ['value_dependencies', Sanitizer.sanitize_dependencies(custom_field.value_dependencies)]
      pairs << ['default_value_dependencies', Sanitizer.sanitize_default_dependencies(custom_field.default_value_dependencies)]
      pairs
    end

    # The format_store a save of +custom_field+ writes, as a new Hash whose
    # YAML equals the stored bytes (limits V4). +store+ is converted as the
    # store coder does; neither it nor the record is changed.
    def storage_preview(custom_field, store)
      preview = ActiveRecord::Store::IndifferentCoder.as_indifferent_hash(store).to_hash
      normalized_store_pairs(custom_field).each { |key, value| preview[key] = value }
      preview
    end

    # Clears the core default value when a given parent resolves.
    def before_custom_field_save(custom_field)
      super
      pairs = normalized_store_pairs(custom_field)
      pairs.each { |key, value| custom_field.public_send("#{key}=", value) }
      parent = pairs.assoc('parent_custom_field_id')
      custom_field.default_value = nil if parent && parent.last
    end

    # nil (new and edit forms, admin views) and an Array of objects (bulk
    # edit) give the full core list, and so does one object without a parent
    # state: no effective parent (WP-10), or an object the field does not
    # belong to, such as the Project core menus and query filters pass for an
    # issue field (WP-15; they read only label and value). Otherwise every
    # option is kept and the ones its parent value does not allow are hidden,
    # so a stored legacy value stays visible. Core 5.1 to 7.0 never pass an
    # Issue, a TimeEntry or another record here (the formats override
    # possible_custom_value_options and value_from_keyword); the record branch
    # is kept, as in 0.0.15, for callers of CustomField#possible_values_options
    # with a record (other plugins, scripts).
    def possible_values_options(custom_field, object = nil)
      single = object.is_a?(Array) ? object.first : object
      base = super(custom_field, single)
      return base if object.nil? || object.is_a?(Array)

      state = DependencyRules.parent_state(custom_field, object)
      return base unless state

      allowed = DependencyRules.allowed_for(custom_field, state)
      base.map do |opt|
        label, value = opt.is_a?(Array) ? opt.take(2) : [opt, opt]
        if value.blank? || allowed.include?(value.to_s)
          [label, value]
        else
          [label, value, { hidden: true, style: 'display:none;' }]
        end
      end
    end

    # Drops blank values first (kept: the value is assigned back). Without a
    # parent state (no effective parent: none, dangling, in or below a stored
    # cycle, WP-10) only core validates. With one,
    # DependencyRules.dependency_check applies D1 per value: while
    # the parent is unchanged the stored values (for a copy, the source's)
    # are kept and only new values must be allowed. When the parent value
    # allows nothing, a blank or rejected value skips the core check; values
    # the rule keeps still get it (core inclusion stays for copies).
    # Otherwise the core errors come first, plus one 'is invalid' not already
    # among them. WP-38: the D1 error of a time entry value the user cannot
    # see is left to NonEditableDependencies (judged_by_record?), which never
    # names it; only core 5.1 and 6.0 validate such a value here.
    def validate_custom_value(custom_value)
      cf = custom_value.custom_field
      sanitized = DependencyRules.normalize_values(custom_value.value)
      custom_value.value = cf.multiple? ? sanitized : sanitized.first

      state = DependencyRules.parent_state(cf, custom_value.customized)
      return super unless state

      allowed_empty, dep_errors = DependencyRules.dependency_check(custom_value, state)
      skip_core = allowed_empty && (sanitized.empty? || dep_errors.any?)
      dep_errors = [] if dep_errors.any? && NonEditableDependencies.judged_by_record?(custom_value)
      return dep_errors if skip_core

      errors = super
      errors + (dep_errors - errors)
    end

    # The core checks, then the parent check (WP-10): a persisted field whose
    # parent id changes may not name itself or one of its dependent fields.
    # Core adds each pair to the record's errors, so the plugin API, the
    # admin form and the services all refuse such a save.
    def validate_custom_field(custom_field)
      super + DependencyRules.parent_errors(custom_field)
    end

    # Matches labels of the full list, hidden values included: import and
    # email set the child before the parent. Case-insensitive (Unicode case
    # folding, as casecmp?), the first label wins. A multiple keyword is
    # split on ';' first, then each part is matched longest label first, as
    # core parse_keyword does with ',' (a label may contain a comma). The
    # label index is built once per record (dcf_memo, rules-3 of the full
    # review); an enumeration keyword is looked up with one query first, so
    # an import row does not load every enumeration.
    def value_from_keyword(custom_field, keyword, customized = nil, **_options)
      return if keyword.blank?
      return dcf_keyword_value(custom_field, keyword.strip) unless custom_field.multiple?

      keyword.split(';').flat_map { |part| dcf_longest_matches(custom_field, part) }.presence
    end

    # WP-16: core's tag plus the data-dcf-* attributes of ClientData (server
    # design 2.2) on the select or the check box group; the caller's options
    # are not changed. Without data (ClientData failed or the field has
    # none), core gets the caller's options as they are. WP-19: before a
    # managed single radio group (or a required select without a '' option)
    # an id-less hidden input with the same name posts '' first; a checked
    # radio or selected option comes later and wins (last-wins parsing).
    # WP-39 (R1): after core's markup, the mapping script the control names.
    def edit_tag(view, tag_id, tag_name, custom_value, options = {})
      cf = custom_value.custom_field
      data, json = ClientData.field_data(cf, context: :form, customized: custom_value.customized,
                                             custom_value: custom_value, tag_name: tag_name, tag_id: tag_id)
      html = super(view, tag_id, tag_name, custom_value, ClientData.merge_options(options, data))
      html = view.hidden_field_tag(tag_name, '', id: nil, data: { dcf_blank: 1 }) + html if dcf_sentinel?(cf, data, tag_name)
      dcf_with_map(view, html, data, json)
    end

    # Bulk edit, time-entry bulk edit and the context-menu wizard: core's
    # select plus the bulk attributes for the selected +objects+, then the
    # mapping script (WP-39).
    def bulk_edit_tag(view, tag_id, tag_name, custom_field, objects, value, options = {})
      data, json = ClientData.field_data(custom_field, context: :bulk, objects: objects, tag_name: tag_name,
                                                       tag_id: tag_id)
      html = super(view, tag_id, tag_name, custom_field, objects, value, ClientData.merge_options(options, data))
      dcf_with_map(view, html, data, json)
    end

    private

    def dcf_sentinel?(cf, data, tag_name)
      ClientData.sentinel?(cf, data) && !tag_name.to_s.end_with?('[]')
    end

    # WP-39 (R1): +html+ followed by the <script type="application/json">
    # whose data-dcf-map-id the control names in data-dcf-map-ref; its text
    # is the JSON of ClientData.field_data, already escaped for a script
    # context (no <, >, & U+2028 or U+2029), so it is written as it is. A
    # data block: never executed, not rendered. No id attribute: core's
    # custom_field_tag_with_label takes label for= from the only ' id="' of
    # the tag. Without JSON, +html+ unchanged.
    def dcf_with_map(view, html, data, json)
      return html unless json && data[:dcf_map_ref]

      html + view.content_tag(:script, json.html_safe, type: 'application/json', data: { dcf_map_id: data[:dcf_map_ref] })
    end

    # The label index of value_from_keyword: folded label => value, first
    # label kept. Memoized on the record.
    def dcf_keyword_index(custom_field)
      custom_field.dcf_memo(:dcf_keyword_index, nil) do
        possible_values_options(custom_field).each_with_object({}) do |opt, index|
          label, value = opt.is_a?(Array) ? opt.take(2) : [opt, opt]
          key = label.to_s.strip.downcase(:fold)
          index[key] = value unless index.key?(key)
        end
      end
    end

    # The value of one stripped keyword, or nil. An enumeration keyword is
    # first looked up among the active names that equal it in SQL (LOWER and
    # TRIM; a superset of the folded match on MySQL collations), checked
    # with the folding of the index, first by position; the full index is
    # built only when that finds nothing (folded forms SQL LOWER does not
    # know, such as 'STRASSE' for 'Straße'), and once built it serves every
    # later keyword of the record.
    def dcf_keyword_value(custom_field, keyword)
      return nil if keyword.blank?

      key = keyword.downcase(:fold)
      if DependencyRules.kind(custom_field) == 'enumeration' && custom_field.id &&
         !custom_field.dcf_memoized?(:dcf_keyword_index, nil) && keyword.encoding == Encoding::UTF_8 &&
         keyword.valid_encoding?
        hit = custom_field.enumerations.where(active: true).where('LOWER(TRIM(name)) = LOWER(?)', keyword)
                          .reorder(:position, :id).pluck(:id, :name)
                          .detect { |_id, name| name.to_s.strip.downcase(:fold) == key }
        return hit.first.to_s if hit
      end
      dcf_keyword_index(custom_field)[key]
    end

    # The values of one ';' part, as core parse_keyword reads a ',' list:
    # the longest run of segments that names a label wins, an unknown first
    # segment is skipped.
    def dcf_longest_matches(custom_field, part)
      segments = part.split(',', -1)
      out = []
      start = 0
      while start < segments.size
        stop = segments.size
        found = nil
        while stop > start
          found = dcf_keyword_value(custom_field, segments[start...stop].join(',').strip)
          break if found

          stop -= 1
        end
        if found
          out << found
          start = stop
        else
          start += 1
        end
      end
      out
    end
  end
end
