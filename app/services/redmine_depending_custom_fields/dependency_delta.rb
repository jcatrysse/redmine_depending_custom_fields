# frozen_string_literal: true

require 'set'

module RedmineDependingCustomFields
  # Compact audit delta v2 of update_dependencies (project design 4, limits
  # design 6.3): counts, samples bounded by entries and by encoded bytes, the
  # mapping digest and the client-reported source and import (SP-12,
  # informational only). A per-call object built from plain Hashes: no
  # query, no class-level state. Labels come only from the two label Hashes
  # (this field and its parent); a key missing there is shown as it is.
  class DependencyDelta
    VERSION = 2
    CAP = 20
    LIST_MAX_BYTES = 4_000
    LABEL_MAX_BYTES = 80
    DEFAULTS_PER_PARENT_CAP = 3
    ELLIPSIS = '...'

    def initialize(old_vd:, old_dd:, new_vd:, new_dd:, parent_labels:, child_labels:, source:, import:)
      @old_vd = Sanitizer.sanitize_dependencies(old_vd)
      @old_dd = Sanitizer.sanitize_default_dependencies(old_dd)
      @new_vd = Sanitizer.sanitize_dependencies(new_vd)
      @new_dd = Sanitizer.sanitize_default_dependencies(new_dd)
      @parent_labels = parent_labels || {}
      @child_labels = child_labels || {}
      @parent_index = @parent_labels.keys.each_with_index.to_h
      @child_index = @child_labels.keys.each_with_index.to_h
      @source = source.to_s
      @import = import
      old_pairs = pairs(@old_vd)
      new_pairs = pairs(@new_vd)
      @old_links = old_pairs.size
      @added = (new_pairs - old_pairs).to_a
      @removed = (old_pairs - new_pairs).to_a
      @defaults_changed = changed_defaults
      @parents_changed = (@added.map(&:first) | @removed.map(&:first) | @defaults_changed).size
      @orphans_removed = @removed.count { |pk, ck| !@parent_labels.key?(pk) || !@child_labels.key?(ck) }
      @links = new_pairs.size
    end

    def before
      { 'v' => VERSION, 'links' => @old_links, 'defaults' => @old_dd.size,
        'mapping_sha256' => DependencyPayload.digest(@old_vd, @old_dd) }
    end

    def after
      added, added_cut = sample(first_pairs(@added), @added.size) { |pk, ck| [parent_label(pk), child_label(ck)] }
      removed, removed_cut = sample(first_pairs(@removed), @removed.size) do |pk, ck|
        [parent_label(pk), child_label(ck)]
      end
      first_defaults = @defaults_changed.min_by(CAP) { |pk| [position(@parent_index, pk), pk] }
      defaults, defaults_cut = sample(first_defaults, @defaults_changed.size) do |pk|
        [parent_label(pk), default_labels(pk)]
      end
      out = { 'v' => VERSION, 'source' => @source, 'links' => @links, 'defaults' => @new_dd.size,
              'mapping_sha256' => DependencyPayload.digest(@new_vd, @new_dd),
              'added' => @added.size, 'removed' => @removed.size, 'orphans_removed' => @orphans_removed,
              'defaults_changed' => @defaults_changed.size, 'parents_changed' => @parents_changed,
              'sample' => { 'added' => added, 'removed' => removed, 'defaults' => defaults },
              'truncated' => added_cut || removed_cut || defaults_cut }
      meta = import_meta
      out['import'] = meta if meta
      out
    end

    # English, counts and the enumerated source only.
    def summary
      "Updated dependency mapping (#{source_part}): +#{@added.size}/-#{@removed.size} links, " \
        "#{@orphans_removed} orphaned removed, #{@defaults_changed.size} default(s) changed, " \
        "#{@parents_changed} parent value(s)"
    end

    private

    def pairs(mapping)
      mapping.each_with_object(Set.new) { |(pk, values), set| values.each { |ck| set << [pk, ck] } }
    end

    # Parent keys whose sorted default list differs ('x' equals ['x']).
    def changed_defaults
      (@old_dd.keys | @new_dd.keys).reject { |pk| Array(@old_dd[pk]).uniq.sort == Array(@new_dd[pk]).uniq.sort }
    end

    def import_meta
      return nil unless @source == 'import' && @import.is_a?(Hash)

      { 'mode' => @import['mode'], 'rows' => @import['rows'] }
    end

    def source_part
      meta = import_meta
      meta ? "import, #{meta['mode']}, #{meta['rows']} rows" : @source
    end

    # The first CAP pairs in value order, unknown keys after the known ones.
    def first_pairs(pairs)
      pairs.min_by(CAP) { |pk, ck| [position(@parent_index, pk), pk, position(@child_index, ck), ck] }
    end

    # Entries for +first+ up to LIST_MAX_BYTES of JSON (a comma counted per
    # entry); [entries, true when fewer than +total+ are kept].
    def sample(first, total)
      out = []
      bytes = 2
      first.each do |item|
        entry = yield(item)
        size = ActiveSupport::JSON.encode(entry).bytesize + 1
        break if bytes + size > LIST_MAX_BYTES

        out << entry
        bytes += size
      end
      [out, out.size < total]
    end

    # The index of +key+ in the value order, or the size for an unknown key.
    def position(index, key)
      index.fetch(key, index.size)
    end

    def default_labels(pk)
      Array(@new_dd[pk]).uniq.min_by(DEFAULTS_PER_PARENT_CAP) { |ck| [position(@child_index, ck), ck] }
                        .map { |ck| child_label(ck) }
    end

    def parent_label(key)
      cut(@parent_labels.fetch(key, key))
    end

    def child_label(key)
      cut(@child_labels.fetch(key, key))
    end

    # Shortened by characters until its JSON form (ActiveSupport escaping,
    # quotes excluded) fits LABEL_MAX_BYTES, then '...' inside the budget.
    def cut(label)
      text = AuditPayload.text(label)
      return text if text.length <= LABEL_MAX_BYTES && encoded_bytes(text) <= LABEL_MAX_BYTES

      text = text[0, LABEL_MAX_BYTES]
      low = 0
      high = text.length
      while low < high
        mid = (low + high + 1) / 2
        if encoded_bytes(text[0, mid]) + ELLIPSIS.bytesize <= LABEL_MAX_BYTES
          low = mid
        else
          high = mid - 1
        end
      end
      "#{text[0, low]}#{ELLIPSIS}"
    end

    def encoded_bytes(text)
      ActiveSupport::JSON.encode(text).bytesize - 2
    end
  end
end
