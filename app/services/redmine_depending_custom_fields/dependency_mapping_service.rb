module RedmineDependingCustomFields
  # Operations F + G: value dependency mapping and default value dependencies,
  # saved together in one transaction. Only depending formats with a parent are
  # eligible. dependencies_json (payload schema v1) is parsed here, after the
  # preamble authorized the user, so every bad input is an audited 422; without
  # that key the deprecated nested params are read. Strict validation with all
  # offenders in the audit summary; the row holds the compact delta v2
  # (DependencyDelta). Only this field is written. See Operations Spec §F/§G.
  class DependencyMappingService < BaseService
    LEGACY_WARNING = '[DCF] update_dependencies received legacy nested params; send dependencies_json ' \
                     '(deprecated in 0.1.0, removable no earlier than 0.2.0)'.freeze
    OFFENDER_SAMPLES = 5
    OFFENDER_CHARS = 40
    SUMMARY_CHARS = 1_000
    ELLIPSIS = '...'.freeze

    # The ok DependencyPayload::Result of this request's parse!, for the 422
    # re-render (SP-17: no second parse); nil on the legacy path and after a
    # parser error.
    attr_reader :parsed_payload

    def audit_action
      'update_dependencies'
    end

    private

    def dependency_op?
      true
    end

    def perform!
      parent = DependencyRules.parent_of(field)
      raise OperationError.new(:error_invalid_dependency) unless parent
      raise OperationError.new(:error_field_not_found, http_status: :not_found) unless FieldRelevance.relevant?(parent, project)

      input = read_input!
      parent_labels = labels(parent)
      child_labels = labels(field)
      vd = Sanitizer.sanitize_dependencies(input[:value_dependencies])
      dd = Sanitizer.sanitize_default_dependencies(input[:default_value_dependencies])
      dd = shape_defaults!(dd) if input[:json]
      validate_mapping!(vd, dd, parent_labels, child_labels)

      delta = DependencyDelta.new(old_vd: field.value_dependencies, old_dd: field.default_value_dependencies,
                                  new_vd: vd, new_dd: dd, parent_labels: parent_labels, child_labels: child_labels,
                                  source: input[:source], import: input[:import])
      field.value_dependencies = vd
      field.default_value_dependencies = dd
      field.save!

      Outcome.new(before: delta.before, after: delta.after, summary: delta.summary,
                  affected_projects_count: affected_projects_count)
    end

    # The JSON path whenever the key was posted (blank or not a String
    # included); the only parse of the request.
    def read_input!
      return legacy_input unless @params.key?(:dependencies_json)

      begin
        @parsed_payload = DependencyPayload.parse!(@params[:dependencies_json])
      rescue DependencyPayload::Invalid => e
        reject_payload!(e)
      end
      { json: true, value_dependencies: @parsed_payload.value_dependencies,
        default_value_dependencies: @parsed_payload.default_value_dependencies,
        source: @parsed_payload.source, import: @parsed_payload.import }
    end

    # The summary is the Invalid message (code and size, never content); the
    # flash values are integers only.
    def reject_payload!(error)
      key = error.reason == :too_large ? :error_dcf_dependencies_too_large_to_send : :error_invalid_dependency_payload
      raise OperationError.new(key, summary: error.message,
                                    interpolations: { size: StorageLimits.delimited(error.bytes),
                                                      limit: StorageLimits.delimited(DependencyPayload::MAX_BYTES) }),
            cause: nil
    end

    # Deprecated in 0.1.0, accepted throughout 0.1.x: nothing posted clears,
    # defaults are stored as submitted. The log line holds no parameter.
    def legacy_input
      Rails.logger.warn(LEGACY_WARNING)
      { json: false, value_dependencies: @params[:value_dependencies],
        default_value_dependencies: @params[:default_value_dependencies], source: 'form', import: nil }
    end

    # Ordered {key => label} of every value, inactive enumerations included.
    def labels(cf)
      DependencyRules.value_options(cf).each_with_object({}) { |(key, label, _active), out| out[key] = label }
    end

    # JSON path only: a list for a multiple field, one value otherwise; more
    # than one value on a single-value field is an offender.
    def shape_defaults!(dd)
      @several_defaults = []
      dd.each_with_object({}) do |(key, value), out|
        values = Array(value)
        if field.multiple?
          out[key] = values
        elsif values.size == 1
          out[key] = values.first
        else
          @several_defaults << key
          out[key] = values
        end
      end
    end

    # Set lookups through DependencyRules.mapping_problems (key Arrays or the
    # label Hashes); every offender is collected into one error.
    def validate_mapping!(vd, dd, parent_keys, child_keys)
      problems = DependencyRules.mapping_problems(vd, dd, parent_keys: parent_keys, child_keys: child_keys)
      several = Array(@several_defaults)
      return if problems.empty? && several.empty?

      raise OperationError.new(:error_invalid_dependency,
                               summary: offender_summary(problems, several, parent_keys, child_keys))
    end

    # 'unknown parent keys: N [first 5]; ...' for the groups with offenders;
    # keys and labels of this field and its parent only, never resolved
    # elsewhere. An unknown default counts as an unknown child value.
    # Offenders are counted by key (labels need not be unique); only the
    # shown ones are labelled.
    def offender_summary(problems, several, parent_keys, child_keys)
      by_type = problems.group_by(&:type)
      unknown_children = Array(by_type[:unknown_child_value]) + Array(by_type[:unknown_default])
      unlinked = Array(by_type[:default_not_linked]).map { |problem| [problem.parent_key, problem.child_key] }
      pair_label = ->(pair) { [label_of(parent_keys, pair.first), label_of(child_keys, pair.last)] }
      groups = [
        ['unknown parent keys', Array(by_type[:unknown_parent_key]).map(&:parent_key), nil],
        ['unknown child values', unknown_children.map(&:child_key), nil],
        ['defaults not linked', unlinked, pair_label],
        ['several defaults on a single-value field', several, ->(key) { label_of(parent_keys, key) }]
      ]
      text = groups.filter_map do |name, keys, label|
        keys = keys.uniq
        next if keys.empty?

        shown = keys.first(OFFENDER_SAMPLES).map { |key| offender(label ? label.call(key) : key) }
        "#{name}: #{keys.size} [#{shown.join(', ')}]"
      end.join('; ')
      text.length > SUMMARY_CHARS ? "#{text[0, SUMMARY_CHARS - ELLIPSIS.length]}#{ELLIPSIS}" : text
    end

    def label_of(keys, key)
      keys.is_a?(Hash) ? keys.fetch(key, key) : key
    end

    # One offender cut at OFFENDER_CHARS; a [parent, child] pair as 'P / C'.
    def offender(value)
      return value.map { |part| offender(part) }.join(' / ') if value.is_a?(Array)

      text = AuditPayload.text(value)
      text.length > OFFENDER_CHARS ? "#{text[0, OFFENDER_CHARS - ELLIPSIS.length]}#{ELLIPSIS}" : text
    end
  end
end
