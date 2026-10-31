require_relative '../rails_helper'

RSpec.describe RedmineDependingCustomFields::DependencyMappingService do
  let(:project) { dcf_create_project }
  let(:user) { dcf_admin }

  def build_pair
    parent = dcf_list_field(name: 'Parent', values: %w[A B], is_for_all: false, projects: [project])
    child = dcf_list_field(format: 'depending_list', name: 'Child', values: %w[c1 c2],
                           parent: parent, is_for_all: false, projects: [project])
    [parent, child]
  end

  def call(field, params)
    described_class.new(project: project, field: field, user: user, params: params).call
  end

  it 'saves a valid mapping and default (T-DEP-1)' do
    _parent, child = build_pair
    call(child, value_dependencies: { 'A' => ['c1'] }, default_value_dependencies: { 'A' => 'c1' })
    expect(child.reload.value_dependencies).to eq('A' => ['c1'])
    expect(child.default_value_dependencies).to eq('A' => 'c1')
  end

  it 'rejects an unknown child value (T-DEP-2)' do
    _parent, child = build_pair
    expect { call(child, value_dependencies: { 'A' => ['nope'] }) }
      .to raise_error(RedmineDependingCustomFields::OperationError) { |e| expect(e.key).to eq(:error_invalid_dependency) }
  end

  it 'rejects an unknown parent key (T-DEP-3)' do
    _parent, child = build_pair
    expect { call(child, value_dependencies: { 'ZZ' => ['c1'] }) }
      .to raise_error(RedmineDependingCustomFields::OperationError) { |e| expect(e.key).to eq(:error_invalid_dependency) }
  end

  it 'rejects a default that is not an allowed child (T-DEP-5)' do
    _parent, child = build_pair
    expect do
      call(child, value_dependencies: { 'A' => ['c1'] }, default_value_dependencies: { 'A' => 'c2' })
    end.to raise_error(RedmineDependingCustomFields::OperationError) { |e| expect(e.key).to eq(:error_invalid_dependency) }
  end

  it 'stores multiple per-parent defaults for a multiple child field (T-DEP-6)' do
    parent = dcf_list_field(name: 'Parent', values: %w[A B], is_for_all: false, projects: [project])
    child = dcf_list_field(format: 'depending_list', name: 'Child', values: %w[c1 c2],
                           parent: parent, is_for_all: false, projects: [project], multiple: true)
    call(child,
         value_dependencies: { 'A' => %w[c1 c2] },
         default_value_dependencies: { 'A' => %w[c1 c2] })
    expect(child.reload.default_value_dependencies).to eq('A' => %w[c1 c2])
  end

  it 'rejects a multiple default that is not an allowed child (T-DEP-6)' do
    parent = dcf_list_field(name: 'Parent', values: %w[A B], is_for_all: false, projects: [project])
    child = dcf_list_field(format: 'depending_list', name: 'Child', values: %w[c1 c2],
                           parent: parent, is_for_all: false, projects: [project], multiple: true)
    expect do
      call(child,
           value_dependencies: { 'A' => %w[c1] },
           default_value_dependencies: { 'A' => %w[c1 c2] })
    end.to raise_error(RedmineDependingCustomFields::OperationError) { |e| expect(e.key).to eq(:error_invalid_dependency) }
  end

  it 'rejects a standard list (no parent / not a depending format) (T-REL-9)' do
    field = dcf_list_field(format: 'list', is_for_all: false, projects: [project])
    expect { call(field, value_dependencies: {}) }
      .to raise_error(RedmineDependingCustomFields::OperationError) { |e| expect(e.key).to eq(:error_format_unsupported) }
  end

  # WP-27 (project design 3.3 and 4): dependencies_json parsed after the
  # preamble, aggregated offenders, defaults in the field's shape, the
  # compact delta v2, the deprecated nested params.
  describe 'dependencies_json and the compact delta (WP-27)' do
    let(:payload) { RedmineDependingCustomFields::DependencyPayload }
    let(:limits) { RedmineDependingCustomFields::StorageLimits }
    let(:rules) { RedmineDependingCustomFields::DependencyRules }
    let(:max_bytes) { payload::MAX_BYTES }

    def run(field, params, as_user = user)
      service = described_class.new(project: project, field: field, user: as_user, params: params)
      error = nil
      begin
        service.call
      rescue RedmineDependingCustomFields::OperationError => e
        error = e
      end
      [service, error]
    end

    def json(vd, dd = {}, extra = {})
      JSON.generate({ 'value_dependencies' => vd, 'default_value_dependencies' => dd }.merge(extra))
    end

    def rows(field)
      RedmineDependingCustomFields::ConfigAuditEvent.where(custom_field_id: field.id).order(:id)
    end

    def stored(field)
      record = CustomField.find(field.id)
      [record.value_dependencies.to_hash, record.default_value_dependencies.to_hash]
    end

    def raw_store(field)
      CustomField.connection.select_value(CustomField.where(id: field.id).select(:format_store).to_sql)
    end

    def single_pair(multiple: false)
      parent = dcf_list_field(name: "Parent-#{SecureRandom.hex(3)}", values: %w[A B], is_for_all: false,
                              projects: [project])
      child = dcf_list_field(format: 'depending_list', name: "Child-#{SecureRandom.hex(3)}", values: %w[c1 c2],
                             parent: parent, is_for_all: false, projects: [project], multiple: multiple)
      dcf_set_dependencies(child, value_dependencies: { 'A' => %w[c1] }, default_value_dependencies: { 'A' => 'c1' })
    end

    it 'saves the JSON mapping, keeps the ok Result in parsed_payload and audits the v2 delta (T-DEP-7)' do
      child = single_pair
      service, error = run(child, dependencies_json: json({ 'A' => %w[c1 c2], 'B' => %w[c2] }, { 'B' => 'c2' }))

      expect(error).to be_nil
      expect(stored(child)).to eq([{ 'A' => %w[c1 c2], 'B' => %w[c2] }, { 'B' => 'c2' }])
      expect(service.parsed_payload).to be_a(payload::Result)
      expect(service.parsed_payload).to be_ok
      row = rows(child).last
      expect([row.action, row.status]).to eq(%w[update_dependencies success])
      before = JSON.parse(row.before_value)
      after = JSON.parse(row.after_value)
      expect(before).to eq('v' => 2, 'links' => 1, 'defaults' => 1,
                           'mapping_sha256' => payload.digest({ 'A' => %w[c1] }, { 'A' => 'c1' }))
      expect(after.slice('v', 'source', 'links', 'defaults', 'added', 'removed', 'defaults_changed'))
        .to eq('v' => 2, 'source' => 'editor', 'links' => 3, 'defaults' => 1, 'added' => 2, 'removed' => 0,
               'defaults_changed' => 2)
      expect(after['mapping_sha256']).to eq(payload.stored_digest(CustomField.find(child.id)))
      expect(row.changes_summary).to eq('Updated dependency mapping (editor): +2/-0 links, 0 orphaned removed, ' \
                                        '2 default(s) changed, 2 parent value(s)')
    end

    it 'ignores a well-formed base and refuses a malformed one (invalid_base)' do
      child = single_pair
      _service, error = run(child, dependencies_json: json({ 'B' => %w[c1] }, {}, 'base' => '0' * 64))
      expect(error).to be_nil
      expect(stored(child)).to eq([{ 'B' => %w[c1] }, {}])
      expect(CustomField.find(child.id).format_store.keys & %w[base source import version]).to eq([])

      service, error = run(child, dependencies_json: json({ 'A' => %w[c1] }, {}, 'base' => 'xyz'))
      expect(error.key).to eq(:error_invalid_dependency_payload)
      expect(service.parsed_payload).to be_nil
      expect(stored(child)).to eq([{ 'B' => %w[c1] }, {}])
    end

    # T-DEP-8, WP-21 open input: every parser code is an audited 422 with
    # the reason and the size; the payload never reaches the row.
    {
      not_a_string: { 'x' => '1' },
      blank: '',
      invalid_json: '{',
      not_an_object: '[]',
      unknown_key: '{"meta":{}}',
      unsupported_version: '{"version":2}',
      invalid_source: '{"source":"admin"}',
      invalid_base: '{"base":"xyz"}',
      invalid_import: '{"source":"editor","import":{"mode":"merge","rows":1}}',
      invalid_links: '{"value_dependencies":{"A":[-1]}}',
      invalid_defaults: '{"default_value_dependencies":{"A":[true]}}',
      number_too_long: '{"value_dependencies":{"A":[12345678901234567890]}}',
      too_large: :oversize
    }.each do |code, sample|
      it "refuses #{code} with an audited 422, the reason and the size, and leaves the mapping (T-DEP-8)" do
        child = single_pair
        raw = sample == :oversize ? 'x' * (max_bytes + 1) : sample
        bytes = raw.is_a?(String) ? raw.bytesize : 0
        raw_before = raw_store(child)

        service, error = run(child, dependencies_json: raw)

        key = code == :too_large ? :error_dcf_dependencies_too_large_to_send : :error_invalid_dependency_payload
        expect([error.key, error.http_status]).to eq([key, :unprocessable_entity])
        expect(error.summary).to eq("dependencies_json rejected: #{code} (#{bytes} bytes)")
        if code == :too_large
          expect(error.interpolations).to eq(size: limits.delimited(max_bytes + 1), limit: limits.delimited(max_bytes))
        end
        expect(service.parsed_payload).to be_nil
        expect(raw_store(child)).to eq(raw_before)
        row = rows(child).last
        expect([row.action, row.status, row.error_message]).to eq(['validation_failed', 'validation_failed', key.to_s])
        expect(row.changes_summary).to eq("dependencies_json rejected: #{code} (#{bytes} bytes)")
        expect([row.before_value, row.after_value]).to eq([nil, nil])
      end
    end

    it 'treats nil and JSON white space as blank, NUL and U+00A0 as unreadable' do
      child = single_pair
      { nil => 'blank (0 bytes)', " \t\r\n" => 'blank (4 bytes)', "\u0000" => 'invalid_json (1 bytes)',
        " " => 'invalid_json (2 bytes)' }.each do |raw, reason|
        _service, error = run(child, dependencies_json: raw)
        expect(error.summary).to eq("dependencies_json rejected: #{reason}"), raw.inspect
      end
      expect(stored(child)).to eq([{ 'A' => %w[c1] }, { 'A' => 'c1' }])
    end

    it 'aggregates every offender in one validation_failed row, the flash key stays generic (T-DEP-10)' do
      child = single_pair
      raw = json({ 'ZZ' => %w[c1], 'YY' => %w[c1], 'A' => %w[c1 c2 nope] }, { 'B' => 'c2', 'A' => %w[c1 c2] })

      service, error = run(child, dependencies_json: raw)

      expect([error.key, error.interpolations]).to eq([:error_invalid_dependency, {}])
      summary = 'unknown parent keys: 2 [ZZ, YY]; unknown child values: 1 [nope]; defaults not linked: 1 [B / c2]; ' \
                'several defaults on a single-value field: 1 [A]'
      expect(error.summary).to eq(summary)
      expect(service.parsed_payload).to be_ok
      expect(rows(child).last.changes_summary).to eq(summary)
      expect(rows(child).where(status: 'validation_failed').count).to eq(1)
      expect(stored(child)).to eq([{ 'A' => %w[c1] }, { 'A' => 'c1' }])
    end

    it 'shows at most 5 offenders per group, each cut at 40 characters, the summary at most 1,000 characters' do
      child = single_pair
      keys = (1..7).map { |i| "#{i}#{"é" * 59}" }
      _service, error = run(child, dependencies_json: json(keys.to_h { |k| [k, %w[c1]] }))

      expect(error.summary).to start_with('unknown parent keys: 7 [')
      items = error.summary[/\[(.*)\]/, 1].split(', ')
      expect(items.size).to eq(5)
      expect(items).to all(satisfy { |item| item.length == 40 && item.end_with?('...') })
      expect(error.summary).to be_valid_encoding
    end

    it 'cuts the offender summary at 1,000 characters' do
      long = ->(prefix) { (1..7).map { |i| "#{prefix}#{i}#{'x' * 60}" } }
      parent = dcf_list_field(name: "Long parent-#{SecureRandom.hex(3)}", values: long.call('p'), is_for_all: false,
                              projects: [project])
      child = dcf_list_field(format: 'depending_list', name: "Long child-#{SecureRandom.hex(3)}", values: long.call('c'),
                             parent: parent, is_for_all: false, projects: [project])
      vd = long.call('P').to_h { |k| [k, [long.call('c').first]] }
      vd[long.call('p').first] = long.call('C')
      dd = long.call('p').to_h { |k| [k, long.call('c').last(2)] }

      _service, error = run(child, dependencies_json: json(vd, dd))

      expect(error.summary.length).to be <= 1_000
      expect(error.summary.length).to be > 900
      expect(error.summary).to start_with('unknown parent keys: 7 [')
      expect(error.summary).to include('; unknown child values: 7 [', '; defaults not linked: 14 [')
      expect(error.summary).to end_with('...')
    end

    it 'counts an unknown default as an unknown child value' do
      child = single_pair
      _service, error = run(child, dependencies_json: json({ 'A' => %w[c1] }, { 'A' => 'zz' }))
      expect(error.summary).to eq('unknown child values: 1 [zz]')

      # one offender under two parents and as a default counts once
      _service, error = run(child, dependencies_json: json({ 'A' => %w[zz], 'B' => %w[zz] }, { 'A' => 'zz' }))
      expect(error.summary).to eq('unknown child values: 1 [zz]')
    end

    it 'names enumeration offenders by the labels of this field and its parent, never by id' do
      parent = dcf_enum_field(names: %w[North South], is_for_all: true)
      child = dcf_enum_field(format: 'depending_enumeration', names: %w[Alpha Beta], parent: parent)
      north, south = parent.enumerations.order(:position).map { |e| e.id.to_s }
      alpha, beta = child.enumerations.order(:position).map { |e| e.id.to_s }

      _service, error = run(CustomField.find(child.id),
                            dependencies_json: json({ north => [alpha, beta] }, { north => [alpha, beta], south => beta }))

      expect(error.summary)
        .to eq('defaults not linked: 1 [South / Beta]; several defaults on a single-value field: 1 [North]')
      # no enumeration id in the offender lists
      expect(error.summary.scan(/\[([^\]]*)\]/).join(' ')).not_to match(/\d/)
    end

    it 'counts distinct offenders by key when two enumeration entries share a label' do
      # All fields first: Project#all_issue_custom_fields is memoized on project.
      parent = dcf_enum_field(names: %w[North], is_for_all: true)
      multiple = dcf_enum_field(format: 'depending_enumeration', names: %w[Old Old], parent: parent)
      multiple.update!(multiple: true)
      twins = dcf_enum_field(names: %w[Twin Twin], is_for_all: true)
      single = dcf_enum_field(format: 'depending_enumeration', names: %w[Alpha Beta], parent: twins)
      north = parent.enumerations.first.id.to_s
      old_one, old_two = multiple.enumerations.order(:position).map { |e| e.id.to_s }

      _service, error = run(CustomField.find(multiple.id), dependencies_json: json({}, { north => [old_one, old_two] }))
      expect(error.summary).to eq('defaults not linked: 2 [North / Old, North / Old]')

      first, second = twins.enumerations.order(:position).map { |e| e.id.to_s }
      alpha, beta = single.enumerations.order(:position).map { |e| e.id.to_s }
      links = { first => [alpha, beta], second => [alpha, beta] }

      _service, error = run(CustomField.find(single.id), dependencies_json: json(links, links))
      expect(error.summary).to eq('several defaults on a single-value field: 2 [Twin, Twin]')
    end

    it 'accepts and keeps links of inactive enumerations (T-DEP-11)' do
      parent = dcf_enum_field(names: %w[North South], is_for_all: true)
      child = dcf_enum_field(format: 'depending_enumeration', names: %w[Alpha Retired], parent: parent)
      north, south = parent.enumerations.order(:position).map { |e| e.id.to_s }
      alpha, retired = child.enumerations.order(:position).map { |e| e.id.to_s }
      CustomFieldEnumeration.where(id: [south, retired]).update_all(active: false)

      _service, error = run(CustomField.find(child.id),
                            dependencies_json: json({ south => [retired], north => [alpha, retired] }, { south => retired }))

      expect(error).to be_nil
      expect(stored(child)).to eq([{ south => [retired], north => [alpha, retired] }, { south => retired }])
    end

    it 'maps a storage refusal to error_dcf_mapping_too_large and keeps parsed_payload (T-DEP-12)' do
      child = single_pair
      bytes = raw_store(child).bytesize
      allow(limits).to receive(:column_limit).and_return(nil)
      allow(limits).to receive(:column_limit).with('format_store').and_return(bytes)
      raw_before = raw_store(child)

      service, error = run(child, dependencies_json: json({ 'A' => %w[c1 c2], 'B' => %w[c1 c2] }))

      expect(error.key).to eq(:error_dcf_mapping_too_large)
      expect(service.parsed_payload).to be_ok
      expect(raw_store(child)).to eq(raw_before)
      expect(rows(child).last.error_message).to eq('error_dcf_mapping_too_large')
    end

    it 'shapes defaults by multiple on the JSON path only (T-DEP-13)' do
      # Both pairs first: Project#all_issue_custom_fields is memoized on project.
      single = single_pair
      multiple = single_pair(multiple: true)
      run(single, dependencies_json: json({ 'A' => %w[c1 c2] }, { 'A' => ['c2'] }))
      expect(stored(single)).to eq([{ 'A' => %w[c1 c2] }, { 'A' => 'c2' }])
      run(single, dependencies_json: json({ 'A' => %w[c1 c2] }, { 'A' => [] }))
      expect(stored(single)).to eq([{ 'A' => %w[c1 c2] }, {}])
      _service, error = run(single, dependencies_json: json({ 'A' => %w[c1 c2] }, { 'A' => %w[c1 c2] }))
      expect(error.summary).to eq('several defaults on a single-value field: 1 [A]')
      expect(stored(single)).to eq([{ 'A' => %w[c1 c2] }, {}])

      run(multiple, dependencies_json: json({ 'A' => %w[c1 c2] }, { 'A' => 'c1' }))
      expect(stored(multiple)).to eq([{ 'A' => %w[c1 c2] }, { 'A' => ['c1'] }])

      # legacy nested params keep the submitted shape (characterized)
      run(single, value_dependencies: { 'A' => %w[c1] }, default_value_dependencies: { 'A' => ['c1'] })
      expect(stored(single)).to eq([{ 'A' => %w[c1] }, { 'A' => ['c1'] }])
    end

    it 'reads the deprecated nested params without the key, logs one constant warning and audits source form' do
      child = single_pair
      allow(Rails.logger).to receive(:warn).and_call_original
      allow(payload).to receive(:parse).and_call_original

      service, error = run(child, value_dependencies: { 'B' => ['c2'] }, default_value_dependencies: { 'B' => 'c2' })

      expect(error).to be_nil
      expect(service.parsed_payload).to be_nil
      expect(payload).not_to have_received(:parse)
      expect(stored(child)).to eq([{ 'B' => %w[c2] }, { 'B' => 'c2' }])
      expect(Rails.logger).to have_received(:warn).with(/deprecated in 0\.1\.0, removable no earlier than 0\.2\.0/).once
      expect(Rails.logger).not_to have_received(:warn).with(/c2/)
      expect(JSON.parse(rows(child).last.after_value)['source']).to eq('form')

      run(child, {})
      expect(stored(child)).to eq([{}, {}])
    end

    it 'prefers dependencies_json over nested params and logs no deprecation then' do
      child = single_pair
      allow(Rails.logger).to receive(:warn).and_call_original

      run(child, dependencies_json: json({ 'B' => %w[c2] }), value_dependencies: { 'A' => %w[c1 c2] })

      expect(stored(child)).to eq([{ 'B' => %w[c2] }, {}])
      expect(Rails.logger).not_to have_received(:warn).with(/deprecated/)
    end

    it 'never runs the admin transport or prune_mapping and asks no confirmation on a global field (UD-23, BC-02)' do
      parent = dcf_list_field(name: 'Global parent', values: %w[A B], is_for_all: true)
      child = dcf_list_field(format: 'depending_list', name: 'Global child', values: %w[c1 c2], parent: parent,
                             is_for_all: true)
      expect(rules).not_to receive(:prune_mapping)
      allow(payload).to receive(:parse).and_call_original
      raw = json({ 'A' => %w[c1] }, {}, 'source' => 'import', 'import' => { 'mode' => 'replace', 'rows' => 1 })

      _service, error = run(child, dependencies_json: raw)

      expect(error).to be_nil
      # The admin transport would parse a second time in validation.
      expect(payload).to have_received(:parse).once
      source = File.read(File.expand_path('../../app/services/redmine_depending_custom_fields/' \
                                          'dependency_mapping_service.rb', __dir__))
      expect(source).not_to match(/dependencies_json\s*=[^=]|prune_mapping|ConfirmationRequired/)
      expect(stored(child)).to eq([{ 'A' => %w[c1] }, {}])
      row = rows(child).last
      expect(JSON.parse(row.after_value).values_at('source', 'import')).to eq(['import', { 'mode' => 'replace', 'rows' => 1 }])
      expect(row.affected_projects_count).to eq(Project.active.count)
    end

    it 'refuses a missing parent and a parent outside the project before any parse (gap 2)' do
      allow(payload).to receive(:parse).and_call_original
      child = single_pair
      other = dcf_create_project(name: 'Elsewhere')
      outside = dcf_list_field(name: 'Outside', values: %w[A], is_for_all: false, projects: [other])
      orphan = dcf_list_field(format: 'depending_list', name: 'Orphan', values: %w[c1], parent: outside,
                              is_for_all: false, projects: [project])
      dangling = CustomField.find(child.id)
      dangling.parent_custom_field_id = 99_999_999
      _service, error = run(dangling, dependencies_json: '{')
      expect([error.key, error.http_status]).to eq([:error_invalid_dependency, :unprocessable_entity])

      _service, error = run(orphan, dependencies_json: '{')
      expect([error.key, error.http_status]).to eq([:error_field_not_found, :not_found])

      expect(payload).not_to have_received(:parse)
      expect(rows(child).last.status).to eq('validation_failed')
      expect(rows(orphan).last.status).to eq('validation_failed')
    end

    it 'refuses a user without the permission before any parse with one authorization_failed row (SP-20b)' do
      allow(payload).to receive(:parse).and_call_original
      child = single_pair
      stranger = dcf_create_user("stranger-#{SecureRandom.hex(3)}")

      ['{', "[#{'9' * 1_000_000}]"].each do |raw|
        _service, error = run(child, { dependencies_json: raw, state_hash: 'stale' }, stranger)
        expect([error.key, error.http_status]).to eq([:error_forbidden, :forbidden])
      end

      expect(payload).not_to have_received(:parse)
      expect(rows(child).where(status: 'authorization_failed').count).to eq(2)
      expect(stored(child)).to eq([{ 'A' => %w[c1] }, { 'A' => 'c1' }])
    end

    it 'writes only the edited field, never a hidden child below it' do
      child = single_pair
      grandchild = dcf_list_field(format: 'depending_list', name: 'Hidden grandchild', values: %w[g1], parent: child,
                                  is_for_all: false, projects: [project])
      grandchild = dcf_set_dependencies(grandchild, value_dependencies: { 'c1' => %w[g1] })
      grandchild.update!(visible: false, role_ids: [dcf_create_role.id])
      before = raw_store(grandchild)

      run(child, dependencies_json: json({ 'B' => %w[c2] }))

      expect(raw_store(grandchild)).to eq(before)
      row = rows(child).last
      expect(row.status).to eq('success')
      expect(row.affected_child_field_ids.to_s).not_to include(grandchild.id.to_s)
      expect(row.changes_summary).not_to include('Hidden grandchild')
    end

    # T-CASC-1 (BC-02): a parent rename cascade rewrites only the renamed key
    # of the child; unrelated, orphan and bracket keys and the defaults keep
    # their values, order and shape. Placed here, the WP-27 Files list has no
    # dcf_value_services_spec.rb.
    it 'keeps the unrelated, orphan and bracket keys of a child through a rename cascade (T-CASC-1)' do
      parent = dcf_list_field(name: 'Cascade parent', values: ['P', 'X', 'A]B', 'Foo [x]'], is_for_all: false,
                              projects: [project])
      child = dcf_list_field(format: 'depending_list', name: 'Cascade child', values: %w[c1 c2], parent: parent,
                             is_for_all: false, projects: [project])
      CustomField.where(id: child.id).update_all(
        ['format_store = ?', CustomField.type_for_attribute('format_store').serialize(
          CustomField.find(child.id).format_store.to_hash.merge(
            'value_dependencies' => { 'P' => %w[c1], 'X' => %w[c2], 'Gone' => %w[c1 zz], 'A]B' => %w[c1],
                                      'Foo [x]' => %w[c2 c1] },
            'default_value_dependencies' => { 'X' => 'c2', 'Gone' => %w[c1], 'Foo [x]' => %w[c1] }
          )
        )]
      )
      vd_before, dd_before = stored(child)

      RedmineDependingCustomFields::RenameValueService
        .new(project: project, field: CustomField.find(parent.id), user: user,
             params: { old_value: 'P', new_value: 'Q', confirm: '1' }).call

      vd_after, dd_after = stored(child)
      expect(vd_after.except('Q').to_a).to eq(vd_before.except('P').to_a)
      expect(vd_after['Q']).to eq(%w[c1])
      expect(dd_after.to_a).to eq(dd_before.to_a)
      expect(dd_after['Gone']).to eq(%w[c1])
    end
  end
end
