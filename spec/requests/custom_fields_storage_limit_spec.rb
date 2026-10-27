# frozen_string_literal: true

require_relative '../rails_helper'

# WP-11 (UN-32, UN-50, UD-28, limits design 4.8 and 4.9): the admin custom
# field form re-renders a save above the column limit with the model message
# and writes nothing; the storage usage line appears at 90 percent of a limit
# on the admin form (with the README line) and on the project values and
# dependency pages (without it), only on MySQL, and never breaks a page.
# The limit and the adapter are stubbed through StorageLimits only.
RSpec.describe 'Custom field storage limit', type: :request do
  fixtures :users

  let(:limits) { RedmineDependingCustomFields::StorageLimits }
  let(:admin) { dcf_admin }

  before { allow(User).to receive(:current).and_return(admin) }

  def raw(field, column)
    CustomField.connection.select_value(CustomField.where(id: field.id).select(column).to_sql)
  end

  def stub_limits(by_column)
    allow(limits).to receive(:column_limit).and_return(nil)
    by_column.each { |column, limit| allow(limits).to receive(:column_limit).with(column).and_return(limit) }
  end

  # Records the bytes each preview_bytes call measures, by column.
  def capture_bytes
    captured = {}
    allow(limits).to receive(:preview_bytes).and_wrap_original do |original, record, column|
      captured[column] = original.call(record, column)
    end
    captured
  end

  def storage_message(attribute, bytes, limit)
    label = IssueCustomField.human_attribute_name(attribute)
    message = I18n.t('activerecord.errors.messages.dcf_storage_too_large',
                     size: limits.delimited(bytes), limit: limits.delimited(limit))
    "#{label} #{message}"
  end

  def page
    expect(response.body).not_to match(/translation[ _]missing/i)
    Nokogiri::HTML(response.body)
  end

  def error_box
    page.css('#errorExplanation li').map { |li| li.text.strip }
  end

  def hint_texts
    page.css('p.dcf-storage-usage em.info').map { |em| em.text.strip }
  end

  def usage_text(attribute, bytes, limit, percent)
    I18n.t(:text_dcf_storage_usage, label: CustomField.human_attribute_name(attribute),
                                    size: limits.delimited(bytes), limit: limits.delimited(limit), percent: percent)
  end

  # The [name, value] entries a browser submits for +form+ as rendered
  # (as in spec/requests/custom_fields_admin_form_spec.rb).
  def browser_entries(form)
    form.css('input, select, textarea').each_with_object([]) do |control, entries|
      next if control['name'].to_s.empty? || control.key?('disabled')

      entries.concat(control_entries(control))
    end
  end

  def control_entries(control)
    name = control['name']
    case control.name
    when 'select'
      options = control.css('option').reject { |o| o.key?('disabled') }
      chosen = options.select { |o| o.key?('selected') }
      chosen = options.first(1) if chosen.empty? && !control.key?('multiple')
      chosen.map { |o| [name, o['value'] || o.text] }
    when 'textarea' then [[name, control.text.sub(/\A\r?\n/, '')]]
    else input_entries(control)
    end
  end

  def input_entries(input)
    type = (input['type'] || 'text').downcase
    return [] if %w[submit button image file reset].include?(type)
    return [] if %w[checkbox radio].include?(type) && !input.key?('checked')

    [[input['name'], input['value'] || (%w[checkbox radio].include?(type) ? 'on' : '')]]
  end

  # Opens the edit form of +field+, lets the block change it and submits
  # every entry a browser would send; returns the entries.
  def submit_edit_form(field)
    get "/custom_fields/#{field.id}/edit"
    expect(response).to have_http_status(200)
    form = page.at_css('form#custom_field_form')
    yield form if block_given?
    entries = browser_entries(form)
    post form['action'], params: URI.encode_www_form(entries),
                         headers: { 'CONTENT_TYPE' => 'application/x-www-form-urlencoded' }
    entries
  end

  # A list field whose stored possible_values are +bytes+ ASCII bytes
  # (LENGTH counts characters on PostgreSQL and SQLite).
  def ascii_list(bytes, **options)
    field = dcf_list_field(values: ['x' * (bytes - 7)], **options)
    expect(raw(field, 'possible_values').bytesize).to eq(bytes)
    field
  end

  # Queries the usage line adds to a page (G6 differential form): the page
  # with the line minus the page with StorageLimits.usage stubbed empty,
  # after one warm-up visit. Returns them with the lines shown.
  def usage_line_overhead(visit)
    visit.call
    with = dcf_count_queries(&visit)
    shown = hint_texts
    allow(limits).to receive(:usage).and_return([])
    without = dcf_count_queries(&visit)
    expect(hint_texts).to eq([])
    [with - without, shown]
  end

  describe 'admin form saves' do
    it 'refuses a new list field over the limit and creates nothing' do
      values = %w[A B C]
      bytes = limits.serialized_bytesize(CustomField, 'possible_values', values)
      stub_limits('possible_values' => bytes - 1)

      expect do
        post '/custom_fields', params: { type: 'IssueCustomField',
                                         custom_field: { name: 'Big list', field_format: 'list', is_for_all: '1',
                                                         possible_values: values.join("\n") } }
      end.not_to change(CustomField, :count)

      expect(response).to have_http_status(200)
      expect(error_box).to eq([storage_message(:possible_values, bytes, bytes - 1)])
    end

    it 'refuses a possible_values change and leaves the column unchanged' do
      field = dcf_list_field(values: %w[A B])
      before = raw(field, 'possible_values')
      values = %w[A B C D]
      bytes = limits.serialized_bytesize(CustomField, 'possible_values', values)
      stub_limits('possible_values' => bytes - 1)

      patch "/custom_fields/#{field.id}", params: { custom_field: { possible_values: values.join("\n") } }

      expect(response).to have_http_status(200)
      expect(error_box).to eq([storage_message(:possible_values, bytes, bytes - 1)])
      expect(raw(field, 'possible_values')).to eq(before)
    end

    it 'refuses the legacy nested mapping params of a depending field and leaves format_store unchanged' do
      parent = dcf_list_field(values: %w[A B])
      field = dcf_list_field(format: 'depending_list', values: %w[a1 b1], parent: parent)
      before = raw(field, 'format_store')
      stub_limits('format_store' => 1)
      captured = capture_bytes

      patch "/custom_fields/#{field.id}", params: { custom_field: {
        parent_custom_field_id: parent.id.to_s,
        value_dependencies: { 'A' => %w[a1], 'B' => %w[b1] },
        default_value_dependencies: { 'A' => 'a1' }
      } }

      expect(response).to have_http_status(200)
      expect(error_box).to eq([storage_message(:value_dependencies, captured.fetch('format_store'), 1)])
      expect(raw(field, 'format_store')).to eq(before)
    end

    # Limits section 14 and V5: a save that writes the stored bytes back is
    # not refused, although the form posts the parent id as a String, which
    # dirties format_store.
    it 'saves a rename through the full edit form of a depending field whose stored columns are above the limit' do
      parent = dcf_list_field(values: %w[A B])
      field = dcf_list_field(format: 'depending_list', values: %w[a1 b1], parent: parent)
      dcf_set_dependencies(field, value_dependencies: { 'A' => %w[a1], 'B' => %w[b1] })
      submit_edit_form(field)
      expect(response).to have_http_status(302)
      before = %w[possible_values format_store].map { |column| raw(field, column) }
      stub_limits('possible_values' => 1, 'format_store' => 1)

      entries = submit_edit_form(field) { |form| form.at_css('input[name="custom_field[name]"]')['value'] = 'Renamed' }

      # Changed by WP-25: the editor posts one blank field (was the matrix params).
      expect(entries).to include(['custom_field[parent_custom_field_id]', parent.id.to_s],
                                 ['custom_field[dependencies_json]', ''])
      expect(entries.map(&:first).grep(/value_dependencies/)).to be_empty
      expect(response).to have_http_status(302), error_box.inspect
      expect(CustomField.find(field.id).name).to eq('Renamed')
      expect(%w[possible_values format_store].map { |column| raw(field, column) }).to eq(before)
    end

    it 'refuses the full edit form when the mapping changes and leaves both columns unchanged' do
      parent = dcf_list_field(values: %w[A B])
      field = dcf_list_field(format: 'depending_list', values: %w[a1 b1], parent: parent)
      dcf_set_dependencies(field, value_dependencies: { 'A' => %w[a1], 'B' => %w[b1] })
      submit_edit_form(field)
      before = %w[possible_values format_store].map { |column| raw(field, column) }
      stub_limits('possible_values' => 1, 'format_store' => 1)
      captured = capture_bytes

      # Changed by WP-25: the change goes through the editor payload (was a matrix tick).
      submit_edit_form(field) do |form|
        base = form.at_css('fieldset[data-dcf-editor]')['data-dcf-editor-base']
        form.at_css('input[name="custom_field[dependencies_json]"]')['value'] =
          JSON.generate('version' => 1, 'source' => 'editor', 'base' => base,
                        'value_dependencies' => { 'A' => %w[a1 b1], 'B' => %w[b1] }, 'default_value_dependencies' => {})
      end

      expect(response).to have_http_status(200)
      expect(error_box).to eq([storage_message(:value_dependencies, captured.fetch('format_store'), 1)])
      expect(%w[possible_values format_store].map { |column| raw(field, column) }).to eq(before)
    end

    it 'answers 422 to an oversized .js update' do
      field = dcf_list_field(values: %w[A B])
      before = raw(field, 'possible_values')
      stub_limits('possible_values' => 1)

      put "/custom_fields/#{field.id}.js", params: { custom_field: { possible_values: "A\nB\nC" } }, xhr: true

      expect(response).to have_http_status(422)
      expect(raw(field, 'possible_values')).to eq(before)
    end

    it 'keeps the drag-and-drop reorder of a field whose stored columns are above the limit' do
      field = dcf_list_field(values: %w[A B C])
      3.times { dcf_list_field(values: %w[X]) }
      position = CustomField.find(field.id).position
      stub_limits('possible_values' => 1, 'format_store' => 1)

      put "/custom_fields/#{field.id}.js", params: { custom_field: { position: position + 3 } }, xhr: true

      expect(response).to have_http_status(200)
      expect(CustomField.find(field.id).position).not_to eq(position)
    end

    it 'shows the message in the request locale' do
      admin.update_column(:language, 'de')
      field = dcf_list_field(values: %w[A B])
      values = %w[A B C D]
      bytes = limits.serialized_bytesize(CustomField, 'possible_values', values)
      stub_limits('possible_values' => bytes - 1)

      patch "/custom_fields/#{field.id}", params: { custom_field: { possible_values: values.join("\n") } }

      expect(response).to have_http_status(200)
      expect(error_box).to eq(["Mögliche Werte ist zu groß zum Speichern (#{bytes} Bytes, die Datenbank erlaubt " \
                               "höchstens #{bytes - 1} Bytes)"])
    end
  end

  describe 'usage line on the admin form' do
    let(:hook) { RedmineDependingCustomFields::Hooks::CustomFieldStorageHook }

    def edit(field)
      get "/custom_fields/#{field.id}/edit"
      expect(response).to have_http_status(200)
    end

    it 'is registered for view_custom_fields_form_upper_box' do
      expect(Redmine::Hook.hook_listeners(:view_custom_fields_form_upper_box)).to include(hook.instance)
    end

    it 'shows the usage and the README line at 90 percent on MySQL, and nothing one byte lower' do
      allow(limits).to receive(:mysql?).and_return(true)
      stub_limits('possible_values' => 1_000)
      at = ascii_list(900)
      below = ascii_list(899)

      edit(at)
      delimiter = I18n.t('number.format.delimiter')
      expect(hint_texts).to eq(["Possible values: 900 of 1#{delimiter}000 bytes used in the database (90%).",
                                'For very large lists use the Key/Value list (depending) format, or widen the ' \
                                'database columns (see the plugin README, section "MySQL / MariaDB and large lists").'])
      expect(page.css('p.dcf-storage-usage svg, p.dcf-storage-usage .icon')).to be_empty
      expect(page.css('div.box.tabular p.dcf-storage-usage').size).to eq(2)

      edit(below)
      expect(page.css('.dcf-storage-usage')).to be_empty
    end

    it 'adds one query to the form when it is shown' do
      allow(limits).to receive(:mysql?).and_return(true)
      stub_limits('possible_values' => 1_000)
      field = ascii_list(950)
      expect(usage_line_overhead(-> { edit(field) }))
        .to eq([1, [usage_text(:possible_values, 950, 1_000, 95), I18n.t(:text_dcf_storage_admin_help)]])
    end

    it 'shows the mapping line in German' do
      admin.update_column(:language, 'de')
      allow(limits).to receive(:mysql?).and_return(true)
      field = ascii_list(100)
      field.update!(url_pattern: 'http://example.test/%value%')
      bytes = raw(field, 'format_store').bytesize
      stub_limits('format_store' => bytes)

      edit(field)
      expect(hint_texts).to eq(["Abhängigkeitszuordnung: #{bytes} von #{bytes} Bytes in der Datenbank belegt (100 %).",
                                I18n.t(:text_dcf_storage_admin_help, locale: :de)])
    end

    it 'is absent when the database is not MySQL, and the hook then runs no SQL' do
      allow(limits).to receive(:mysql?).and_return(false)
      stub_limits('possible_values' => 900)
      field = ascii_list(900)

      edit(field)
      expect(response.body).not_to include('dcf-storage-usage')
      html = nil
      expect(dcf_plugin_overhead(with: -> { html = hook.instance.view_custom_fields_form_upper_box(custom_field: field) },
                                 without: -> {})).to eq(0)
      expect(html).to eq('')
    end

    it 'is absent with the real adapter for a small field and on the new form' do
      field = dcf_list_field(values: %w[A B])
      edit(field)
      expect(response.body).not_to include('dcf-storage-usage')
      get '/custom_fields/new', params: { type: 'IssueCustomField' }
      expect(response).to have_http_status(200)
      expect(response.body).not_to include('dcf-storage-usage')
    end

    it 'never breaks the form' do
      allow(limits).to receive(:usage).and_raise(StandardError, 'boom')
      field = dcf_list_field(values: %w[A B])

      edit(field)
      expect(page.css('form#custom_field_form')).not_to be_empty
      expect(response.body).not_to include('dcf-storage-usage')
      expect(hook.instance.view_custom_fields_form_upper_box(custom_field: field)).to eq('')
      expect(hook.instance.view_custom_fields_form_upper_box({})).to eq('')
    end

    it 'shows the stored usage after a refused save' do
      allow(limits).to receive(:mysql?).and_return(true)
      stub_limits('possible_values' => 1_000)
      field = ascii_list(950)

      patch "/custom_fields/#{field.id}", params: { custom_field: { possible_values: 'x' * 2_000 } }

      expect(response).to have_http_status(200)
      expect(error_box.size).to eq(1)
      expect(hint_texts.first).to eq(usage_text(:possible_values, 950, 1_000, 95))
    end
  end

  describe 'usage line on the project pages' do
    let(:project) { dcf_create_project }
    let(:manager) { dcf_manager(project) }

    before { allow(User).to receive(:current).and_return(manager) }

    def values_page(field)
      get custom_field_configuration_field_path(project, field)
      expect(response).to have_http_status(200)
    end

    def dependency_page(field)
      get custom_field_configuration_field_dependencies_path(project, field)
      expect(response).to have_http_status(200)
    end

    def depending_child(bytes)
      parent = dcf_list_field(values: %w[A B])
      child = ascii_list(bytes, format: 'depending_list', parent: parent)
      dcf_set_dependencies(child, value_dependencies: { 'A' => [child.possible_values.first] })
    end

    it 'shows the usage line without the README line on the values and dependency pages' do
      allow(limits).to receive(:mysql?).and_return(true)
      child = depending_child(900)
      stub_limits('possible_values' => 1_000)
      expected = [usage_text(:possible_values, 900, 1_000, 90)]

      values_page(child)
      expect(hint_texts).to eq(expected)
      expect(page.text).not_to include(I18n.t(:text_dcf_storage_admin_help))
      expect(response.body).not_to include('README')

      dependency_page(child)
      expect(hint_texts).to eq(expected)
      expect(page.text).not_to include(I18n.t(:text_dcf_storage_admin_help))
      expect(response.body).not_to include('README')
    end

    it 'adds one query to each page when it is shown' do
      allow(limits).to receive(:mysql?).and_return(true)
      child = depending_child(950)
      stub_limits('possible_values' => 1_000)
      expected = [usage_text(:possible_values, 950, 1_000, 95)]

      expect(usage_line_overhead(-> { values_page(child) })).to eq([1, expected])
      allow(limits).to receive(:usage).and_call_original
      expect(usage_line_overhead(-> { dependency_page(child) })).to eq([1, expected])
    end

    it 'renders in German on both pages' do
      manager.update_column(:language, 'de')
      allow(limits).to receive(:mysql?).and_return(true)
      child = depending_child(900)
      stub_limits('possible_values' => 1_000)
      delimiter = I18n.t('number.format.delimiter', locale: :de)
      expected = ["Mögliche Werte: 900 von 1#{delimiter}000 Bytes in der Datenbank belegt (90 %)."]

      values_page(child)
      expect(hint_texts).to eq(expected)
      dependency_page(child)
      expect(hint_texts).to eq(expected)
    end

    it 'is absent below 90 percent and when the database is not MySQL' do
      allow(limits).to receive(:mysql?).and_return(true)
      child = depending_child(899)
      stub_limits('possible_values' => 1_000)
      values_page(child)
      expect(response.body).not_to include('dcf-storage-usage')

      allow(limits).to receive(:mysql?).and_return(false)
      child = depending_child(950)
      values_page(child)
      expect(response.body).not_to include('dcf-storage-usage')
      dependency_page(child)
      expect(response.body).not_to include('dcf-storage-usage')
    end

    it 'never breaks either page' do
      allow(limits).to receive(:usage).and_raise(StandardError, 'boom')
      child = depending_child(100)

      values_page(child)
      expect(response.body).not_to include('dcf-storage-usage')
      dependency_page(child)
      expect(response.body).not_to include('dcf-storage-usage')
    end

    it 'is absent from the issue form' do
      field = ascii_list(100)
      issue = dcf_real_issue(project, field => 'x' * 93)
      allow(limits).to receive(:mysql?).and_return(true)
      stub_limits('possible_values' => 1)
      allow(limits).to receive(:usage).and_call_original
      allow(User).to receive(:current).and_return(admin)

      get "/issues/#{issue.id}/edit"
      expect(response).to have_http_status(200)
      expect(page.css("#issue_custom_field_values_#{field.id}")).not_to be_empty
      expect(response.body).not_to include('dcf-storage-usage')
      expect(limits).not_to have_received(:usage)
    end
  end
end
