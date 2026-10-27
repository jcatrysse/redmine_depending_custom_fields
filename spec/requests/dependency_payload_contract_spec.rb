# frozen_string_literal: true

require_relative '../rails_helper'

# WP-23 (quality 5.6, editor design 5.5, R3, QA-02): the payload goldens the
# editor model writes (test/js/payload_golden.test.js) are posted byte for
# byte to the admin transport of WP-22, with the placeholder base replaced by
# the stored digest. The fields hold the lists of the JS side, so nothing is
# pruned and the stored mapping equals the golden; a stale base is refused.
# WP-27 adds the project half here, with the same goldens and fields.
RSpec.describe 'Dependency payload contract (WP-23)', type: :request do
  fixtures :users

  golden_names = %w[clear enumeration_save import_merge import_replace list_save tricky_values]

  let(:payload) { RedmineDependingCustomFields::DependencyPayload }
  let(:rules) { RedmineDependingCustomFields::DependencyRules }
  let(:golden_dir) { File.expand_path('../../test/js/fixtures/payload', __dir__) }
  let(:placeholder) { '0123456789abcdef' * 4 }
  let(:countries) { %w[Belgium France Germany Netherlands] }
  let(:cities) { %w[Antwerp Brussels Ghent Lyon Paris Berlin Utrecht] }
  let(:named) { %w[__proto__ constructor toString hasOwnProperty valueOf toJSON] }
  let(:tricky_parents) do
    DcfLargeList::TRICKY + named +
      ['Foo [x]', '[b', '"><script>alert(1)</script>', '</script>', '&', 'a/b', '12345678901234567890', '007', '10',
       '2', "\u00e9", "e\u0301", "line\u2028sep", 'back\\slash', "\u{1f600} smile"]
  end
  let(:tricky_children) do
    ['__proto__', 'constructor', 'toString', 'hasOwnProperty', 'toJSON', 'b', '[x]', 'a]', '<b>x</b>', '&amp;', '1.0',
     'null', 'a/b/c', '9007199254740993', "\u00dcn\u00efc\u00f8d\u00e9 \u00f1", "tab\tin"]
  end

  # Read as UTF-8: the default external encoding may be US-ASCII (CI shells).
  def golden(name)
    File.read(File.join(golden_dir, "#{name}.json"), encoding: 'UTF-8')
  end

  # The golden text with only the placeholder replaced (never re-encoded).
  def with_base(raw, field)
    expect(raw.scan(placeholder).size).to eq(1)
    raw.sub(placeholder, payload.stored_digest(CustomField.find(field.id)))
  end

  # The golden's mapping as the transport stores it: ids as Strings, each
  # default in the posted shape (the field's multiple matches it).
  def expected_mapping(raw)
    data = JSON.parse(raw)
    links = data['value_dependencies'].transform_values { |values| values.map(&:to_s) }
    defaults = data['default_value_dependencies'].transform_values do |value|
      value.is_a?(Array) ? value.map(&:to_s) : value.to_s
    end
    [links, defaults]
  end

  # [parent, child] holding the lists of payload_golden.test.js, with a
  # stored mapping the golden replaces.
  def contract_fields(name)
    parent, child = case name
                    when 'enumeration_save' then enumeration_fields
                    when 'tricky_values' then list_fields(tricky_parents, tricky_children, false)
                    when 'import_replace' then list_fields(countries, cities, true)
                    else list_fields(countries, cities, false)
                    end
    child = dcf_set_dependencies(child, value_dependencies: { rules.value_keys(parent).last => [rules.value_keys(child).first] })
    [parent, child]
  end

  def list_fields(parent_values, child_values, multiple)
    parent = dcf_list_field(name: "Parent-#{SecureRandom.hex(3)}", values: parent_values)
    child = dcf_list_field(format: 'depending_list', name: "Child-#{SecureRandom.hex(3)}", values: child_values,
                           parent: parent, multiple: multiple)
    expect(rules.value_keys(parent)).to eq(parent_values)
    expect(rules.value_keys(child)).to eq(child_values)
    [parent, child]
  end

  # Entries through dcf_fixture_record, parent first, so their ids are the
  # golden's (9_200_001 and up, creation order is position order).
  def enumeration_fields
    parent = enum_field('enumeration', nil, false, [['North', true], ['South', true], ['Old region', false]])
    child = enum_field('depending_enumeration', parent, true,
                       [['Alpha', true], ['Beta', true], ['Gamma', true], ['Retired', false]])
    expect(rules.value_options(parent)).to eq([['9200001', 'North', true], ['9200002', 'South', true],
                                               ['9200003', 'Old region', false]])
    expect(rules.value_options(child)).to eq([['9200004', 'Alpha', true], ['9200005', 'Beta', true],
                                              ['9200006', 'Gamma', true], ['9200007', 'Retired', false]])
    [parent, child]
  end

  def enum_field(format, parent, multiple, entries)
    field = IssueCustomField.new(name: "Enum-#{SecureRandom.hex(3)}", field_format: format, is_for_all: true,
                                 multiple: multiple)
    field.parent_custom_field_id = parent.id if parent
    field.save!
    entries.each_with_index do |(entry_name, active), i|
      dcf_fixture_record(CustomFieldEnumeration,
                         { custom_field_id: field.id, name: entry_name, position: i + 1, active: active })
    end
    field.reload
  end

  def raw_store(field)
    CustomField.connection.select_value(CustomField.where(id: field.id).select(:format_store).to_sql)
  end

  def error_box
    expect(response.body).not_to match(/translation[ _]missing/i)
    Nokogiri::HTML(response.body).css('#errorExplanation li').map { |li| li.text.strip }
  end

  def stale_message
    "#{IssueCustomField.human_attribute_name(:value_dependencies)} " \
      "#{I18n.t('activerecord.errors.messages.dcf_stale_dependencies')}"
  end

  def put_json(field, raw)
    put "/custom_fields/#{field.id}", params: { custom_field: { dependencies_json: raw } }
  end

  it 'finds exactly the six goldens' do
    names = Dir[File.join(golden_dir, '*.json')].map { |path| File.basename(path, '.json') }.sort
    expect(names).to eq(golden_names)
  end

  it 'parses every golden as committed (placeholder base, source and import as written)' do
    golden_names.each do |name|
      raw = golden(name)
      expect(raw).to be_valid_encoding
      result = payload.parse(raw)
      expect(result).to be_ok, "#{name}: #{result&.error}"
      expect(result.base).to eq(placeholder)
      expect(result.base).not_to eq(payload.digest({}, {}))
      links, defaults = expected_mapping(raw)
      expect([result.value_dependencies, result.default_value_dependencies]).to eq([links, defaults])
      if name.start_with?('import_')
        expect(result.source).to eq('import')
        expect(result.import.keys).to eq(%w[mode rows])
        expect(result.import['mode']).to eq(name.delete_prefix('import_'))
      else
        expect([result.source, result.import]).to eq(['editor', nil])
      end
    end
  end

  describe 'admin form (PUT /custom_fields/:id, WP-22 transport)' do
    before { allow(User).to receive(:current).and_return(dcf_admin) }

    golden_names.each do |name|
      it "saves #{name}.json as posted, with the stored digest as base and source and import ignored" do
        parent, child = contract_fields(name)
        raw = golden(name)
        body = with_base(raw, child)

        expect { put_json(child, body) }.not_to change(RedmineDependingCustomFields::ConfigAuditEvent, :count)

        expect(response).to redirect_to("/custom_fields/#{child.id}/edit")
        links, defaults = expected_mapping(raw)
        record = CustomField.find(child.id)
        expect(record.value_dependencies.to_hash).to eq(links)
        expect(record.default_value_dependencies.to_hash).to eq(defaults)
        expect(record.value_dependencies.keys).to eq(rules.value_keys(parent) & links.keys)
        record.value_dependencies.each_value { |values| expect(values).to eq(rules.value_keys(record) & values) }
        expect(record.value_dependencies.values.flatten).to all(be_a(String))
        expect(record.format_store.keys & %w[version source import base dependencies_json]).to eq([])
        expect(payload.stored_digest(record)).to eq(payload.digest(links, defaults))
      end
    end

    it 'keeps the tricky names, markup, brackets and non-ASCII keys of tricky_values.json byte for byte' do
      _parent, child = contract_fields('tricky_values')
      put_json(child, with_base(golden('tricky_values'), child))

      expect(response).to redirect_to("/custom_fields/#{child.id}/edit")
      record = CustomField.find(child.id)
      links = record.value_dependencies.to_hash
      expect(links.keys).to match_array(tricky_parents)
      expect(links['__proto__']).to eq(['__proto__'])
      expect(links['constructor']).to eq(['b'])
      expect(links['hasOwnProperty']).to eq(['b'])
      expect(links['toString']).to eq(%w[toString b])
      expect(links['toJSON']).to eq(['toJSON'])
      expect(record.default_value_dependencies['__proto__']).to eq('__proto__')
      expect(links.keys).to include("\u00e9", "e\u0301", "line\u2028sep", '"><script>alert(1)</script>', '</script>')
      expect(links.values.flatten).to include('<b>x</b>', '&amp;', '9007199254740993', "tab\tin")
    end

    it 'refuses each golden with a well-formed base that is not the stored digest (dcf_stale_dependencies)' do
      golden_names.each do |name|
        _parent, child = contract_fields(name)
        expect(payload.stored_digest(CustomField.find(child.id))).not_to eq(placeholder)
        raw_before = raw_store(child)

        put_json(child, golden(name))

        expect(response).to have_http_status(200)
        expect(error_box).to eq([stale_message])
        expect(raw_store(child)).to eq(raw_before)
      end
    end

    it 'refuses a stale base even when the golden equals the stored mapping' do
      _parent, child = contract_fields('enumeration_save')
      raw = golden('enumeration_save')
      links, defaults = expected_mapping(raw)
      child = dcf_set_dependencies(child, value_dependencies: links, default_value_dependencies: defaults)
      expect(payload.stored_digest(child)).to eq(payload.digest(links, defaults))
      raw_before = raw_store(child)

      put_json(child, raw)

      expect(response).to have_http_status(200)
      expect(error_box).to eq([stale_message])
      expect(raw_store(child)).to eq(raw_before)
      record = CustomField.find(child.id)
      record.dependencies_json = raw
      expect(record).not_to be_valid
      expect(record.errors.details[:value_dependencies]).to eq([{ error: :dcf_stale_dependencies }])
    end
  end
end
