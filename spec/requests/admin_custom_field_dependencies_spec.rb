# frozen_string_literal: true

require_relative '../rails_helper'
require 'stringio'
require 'logger'

# WP-22 (editor design 3.1 to 3.4, compat 2.4 and 3, UD-15, UD-17): the admin
# custom field form accepts the dependency mapping as one JSON field,
# custom_field[dependencies_json]. Absent or blank keeps the mapping, '{}'
# clears it, an unreadable, oversize or stale payload re-renders the form
# with the error on "Dependency mapping" and writes nothing. Changed by
# WP-25: the form renders the editor (one blank hidden input, the mapping in
# data-dcf-editor-mapping) instead of the matrix; most examples still post the
# field directly, the WP-25 block below drives the rendered form.
RSpec.describe 'Admin custom field dependencies_json (WP-22)', type: :request do
  fixtures :users

  let(:payload) { RedmineDependingCustomFields::DependencyPayload }
  let(:rules) { RedmineDependingCustomFields::DependencyRules }
  let(:limits) { RedmineDependingCustomFields::StorageLimits }
  let(:admin) { dcf_admin }
  let(:parent) { dcf_list_field(name: "Parent-#{SecureRandom.hex(3)}", values: %w[A B C]) }
  let(:child) do
    field = dcf_list_field(format: 'depending_list', name: "Child-#{SecureRandom.hex(3)}", values: %w[a1 b1 c1],
                           parent: parent)
    dcf_set_dependencies(field, value_dependencies: { 'A' => %w[a1], 'B' => %w[b1] },
                                default_value_dependencies: { 'A' => 'a1' })
  end

  messages = {
    en: { invalid: 'Dependency mapping could not be read. Reload the page and try again.',
          stale: 'Dependency mapping was changed by someone else after you opened this page. Your changes were not ' \
                 'saved. The editor shows the current version and your version so that you can choose which one ' \
                 'to keep.',
          too_large: 'Dependency mapping is too large to be sent (%<size>s bytes, at most %<limit>s bytes). Remove ' \
                     'links and try again.' },
    de: { invalid: 'Abhängigkeitszuordnung konnte nicht gelesen werden. Laden Sie die Seite neu und versuchen Sie es ' \
                   'erneut.',
          stale: 'Abhängigkeitszuordnung wurde von jemand anderem geändert, nachdem Sie diese Seite geöffnet haben. ' \
                 'Ihre Änderungen wurden nicht gespeichert. Der Editor zeigt die aktuelle Version und Ihre Version, ' \
                 'damit Sie wählen können, welche erhalten bleibt.',
          too_large: 'Abhängigkeitszuordnung ist zu groß zum Senden (%<size>s Bytes, höchstens %<limit>s Bytes). ' \
                     'Entfernen Sie Verknüpfungen und versuchen Sie es erneut.' },
    fr: { invalid: "Mappage des dépendances n'a pas pu être lu. Rechargez la page et réessayez.",
          stale: "Mappage des dépendances a été modifié par quelqu'un d'autre après l'ouverture de cette page. Vos " \
                 "modifications n'ont pas été enregistrées. L'éditeur affiche la version actuelle et votre version " \
                 'pour que vous puissiez choisir celle à conserver.' },
    nl: { invalid: 'Afhankelijkheidskoppeling kon niet worden gelezen. Herlaad de pagina en probeer het opnieuw.',
          stale: 'Afhankelijkheidskoppeling is door iemand anders gewijzigd nadat u deze pagina opende. Uw wijzigingen ' \
                 'zijn niet opgeslagen. De editor toont de huidige versie en uw versie, zodat u kunt kiezen welke u ' \
                 'bewaart.' }
  }.freeze
  max_bytes = 4 * 1024 * 1024

  def json(links = {}, defaults = nil, extra = {})
    body = {}
    extra.each { |key, value| body[key.to_s] = value }
    body['value_dependencies'] = links
    body['default_value_dependencies'] = defaults unless defaults.nil?
    JSON.generate(body)
  end

  def raw_store(field)
    CustomField.connection.select_value(CustomField.where(id: field.id).select(:format_store).to_sql)
  end

  def stored(field)
    record = CustomField.find(field.id)
    [record.value_dependencies.to_hash, record.default_value_dependencies.to_hash]
  end

  # options: further keywords for put (headers:), given as a Hash.
  def put_field(field, attributes, options = {})
    put "/custom_fields/#{field.id}", params: { custom_field: attributes }, **options
  end

  def page
    expect(response.body).not_to match(/translation[ _]missing/i)
    Nokogiri::HTML(response.body)
  end

  def error_box
    page.css('#errorExplanation li').map { |li| li.text.strip }
  end

  def expect_saved(field)
    expect(response).to redirect_to("/custom_fields/#{field.id}/edit"), response.body[0, 2_000]
  end

  def expect_refused(field, raw_before, message)
    expect(response).to have_http_status(200)
    expect(error_box).to eq([message])
    expect(raw_store(field)).to eq(raw_before)
  end

  # Changed by WP-25 (was matrix_box): the editor root of the page.
  def editor_root
    page.at_css('fieldset.dcf-dep-editor[data-dcf-editor]')
  end

  def editor_json(name)
    JSON.parse(editor_root["data-dcf-editor-#{name}"])
  end

  def hidden_inputs
    page.css('[name="custom_field[dependencies_json]"]')
  end

  def multipart
    { 'CONTENT_TYPE' => 'multipart/form-data' }
  end

  # A Key/Value list (depending) child of a Key/Value list parent whose
  # stored links and defaults use the inactive entries z and z1.
  def inactive_enum_child
    enum_parent = dcf_enum_field(name: "EnumParent-#{SecureRandom.hex(3)}", names: %w[X Y Z])
    enum_child = dcf_enum_field(format: 'depending_enumeration', names: %w[x1 y1 z1], parent: enum_parent)
    x, y, z = enum_parent.enumerations.order(:position).map { |e| e.id.to_s }
    x1, y1, z1 = enum_child.enumerations.order(:position).map { |e| e.id.to_s }
    dcf_set_dependencies(enum_child, value_dependencies: { x => [x1, z1], y => [y1], z => [x1] },
                                     default_value_dependencies: { x => z1, y => y1, z => x1 })
    CustomFieldEnumeration.where(id: [z, z1]).update_all(active: false)
    [enum_child, x, y, z, x1, y1, z1]
  end

  describe 'as an administrator' do
    before { allow(User).to receive(:current).and_return(admin) }

    it "clears the mapping with '{}', parsing it once" do
      child
      allow(payload).to receive(:parse).and_call_original

      put_field(child, dependencies_json: '{}')

      expect_saved(child)
      expect(payload).to have_received(:parse).once
      expect(stored(child)).to eq([{}, {}])
    end

    it 'keeps the row byte-identical when the field is absent or holds JSON white space only' do
      raw_before = raw_store(child)
      allow(payload).to receive(:parse).and_call_original

      put_field(child, name: "#{child.name}-1")
      expect_saved(child)
      expect(payload).not_to have_received(:parse)

      ['', "  \t\r\n"].each_with_index do |raw, i|
        put_field(child, name: "#{child.name}-#{i + 2}", dependencies_json: raw)
        expect_saved(child)
      end
      expect(raw_store(child)).to eq(raw_before)
      expect(CustomField.find(child.id).name).to eq("#{child.name}-3")
    end

    it 'refuses U+00A0 as unreadable' do
      raw_before = raw_store(child)
      put_field(child, dependencies_json: "\u00a0")
      expect_refused(child, raw_before, messages[:en][:invalid])
    end

    it 'stores keys and values with brackets, quotes, markup and non-ASCII byte for byte' do
      parent_values = ['A', 'C]D', '[x]', 'a]', '__proto__', 'constructor', 'hasOwnProperty',
                       '"><script>alert(1)</script>', 'Ünïcødé ñ', "O'Brien & co", 'yes', 'null', '~', ':sym',
                       '1e3', '---', '!ruby/object:Object', '- dash', "e\u0301", "\u00e9"]
      child_values = ['c]1', '[y]', '<b>x</b>', 'toString', '__proto__', 'é ü']
      tricky_parent = dcf_list_field(name: "Tricky-#{SecureRandom.hex(3)}", values: parent_values)
      field = dcf_list_field(format: 'depending_list', name: "TrickyChild-#{SecureRandom.hex(3)}",
                             values: child_values, parent: tricky_parent)
      links = parent_values.reject { |v| v == "é" }.each_with_index.to_h do |value, i|
        [value, [child_values[i % child_values.size], child_values[(i + 1) % child_values.size]]]
      end
      ordered = links.transform_values { |values| values.sort_by { |v| child_values.index(v) } }
      defaults = { '"><script>alert(1)</script>' => ordered['"><script>alert(1)</script>'].first,
                   '__proto__' => ordered['__proto__'].last }

      put_field(field, dependencies_json: json(links, defaults))

      expect_saved(field)
      saved_links, saved_defaults = stored(field)
      expect(saved_links).to eq(ordered)
      expect(saved_links.keys).to eq(ordered.keys)
      expect(saved_links.keys).not_to include("é")
      expect(saved_links.keys.flat_map { |k| [k] + saved_links[k] }).to all(be_a(String))
      expect(saved_defaults).to eq(defaults)

      get "/custom_fields/#{field.id}/edit"
      expect(response).to have_http_status(200)
      expect(response.body).not_to include('<script>alert(1)')
      # Changed by WP-25: the editor mapping attribute instead of a matrix box.
      expect(editor_json('mapping')['value_dependencies']).to eq(ordered)
      expect(editor_json('mapping')['default_value_dependencies']).to eq(defaults)
    end

    it 'saves 5,000 links sent in the one form param' do
      big_parent = dcf_list_field(values: (1..100).map { |i| "P#{i}" })
      children = (1..50).map { |i| "c#{i}" }
      field = dcf_list_field(format: 'depending_list', values: children, parent: big_parent)
      links = (1..100).to_h { |i| ["P#{i}", children] }

      put "/custom_fields/#{field.id}", params: URI.encode_www_form('custom_field[dependencies_json]' => json(links)),
                                        headers: { 'CONTENT_TYPE' => 'application/x-www-form-urlencoded' }

      expect_saved(field)
      expect(request.request_parameters['custom_field'].keys).to eq(['dependencies_json'])
      expect(stored(field)[0].values.sum(&:size)).to eq(5_000)
    end

    it 'lets the JSON win over the nested params of the same request, in either order' do
      nested = [['custom_field[value_dependencies][A][]', 'a1'], ['custom_field[value_dependencies][A][]', 'c1'],
                ['custom_field[default_value_dependencies][A]', 'c1']]
      transport = [['custom_field[dependencies_json]', json('B' => %w[b1])]]
      [nested + transport, transport + nested].each do |entries|
        field = CustomField.find(child.id)
        dcf_set_dependencies(field, value_dependencies: { 'A' => %w[a1] }, default_value_dependencies: { 'A' => 'a1' })

        put "/custom_fields/#{field.id}", params: URI.encode_www_form(entries),
                                          headers: { 'CONTENT_TYPE' => 'application/x-www-form-urlencoded' }

        expect_saved(field)
        expect(stored(field)).to eq([{ 'B' => %w[b1] }, {}])
      end
    end

    describe 'unreadable payloads' do
      {
        'not JSON' => 'not json',
        'an unknown top-level key' => '{"meta":{}}',
        'a negative integer' => '{"value_dependencies":{"A":[-1]}}',
        'a float' => '{"value_dependencies":{"A":[1.5]}}',
        'a boolean' => '{"value_dependencies":{"A":[true]}}',
        'null' => '{"value_dependencies":{"A":[null]}}',
        'a top-level Array' => '[]',
        'nesting deeper than 3' => '{"value_dependencies":{"A":[["a1"]]}}'
      }.each do |label, raw|
        it "re-renders #{label} with the unreadable message and writes nothing" do
          raw_before = raw_store(child)
          put_field(child, dependencies_json: raw)
          expect_refused(child, raw_before, messages[:en][:invalid])
        end
      end

      it 'rejects a 1,000,000-digit and a 20-digit integer before JSON.parse' do
        raw_before = raw_store(child)
        allow(JSON).to receive(:parse).and_call_original
        ["{\"value_dependencies\":{\"A\":[#{'9' * 1_000_000}]}}", '{"value_dependencies":{"A":[12345678901234567890]}}']
          .each do |raw|
          put_field(child, dependencies_json: raw)
          expect_refused(child, raw_before, messages[:en][:invalid])
        end
        expect(JSON).not_to have_received(:parse)
      end

      it 'refuses a nested Hash or Array param and a file part as unreadable (never a 500)' do
        raw_before = raw_store(child)
        put "/custom_fields/#{child.id}", params: 'custom_field[dependencies_json][value_dependencies]=1',
                                          headers: { 'CONTENT_TYPE' => 'application/x-www-form-urlencoded' }
        expect_refused(child, raw_before, messages[:en][:invalid])

        put "/custom_fields/#{child.id}", params: 'custom_field[dependencies_json][]=%7B%7D',
                                          headers: { 'CONTENT_TYPE' => 'application/x-www-form-urlencoded' }
        expect_refused(child, raw_before, messages[:en][:invalid])

        file = Rack::Test::UploadedFile.new(StringIO.new('{}'), 'application/json', original_filename: 'm.json')
        put_field(child, { dependencies_json: file }, headers: multipart)
        expect_refused(child, raw_before, messages[:en][:invalid])
      end

      it 'answers 422 to the .js update' do
        raw_before = raw_store(child)
        put "/custom_fields/#{child.id}.js", params: { custom_field: { dependencies_json: '{' } }, xhr: true

        expect(response).to have_http_status(422)
        expect(raw_store(child)).to eq(raw_before)
      end
    end

    it 'gives the size message for a multipart payload above 4 MiB, without JSON.parse, and writes nothing' do
      raw_before = raw_store(child)
      body = json('C' => %w[c1])
      above = body + (' ' * (max_bytes + 1 - body.bytesize))
      allow(JSON).to receive(:parse).and_call_original

      put_field(child, { dependencies_json: above }, headers: multipart)

      expect(JSON).not_to have_received(:parse)
      expect_refused(child, raw_before, format(messages[:en][:too_large], size: limits.delimited(max_bytes + 1),
                                                                         limit: limits.delimited(max_bytes)))
    end

    it 'refuses a stale base with the conflict message and saves with the current one, parsing once each (UD-17)' do
      raw_before = raw_store(child)
      allow(payload).to receive(:parse).and_call_original
      put_field(child, dependencies_json: json({ 'C' => %w[c1] }, nil, 'base' => '0' * 64))
      expect_refused(child, raw_before, messages[:en][:stale])
      expect(payload).to have_received(:parse).once

      put_field(child, dependencies_json: json({ 'C' => %w[c1] }, nil,
                                               'base' => payload.stored_digest(CustomField.find(child.id))))
      expect_saved(child)
      expect(payload).to have_received(:parse).twice
      expect(stored(child)).to eq([{ 'C' => %w[c1] }, {}])
    end

    it 'renders nothing from the param on GET /custom_fields/new and does not parse it (SP-11)' do
      marker = "MARK#{SecureRandom.hex(8)}"
      io = StringIO.new
      allow(Rails).to receive(:logger).and_return(Logger.new(io))
      allow(payload).to receive(:parse).and_call_original
      [json({ "<script>#{marker}</script>" => %w[a1] }, { marker => 'a1' }),
       "{\"#{marker}\":",
       json({ 'A' => [marker] }, nil, 'base' => '0' * 64)].each do |raw|
        params = { type: 'IssueCustomField',
                   custom_field: { field_format: 'depending_list', parent_custom_field_id: parent.id.to_s,
                                   possible_values: "a1\nb1", dependencies_json: raw } }
        get '/custom_fields/new', params: params
        expect(response).to have_http_status(200)
        expect(response.body).not_to include(marker)
        # Changed by WP-25: the editor's one blank hidden input (was: none).
        expect(hidden_inputs.map { |i| i['value'] }).to eq([''])
        expect(editor_root['data-dcf-editor-dirty']).to be_nil

        get '/custom_fields/new.js', params: params, xhr: true
        expect(response).to have_http_status(200)
        expect(response.body).not_to include(marker)
      end
      expect(payload).not_to have_received(:parse)
      # Rails logs the request line with its query; the transport logs nothing.
      expect(io.string).not_to include('dependencies_json rejected')
    end

    it 'keeps links from and to inactive Key/Value entries when the stored mapping is posted back (D6, G1 red-green)' do
      enum_child, x, y, z, x1, y1, z1 = inactive_enum_child
      mapping = [{ x => [x1, z1], y => [y1], z => [x1] }, { x => z1, y => y1, z => x1 }]
      allow(rules).to receive(:prune_mapping).and_call_original

      put_field(enum_child, dependencies_json: json(*mapping))

      expect_saved(enum_child)
      expect(rules).to have_received(:prune_mapping).once
      expect(stored(enum_child)).to eq(mapping)
    end

    it 'adds a link next to the links from and to inactive Key/Value entries (D6)' do
      enum_child, x, y, z, x1, y1, z1 = inactive_enum_child

      put_field(enum_child, dependencies_json: json({ x => [x1, z1], y => [y1, x1], z => [x1] },
                                                    { x => z1, y => y1, z => x1 }))

      expect_saved(enum_child)
      expect(stored(enum_child)).to eq([{ x => [x1, z1], y => [x1, y1], z => [x1] }, { x => z1, y => y1, z => x1 }])
    end

    it 'prunes the links to a parent changed in the same request' do
      second = dcf_list_field(name: "Second-#{SecureRandom.hex(3)}", values: %w[C B])

      put_field(child, parent_custom_field_id: second.id.to_s,
                       dependencies_json: json({ 'A' => %w[a1], 'B' => %w[b1], 'C' => %w[c1 zz] }, { 'A' => 'a1' }))

      expect_saved(child)
      links, defaults = stored(child)
      expect(links).to eq('C' => %w[c1], 'B' => %w[b1])
      expect(links.keys).to eq(%w[C B])
      expect(defaults).to eq({})
      expect(CustomField.find(child.id).parent_custom_field_id).to eq(second.id)
    end

    it 'keeps the posted keys and stores no parent for an unknown parent id (D9)' do
      put_field(child, parent_custom_field_id: (CustomField.maximum(:id).to_i + 1_000).to_s,
                       dependencies_json: json('X' => %w[a1], 'Y' => %w[zz b1]))

      expect_saved(child)
      expect(stored(child)).to eq([{ 'X' => %w[a1], 'Y' => %w[b1] }, {}])
      expect(CustomField.find(child.id).parent_custom_field_id).to be_nil
    end

    it 'creates a field with the pruned mapping and ignores the base on create' do
      parent
      expect do
        post '/custom_fields', params: {
          type: 'IssueCustomField',
          custom_field: { name: "Created-#{SecureRandom.hex(3)}", field_format: 'depending_list',
                          possible_values: "b1\na1", parent_custom_field_id: parent.id.to_s, is_for_all: '1',
                          dependencies_json: json({ 'B' => %w[a1 b1 zz], 'ZZ' => %w[a1] }, { 'B' => %w[a1 b1] },
                                                  'base' => '0' * 64) }
        }
      end.to change(CustomField, :count).by(1)

      expect(response).to have_http_status(302)
      expect(stored(CustomField.order(:id).last)).to eq([{ 'B' => %w[b1 a1] }, { 'B' => 'b1' }])
    end

    # Changed by WP-25 (gap 1): the editor attributes instead of the matrix
    # boxes; the hidden input renders blank, the mapping attribute holds the
    # pruned posted mapping and the editor starts dirty.
    it 'keeps the pruned posted mapping on the form after a save refused for another reason (gap 1)' do
      raw_before = raw_store(child)
      marker = "MARK#{SecureRandom.hex(8)}"

      allow(payload).to receive(:parse).and_call_original

      put_field(child, name: '', dependencies_json: json({ 'A' => %w[a1 c1], 'C' => %w[b1], marker => %w[a1] },
                                                         { 'C' => 'b1', marker => 'a1' }))

      expect(response).to have_http_status(200)
      expect(payload).to have_received(:parse).once
      expect(page.css('#errorExplanation li').size).to eq(1)
      expect(hidden_inputs.map { |i| i['value'] }).to eq([''])
      expect(editor_json('mapping')).to eq('value_dependencies' => { 'A' => %w[a1 c1], 'C' => %w[b1] },
                                           'default_value_dependencies' => { 'C' => 'b1' })
      expect(editor_root['data-dcf-editor-dirty']).to eq('1')
      expect(editor_root['data-dcf-editor-echo']).to be_nil
      expect(editor_root['data-dcf-editor-conflict-mapping']).to be_nil
      ['"value_dependencies"', marker, 'JSON::', 'unexpected token'].each do |text|
        expect(response.body).not_to include(text)
      end
      expect(raw_store(child)).to eq(raw_before)
    end

    it 'shows the stored mapping, not dirty, after a refused payload (unreadable or too large)' do
      raw_before = raw_store(child)
      stored_mapping = { 'value_dependencies' => { 'A' => %w[a1], 'B' => %w[b1] },
                         'default_value_dependencies' => { 'A' => 'a1' } }
      [['{"value_dependencies":{"C":', {}], ['x' * (max_bytes + 1), { headers: multipart }]].each do |raw, options|
        put_field(child, { dependencies_json: raw }, options)

        expect(response).to have_http_status(200)
        expect(error_box.size).to eq(1)
        expect(hidden_inputs.map { |i| i['value'] }).to eq([''])
        expect(editor_json('mapping')).to eq(stored_mapping)
        expect(editor_root['data-dcf-editor-dirty']).to be_nil
        expect(response.body).not_to include('xxxxxxxxxx')
      end
      expect(raw_store(child)).to eq(raw_before)
    end

    it 'shows the stored mapping, the refused version and the fresh base after a stale refusal (UD-17)' do
      raw_before = raw_store(child)
      put_field(child, dependencies_json: json({ 'C' => %w[c1] }, { 'C' => 'c1' }, 'base' => '0' * 64))

      expect_refused(child, raw_before, messages[:en][:stale])
      expect(editor_json('mapping')).to eq('value_dependencies' => { 'A' => %w[a1], 'B' => %w[b1] },
                                           'default_value_dependencies' => { 'A' => 'a1' })
      expect(editor_json('conflict-mapping')).to eq('value_dependencies' => { 'C' => %w[c1] },
                                                    'default_value_dependencies' => { 'C' => 'c1' },
                                                    'source' => 'editor', 'import' => nil)
      expect(editor_root['data-dcf-editor-base']).to eq(payload.stored_digest(CustomField.find(child.id)))
      expect(editor_root['data-dcf-editor-dirty']).to be_nil
      expect(hidden_inputs.map { |i| i['value'] }).to eq([''])
    end

    # Changed by WP-25: the stale re-render carries the refused version in
    # data-dcf-editor-conflict-mapping, JSON-encoded and escaped once; the
    # markup never appears as markup (was: the text nowhere in the page).
    it 'escapes markup of an unreadable or stale payload nowhere into the page as markup' do
      markup = '<img src=x onerror=alert(1)>'
      raw_before = raw_store(child)
      [json({ markup => [markup] }, nil, 'base' => '0' * 64), "{\"#{markup}\":"].each_with_index do |raw, i|
        put_field(child, dependencies_json: raw)
        expect(response).to have_http_status(200)
        expect(response.body).not_to include('<img src=x')
        expect(response.body).not_to include('&lt;img')
        expect(response.body).not_to include('&amp;quot;')
        expect(page.css('img[src=x]')).to be_empty
        if i.zero?
          expect(editor_json('conflict-mapping')['value_dependencies']).to eq(markup => [markup])
        else
          expect(editor_root['data-dcf-editor-conflict-mapping']).to be_nil
          expect(response.body).not_to include('onerror=alert(1)')
        end
      end
      expect(raw_store(child)).to eq(raw_before)
    end

    [:de, :fr, :nl].each do |locale|
      it "renders the unreadable and the stale message in #{locale}, escaped once" do
        admin.update_column(:language, locale.to_s)
        raw_before = raw_store(child)

        put_field(child, dependencies_json: '{')
        expect_refused(child, raw_before, messages[locale][:invalid])
        expect(response.body).not_to include('&amp;#39;')

        put_field(child, dependencies_json: json({ 'C' => %w[c1] }, nil, 'base' => '0' * 64))
        expect_refused(child, raw_before, messages[locale][:stale])
        expect(response.body).not_to include('&amp;#39;')
      end
    end

    it 'renders the size message in German with German delimiters' do
      admin.update_column(:language, 'de')
      raw_before = raw_store(child)

      put_field(child, { dependencies_json: 'x' * (max_bytes + 1) }, headers: multipart)

      size, limit = I18n.with_locale(:de) do
        [ActiveSupport::NumberHelper.number_to_delimited(max_bytes + 1),
         ActiveSupport::NumberHelper.number_to_delimited(max_bytes)]
      end
      expect_refused(child, raw_before, format(messages[:de][:too_large], size: size, limit: limit))
    end

    it 'writes no audit row for an ok, a stale or an unreadable payload (D6)' do
      child
      expect do
        put_field(child, dependencies_json: json('C' => %w[c1]))
        expect_saved(child)
        expect(stored(child)).to eq([{ 'C' => %w[c1] }, {}])
        raw_before = raw_store(child)

        put_field(child, dependencies_json: json({ 'B' => %w[b1] }, nil, 'base' => '0' * 64))
        expect_refused(child, raw_before, messages[:en][:stale])

        put_field(child, dependencies_json: '{')
        expect_refused(child, raw_before, messages[:en][:invalid])
      end.not_to change(RedmineDependingCustomFields::ConfigAuditEvent, :count)
    end

    it 'runs the same queries for 10 and 5,000 links as a nested-param save of the 10 links' do
      big_parent = dcf_list_field(values: (1..100).map { |i| "P#{i}" })
      children = (1..50).map { |i| "c#{i}" }
      # A warm-up request first: after some earlier examples the first request
      # reloads core settings (rest_api_enabled and
      # force_default_language_for_loggedin) that later ones read from the cache.
      warm_up = dcf_list_field(format: 'depending_list', values: children, parent: big_parent)
      put_field(warm_up, dependencies_json: '{}')
      expect_saved(warm_up)
      counts = [10, 5_000].map do |size|
        field = dcf_list_field(format: 'depending_list', values: children, parent: big_parent)
        links = if size == 10
                  (1..10).to_h { |i| ["P#{i}", %w[c1]] }
                else
                  (1..100).to_h { |i| ["P#{i}", children] }
                end
        count = dcf_count_queries { put_field(field, dependencies_json: json(links)) }
        expect_saved(field)
        expect(stored(field)[0].values.sum(&:size)).to eq(size)
        count
      end
      expect(counts[0]).to eq(counts[1])

      field = dcf_list_field(format: 'depending_list', values: children, parent: big_parent)
      nested = (1..10).map { |i| ["custom_field[value_dependencies][P#{i}][]", 'c1'] }
      count = dcf_count_queries do
        put "/custom_fields/#{field.id}", params: URI.encode_www_form(nested),
                                          headers: { 'CONTENT_TYPE' => 'application/x-www-form-urlencoded' }
      end
      expect_saved(field)
      expect(stored(field)[0].values.sum(&:size)).to eq(10)
      expect(count).to eq(counts[0])
    end
  end

  describe 'without administrator rights' do
    def attempt(field, raw)
      put_field(field, dependencies_json: raw)
      put_status = response.status
      post '/custom_fields', params: { type: 'IssueCustomField',
                                       custom_field: { name: 'X', field_format: 'depending_list',
                                                       dependencies_json: raw } }
      [put_status, response.status]
    end

    it 'never reaches the transport for anonymous users and non-administrators' do
      project = dcf_create_project
      manager = dcf_manager(project)
      raw_before = raw_store(child)
      count = CustomField.count
      allow(payload).to receive(:parse).and_call_original

      [User.anonymous, manager].each do |user|
        allow(User).to receive(:current).and_return(user)
        ['{}', '{', "{\"value_dependencies\":{\"A\":[#{'9' * 1_000}]}}"].each do |raw|
          statuses = attempt(child, raw)
          expect(statuses).to all(satisfy { |s| [302, 401, 403].include?(s) }), statuses.inspect
        end
      end
      expect(payload).not_to have_received(:parse)
      expect(raw_store(child)).to eq(raw_before)
      expect(CustomField.count).to eq(count)
    end

    it 'does not accept an administrator API key on the update (core accept_api_auth :index only)' do
      with_settings = Setting.rest_api_enabled
      Setting.rest_api_enabled = '1'
      raw_before = raw_store(child)
      allow(payload).to receive(:parse).and_call_original

      put "/custom_fields/#{child.id}.json", params: { custom_field: { dependencies_json: '{}' } },
                                             headers: { 'X-Redmine-API-Key' => admin.api_key }

      expect([401, 403]).to include(response.status)
      expect(payload).not_to have_received(:parse)
      expect(raw_store(child)).to eq(raw_before)
    ensure
      Setting.rest_api_enabled = with_settings
    end
  end

  # WP-25 (editor design 5.2, 5.9, 3.4; UD-16; compat 2.2): the admin form
  # renders the editor last, posts one blank field until the editor is
  # dirty, and saves the mapping through the rendered form.
  describe 'the admin form with the dependency editor (WP-25)' do
    before { allow(User).to receive(:current).and_return(admin) }

    # The [name, value] entries a browser submits for +form+ as rendered.
    def browser_entries(form)
      skipped = %w[submit button image file reset]
      form.css('input, select, textarea').each_with_object([]) do |control, entries|
        next if control['name'].to_s.empty? || control.key?('disabled')

        name = control['name']
        case control.name
        when 'select'
          options = control.css('option')
          chosen = options.select { |o| o.key?('selected') }
          chosen = options.first(1) if chosen.empty? && !control.key?('multiple')
          chosen.each { |o| entries << [name, o['value'] || o.text] }
        when 'textarea' then entries << [name, control.text.sub(/\A\r?\n/, '')]
        else
          type = (control['type'] || 'text').downcase
          checkable = type == 'checkbox' || type == 'radio'
          next if skipped.include?(type) || (checkable && !control.key?('checked'))

          entries << [name, control['value'] || (checkable ? 'on' : '')]
        end
      end
    end

    def edit_form(field)
      get "/custom_fields/#{field.id}/edit"
      expect(response).to have_http_status(200)
      page.at_css('form#custom_field_form')
    end

    def submit_urlencoded(form)
      post form['action'], params: URI.encode_www_form(browser_entries(form)),
                           headers: { 'CONTENT_TYPE' => 'application/x-www-form-urlencoded' }
    end

    def positions(body, needles)
      needles.map { |needle| body.index(needle) }
    end

    it 'renders the editor last, after the default value row, url_pattern, the parent select and the options' do
      enum_parent = dcf_enum_field(name: "EP-#{SecureRandom.hex(3)}", names: %w[X Y])
      enum_child = dcf_enum_field(format: 'depending_enumeration', names: %w[x1 y1], parent: enum_parent)
      [[child, 'id="custom_field_possible_values"'], [enum_child, "/custom_fields/#{enum_child.id}/enumerations"]]
        .each do |field, first|
        get "/custom_fields/#{field.id}/edit"
        expect(response).to have_http_status(200)
        body = response.body
        order = positions(body, [first, 'data-dcf-default-value-row', 'id="custom_field_url_pattern"',
                                 'id="custom_field_parent_custom_field_id"', 'custom_field[hide_when_disabled]',
                                 'id="custom_field_edit_tag_style"', 'data-dcf-editor="1"'])
        expect(order).to all(be_an(Integer)), order.inspect
        expect(order).to eq(order.sort), field.field_format
        expect(page.css('table.dependencies-matrix, .dependencies-defaults, .dependencies-defaults-container')).to be_empty
        expect(page.css('[name^="custom_field[value_dependencies]"], [name^="custom_field[default_value_dependencies]"]'))
          .to be_empty
        expect(hidden_inputs.map { |i| [i['type'], i['value'], i['id'], i['autocomplete']] })
          .to eq([['hidden', '', 'custom_field_dependencies_json', 'off']])
        expect(page.at_css('form#custom_field_form')['enctype']).to be_nil
        expect(page.css('p[data-dcf-editor-required-warning]').size).to eq(1)
        expect(body.scan(I18n.t(:warning_required_child_no_options)).size).to eq(1)
        expect(page.css('p[data-dcf-default-value-row]').map { |p| p['class'] }).to eq(['dcf-hidden'])
        expect(page.css('form#custom_field_form script:not([src])').map(&:text).join).not_to include('dcf')
        expect(body).not_to match(/translation[ _]missing/i)
      end
    end

    it 'renders the default value row visible without a parent and hidden with one, and still clears the default' do
      get '/custom_fields/new', params: { type: 'IssueCustomField', custom_field: { field_format: 'depending_list' } }
      expect(response).to have_http_status(200)
      row = page.at_css('p[data-dcf-default-value-row]')
      expect(row['class'].to_s).not_to include('dcf-hidden')
      expect(row.at_css('#custom_field_default_value')).not_to be_nil
      expect(editor_root.at_css('[data-dcf-editor-placeholder]')['class']).not_to include('dcf-hidden')

      put_field(child, default_value: 'a1')
      expect_saved(child)
      expect(CustomField.find(child.id).default_value).to be_nil
      get "/custom_fields/#{child.id}/edit"
      expect(page.at_css('p[data-dcf-default-value-row]')['class']).to eq('dcf-hidden')
    end

    it 'renders the editor in de, fr and nl without a missing translation' do
      %w[de fr nl].each do |locale|
        admin.update_column(:language, locale)
        get "/custom_fields/#{child.id}/edit"
        expect(response).to have_http_status(200)
        expect(response.body).not_to match(/translation[ _]missing/i), locale
        expect(editor_json('i18n')['show_more']).to eq(I18n.t(:button_dcf_show_more, locale: locale)), locale
      end
    ensure
      admin.update_column(:language, 'en')
    end

    it 'renders warn-unsaved 0 when the user turned the warning off' do
      admin.pref.update!(warn_on_leaving_unsaved: '0')
      get "/custom_fields/#{child.id}/edit"
      expect(editor_root['data-dcf-editor-warn-unsaved']).to eq('0')
    end

    it 'saves the rendered form as is (no JavaScript): the mapping stays byte-identical, the name is saved' do
      # A first save writes the form's own store keys (url_pattern and the others).
      submit_urlencoded(edit_form(child))
      expect_saved(child)
      raw_before = raw_store(child)
      form = edit_form(child)
      form.at_css('input[name="custom_field[name]"]')['value'] = 'Renamed'

      submit_urlencoded(form)

      expect_saved(child)
      expect(CustomField.find(child.id).name).to eq('Renamed')
      expect(stored(child)).to eq([{ 'A' => %w[a1], 'B' => %w[b1] }, { 'A' => 'a1' }])
      expect(raw_store(child)).to eq(raw_before)
    end

    it 'keeps the old keys under a parent changed without JavaScript (documented, compat 2.2)' do
      second = dcf_list_field(name: "Second-#{SecureRandom.hex(3)}", values: %w[C B])
      form = edit_form(child)
      select = form.at_css('select#custom_field_parent_custom_field_id')
      select.css('option[selected]').each { |o| o.remove_attribute('selected') }
      option = select.at_css("option[value='#{second.id}']")
      option ||= select.add_child("<option value=\"#{second.id}\">x</option>").first
      option['selected'] = 'selected'

      submit_urlencoded(form)

      expect_saved(child)
      expect(CustomField.find(child.id).parent_custom_field_id).to eq(second.id)
      expect(stored(child)).to eq([{ 'A' => %w[a1], 'B' => %w[b1] }, { 'A' => 'a1' }])
    end

    it 'saves the editor payload written into the rendered form, against the rendered base' do
      form = edit_form(child)
      root = form.at_css('fieldset[data-dcf-editor]')
      body = { 'version' => 1, 'source' => 'editor', 'base' => root['data-dcf-editor-base'],
               'value_dependencies' => { 'C' => %w[c1 a1] }, 'default_value_dependencies' => { 'C' => 'a1' } }
      form.at_css('input[name="custom_field[dependencies_json]"]')['value'] = JSON.generate(body)

      submit_urlencoded(form)

      expect_saved(child)
      expect(stored(child)).to eq([{ 'C' => %w[a1 c1] }, { 'C' => 'a1' }])
    end

    it 'saves a multipart PUT with a 3 MB dependencies_json (UD-16)' do
      big_parent = dcf_list_field(values: (1..130).map { |i| "Parent value #{i}" })
      children = (1..1_000).map { |i| "Child value number #{i}" }
      field = dcf_list_field(format: 'depending_list', values: children, parent: big_parent)
      links = (1..130).to_h { |i| ["Parent value #{i}", children] }
      raw = json(links)
      expect(raw.bytesize).to be_between(3_000_000, max_bytes)

      put_field(field, { dependencies_json: raw }, headers: multipart)

      expect_saved(field)
      expect(stored(field)[0]).to eq(links)
    end

    # Rack refuses an urlencoded body above its query parser limit before
    # routing (documents the multipart switch and the client pre-check):
    # Rack 3 (6.0 and later) drops _method=put, so the browser POST matches
    # no route (404); Rack 2.2 (5.1) raises the limit error out of
    # MethodOverride (500). The limit is 4 MiB with Rack's defaults; core
    # config/boot.rb of the tested 5.1, 6.0, 6.1 and 7.0 releases raises it
    # to 32 MiB (RACK_QUERY_PARSER_BYTESIZE_LIMIT).
    it 'refuses an urlencoded form body above the Rack query parser limit before routing, row unchanged' do
      raw_before = raw_store(child)
      limit = Rack::Utils.default_query_parser.bytesize_limit
      expect(limit).to be >= max_bytes
      body = URI.encode_www_form([['_method', 'put'], ['custom_field[name]', 'Renamed'],
                                  ['custom_field[dependencies_json]', 'a' * (limit + 10)]])
      expect(body.bytesize).to be > limit

      post "/custom_fields/#{child.id}", params: body, headers: { 'CONTENT_TYPE' => 'application/x-www-form-urlencoded' }

      expect(response).to have_http_status(Gem::Version.new(Rack::RELEASE) >= Gem::Version.new('3') ? 404 : 500)
      expect(raw_store(child)).to eq(raw_before)
      expect(CustomField.find(child.id).name).to eq(child.name)
    end

    it 'refuses a multipart PUT without the authenticity token (CSRF) and saves one with it' do
      raw_before = raw_store(child)
      ActionController::Base.allow_forgery_protection = true
      put_field(child, { name: 'Forged', dependencies_json: '{}' }, headers: multipart)
      expect(response).to have_http_status(422)
      expect(raw_store(child)).to eq(raw_before)

      token = edit_form(child).at_css('input[name="authenticity_token"]')['value']
      expect(token).to be_present
      put "/custom_fields/#{child.id}", params: { authenticity_token: token, custom_field: { dependencies_json: '{}' } },
                                        headers: multipart
      expect_saved(child)
      expect(stored(child)).to eq([{}, {}])
    ensure
      ActionController::Base.allow_forgery_protection = false
    end

    it 'keeps dirty and a blank input after a storage refusal (failed-save rule, limits 4.10)' do
      raw_before = raw_store(child)
      allow(limits).to receive(:column_limit).and_call_original
      allow(limits).to receive(:column_limit).with('format_store').and_return(1)

      put_field(child, dependencies_json: json('C' => %w[c1]))

      expect(response).to have_http_status(200)
      expect(error_box.size).to eq(1)
      expect(editor_root['data-dcf-editor-dirty']).to eq('1')
      expect(editor_json('mapping')['value_dependencies']).to eq('C' => %w[c1])
      expect(hidden_inputs.map { |i| i['value'] }).to eq([''])
      expect(raw_store(child)).to eq(raw_before)
    end
  end
end
