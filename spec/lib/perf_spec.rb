# frozen_string_literal: true

require_relative '../rails_helper'

# WP-31 (limits design 9.1 and 9.3, quality G6 and 5.7): opt-in wall-clock
# budgets, run with DCF_PERF_SPECS=1 (rails_helper excludes :perf
# otherwise). Inputs are built outside the timer; a budget is the best of
# three runs after one warm-up, with GC started before each run. Every
# measurement is printed as a DCF PERF line.
RSpec.describe 'Large-list performance budgets (WP-31)', :perf do
  fixtures :users

  let(:rules) { RedmineDependingCustomFields::DependencyRules }

  # Best of +runs+ timings in milliseconds, after one warm-up run.
  def best_ms(runs = 3)
    yield
    Array.new(runs) do
      GC.start
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
      (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000.0
    end.min
  end

  def report(text)
    RSpec.configuration.reporter.message("DCF PERF #{text}")
  end

  it 'validates a 5,000 x 25,000 mapping in under 1 s (DependencyMappingService#validate_mapping!)' do
    parents = DcfLargeList.names(5_000, prefix: 'P')
    children = DcfLargeList.names(25_000)
    vd = DcfLargeList.partition(parents, children)
    dd = DcfLargeList.first_child_defaults(vd)
    parent_labels = parents.to_h { |key| [key, key] }
    child_labels = children.to_h { |key| [key, key] }
    service = RedmineDependingCustomFields::DependencyMappingService
              .new(project: Project.new, field: IssueCustomField.new, user: User.find(1), params: {})
    expect(vd.size).to eq(5_000)
    expect(vd.values.sum(&:size)).to eq(25_000)
    expect(rules.mapping_problems(vd, dd, parent_keys: parent_labels, child_keys: child_labels)).to be_empty
    bad = vd.merge('Unknown parent' => [children.first])
    expect(rules.mapping_problems(bad, dd, parent_keys: parent_labels, child_keys: child_labels).size).to eq(1)

    elapsed = best_ms { service.send(:validate_mapping!, vd, dd, parent_labels, child_labels) }

    report(format('validate_mapping 5000 x 25000 best of 3: %.1f ms (budget 1000 ms)', elapsed))
    expect(elapsed).to be < 1_000
  end

  # Rows are inserted without validation (each S1 store is about 100 KB of
  # YAML); the timing includes fetching them, so select and extraction are
  # reported apart.
  it 'loads the FieldIndex of 50 S1 depending fields in under 50 ms (FieldIndex.load)' do
    parent = dcf_list_field(values: DcfLargeList.names(27, prefix: 'P'))
    mapping = DcfLargeList.partition(parent.possible_values, DcfLargeList.names(5_570))
    store = { 'parent_custom_field_id' => parent.id, 'value_dependencies' => mapping,
              'default_value_dependencies' => DcfLargeList.first_child_defaults(mapping) }
    rows = Array.new(50) do |i|
      { type: 'IssueCustomField', name: "S1-#{i}-#{SecureRandom.hex(3)}", field_format: 'depending_list',
        is_for_all: true }
    end
    CustomField.insert_all(rows)
    ids = CustomField.where(field_format: 'depending_list', name: rows.map { |row| row[:name] }).pluck(:id)
    yaml = CustomField.type_for_attribute('format_store').serialize(store)
    CustomField.where(id: ids).update_all(['format_store = ?', yaml])
    raw_sql = CustomField.where(id: ids).select(:id, :type, :field_format, :format_store).to_sql
    raws = CustomField.connection.select_all(raw_sql).map { |row| row['format_store'] }
    expect(ids.size).to eq(50)
    expect(raws.map(&:bytesize).min).to be > 50_000

    index = nil
    loads = dcf_count_yaml_loads { RedmineDependingCustomFields::FieldIndex.load }
    total = best_ms { index = RedmineDependingCustomFields::FieldIndex.load }
    select = best_ms { CustomField.connection.select_all(raw_sql).to_a }
    extract = best_ms { raws.each { |raw| RedmineDependingCustomFields::FieldIndex.parent_id_from_raw(raw) } }

    report(format('FieldIndex.load 50 S1 rows (%.1f MB) best of 3: %.1f ms (budget 50 ms); select %.1f ms, ' \
                  'extraction %.1f ms', raws.sum(&:bytesize) / 1_048_576.0, total, select, extract))
    expect(ids.map { |id| index.row(id).parent_id }).to all(eq(parent.id))
    expect(loads).to eq(0)
    expect(total).to be < 50
  end
end
