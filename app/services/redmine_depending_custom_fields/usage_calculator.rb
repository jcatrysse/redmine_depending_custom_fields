module RedmineDependingCustomFields
  # Computes how a value is used: CustomValue counts (this project / other
  # projects) and dependency reference counts on BOTH sides — own-side (this
  # field as child) and parent-side (this field's value used as a parent key in
  # depending children). See Feasibility §5 and Functional §8.
  module UsageCalculator
    # Past this many CustomValue rows we stop counting and report "too large"
    # rather than running an unbounded scan (Functional §7 / UI §4).
    USAGE_CAP = 50_000

    # Exact usage of one value on the values page (page_usage).
    PageUsage = Struct.new(:here, :other, :refs, keyword_init: true)

    module_function

    # value_key is the stored CustomValue.value: the option string for list
    # families, the enumeration id (string) for enum families.
    def usage_total(field, value_key)
      value_rows(field, value_key).limit(USAGE_CAP + 1).count
    end

    def usage_here(field, value_key, project)
      scope_to_project(field, value_rows(field, value_key), project).limit(USAGE_CAP + 1).count
    end

    def usage_other(field, value_key, project)
      usage_split(field, value_key, project).last
    end

    # [usage_here, usage_other] with one count each (full review of
    # 2026-11-05, project-pages-9: usage_other used to count here again).
    def usage_split(field, value_key, project)
      here = usage_here(field, value_key, project)
      [here, [usage_total(field, value_key) - here, 0].max]
    end

    def capped?(count)
      count > USAGE_CAP
    end

    def scope_to_project(field, base, project)
      if field.is_a?(ProjectCustomField)
        base.where(customized_type: 'Project', customized_id: project.id)
      else
        base.where(customized_type: 'Issue',
                   customized_id: Issue.where(project_id: project.id).select(:id))
      end
    end

    # Own-side: how many times this child field's own value appears as an
    # allowed child value in its own mapping. Only depending formats have one.
    def own_dep_refs(field, child_value)
      return 0 unless FieldRelevance.depending_format?(field)

      cv = child_value.to_s
      count = 0
      (field.value_dependencies || {}).each_value do |vals|
        count += Array(vals).map(&:to_s).count(cv)
      end
      (field.default_value_dependencies || {}).each_value do |v|
        count += Array(v).map(&:to_s).count(cv)
      end
      count
    end

    # Parent-side: how many depending children reference this value as a parent
    # key in value_dependencies and/or default_value_dependencies. +children+
    # (FieldRelevance.children_of(field)) when the caller loaded them.
    def parent_key_refs(field, parent_value, children: nil)
      pv = parent_value.to_s
      (children || FieldRelevance.children_of(field)).sum do |child|
        refs = 0
        refs += 1 if (child.value_dependencies || {}).key?(pv)
        refs += 1 if (child.default_value_dependencies || {}).key?(pv)
        refs
      end
    end

    def affected_child_fields(field, parent_value, children: nil)
      pv = parent_value.to_s
      (children || FieldRelevance.children_of(field)).select do |child|
        (child.value_dependencies || {}).key?(pv) ||
          (child.default_value_dependencies || {}).key?(pv)
      end
    end

    # Exact usage of the keys of one values page (project design 5): two
    # grouped CustomValue counts (all, and scoped to the project like
    # usage_here), own references from the field's stores in memory and
    # parent references from the children the FieldIndex lists, loaded in one
    # query. Equals usage_here, usage_other and own_dep_refs plus
    # parent_key_refs per key, without USAGE_CAP; byte-exact on PostgreSQL,
    # SQLite, MySQL and MariaDB, like the per-value methods (SD-17).
    # {key => PageUsage}.
    def page_usage(field, keys, project, index: FieldIndex.load)
      keys = keys.map(&:to_s).uniq
      return {} if keys.empty?

      base = value_rows(field, keys)
      totals = grouped_value_counts(base)
      here = grouped_value_counts(scope_to_project(field, base, project))
      refs = own_refs_by_key(field, keys)
      DependencyRules.children_of(field, index: index).each do |child|
        vd = child.value_dependencies || {}
        dd = child.default_value_dependencies || {}
        keys.each do |key|
          refs[key] += 1 if vd.key?(key)
          refs[key] += 1 if dd.key?(key)
        end
      end
      keys.each_with_object({}) do |key, out|
        count = here.fetch(key, 0)
        out[key] = PageUsage.new(here: count, other: [totals.fetch(key, 0) - count, 0].max, refs: refs[key])
      end
    end

    # The CustomValue rows of +field+ stored exactly as +values+ (one value or
    # an Array; ids become strings), the one lookup of stored values by value
    # (SD-17). MySQL and MariaDB compare TEXT with the column collation (case
    # and accents ignored, trailing spaces padded), so the bytes are compared
    # there as well; the plain predicate stays for any index on value.
    # PostgreSQL and SQLite compare exactly already.
    def value_rows(field, values)
      values = values.is_a?(Array) ? values.map(&:to_s) : values.to_s
      rows = CustomValue.where(custom_field_id: field.id, value: values)
      return rows unless Redmine::Database.mysql?

      rows.where("#{binary_value_sql} #{values.is_a?(Array) ? 'IN (?)' : '= ?'}", values)
    end

    # The UTF-8 bytes of the stored value on MySQL and MariaDB, whatever the
    # column character set; bound values arrive in the UTF-8 connection
    # encoding of database.yml.
    def binary_value_sql
      "CAST(CONVERT(#{CustomValue.table_name}.value USING utf8mb4) AS BINARY)"
    end

    # {value => count} of a CustomValue scope, byte-exact. MySQL and MariaDB
    # would put 'A' and 'a' in one group: group by the bytes there and read
    # them back as UTF-8.
    def grouped_value_counts(scope)
      return scope.group(:value).count unless Redmine::Database.mysql?

      scope.group(Arel.sql(binary_value_sql)).count.transform_keys do |key|
        key.to_s.dup.force_encoding(Encoding::UTF_8)
      end
    end

    # own_dep_refs for every key in one pass over the field's stores.
    def own_refs_by_key(field, keys)
      counts = Hash.new(0)
      return counts unless FieldRelevance.depending_format?(field)

      wanted = keys.to_h { |key| [key, true] }
      [field.value_dependencies || {}, field.default_value_dependencies || {}].each do |store|
        store.each_value do |values|
          Array(values).each do |value|
            text = value.to_s
            counts[text] += 1 if wanted.key?(text)
          end
        end
      end
      counts
    end

    # SD-16: the one naming rule of the WP-12 errors (BaseService#nameable_field?
    # delegates here) and the confirmation panel: the edited field, an
    # administrator, or a field used in the project and visible to the user.
    # Fail closed.
    def nameable_child?(child, field, project, user)
      return true if child.id == field.id || user.admin?

      FieldRelevance.in_project?(child, project) && child.visible_by?(project, user)
    rescue StandardError
      false
    end
  end
end
